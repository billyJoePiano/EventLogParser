/**
 * Called from ApexUnexpectedExceptionTrigger.  Has two major functions:
 *  1) Before insert/update: Sets the ExceptionMessageSummary__c field based on the ExceptionMessage__c field,
 *     and sets the HasUnmappedValues__c field based on the UnmappedValues__c field.
 *  2) After insert, Sends message to Slack channel using SlackServiceUtil, with summary of the Exceptions
 */
public without sharing class ApexUnexpectedExceptionTriggerHandler {
    public static final String EXPECTED_MSG_PREFIX = '"Developer script exception from ' + UserInfo.getOrganizationName() + ' : ';
    public static final String ORG_URL = System.URL.getOrgDomainUrl().toExternalForm() + '/';

    public void beforeInsert(List<ApexUnexpectedException__c> newList) {
        this.populateExceptionMessageSummary(newList);
        this.setHasUnmappedValues(newList);
    }

    public void afterInsert(List<ApexUnexpectedException__c> newList) {
        this.sendSlackMsgs(newList);
    }

    public void beforeUpdate(List<ApexUnexpectedException__c> newList, Map<Id, ApexUnexpectedException__c> oldMap) {
        this.populateExceptionMessageSummary(newList);
        this.setHasUnmappedValues(newList);
    }

    public void afterUpdate(List<ApexUnexpectedException__c> newList, Map<Id, ApexUnexpectedException__c> oldMap) {

    }

    public void populateExceptionMessageSummary(List<ApexUnexpectedException__c> newList) {
        for (ApexUnexpectedException__c exc : newList) {
            String msg = exc.ExceptionMessage__c;
            if (msg != null) {
                if (msg.length() >= EXPECTED_MSG_PREFIX.length() && msg.substring(0, EXPECTED_MSG_PREFIX.length()) == EXPECTED_MSG_PREFIX) {
                    msg = '"... ' + msg.substring(EXPECTED_MSG_PREFIX.length());
                }
                msg = msg.abbreviate(255);
            }
            exc.ExceptionMessageSummary__c = msg;
        }
    }

    public void setHasUnmappedValues(List<ApexUnexpectedException__c> newList) {
        for (ApexUnexpectedException__c exc : newList) {
            exc.HasUnmappedValues__c = exc.UnmappedValues__c != null && exc.UnmappedValues__c.length() > 0;
        }
    }

    public void sendSlackMsgs(List<ApexUnexpectedException__c> newList) {
        Set<Id> userIds = new Set<Id>();
        for (ApexUnexpectedException__c exc : newList) {
            if (exc.User__c != null) {
                userIds.add(exc.User__c);
            }
        }
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :userIds]);

        List<String> msgs = new List<String>();
        for (ApexUnexpectedException__c exc : newList) {
            msgs.add(generateSlackMsg(exc, users.get(exc.User__c)));
        }
        SlackServiceUtil.slackMsg(String.join(msgs, '\n\n\n'));
    }
    
    public static String generateSlackMsg(ApexUnexpectedException__c exc, User usr) {
        List<String> lines = new List<String>();
        lines.add(exc.EventType__c);
        lines.add(ORG_URL + exc.Id);
        if (usr != null) {
            lines.add('User: ' + usr.Name);
        } else {
            lines.add('User Id (unrecognized): ' + JSON.serialize(exc.UserId__c));
        }
        if (exc.Timestamp__c != null) {
            lines.add('Timestamp: ' + exc.Timestamp__c.format('yyyy-MM-dd HH:mm:ss', 'America/New_York') + ' (Eastern Time)');
        }
        addIfNotBlank(lines, 'Exception Type: ', exc.ExceptionType__c);
        addIfNotBlank(lines, 'Apex Entity Name: ', exc.ApexEntityName__c);
        addIfNotBlank(lines, 'Exception Message:\n', exc.ExceptionMessage__c);
        addIfNotBlank(lines, 'Stack Trace:\n', exc.StackTrace__c);
        return String.join(lines, '\n');
    }

    public static void addIfNotBlank(List<String> lines, String label, String value) {
        if (value != null && value.length() > 0) {
            lines.add(label + value);
        }
    }
}