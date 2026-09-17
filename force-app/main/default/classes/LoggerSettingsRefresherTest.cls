@IsTest
public class LoggerSettingsRefresherTest {
    public static final String STATIC_RESOURCE_NAME = LoggerSettingsRefresher.STATIC_RESOURCE_NAME;
    public static final String MOCK_RESOURCE = '{"LoggingLevel__c":"DEBUG","IsSavingEnabled__c":true,"IsRecordFieldStrippingEnabled__c":false,"IsJavaScriptLightningLoggerEnabled__c":false,"IsJavaScriptConsoleLoggingEnabled__c":false,"IsEnabled__c":true,"IsDataMaskingEnabled__c":true,"IsApexSystemDebugLoggingEnabled__c":false,"IsAnonymousModeEnabled__c":false,"DefaultSaveMethod__c":"EVENT_BUS","DefaultPlatformEventStorageLocation__c":"CUSTOM_OBJECTS","DefaultLogShareAccessLevel__c":"Read","DefaultLogPurgeAction__c":"Delete"}';
    
    public static void assertRequest(HttpMock mock) {
        assertRequest(mock, '');
    }

    public static void assertRequest(HttpMock mock, String urlSuffix) {
        Boolean callout = false;
        String url = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v66.0/tooling/sobjects/StaticResource' + urlSuffix;
        for (HttpRequest request : mock.requests) {
            if (request.getEndpoint() == url) {
                callout = true;
            }
        }
        System.assert(callout, 'Callout expected to URL ' + url + ' , actual number of callouts: ' + mock.requests.size());
    }
    
    public static LogEntry__c getLogEntry1() {
        List<LogEntry__c> entries = [SELECT Id, Message__c, LoggingLevel__c
                                     FROM LogEntry__c
                                     WHERE OriginLocation__c = 'StaticResourceUtil.updateStaticResource'
                                     AND LoggingLevelOrdinal__c > 2
                                     ORDER BY Timestamp__c DESC
                                     LIMIT 1];
        if (entries.size() < 1) return null;
        else return entries.get(0);
    }

    public static void assertLogEntry1(LogEntry__c before, String loggingLevel, String messageSuffix) {
        LogEntry__c after = getLogEntry1();
        System.assertNotEquals(null, after, 'Expected new log entry');
        if (before != null) {
            System.assertNotEquals(before.Id, after.Id, 'Expected new log entry');
        }
        System.assertEquals(loggingLevel, after.LoggingLevel__c);
        System.assertEquals('LoggerSettingsRefresher.updateStaticResource: ' + STATIC_RESOURCE_NAME + ' static resource ' + messageSuffix, after.Message__c);
    }

    public static LogEntry__c getLogEntry2() {
        List<LogEntry__c> entries = getLogEntry2(1);
        if (entries.size() < 1) return null;
        else return entries.get(0);
    }

    public static List<LogEntry__c> getLogEntry2(Integer count) {
        return [SELECT Id, Message__c, LoggingLevel__c, Log__c
                FROM LogEntry__c
                WHERE OriginLocation__c = 'LoggerSettingsRefresher.populateFromStaticResource'
                AND LoggingLevelOrdinal__c > 2
                ORDER BY Timestamp__c DESC
                LIMIT :count];
    }

    public static void assertLogEntry2(LogEntry__c before, String loggingLevel, String messageSuffix) {
        assertLogEntry2(before, getLogEntry2(), loggingLEvel, messageSuffix);
    }

    public static void assertLogEntry2(LogEntry__c before, LogEntry__c after, String loggingLevel, String messageSuffix) {
        System.assertNotEquals(null, after, 'Expected new log entry');
        if (before != null) {
            System.assertNotEquals(before.Id, after.Id, 'Expected new log entry');
        }
        System.assertEquals(loggingLevel, after.LoggingLevel__c);
        System.assertEquals('LoggerSettingsRefresher.populateFromStaticResource: ' + messageSuffix, after.Message__c);
    }

