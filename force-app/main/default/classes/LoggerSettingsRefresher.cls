/**
 * Populates the LoggerSettings__c using data in the static resource LoggerSettings.
 */
public class LoggerSettingsRefresher {
    public static final String STATIC_RESOURCE_NAME = 'LoggerSettings';
    public static final String STATIC_RESOURCE_DESCRIPTION = 'LeggerSettings__c data that controls Nebula Logger, used to repopulate settings after sandbox refreshes.  See Apex class LoggerSettingsRefresher';

    @TestVisible
    private static Boolean runUpserts = !Test.isRunningTest();

    @Future(callout=true)
    public static void updateStaticResourceAsync() {
        updateStaticResource();
    }

    public static StaticResourceUtil.Result updateStaticResource() {
        try {
            Id setupOwnerId = UserInfo.getOrganizationId();
            LoggerSettings__c orgSettings = LoggerSettings__c.getValues(setupOwnerId);

            Map<String, Object> untyped = StaticResourceUtil.stripFields(orgSettings, new List<String> {'Name', 'SetupOwnerId'});

            return new StaticResourceUtil('LoggerSettingsRefresher.updateStaticResource')
                .updateJsonStaticResource(STATIC_RESOURCE_NAME, STATIC_RESOURCE_DESCRIPTION, false, Blob.valueOf(JSON.serialize(untyped)));
        } catch (Exception e) {
            Logger.error('LoggerSettingsRefresher.updateStaticResource: ' + STATIC_RESOURCE_NAME + ' EXCEPTION', e);
            Logger.saveLog();
            return new StaticResourceUtil.Result(e);
        }
    }

    @Future
    public static void populateFromStaticResourceAsync() {
        populateFromStaticResource();
    }

    public static void populateFromStaticResource() {
        try {
            StaticResource resource = StaticResourceUtil.getStaticResource(STATIC_RESOURCE_NAME);
            if (resource == null) {
                Logger.warn('LoggerSettingsRefresher.populateFromStaticResource: No static resource found named ' + STATIC_RESOURCE_NAME);
                Logger.saveLog();
                return;
            }

            Id setupOwnerId = UserInfo.getOrganizationId();
            LoggerSettings__c newOrgSettings = (LoggerSettings__c)JSON.deserialize(resource.Body.toString(), LoggerSettings__c.class);
            LoggerSettings__c existingOrgSettings = LoggerSettings__c.getValues(setupOwnerId);
            if (existingOrgSettings != null) {
                newOrgSettings.Id = existingOrgSettings.Id;
            }
            newOrgSettings.SetupOwnerId = setupOwnerId;
            if (runUpserts) {
                Database.upsert(newOrgSettings, System.AccessLevel.SYSTEM_MODE);
            }

            //Log success
            Logger.info('LoggerSettingsRefresher.populateFromStaticResource: Successful');
			Logger.saveLog();

        } catch (Exception e) {
            Logger.error('LoggerSettingsRefresher.populateFromStaticResource: EXCEPTION', e);
            Logger.saveLog();
            throw e;
        }
    }
}