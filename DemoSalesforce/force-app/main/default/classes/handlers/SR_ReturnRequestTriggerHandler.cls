public with sharing class SR_ReturnRequestTriggerHandler {
    private static Map<Id, Integer> authorizedStatusUpdateDepthById = new Map<Id, Integer>();

    public static void authorizeStatusUpdates(Set<Id> requestIds) {
        if (requestIds == null) {
            return;
        }
        for (Id requestId : requestIds) {
            Integer depth = authorizedStatusUpdateDepthById.get(requestId);
            authorizedStatusUpdateDepthById.put(requestId, depth == null ? 1 : depth + 1);
        }
    }

    public static void revokeStatusUpdates(Set<Id> requestIds) {
        if (requestIds == null) {
            return;
        }
        for (Id requestId : requestIds) {
            Integer depth = authorizedStatusUpdateDepthById.get(requestId);
            if (depth == null || depth <= 1) {
                authorizedStatusUpdateDepthById.remove(requestId);
            } else {
                authorizedStatusUpdateDepthById.put(requestId, depth - 1);
            }
        }
    }

    public static void beforeUpdate(
        List<Return_Request__c> newRecords,
        Map<Id, Return_Request__c> oldMap
    ) {
        for (Return_Request__c newRecord : newRecords) {
            Return_Request__c oldRecord = oldMap.get(newRecord.Id);
            if (
                oldRecord != null
                && oldRecord.Status__c != newRecord.Status__c
                && !authorizedStatusUpdateDepthById.containsKey(newRecord.Id)
            ) {
                newRecord.Status__c.addError(
                    String.format(
                        System.Label.SR_MSG_20,
                        new List<String>{ oldRecord.Status__c, newRecord.Status__c }
                    )
                );
            }
        }
    }

    public static void afterInsert(List<Return_Request__c> newRecords) {
        List<Return_Request_History__c> histories = new List<Return_Request_History__c>();
        Datetime changedAt = System.now();
        Id changedBy = UserInfo.getUserId();

        for (Return_Request__c requestRecord : newRecords) {
            histories.add(new Return_Request_History__c(
                Return_Request__c = requestRecord.Id,
                From_Status__c = null,
                To_Status__c = requestRecord.Status__c,
                Changed_By__c = changedBy,
                Changed_At__c = changedAt,
                Note__c = 'Initial status'
            ));
        }

        if (!histories.isEmpty()) {
            // Mandatory audit data: an error must roll back the parent request insert.
            Database.insert(histories, true, AccessLevel.SYSTEM_MODE);
        }

        // Màn hình duyệt (D.2) tự hiện yêu cầu mới. Publish After Commit: insert rollback thì không gửi.
        SR_EventPublisher.publishChanges(newRecords, null);
    }

    public static void afterUpdate(
        List<Return_Request__c> newRecords,
        Map<Id, Return_Request__c> oldMap
    ) {
        // Màn hình duyệt (D.2) tự làm mới dòng: đổi trạng thái, người duyệt, số tiền...
        SR_EventPublisher.publishChanges(newRecords, oldMap);
    }
}
