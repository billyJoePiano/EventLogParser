/**
 * @description       : Generic Utility for updating Static Resources dynamically.  Code was originally for AssessmentQuestionRefresher, but
 *                      was abstracted to this class for general-purpose use by other classes.
 *                      The Apex test(s) for this class are:
 *                         AssessmentQuestionRefresherTest
 *                         LoggerSettingsRefresherTest
 *                         CRTUserRefresherTest
 * 
 * @author            : Bill Anderson
 * @created on        : 7-6-2026
 **/
public class StaticResourceUtil {
    public static final String JSON_CONTENT_TYPE = 'application/json';
    public static final String CSV_CONTENT_TYPE = 'text/csv';

    public final String caller;

    public StaticResourceUtil(String caller) {
        this.caller = caller;
    }

    public class Result {
        public final Boolean success;
        public final HttpRequest request;
        public final HttpResponse response;
        public final Map<String, Object> payload;
        public final Exception exc;

        public Result(Exception exc) {
            this(false, null, null, null, exc);
        }

        private Result(Boolean success, HttpRequest req, HttpResponse res, Map<String, Object> payload, Exception exc) {
            this.success = success;
            this.request = req;
            this.response = res;
            this.payload = payload;
            this.exc = exc;
        }
    }

    @TestVisible
    private static StaticResource mockResource = null;

    @TestVisible
    private static Boolean useMockResource = false;

    public static StaticResource getStaticResource(String resourceName) {
        if (useMockResource && Test.isRunningTest()) {
            return mockResource;
        }
        List<StaticResource> resources = [SELECT Id, Body FROM StaticResource WHERE Name = :resourceName];
        return resources.size() > 0 ? resources.get(0) : null;
    }

    public Result updateJsonStaticResource(String resourceName, String resourceDescription, Boolean cachePublic, Blob resourceContent) {
        return this.updateStaticResource(resourceName, resourceDescription, JSON_CONTENT_TYPE, cachePublic, resourceContent);
    }

    public Result updateCsvStaticResource(String resourceName, String resourceDescription, Boolean cachePublic, Blob resourceContent) {
        return this.updateStaticResource(resourceName, resourceDescription, CSV_CONTENT_TYPE, cachePublic, resourceContent);
    }

    public Result updateStaticResource(String resourceName, String resourceDescription, String contentType, Boolean cachePublic, Blob resourceContent) {
        HttpRequest req = null;
        HttpResponse res = null;
        Map<String, Object> payloadMetadata;
        Map<String, Object> payload;

        try {
            payloadMetadata = new Map<String, Object> {
                'contentType' => contentType,
                'cacheControl' => cachePublic ? 'Public' : 'Private',
                'description' => resourceDescription,
                'content' => EncodingUtil.base64Encode(resourceContent)
            };
            payload = new Map<String, Object> {
                'FullName' => resourceName,
                'Metadata'=> payloadMetadata
            };

            req = new HttpRequest();
            Id existingId = getStaticResource(resourceName)?.Id;
            String action;
            Integer expectedStatus;

            if (existingId == null) {
                action = 'creation';
                expectedStatus = 201;
            	req.setEndPoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v66.0/tooling/sobjects/StaticResource');
                req.setMethod('POST');
            } else {
                action = 'update';
                expectedStatus = 204;
                req.setEndPoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v66.0/tooling/sobjects/StaticResource/' + existingId);
                req.setMethod('PATCH');
            }
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

            req.setBody(JSON.serialize(payload));
            res = new Http().send(req);

            payloadMetadata.put('content', '<Body removed due to excessive length>'); //removed for logging purposes only
            req.setBody(JSON.serialize(payload));
            Boolean success = res.getStatusCode() == expectedStatus;
            if (success) {
                Logger.info(this.caller + ': ' + resourceName + ' static resource ' + action + ' successful')
                    .setHttpRequestDetails(req)
                    .setHttpResponseDetails(res);
                
            } else {
                Logger.warn(this.caller + ': ' + resourceName + ' static resource ' + action + ' FAILED')
                    .setHttpRequestDetails(req)
                    .setHttpResponseDetails(res);
            }
            Logger.saveLog();
            return new Result(success, req, res, payload, null);

        } catch (Exception e) {
            if (req != null && req.getBody() != null && req.getBody().length() > 0) {
            	payloadMetadata.put('content', '<Body removed due to excessive length>'); //removed for logging purposes only
                req.setBody(JSON.serialize(payload));
            }
            Logger.error(this.caller + ': ' + resourceName + ' static resource creation/update EXCEPTION', e)
                .setHttpRequestDetails(req)
                .setHttpResponseDetails(res);
            Logger.saveLog();
            return new Result(false, req, res, payload, e);
        }
    }

    public static Map<String, Object> stripFields(SObject obj) {
        return stripFields(obj, new List<String> {});
    }

    public static Map<String, Object> stripFields(SObject obj, List<String> fields) {
        Map<String, Object> untyped = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(obj));
        return stripFields(untyped, fields);
    }

    public static Map<String, Object> stripFields(Map<String, Object> untyped) {
        return stripFields(untyped, new List<String> {});
    }

    public static Map<String, Object> stripFields(Map<String, Object> untyped, List<String> fields) {
        untyped.remove('attributes');
        untyped.remove('Id');
        untyped.remove('IsDeleted');
        untyped.remove('CreatedDate');
        untyped.remove('CreatedById');
        untyped.remove('LastModifiedDate');
        untyped.remove('LastModifiedById');
        untyped.remove('SystemModstamp');
        for (String field : fields) {
            untyped.remove(field);
        }
        return untyped;
    }
}