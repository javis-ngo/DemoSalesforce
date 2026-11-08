trigger ReturnRequestTrigger on Return_Request__c (before update, after insert, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        SR_ReturnRequestTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        SR_ReturnRequestTriggerHandler.afterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        SR_ReturnRequestTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
