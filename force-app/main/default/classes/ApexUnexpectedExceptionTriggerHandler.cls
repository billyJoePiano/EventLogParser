/**
 * Called from ApexUnexpectedExceptionTrigger.  Has two major functions, both are before insert/update:
 *  1) Sets the ExceptionMessageSummary__c field based on the ExceptionMessage__c field
 *  2) Sets the HasUnmappedValues__c field based on the UnmappedValues__c field
 */
public without sharing class ApexUnexpectedExceptionTriggerHandler {
    public static final String EXPECTED_MSG_PREFIX = '"Developer script exception from ' + UserInfo.getOrganizationName() + ' : ';
    public static final String ORG_URL = System.URL.getOrgDomainUrl().toExternalForm() + '/';

    public void beforeInsert(List<ApexUnexpectedException__c> newList) {
        this.populateExceptionMessageSummary(newList);
        this.setHasUnmappedValues(newList);
    }

    public void afterInsert(List<ApexUnexpectedException__c> newList) {

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
}