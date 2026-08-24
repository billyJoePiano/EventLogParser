@IsTest
public class AsyncTest {
    public class TestIterator extends AsyncIterator {
        public Integer currentTime = super.getTime();
        public Integer limitTime = super.getLimitTime();

        public TestIterator(System.Iterator<Object> it) {
            super(it);
        }

        override public Integer getTime() {
            return this.currentTime;
        }

        override public Integer getLimitTime() {
            return this.limitTime;
        }
    }

    public class TestProcessor extends AsyncProcessor.WithFinish {
        public final TestIterator testIt;
        public Integer timeAfterIteration = 0;
        public Boolean ranFinish = false;

        public TestProcessor(System.Iterator<Object> it) {
            super(new TestIterator(it));
            this.testIt = (TestIterator)this.it;
        }

        override public void execute(QueueableContext qc, AsyncIterator itGeneric) {
            TestIterator it = (TestIterator)itGeneric;
            for (Object obj : it) {
                it.currentTime += (Integer)obj;
                Integer maxIterationsBefore = it.maxIterationsThisCycle;
                it.setBufferTime(it.getBufferTime()); //trigger recalc of maxIterationsThisCycle
                System.assertEquals(maxIterationsBefore, it.maxIterationsThisCycle);
            }
            it.currentTime += this.timeAfterIteration;
        }

        override public void finish(QueueableContext qc) {
            this.ranFinish = true;
        }
    }

    @IsTest
    public static void testAsyncProcessing() {
        List<Object> listToConsume = new List<Object> { 3, 2, 1, 4, 5, 6, 500, 500, 2000, 3000, 4000, 5000, 6000 };
        TestProcessor proc = new TestProcessor(new AsyncProcessor.CannibalizingListIterator(listToConsume));
        proc.testIt.currentTime = 0;
        proc.testIt.limitTime = 3 + 2 + 1 + 4 + 5 + 6 + 9 + 10;
        proc.timeAfterIteration = 9;

        proc.setExtraBufferTime(10);
        System.assertEquals(0, proc.getMaxAfterIterationTime());
        System.assertEquals(10, proc.it.getBufferTime());

        proc.execute(null);

        System.assertEquals(true, proc.it.hasMore());
        System.assertEquals(7, listToConsume.size());
        System.assertEquals(9, proc.getMaxAfterIterationTime());
        System.assertEquals(5, proc.it.getMaxIterationTime());
        System.assertEquals(4, proc.it.getMaxIterationsPerCycle());
        System.assertEquals(true, proc.it.isStillAdjusting());
        System.assertEquals(0, proc.it.getMaxTimeBetweenCycles());

        proc.testIt.currentTime += 17;
        proc.enqueue(); //triggers recalc of maxAfterIterationTime;
        System.assertEquals(9 + 17, proc.getMaxAfterIterationTime());

        proc.testIt.currentTime = 0;
        proc.testIt.limitTime = 500 + 500 + 2000 + 3000 + 4000 + 5000 + 6000 + 5000 * 2 + 10 + 9 * 2;
        proc.resetTimingCounters();
        System.assertEquals(10, proc.getExtraBufferTime());
        
        proc.executeSyncNoFinish();

        System.assertEquals(false, proc.it.hasMore());
        System.assertEquals(0, listToConsume.size());
        System.assertEquals(9, proc.getMaxAfterIterationTime());
        System.assertEquals(6000, proc.it.getMaxIterationTime());
        System.assertEquals(1, proc.it.getMaxIterationsPerCycle());
        System.assertEquals(false, proc.it.isStillAdjusting());
        System.assertEquals(0, proc.it.getMaxTimeBetweenCycles());

        System.assertEquals(0, ((AsyncProcessor.CannibalizingListIterator)proc.it.it).listToConsume.size());
        System.assertEquals(false, proc.it.it.hasNext());
        System.assertEquals(false, proc.it.hasMore());
        System.assertEquals(false, proc.hasMore);
        System.assertEquals(false, proc.ranFinish);
        proc.execute(null);
        System.assertEquals(true, proc.ranFinish);
    }

    public class TestProcessor2 extends AsyncProcessor.WithFinish {
        public TestProcessor2(Boolean parentOnThisTransaction, AsyncIterator it) {
            super(parentOnThisTransaction, it);
        }

        public TestProcessor2(BatchableLogger predecessor, AsyncIterator it) {
            super(predecessor, it);
        }

        public TestProcessor2(String loggerTransactionId, AsyncIterator it) {
            super(loggerTransactionId, it);
        }

        public TestProcessor2(System.Iterator<Object> it) {
            super(it);
        }

        public TestProcessor2(Boolean parentOnThisTransaction, System.Iterator<Object> it) {
            super(parentOnThisTransaction, it);
        }

        public TestProcessor2(BatchableLogger predecessor, System.Iterator<Object> it) {
            super(predecessor, it);
        }

        public TestProcessor2(String loggerTransactionId, System.Iterator<Object> it) {
            super(loggerTransactionId, it);
        }
        
        override public void execute(QueueableContext qc, AsyncIterator itGeneric) { }

        override public void finish(QueueableContext qc) { }
    }

    @IsTest
    public static void testAlternateConstructors() {
        AsyncIterator asyncIt = null;
        new TestProcessor2(true, asyncIt);
        new TestProcessor2(new TestProcessor2(Logger.getTransactionId(), asyncIt), asyncIt);

        System.Iterator<Object> it = null;
        new TestProcessor2(it);
        new TestProcessor2(true, it);
        new TestProcessor2(new TestProcessor2(Logger.getTransactionId(), it), it);
    }
}