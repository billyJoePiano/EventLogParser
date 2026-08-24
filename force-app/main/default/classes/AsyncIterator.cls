/**
 * Utility for handling intensive or long-running jobs that require multiple transactions.  To prevent overrunning governor limits,
 * the AsyncIterator monitors CPU limits (or another time limit that can be customized by overriding getTime() and getTimeLimit())
 * and stops iteration before the limits are reached.
 * 
 * See also: AsyncProcessor class.
 */
global virtual class AsyncIterator implements System.Iterable<Object> {
    @TestVisible
    private final System.Iterator<Object> it;

    // used for tracking CPU limits
    private Double maxIterationTime = 0; // maximum time per iteration so far
    private Integer maxTimeBetweenCycles = 0; // maximum time needed between cycles so far, to run time checks and other iterator logic
    private Integer maxIterationsPerCycle = 1; // number of iterations per cycle.  Is adjusted based on observed performance
    private Boolean stillAdjusting = true; // remains true while there is still room for maxIterationsPerCycle to increase, 
                                           // i.e. until maxIterationsPerCycle * maxIterationTime would exceed 1000 milliseconds

    private transient Integer bufferTime = 0; // can be set by caller, to provide an extra buffer time before the time limit runs out (e.g. typically any after-work, and enough time to re-enqueue the job)
    private transient Integer endBy = null;

    private transient Integer cycleStart = null; // start time of current cycle
    private transient Integer cycleEnd = null; // end time of current cycle
    private transient Integer iterationsCounter = null; // counter for number of iterations this cycle
    @TestVisible
    private transient Integer maxIterationsThisCycle = null; // total number of iterations allowed this cycle before checks must be run (typically this variable will be same as maxIterationsPerCycle, but shrinks as we are getting closer to the time limit for the transaction)


    public AsyncIterator(System.Iterator<Object> it) {
        this.it = it;
    }

    public System.Iterator<Object> iterator() {
        return new ChildIterator(this);
    }

    public Boolean hasNext() {
        if (this.iterationsCounter == null) {
            //first iteration of transaction. initialize transient tracking variables
            this.cycleEnd = this.getTime(); // needed to calculate processing time before cycle start
            this.iterationsCounter = 0;
            if (this.endBy == null) {
                this.setBufferTime(this.bufferTime); //force calculation of this.endBy
            }
            if (!this.checkMaxIterationsThisCycle(this.cycleEnd + this.maxTimeBetweenCycles)) {
                // always allow at least 1 iteration in the very first cycle of a new transaction
                this.maxIterationsThisCycle = 1;
            }
            return it.hasNext();

        } else if (this.iterationsCounter < this.maxIterationsThisCycle) {
            if (it.hasNext()) {
                return true;
            } else {
                this.cycleEnd = this.getTime();
                if (this.cycleStart != null && this.iterationsCounter > 0) {
                    this.calcIterationTime(); //capture time data before ending the loop
                }
                return false;
            }
        } else {
            this.cycleEnd = this.getTime();
            if (this.iterationsCounter > 0) {
                this.calcIterationTime(); //resets this.iterationsCounter
            }
            return this.checkMaxIterationsThisCycle(this.cycleEnd + this.maxTimeBetweenCycles) && it.hasNext();
        }
    }

    public Object next() {
        if (this.iterationsCounter == 0 || this.iterationsCounter == null) {
            if (this.cycleEnd == null) {
                throw new IllegalArgumentException('Cannot call AsyncIterator.next() until AsyncIterator.hasNext() has been called first');
            }
            this.cycleStart = this.getTime();
            Integer timeBetweenCycles = this.cycleStart - this.cycleEnd;
            this.cycleEnd = null;
            if (timeBetweenCycles > this.maxTimeBetweenCycles) {
                this.maxTimeBetweenCycles = timeBetweenCycles;
            }
        } else if (!(this.iterationsCounter < this.maxIterationsThisCycle)) {
            throw new IllegalArgumentException('Cannot call AsyncIterator.next() unless AsyncIterator.hasNext() has been called first and returned true');
        }
        this.iterationsCounter++;
        return it.next();
    }

    public Boolean hasMore() {
        return it.hasNext();
    }

    virtual public Integer getLimitTime() {
        return Limits.getLimitCpuTime();
    }

    virtual public Integer getTime() {
        return Limits.getCpuTime();
    }

    public Double getMaxIterationTime() {
        return this.maxIterationTime;
    }

    public Integer getMaxTimeBetweenCycles() {
        return this.maxTimeBetweenCycles;
    }

    public Integer getMaxIterationsPerCycle() {
        return this.maxIterationsPerCycle;
    }

    public Boolean isStillAdjusting() {
        return this.stillAdjusting;
    }

    public void setBufferTime(Integer bufferTime) {
        this.bufferTime = bufferTime;
        this.endBy = this.getLimitTime() - bufferTime;
        if (this.cycleStart != null) {
            this.checkMaxIterationsThisCycle(this.cycleStart);
        }
    }

    public Integer getBufferTime() {
        return this.bufferTime;
    }

    public Integer getCycleEndTime() {
        return this.cycleEnd;
    }

    public void resetTimingCounters() {
        this.maxIterationTime = 0;
        this.maxTimeBetweenCycles = 0;
        this.maxIterationsPerCycle = 1;
        this.stillAdjusting = true;

        // bufferTime must be seperately reset using the exposed setter: setBufferTime(Integer bufferTime)
        this.cycleStart = null;
        this.cycleEnd = null;
        this.iterationsCounter = null;
        this.maxIterationsThisCycle = null;
    }

    private void calcIterationTime() {
        Double iterationTime = (this.cycleEnd - this.cycleStart) / ((Double)this.iterationsCounter);
        if (iterationTime > this.maxIterationTime) {
            this.maxIterationTime = iterationTime;
            this.adjustMaxIterationsPerCycle();
        } else if (this.stillAdjusting) {
            this.adjustMaxIterationsPerCycle();
        }
        this.iterationsCounter = 0;
    }

    private void adjustMaxIterationsPerCycle() {
        Double cycleTime = this.maxIterationTime * this.maxIterationsPerCycle;
        if (cycleTime + this.maxIterationTime <= 1000) {
            // adjust maxIterationsPerCycle upwards
            this.maxIterationsPerCycle++;
        } else {
            // adjust maxIterationsPerCycle downwards if needed
            this.stillAdjusting = false;
            if (cycleTime > 1000 && this.maxIterationsPerCycle > 1) {
                this.maxIterationsPerCycle = Math.floor(1000 / this.maxIterationTime).intValue();
                if (this.maxIterationsPerCycle < 1) {
                    this.maxIterationsPerCycle = 1;
                }
            }
        }
    }

    private Boolean checkMaxIterationsThisCycle(Integer cycleStartTime) {
        if (this.maxIterationTime > 0) {
            Integer remainingTime = this.endBy - cycleStartTime - 2 * this.maxTimeBetweenCycles;
            Integer possibleIterations = Math.floor(remainingTime / this.maxIterationTime).intValue() - 1;
            this.maxIterationsThisCycle = Math.max(0, Math.min(this.maxIterationsPerCycle, possibleIterations));
        } else {
            this.maxIterationsThisCycle = this.maxIterationsPerCycle;
        }
        return this.maxIterationsThisCycle > 0;
    }

    private class ChildIterator implements System.Iterator<Object> {
        public final AsyncIterator parent;
        
        private ChildIterator(AsyncIterator parent) {
            this.parent = parent;
        }

        public Boolean hasNext() {
            return this.parent.hasNext();
        }

        public Object next() {
            return this.parent.next();
        }
    }
}