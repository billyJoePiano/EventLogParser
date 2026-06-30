public class ApexUnexpectedExceptionTriggerHandler {
    public void beforeInsert(List<ApexUnexpectedException__c> newList) {
        this.populateExceptionMessageSummary(newList);
    }

    public void afterInsert(List<ApexUnexpectedException__c> newList) {

    }

    public void beforeUpdate(List<ApexUnexpectedException__c> newList, Map<Id, ApexUnexpectedException__c> oldMap) {
        this.populateExceptionMessageSummary(newList);
    }

    public void afterUpdate(List<ApexUnexpectedException__c> newList, Map<Id, ApexUnexpectedException__c> oldMap) {

    }

    public void populateExceptionMessageSummary(List<ApexUnexpectedException__c> newList) {
        String expectedPrefix = '"Developer script exception from ' + UserInfo.getOrganizationName() + ' : ';
        for (ApexUnexpectedException__c exc : newList) {
            String msg = exc.ExceptionMessage__c;
            if (msg != null) {
                if (msg.length() >= expectedPrefix.length() && msg.substring(0, expectedPrefix.length()) == expectedPrefix) {
                    msg = '"... ' + msg.substring(expectedPrefix.length());
                }
                msg = msg.abbreviate(255);
            }
            exc.ExceptionMessageSummary__c = msg;
        }
    }
}