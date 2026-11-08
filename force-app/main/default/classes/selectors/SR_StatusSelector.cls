public with sharing class SR_StatusSelector {
    public static Map<Id, Return_Request__c> selectForUpdate(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) return new Map<Id, Return_Request__c>();
        return new Map<Id, Return_Request__c>([
            SELECT Id, Name, Status__c, Approval_Level__c, Assigned_Approver__c, Channel__c, Version_Token__c
            FROM Return_Request__c WHERE Id IN :ids FOR UPDATE
        ]);
    }
}
