public with sharing class SR_ReturnRequestTriggerHandler {
    private static Set<Id> authorizedStatusUpdateIds = new Set<Id>();

    public static void beforeUpdate(
        List<Return_Request__c> newRecords,
        Map<Id, Return_Request__c> oldMap
    ) {
        for (Return_Request__c currentRecord : newRecords) {
            Return_Request__c oldRecord = oldMap.get(currentRecord.Id);
            if (
                currentRecord.Status__c != oldRecord.Status__c &&
                !authorizedStatusUpdateIds.contains(currentRecord.Id)
            ) {
                currentRecord.Status__c.addError(
                    String.format(
                        System.Label.SR_MSG_20,
                        new List<String>{ oldRecord.Status__c, currentRecord.Status__c }
                    )
                );
            }
        }
    }

    public static void afterInsert(List<Return_Request__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<Return_Request_History__c> histories =
            new List<Return_Request_History__c>();

        for (Return_Request__c requestRecord : newRecords) {
            histories.add(new Return_Request_History__c(
                Return_Request__c = requestRecord.Id,
                From_Status__c = null,
                To_Status__c = requestRecord.Status__c,
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now(),
                Note__c = 'Initial status'
            ));
        }

        List<Database.SaveResult> results = Database.insert(
            histories,
            false,
            AccessLevel.SYSTEM_MODE
        );

        List<String> failures = new List<String>();
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                continue;
            }
            for (Database.Error errorValue : results[index].getErrors()) {
                failures.add(
                    'History row=' + index
                    + ' status=' + String.valueOf(errorValue.getStatusCode())
                    + ' fields=' + String.valueOf(errorValue.getFields())
                    + ' message=' + errorValue.getMessage()
                );
            }
        }

        if (!failures.isEmpty()) {
            throw new SR_ReturnRequestException(
                String.join(failures, '\n')
            );
        }
    }

    public static void authorizeStatusUpdates(Set<Id> requestIds) {
        authorizedStatusUpdateIds.addAll(requestIds);
    }

    public static void revokeStatusUpdates(Set<Id> requestIds) {
        authorizedStatusUpdateIds.removeAll(requestIds);
    }

    @TestVisible
    static void resetAuthorization() {
        authorizedStatusUpdateIds.clear();
    }

    public class SR_ReturnRequestException extends Exception {}

}