    public static void insertLoggerSettingsRecord() {
        Id setupOwnerId = UserInfo.getOrganizationId();
        LoggerSettings__c newOrgSettings = (LoggerSettings__c)JSON.deserialize(MOCK_RESOURCE, LoggerSettings__c.class);
        LoggerSettings__c existingOrgSettings = LoggerSettings__c.getValues(setupOwnerId);
        if (existingOrgSettings != null) {
            newOrgSettings.Id = existingOrgSettings.Id;
        }
        newOrgSettings.SetupOwnerId = setupOwnerId;
        Database.upsert(newOrgSettings, System.AccessLevel.SYSTEM_MODE);
    }

    @IsTest(seeAllData=true)
    public static void testCreateStaticResourceSuccess() {
        StaticResourceUtil.useMockResource = true;
        StaticResourceUtil.mockResource = null;
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock(201);

        Test.startTest();
        LoggerSettingsRefresher.updateStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertRequest(mock);
        assertLogEntry1(before, 'INFO', 'creation successful');
    }

    @IsTest(seeAllData=true)
    public static void testUpdateStaticResourceSuccess() {
        StaticResource resource = StaticResourceUtil.getStaticResource(STATIC_RESOURCE_NAME);
        if (resource == null) {
            resource = new StaticResource(Id = new Random().id(StaticResource.sObjectType));
        }
        StaticResourceUtil.mockResource = resource;
        StaticResourceUtil.useMockResource = true;
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock(204);

        Test.startTest();
        LoggerSettingsRefresher.updateStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertRequest(mock, '/' + resource.Id);
        assertLogEntry1(before, 'INFO', 'update successful');
    }

    @IsTest
    public static void testStaticResource400Status() {
        insertLoggerSettingsRecord();

        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;        
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock(400);

        Test.startTest();
        LoggerSettingsRefresher.updateStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertRequest(mock);
        assertLogEntry1(before, 'WARN', 'creation FAILED');
    }

    @IsTest
    public static void testUpdateStaticResourceException() {
        insertLoggerSettingsRecord();

        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock.ExceptionThrower();

        Test.startTest();
        StaticResourceUtil.Result result = LoggerSettingsRefresher.updateStaticResource();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertNotEquals(null, result.exc);
        System.assert(result.exc instanceof CalloutException);
        assertRequest(mock);
        assertLogEntry1(before, 'ERROR', 'creation/update EXCEPTION');
    }

    @IsTest(seeAllData=true)
    public static void testPopulateLoggerSettingsFromStaticResource() {
        StaticResourceUtil.mockResource = new StaticResource(Body = Blob.valueof(MOCK_RESOURCE));
        StaticResourceUtil.useMockResource = true;
        LoggerSettingsRefresher.runUpserts = true;

        LogEntry__c before = getLogEntry2();

        Test.startTest();
        LoggerSettingsRefresher.populateFromStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        AssertLogEntry2(before, 'INFO', 'Successful');
    }

	@IsTest
    public static void testStaticResourceMissing() {
        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;

        LogEntry__c before = getLogEntry2();

        Test.startTest();
        LoggerSettingsRefresher.populateFromStaticResource();
        Test.getEventBus().deliver();
        Test.stopTest();

        AssertLogEntry2(before, 'WARN', 'No static resource found named ' + STATIC_RESOURCE_NAME);
    }
    
    @IsTest
    public static void testStaticResourceInvalid() {
        StaticResourceUtil.mockResource = new StaticResource(Body = Blob.valueOf('INVALID JSON'));
        StaticResourceUtil.useMockResource = true;
        LogEntry__c before = getLogEntry2();

        Test.startTest();
        try {
            LoggerSettingsRefresher.populateFromStaticResource();
            System.assert(false, 'Expected JSONException');
        } catch (JSONException e) { }
        Test.getEventBus().deliver();
        Test.stopTest();

        AssertLogEntry2(before, 'ERROR', 'EXCEPTION');
    }
}