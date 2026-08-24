/**
 * Utility for handling intensive or long-running jobs that require multiple transactions via the queueable interface.
 * See also: AsyncIterator class.
 * 
 * Created By: Bill Anderson
 * Created On: 8-24-2026
 */
global abstract class AsyncProcessor extends BatchableLogger implements Queueable {
    public final AsyncIterator it;
    private Integer maxAfterIterationTime = 0;
    private Integer extraBufferTime = 0;

    private transient Integer finishIterationTime = null;
    public transient Id enqueuedJobId = null;

    @TestVisible
    private transient Boolean hasMore = null;

    @TestVisible
    private Boolean doEnqueue = !Test.isRunningTest();

    public AsyncProcessor(AsyncIterator it) {
        super();
        this.it = it;
    }

    public AsyncProcessor(Boolean parentOnThisTransaction, AsyncIterator it) {
        super(parentOnThisTransaction);
        this.it = it;
    }

    public AsyncProcessor(BatchableLogger predecessor, AsyncIterator it) {
        super(predecessor);
        this.it = it;
    }

    public AsyncProcessor(String loggerTransactionId, AsyncIterator it) {
        super(loggerTransactionId);
        this.it = it;
    }

    public AsyncProcessor(System.Iterator<Object> it) {
        this(new AsyncIterator(it));
    }

    public AsyncProcessor(Boolean parentOnThisTransaction, System.Iterator<Object> it) {
        this(parentOnThisTransaction, new AsyncIterator(it));
    }

    public AsyncProcessor(BatchableLogger predecessor, System.Iterator<Object> it) {
        this(predecessor, new AsyncIterator(it));
    }

    public AsyncProcessor(String loggerTransactionId, System.Iterator<Object> it) {
        this(loggerTransactionId, new AsyncIterator(it));
    }
    
    abstract global void execute(QueueableContext qc, AsyncIterator it);

    public void resetTimingCounters() {
        this.maxAfterIterationTime = 0;
        this.it.resetTimingCounters();
    }

    virtual public Id enqueue() {
        this.checkAfterIterationTime();
        return this.enqueuedJobId = (this.doEnqueue ? System.enqueueJob(this) : null);
    }

    public void execute(QueueableContext qc) {
        this.execute(qc, true);
    }

    public void executeSync(Boolean enqueueWhenDone) {
        this.execute(null, enqueueWhenDone);
    }

    virtual protected void execute(QueueableContext qc, Boolean enqueueWhenDone) {
        this.setLoggerTransactionId();
        this.it.setBufferTime(this.maxAfterIterationTime * 2 + this.extraBufferTime);
        this.execute(null, this.it);
        this.finishIterationTime = this.it.getCycleEndTime() ?? this.it.getTime();
        this.hasMore = this.it.hasMore();
        if (this.hasMore && enqueueWhenDone) {
            this.enqueue();
        } else {
            this.checkAfterIterationTime();
        }
    }

    public void setExtraBufferTime(Integer extraBufferTime) {
        this.extraBufferTime = extraBufferTime;
        this.it.setBufferTime(this.maxAfterIterationTime * 2 + extraBufferTime);
    }

    public Integer getExtraBufferTime() {
        return this.extraBufferTime;
    }

    public Integer getMaxAfterIterationTime() {
        return this.maxAfterIterationTime;
    }

    protected void checkAfterIterationTime() {
        Integer finishIterationTime = this.finishIterationTime ?? this.it.getCycleEndTime();
        if (finishIterationTime != null) {
            Integer afterIterationTime = this.it.getTime() - finishIterationTime;
            if (afterIterationTime > this.maxAfterIterationTime) {
                this.maxAfterIterationTime = afterIterationTime;
                // No need to set this.it.setBufferTime(...) because AsyncIterator.bufferTime is a transient variable, and thist method is only called
                // at the end of the transaction.  Also, this.it.setBufferTime(...) will be run at the start of the next transaction -- in execute(qc)
            }
        }
    }

    abstract public class WithFinish extends AsyncProcessor {
        public WithFinish(AsyncIterator it) {
            super(it);
        }

        public WithFinish(Boolean parentOnThisTransaction, AsyncIterator it) {
            super(parentOnThisTransaction, it);
        }

        public WithFinish(BatchableLogger predecessor, AsyncIterator it) {
            super(predecessor, it);
        }

        public WithFinish(String loggerTransactionId, AsyncIterator it) {
            super(loggerTransactionId, it);
        }

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

        override virtual protected void execute(QueueableContext qc, Boolean enqueueWhenDone) {
            if (this.it.hasMore()) {
                super.execute(qc, enqueueWhenDone);
                if (!this.hasMore && enqueueWhenDone) {
                    this.enqueue();
                }
            } else {
                this.setLoggerTransactionId();
                this.finish(qc);
            }
        }

        public void executeSyncNoFinish() {
            if (this.it.hasMore()) {
                super.execute(null, false);
            }
        }
    }

    public class CannibalizingListIterator implements System.Iterator<Object> {
        public final List<Object> listToConsume;

        public CannibalizingListIterator(List<Object> listToConsume) {
            this.listToConsume = listToConsume;
        }

        public Boolean hasNext() {
            return listToConsume.size() > 0;
        }

        public Object next() {
            return listToConsume.remove(0);
        }
    }
}