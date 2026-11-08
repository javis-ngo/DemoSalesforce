public without sharing class SR_EscalateApprovalBatch
    implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime now = System.now();
        return Database.getQueryLocator([
            SELECT Id
            FROM Return_Request__c
            WHERE Status__c = :SR_StatusMachine.PENDING_APPROVAL
              AND Approval_Level__c = 'CHT'
              AND Approval_Due_At__c != null
              AND Approval_Due_At__c <= :now
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        Set<Id> requestIds = new Set<Id>();
        for (SObject row : scope) {
            requestIds.add((Id) row.get('Id'));
        }
        List<Return_Request__c> overdue =
            SR_AutomationSelector.selectOverdueChtApprovals(requestIds, System.now());
        if (overdue.isEmpty()) {
            return;
        }

        List<Return_Request__c> updates = new List<Return_Request__c>();
        List<Return_Request__c> requestsForUpdate = new List<Return_Request__c>();
        SR_Logger logger = SR_Logger.getInstance();
        for (Return_Request__c requestRecord : overdue) {
            Id regionalManagerId = requestRecord.Store__r == null
                ? null
                : requestRecord.Store__r.Regional_Manager__c;
            if (regionalManagerId == null) {
                logger.error(
                    'SR_EscalateApprovalBatch.execute',
                    'SR_EscalateApprovalBatch',
                    requestRecord.Name,
                    'Không có QLV được cấu hình cho cửa hàng; yêu cầu vẫn chờ duyệt.',
                    requestRecord.Id,
                    null
                );
                continue;
            }
            updates.add(new Return_Request__c(
                Id = requestRecord.Id,
                Approval_Level__c = 'QLV',
                Assigned_Approver__c = regionalManagerId
            ));
            requestsForUpdate.add(new Return_Request__c(
                Id = requestRecord.Id,
                Assigned_Approver__c = regionalManagerId
            ));
        }

        if (updates.isEmpty()) {
            logger.push();
            return;
        }
        List<Database.SaveResult> results = Database.update(updates, false);
        List<Return_Request__c> successfullyEscalated = new List<Return_Request__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successfullyEscalated.add(requestsForUpdate[i]);
            } else {
                for (Database.Error errorValue : results[i].getErrors()) {
                    logger.error(
                        'SR_EscalateApprovalBatch.execute',
                        'SR_EscalateApprovalBatch',
                        requestsForUpdate[i].Name,
                        errorValue.getMessage(),
                        requestsForUpdate[i].Id,
                        null
                    );
                }
            }
        }
        SR_NotificationService.notifyRegionalManagers(successfullyEscalated);
        logger.push();
    }

    public void finish(Database.BatchableContext context) {
    }
}
