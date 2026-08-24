/**
 * Note: To achieve needed code coverage for the BatchableLogger Apex class, you will also need to use the tests in ApexUnxpectedExceptionTest.
 * This is only to provide code coverage for the SaveListener plugin.
 */
@IsTest
public class BatchableLoggerSaveListenerTest {

    @IsTest
    public static void testSaveListener() {
        LoggerTestConfigurator.setMock(LoggerPlugin__mdt.getInstance('BatchableLogger_SaveListener'));

        Test.startTest();
        BatchableLogger logger1 = new BatchableLogger();
        Logger.info('test log message 1');
        Logger.saveLog();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertLoggerIdExists(logger1);

        BatchableLogger logger2 = new BatchableLogger(logger1);
        assertLoggerIdExists(logger2);

        logger2.confirmedExists = false;
        logger2.setLoggerTransactionId();
        assertLoggerIdExists(logger2);

        logger2.confirmedExists = false;
        BatchableLogger.savedTransactionIds.clear();
        logger2.setLoggerTransactionId();
        assertLoggerIdExists(logger2);

        logger2.confirmedExists = false;
        BatchableLogger.savedTransactionIds.clear();
        BatchableLogger.getPartition().remove(logger2.getLoggerTransactionId().replace('-', ''));
        logger2.setLoggerTransactionId();
        assertLoggerIdExists(logger2);
    }

    public static void assertLoggerIdExists(BatchableLogger logr) {
        System.assertEquals(true, logr.confirmedExists);
        System.assert(BatchableLogger.savedTransactionIds.contains(logr.getLoggerTransactionId()));
        System.assertEquals(true, BatchableLogger.getPartition().get(logr.getLoggerTransactionId().replace('-', '')));
    }
}