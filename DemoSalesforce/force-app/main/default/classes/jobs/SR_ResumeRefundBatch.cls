public without sharing class SR_ResumeRefundBatch
    implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        Set<String> statuses = new Set<String>{
            SR_StatusMachine.INSPECTING,
            SR_StatusMachine.REFUND_PROCESSING
        };
        return Database.getQueryLocator([
            SELECT Id
            FROM Return_Request__c
            WHERE Inspection_Completed_At__c != null
              AND PayHub_Refund_Id__c = null
              AND Next_Retry_At__c = null
              AND Status__c IN :statuses
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        if (!SR_Config.isPayHubEnabled() || scope.isEmpty()) {
            return;
        }

        Set<Id> requestIds = new Set<Id>();
        for (SObject row : scope) {
            requestIds.add((Id) row.get('Id'));
        }
        List<Return_Request__c> eligible =
            SR_AutomationSelector.selectCompletedInspectionsForRefund(requestIds);
        List<SR_StatusChangeDTO> changes = new List<SR_StatusChangeDTO>();
        List<Return_Request__c> inspecting = new List<Return_Request__c>();
        Set<Id> refundRequestIds = new Set<Id>();
        for (Return_Request__c requestRecord : eligible) {
            if (requestRecord.Status__c == SR_StatusMachine.INSPECTING) {
                SR_StatusChangeDTO change = new SR_StatusChangeDTO();
                change.requestId = requestRecord.Id;
                change.toStatus = SR_StatusMachine.REFUND_PROCESSING;
                change.note = 'Tiếp tục gửi hoàn tiền sau khi bật PayHub';
                change.correlationId = requestRecord.Name;
                changes.add(change);
                inspecting.add(requestRecord);
            } else {
                refundRequestIds.add(requestRecord.Id);
            }
        }

        List<SR_ActionResultDTO> results = SR_StatusMachine.change(changes);
        SR_Logger logger = SR_Logger.getInstance();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i] != null && results[i].success == true) {
                refundRequestIds.add(inspecting[i].Id);
            } else {
                logger.error(
                    'SR_ResumeRefundBatch.execute',
                    'SR_ResumeRefundBatch',
                    inspecting[i].Name,
                    results[i] == null
                        ? 'Không thể tiếp tục yêu cầu hoàn tiền.'
                        : results[i].message,
                    inspecting[i].Id,
                    null
                );
            }
        }
        if (!refundRequestIds.isEmpty()) {
            SR_RefundService.enqueue(refundRequestIds);
        }
        logger.push();
    }

    public void finish(Database.BatchableContext context) {
    }
}
