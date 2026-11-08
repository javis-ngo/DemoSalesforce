public without sharing class SR_AutomationSelector {

    public static List<Return_Request__c> selectExpiredAwaitingGoods(
        Set<Id> requestIds,
        Datetime now
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<Return_Request__c>();
        }
        return [
            SELECT Id, Name, Status__c, Goods_Due_Date__c
            FROM Return_Request__c
            WHERE Id IN :requestIds
              AND Status__c = :SR_StatusMachine.AWAITING_GOODS
              AND Goods_Due_Date__c != null
              AND Goods_Due_Date__c <= :now
            FOR UPDATE
        ];
    }

    public static List<Return_Request__c> selectOverdueChtApprovals(
        Set<Id> requestIds,
        Datetime now
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<Return_Request__c>();
        }
        return [
            SELECT Id, Name, Status__c, Approval_Level__c, Assigned_Approver__c,
                Approval_Due_At__c, Store__r.Regional_Manager__c
            FROM Return_Request__c
            WHERE Id IN :requestIds
              AND Status__c = :SR_StatusMachine.PENDING_APPROVAL
              AND Approval_Level__c = 'CHT'
              AND Approval_Due_At__c != null
              AND Approval_Due_At__c <= :now
            FOR UPDATE
        ];
    }

    public static List<Return_Request__c> selectCompletedInspectionsForRefund(
        Set<Id> requestIds
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<Return_Request__c>();
        }
        Set<String> eligibleStatuses = new Set<String>{
            SR_StatusMachine.INSPECTING,
            SR_StatusMachine.REFUND_PROCESSING
        };
        return [
            SELECT Id, Name, Status__c, Inspection_Completed_At__c,
                PayHub_Refund_Id__c, Next_Retry_At__c
            FROM Return_Request__c
            WHERE Id IN :requestIds
              AND Inspection_Completed_At__c != null
              AND PayHub_Refund_Id__c = null
              AND Next_Retry_At__c = null
              AND Status__c IN :eligibleStatuses
            FOR UPDATE
        ];
    }
}
