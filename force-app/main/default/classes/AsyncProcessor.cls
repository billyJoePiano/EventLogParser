abstract public class AsyncProcessor extends BatchableLogger implements Queueable {
    private final AsyncIterator it;

    public AsyncProcessor(System.Iterator<Object> it) {
        super();
        this.it = new AsyncIterator(this, it);
    }

    public AsyncProcessor(Boolean parentOnThisTransaction, System.Iterator<Object> it) {
        super(parentOnThisTransaction);
        this.it = new AsyncIterator(this, it);
    }

    public AsyncProcessor(BatchableLogger predecessor, System.Iterator<Object> it) {
        super(predecessor);
        this.it = new AsyncIterator(this, it);
    }

    public AsyncProcessor(String loggerTransactionId, System.Iterator<Object> it) {
        super(loggerTransactionId);
        this.it = new AsyncIterator(this, it);
    }
    
    abstract public void execute(QueueableContext qc, AsyncIterator it);

    // used for tracking CPU limits
    private Integer schedulingTime = 0; // time required to enqueue a new job
    private Double maxIterationTime = 0; // maximum time per iteration so far
    private Integer iterationsPerCycle = 1; // number of iterations per cycle.  Is adjusted based on observed performance
    private Boolean stillAdjusting = true; // remains true while there is still room for iterationsPerCycle to increase, 
                                           // i.e. until iterationsPerCycle * maxIterationTime would exceed 1000 milliseconds

    private transient Integer prevIteration = this.getTime();
    private transient Integer limitMinusSchedulingTime = null;
    private transient Integer stopAt = null;
    protected transient Boolean hasNext;

    virtual public Integer getLimitTime() {
        return Limits.getLimitCpuTime();
    }

    virtual public Integer getTime() {
        return Limits.getCpuTime();
    }

    public void resetTimingCounters() {
        this.schedulingTime = 0;
        this.maxITerationTime = 0;
        this.iterationsPerCycle = 1;
        this.stillAdjusting = true;
        this.prevIteration = this.getTime();
        this.limitMinusSchedulingTime = null;
        this.stopAt = null;
    }

    virtual public Id enqueue() {
        Integer start = this.getTime();
        Id jobId = System.enqueueJob(this);
        Integer diff = this.getTime() - start;
        if (diff > this.schedulingTime) {
            this.schedulingTime = diff;
        }
        return jobId;
    }

    virtual public void execute(QueueableContext qc) {
        this.setLoggerTransactionId();
        this.prevIteration = this.getTime();
        this.limitMinusSchedulingTime = this.getLimitTime() - this.schedulingTime * 2;
        this.stopAt = Math.floor(this.limitMinusSchedulingTime - this.maxIterationTime * 2).intValue();

        this.execute(qc, this.it);

        if (this.hasNext) {
            this.enqueue();
        }
    }

    public void executeSync() {
        this.executeSync(500);
    }

    public void executeSync(Integer msBuffer) {
        this.prevIteration = this.getTime();
        this.limitMinusSchedulingTime = this.getLimitTime() - msBuffer;
        this.stopAt = Math.floor(this.limitMinusSchedulingTime - this.maxIterationTime * 2).intValue();
        
        this.execute(null, this.it);
    }
    
    private Boolean checkLimits() {
        Integer newIteration = this.getTime();
        Double diff = (newIteration - this.prevIteration) / ((Double)this.iterationsPerCycle);
        this.prevIteration = newIteration;
        if (diff > this.maxIterationTime) {
            this.maxIterationTime = diff;
            System.debug('Max Iteration Time: ' + this.maxIterationTime);
            this.adjustIterationsPerCycle(true);
        } else if (this.stillAdjusting) {
            this.adjustIterationsPerCycle(false);
        }
        return newIteration < this.stopAt;
    }

    private void adjustIterationsPerCycle(Boolean updateStopAt) {
        Double cycleTime = this.maxIterationTime * this.iterationsPerCycle;
        if (cycleTime + this.maxIterationTime <= 1000) {
            this.iterationsPerCycle += 1;
            updateStopAt = true;
            System.debug('Iterations per cycle (inc): ' + this.iterationsPerCycle);
        } else {
            this.stillAdjusting = false;
            if (cycleTime > 1000 && this.iterationsPerCycle > 1) {
                do {
                    this.iterationsPerCycle -= 1;
                    cycleTime = this.maxIterationTime * this.iterationsPerCycle;
                } while (cycleTime > 1000 && this.iterationsPerCycle > 1);
                updateStopAt = true;
                System.debug('Iterations per cycle (dec): ' + this.iterationsPerCycle);
            }
        }
        if (updateStopAt) {
            this.stopAt = Math.floor(this.limitMinusSchedulingTime - this.maxIterationTime * this.iterationsPerCycle * 2).intValue();
        }
    }

    public class AsyncIterator implements System.Iterator<Object>, System.Iterable<Object> {
        private final System.Iterator<Object> it;
        private final AsyncProcessor parent;
        private transient Integer cycleIterations = 0;

        private AsyncIterator(AsyncProcessor parent, System.Iterator<Object> it) {
            this.it = it;
            this.parent = parent;
        }
            
        public System.Iterator<Object> iterator() {
            return this;
        }

        public Boolean hasNext() {
            Boolean hasNext = it.hasNext();
            this.parent.hasNext = hasNext;
            if (this.cycleIterations < this.parent.iterationsPerCycle) {
                return hasNext;
            } else {
                this.cycleIterations = 0;
                return this.parent.checkLimits() && hasNext;
            }
        }

        public Object next() {
            this.cycleIterations++;
            return it.next();
        }
    }

    abstract public class WithFinish extends AsyncProcessor {
        private Boolean runFinish = false;

        public WithFinish(System.Iterator<Object> it) {
            super(it);
        }
    
        public WithFinish(Boolean parentOnThisTransaction, System.Iterator<Object> it) {
            super(parentOnThisTransaction, it);
        }
    
        public WithFinish(BatchableLogger predecessor, System.Iterator<Object> it) {
            super(predecessor, it);
        }
    
        public WithFinish(String loggerTransactionId, System.Iterator<Object> it) {
            super(loggerTransactionId, it);
        }

        abstract public void finish(QueueableContext qc);

        override virtual public void execute(QueueableContext qc) {
            if (!runFinish) {
                super.execute(qc);
                if (!this.hasNext) {
                    this.runFinish = true;
                    this.enqueue();
                }
            } else {
                this.finish(qc);
            }
        }
    }

    public class CannibalizingListIterator implements System.Iterator<Object> {
        public final List<Object> myList;

        public CannibalizingListIterator(List<Object> myList) {
            this.myList = myList;
        }

        public Boolean hasNext() {
            return myList.size() > 0;
        }

        public Object next() {
            return myList.remove(0);
        }
    }

    public class CombinedIterator implements System.Iterator<Object> {
        public final List<System.Iterator<Object>> its;

        public CombinedIterator(List<System.Iterator<Object>> its) {
            this.its = its;
        }

        public Boolean hasNext() {
            while (this.its.size() > 0) {
                if (this.its.get(0).hasNext()) {
                    return true;
                }
                this.its.remove(0);
            }
            return false;
        }

        public Object next() {
            return this.its.get(0).next();
        }
    }
}