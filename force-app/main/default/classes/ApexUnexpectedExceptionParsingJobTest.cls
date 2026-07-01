/**
 * TODO: These tests ensure code coverage, but don't enforce the expected functionality of the 2 classes under test.
 * They depend on already-existing EventLogFiles (with Apex Unexpected Exceptions) in the sandbox/org.  Ideally, there
 * should be more assertions to verify expected results, and tests should use mock CSV files designed for testing.
 */
@IsTest
public class ApexUnexpectedExceptionParsingJobTest {
    public static final ApexUnexpectedExceptionParsingJob.QueryMode AFTER_MOST_RECENT = ApexUnexpectedExceptionParsingJob.AFTER_MOST_RECENT;
    public static final ApexUnexpectedExceptionParsingJob.QueryMode ID_NOT_YET_PARSED = ApexUnexpectedExceptionParsingJob.ID_NOT_YET_PARSED;

    @IsTest
    public static void testExecuteSync1() {
        ApexUnexpectedExceptionParsingJob.DEFAULT_QUERY_MODE = AFTER_MOST_RECENT;
        new ApexUnexpectedExceptionParsingJob().executeSync();
        new ApexUnexpectedExceptionParsingJob().executeSync();
    }

    @IsTest
    public static void testExecuteSync2() {
        ApexUnexpectedExceptionParsingJob.DEFAULT_QUERY_MODE = ID_NOT_YET_PARSED;
        new ApexUnexpectedExceptionParsingJob().executeSync();
        new ApexUnexpectedExceptionParsingJob().executeSync();
    }

    @IsTest
    public static void testExecuteBatch1() {
        ApexUnexpectedExceptionParsingJob.DEFAULT_QUERY_MODE = AFTER_MOST_RECENT;
        Test.startTest();
        new ApexUnexpectedExceptionParsingJob((Integer)null).executeBatch();
        Test.stopTest();
    }

    @IsTest
    public static void testExecuteBatch2() {
        Test.startTest();
        new ApexUnexpectedExceptionParsingJob(ID_NOT_YET_PARSED).executeBatch();
        Test.stopTest();
    }

    @IsTest
    public static void testBatchableLoggerFailure() {
        List<EventLogFileParsing__c> parsings = new List<EventLogFileParsing__c> {
            new EventLogFileParsing__c(
                Id__c = '1234567890abcdefghijklmnopqrstuvwxyz' //will exceed the limit of 18 characters when inserting
            )    
        };

        // test full failure
        List<Database.SaveResult> saveResults = Database.insert(parsings, false, AccessLevel.SYSTEM_MODE);
        new ApexUnexpectedExceptionParsingJob()
            .processAndLogDatabaseSaveResults('ApexUnexpectedExceptionParsingJobTest.testBatchableLoggerFailure',
                                              EventLogFileParsing__c.SObjectType, saveResults, parsings);

        //test partial success
        parsings.add(new EventLogFileParsing__c());
        saveResults = Database.insert(parsings, false, AccessLevel.SYSTEM_MODE);
        new ApexUnexpectedExceptionParsingJob()
            .processAndLogDatabaseSaveResults('ApexUnexpectedExceptionParsingJobTest.testBatchableLoggerFailure',
                                              EventLogFileParsing__c.SObjectType, saveResults, parsings);

        // test update trigger handler code path for ApexUnexpectedException__c
        System.assert(saveResults.get(1).isSuccess());
        ApexUnexpectedException__c exc = new ApexUnexpectedException__c(
            EventLogFileParsing__c = parsings.get(1).Id,
            ExceptionMessage__c = 'test1'
        );
        Database.insert(exc, AccessLevel.SYSTEM_MODE);
        exc = [SELECT Id, ExceptionMessageSummary__c FROM ApexUnexpectedException__c WHERE Id = :exc.Id WITH SYSTEM_MODE];
        System.assertEquals('test1', exc.ExceptionMessageSummary__c);

        exc.ExceptionMessage__c = ApexUnexpectedExceptionTriggerHandler.EXPECTED_MSG_PREFIX + 'test2"';
        Database.update(exc, AccessLevel.SYSTEM_MODE);
        exc = [SELECT Id, ExceptionMessageSummary__c FROM ApexUnexpectedException__c WHERE Id = :exc.Id WITH SYSTEM_MODE];
        System.assertEquals('"... test2"', exc.ExceptionMessageSummary__c);
    }
}