/* TODO: This ensures code coverage, but doesn't enforce the expected functionality of the class under test,
 * and depends on already-existing EventLogFiles with Apex Unexpected Exceptions in the sandbox/org.
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
    }
}