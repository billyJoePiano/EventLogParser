trigger ApexUnexpectedExceptionTrigger on ApexUnexpectedException__c (before insert, before update) {
    String expectedPrefix = '"Developer script exception from ' + UserInfo.getOrganizationName() + ' : ';
    for (ApexUnexpectedException__c exc : Trigger.new) {
        String msg = exc.ExceptionMessage__c;
        if (msg != null) {
            if (msg.length() >= expectedPrefix.length() && msg.substring(0, expectedPrefix.length()) == expectedPrefix) {
                msg = '"...' + msg.substring(expectedPrefix.length());
            }
            msg = msg.abbreviate(255);
        }
        exc.ExceptionMessageSummary__c = msg;
    }
}