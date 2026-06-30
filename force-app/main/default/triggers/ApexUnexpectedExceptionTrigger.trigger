trigger ApexUnexpectedExceptionTrigger on ApexUnexpectedException__c (before insert, before update, after insert, after update) {
    ApexUnexpectedExceptionTriggerHandler handler = new ApexUnexpectedExceptionTriggerHandler();
    if (Trigger.isInsert) {
        if (Trigger.isBefore) {
            handler.beforeInsert(Trigger.new);
        } else {
            handler.afterInsert(Trigger.new);
        }
    } else if (Trigger.isUpdate) {
        if (Trigger.isBefore) {
            handler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else {
            handler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}