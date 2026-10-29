public without sharing class SR_ExpireAwaitingGoodsBatch
    implements Database.Batchable<SObject> {

    private static final String EXPIRY_NOTE = 'Quá hạn mang hàng theo quy định';

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime now = System.now();
        return Database.getQueryLocator([
            SELECT Id
            FROM Return_Request__c
            WHERE Status__c = :SR_StatusMachine.AWAITING_GOODS
              AND Goods_Due_Date__c != null
              AND Goods_Due_Date__c <= :now
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
        List<Return_Request__c> expired =
            SR_AutomationSelector.selectExpiredAwaitingGoods(requestIds, System.now());
        if (expired.isEmpty()) {
            return;
        }

        List<SR_StatusChangeDTO> changes = new List<SR_StatusChangeDTO>();
        for (Return_Request__c requestRecord : expired) {
            SR_StatusChangeDTO change = new SR_StatusChangeDTO();
            change.requestId = requestRecord.Id;
            change.toStatus = SR_StatusMachine.CANCELLED;
            change.note = EXPIRY_NOTE;
            change.correlationId = requestRecord.Name;
            changes.add(change);
        }
        List<SR_ActionResultDTO> results = SR_StatusMachine.change(changes);
        logFailures(results, expired);
    }

    public void finish(Database.BatchableContext context) {
    }

    private static void logFailures(
        List<SR_ActionResultDTO> results,
        List<Return_Request__c> requests
    ) {
        SR_Logger logger = SR_Logger.getInstance();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i] == null || results[i].success != true) {
                logger.error(
                    'SR_ExpireAwaitingGoodsBatch.execute',
                    'SR_ExpireAwaitingGoodsBatch',
                    requests[i].Name,
                    results[i] == null ? 'Không thể hủy yêu cầu quá hạn.' : results[i].message,
                    requests[i].Id,
                    null
                );
            }
        }
        logger.push();
    }
}
