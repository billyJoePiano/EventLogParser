@IsTest
public class CRTUserRefresherTest {
    public static final String STATIC_RESOURCE_NAME = CRTUserRefresher.STATIC_RESOURCE_NAME;
    public static final String MOCK_RESOURCE = '''
[
    {
        "PublicGroups": [
            "CRT_Test_Users"
        ],
        "PermissionSetAssignments": {
            "records": []
        },
        "Profile": {
            "Name": "System Administrator"
        },
        "LanguageLocaleKey": "en_US",
        "EmailEncodingKey": "UTF-8",
        "LocaleSidKey": "en_US",
        "TimeZoneSidKey": "America/New_York",
        "Alias": "crtadmin",
        "Email": "famli.qa+admin@maryland.gov",
        "LastName": "Test",
        "FirstName": "CRT Admin",
        "Username": "crtadmin.test@maryland.gov.mdfamli"
    },
    {
        "PublicGroups": [],
        "UserRole": {
            "DeveloperName": "Customer_Care_Agent"
        },
        "Profile": {
            "Name": "Minimum Access - Salesforce"
        },
        "PermissionSetAssignments": {
            "records": [
                {
                    "PermissionSet": {
                        "Name": "Customer_Care_Agent"
                    }
                }
            ]
        },
        "LanguageLocaleKey": "en_US",
        "EmailEncodingKey": "UTF-8",
        "LocaleSidKey": "en_US",
        "TimeZoneSidKey": "America/New_York",
        "Alias": "ccagent",
        "Email": "famli.qa+customercareagent@maryland.gov",
        "LastName": "Test",
        "FirstName": "Customer Care Agent",
        "Username": "customer.care.agent.test@maryland.gov.mdfamli"
    },
    {
        "PublicGroups": [
            "CRT_Test_Users"
        ],
        "UserRole": {
            "DeveloperName": "Product"
        },
        "Profile": {
            "Name": "Minimum Access - Salesforce"
        },
        "PermissionSetAssignments": {
            "records": [
                {
                    "PermissionSet": {
                        "PermissionSetGroup": {
                            "DeveloperName": "DigitalServices_ProductReadOnly"
                        }
                    }
                },
                {
                    "PermissionSet": {
                        "Name": "Customer_Care_Agent"
                    }
                }
            ]
        },
        "LanguageLocaleKey": "en_US",
        "EmailEncodingKey": "UTF-8",
        "LocaleSidKey": "en_US",
        "TimeZoneSidKey": "America/New_York",
        "Alias": "product",
        "Email": "famli.qa+product@maryland.gov",
        "LastName": "Test",
        "FirstName": "Product",
        "Username": "product.test@maryland.gov.mdfamli"
    },
    {
        "PublicGroups": [
            "CRT_Test_Users"
        ],
        "UserRole": {
            "DeveloperName": "Product"
        },
        "Profile": {
            "Name": "Minimum Access - Salesforce"
        },
        "PermissionSetAssignments": {
            "records": [
                {
                    "PermissionSet": {
                        "PermissionSetGroup": {
                            "DeveloperName": "DigitalServices_ProductReadOnly"
                        }
                    }
                },
                {
                    "PermissionSet": {
                        "Name": "Customer_Care_Agent"
                    }
                }
            ]
        },
        "LanguageLocaleKey": "en_US",
        "EmailEncodingKey": "UTF-8",
        "LocaleSidKey": "en_US",
        "TimeZoneSidKey": "America/New_York",
        "Alias": "nonexist",
        "Email": "famli.qa+nonexistentuser@maryland.gov",
        "LastName": "Test",
        "FirstName": "Nonexistent",
        "Username": "nonexistent.test@maryland.gov.mdfamli"
    }
]''';

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
        System.assertEquals('CRTUserRefresher.updateStaticResource: ' + STATIC_RESOURCE_NAME + ' static resource ' + messageSuffix, after.Message__c);
    }

    public static LogEntry__c getLogEntry2() {
        List<LogEntry__c> entries = getLogEntry2(1);
        if (entries.size() < 1) return null;
        else return entries.get(0);
    }

    public static List<LogEntry__c> getLogEntry2(Integer count) {
        return [SELECT Id, Message__c, LoggingLevel__c, Log__c
                FROM LogEntry__c
                WHERE OriginLocation__c = 'CRTUserRefresher.populateFromStaticResource'
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
        System.assertEquals('CRTUserRefresher.populateFromStaticResource: ' + messageSuffix, after.Message__c);
    }

    @IsTest
    public static void testCreateStaticResourceSuccess() {
        StaticResourceUtil.useMockResource = true;
        
        //populate with users from mock resource first
        StaticResourceUtil.mockResource = new StaticResource(Body = Blob.valueOf(MOCK_RESOURCE));
        CRTUserRefresher.logAfterPopulate = false;
        CRTUserRefresher.populateFromStaticResource();
        CRTUserRefresher.logAfterPopulate = true;
        
        StaticResourceUtil.mockResource = null;
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock(201);

        Test.startTest();
        CRTUserRefresher.updateStaticResourceAsync();
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
        CRTUserRefresher.updateStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertRequest(mock, '/' + resource.Id);
        assertLogEntry1(before, 'INFO', 'update successful');
    }

    @IsTest
    public static void testStaticResource400Status() {
        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;        
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock(400);

        Test.startTest();
        CRTUserRefresher.updateStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        assertRequest(mock);
        assertLogEntry1(before, 'WARN', 'creation FAILED');
    }

    @IsTest
    public static void testUpdateStaticResourceException() {
        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;
        LogEntry__c before = getLogEntry1();
        HttpMock mock = new HttpMock.ExceptionThrower();

        Test.startTest();
        StaticResourceUtil.Result result = CRTUserRefresher.updateStaticResource();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertNotEquals(null, result.exc);
        System.assert(result.exc instanceof CalloutException);
        assertRequest(mock);
        assertLogEntry1(before, 'ERROR', 'creation/update EXCEPTION');
    }

    @IsTest(seeAllData=true)
    public static void testPopulateUsersFromStaticResource() {
        StaticResourceUtil.mockResource = new StaticResource(Body = Blob.valueof(MOCK_RESOURCE));
        StaticResourceUtil.useMockResource = true;

        LogEntry__c before = getLogEntry2();

        Test.startTest();
        CRTUserRefresher.populateFromStaticResourceAsync();
        Test.getEventBus().deliver();
        Test.stopTest();

        AssertLogEntry2(before, 'INFO', 'success adding/updating users');
    }

	@IsTest
    public static void testStaticResourceMissing() {
        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;

        LogEntry__c before = getLogEntry2();

        Test.startTest();
        CRTUserRefresher.populateFromStaticResource();
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
            CRTUserRefresher.populateFromStaticResource();
            System.assert(false, 'Expected JSONException');
        } catch (JSONException e) { }
        Test.getEventBus().deliver();
        Test.stopTest();
        
        AssertLogEntry2(before, 'ERROR', 'EXCEPTION');
    }
}