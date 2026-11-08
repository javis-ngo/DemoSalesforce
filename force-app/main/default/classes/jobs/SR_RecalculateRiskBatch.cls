public without sharing class SR_RecalculateRiskBatch
    implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Risk_Flag__c
            FROM Account
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }
        List<Account> accounts = new List<Account>();
        Set<Id> accountIds = new Set<Id>();
        for (SObject row : scope) {
            Account accountRecord = (Account) row;
            accounts.add(accountRecord);
            accountIds.add(accountRecord.Id);
        }
        Datetime since = System.now().addDays(-SR_Config.riskWindowDays());
        Map<Id, SR_ReturnRequestSelector.RiskAggregate> aggregates =
            SR_ReturnRequestSelector.aggregateRisk(accountIds, since);

        List<Account> updates = new List<Account>();
        for (Account accountRecord : accounts) {
            SR_ReturnRequestSelector.RiskAggregate aggregate =
                aggregates.get(accountRecord.Id);
            Integer requestCount = aggregate == null ? 0 : aggregate.requestCount;
            Decimal totalAmount = aggregate == null || aggregate.totalAmount == null
                ? 0
                : aggregate.totalAmount;
            Boolean isRisky = requestCount >= SR_Config.riskRequestCount()
                || totalAmount > SR_Config.riskTotalAmount();
            if (accountRecord.Risk_Flag__c != isRisky) {
                updates.add(new Account(
                    Id = accountRecord.Id,
                    Risk_Flag__c = isRisky,
                    Risk_Flag_Updated_At__c = System.now()
                ));
            }
        }
        if (updates.isEmpty()) {
            return;
        }

        List<Database.SaveResult> results = Database.update(updates, false);
        SR_Logger logger = SR_Logger.getInstance();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error errorValue : results[i].getErrors()) {
                    logger.error(
                        'SR_RecalculateRiskBatch.execute',
                        'SR_RecalculateRiskBatch',
                        null,
                        errorValue.getMessage(),
                        updates[i].Id,
                        null
                    );
                }
            }
        }
        logger.push();
    }

    public void finish(Database.BatchableContext context) {
    }
}
