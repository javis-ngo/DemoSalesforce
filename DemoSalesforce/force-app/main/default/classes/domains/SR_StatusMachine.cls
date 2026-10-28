// User-facing services enforce sharing; scheduled maintenance batches use system context.
public inherited sharing class SR_StatusMachine {
    public static final String STATUS_NEW = 'NEW';        
    public static final String PENDING_APPROVAL = 'PENDING_APPROVAL';        
    public static final String AWAITING_GOODS = 'AWAITING_GOODS';        
    public static final String INSPECTING = 'INSPECTING';        
    public static final String REFUND_PROCESSING = 'REFUND_PROCESSING';        
    public static final String COMPLETED = 'COMPLETED';        
    public static final String REFUND_FAILED = 'REFUND_FAILED';        
    public static final String REJECTED = 'REJECTED';        
    public static final String CANCELLED = 'CANCELLED';        
    private static final String INVALID_TRANSITION = 'INVALID_STATUS_TRANSITION';        
    private static final String REJECTION_REASON_REQUIRED = 'REJECTION_REASON_REQUIRED';        
    private static final String INVALID_VALUE = 'INVALID_VALUE';        
    private static final String REQUEST_NOT_FOUND = 'REQUEST_NOT_FOUND';        
    private static final String DUPLICATE_REQUEST = 'DUPLICATE_REQUEST';        
    private static Map<String, String> statusLabelsByValue;        
    private static final Map<String, Set<String>> TRANSITIONS = buildTransitions();        
    public static List<SR_ActionResultDTO> change(List<SR_StatusChangeDTO> changes) {        
        List<SR_ActionResultDTO> results = new List<SR_ActionResultDTO>();        
        if (changes == null || changes.isEmpty()) {        
            return results;        
        }        
        Set<Id> requestIds = new Set<Id>();        
        Map<Id, Integer> firstIndexById = new Map<Id, Integer>();        
        for (Integer index = 0; index < changes.size(); index++) {        
            results.add(null);        
            SR_StatusChangeDTO input = changes[index];        
            if (input == null || input.requestId == null || String.isBlank(input.toStatus)) {        
                results[index] = failure(null, INVALID_VALUE, 'requestId and toStatus are required.');        
                continue;        
            }        
            if (firstIndexById.containsKey(input.requestId)) {        
                results[index] = failure(        
                    input.requestId,        
                    DUPLICATE_REQUEST,        
                    'A request can appear only once in a status-change batch.'        
                );        
                continue;        
            }        
            firstIndexById.put(input.requestId, index);        
            requestIds.add(input.requestId);        
        }        
        Map<Id, Return_Request__c> requestsById = new Map<Id, Return_Request__c>([        
            SELECT Id, Name, Status__c, Rejection_Reason__c, LastModifiedDate        
            FROM Return_Request__c        
            WHERE Id IN :requestIds        
            FOR UPDATE        
        ]);        
        List<Return_Request__c> recordsToUpdate = new List<Return_Request__c>();        
        List<Integer> updateResultIndexes = new List<Integer>();        
        List<Return_Request_History__c> histories = new List<Return_Request_History__c>();        
        List<Integer> historyResultIndexes = new List<Integer>();        
        for (Id requestId : firstIndexById.keySet()) {        
            Integer index = firstIndexById.get(requestId);        
            if (results[index] != null) {        
                continue;        
            }        
            SR_StatusChangeDTO input = changes[index];        
            Return_Request__c currentRecord = requestsById.get(requestId);        
            if (currentRecord == null) {        
                results[index] = failure(requestId, REQUEST_NOT_FOUND, 'Return request was not found.');        
                continue;        
            }        
            String toStatus = input.toStatus.trim().toUpperCase();        
            String fromStatus = currentRecord.Status__c;        
            if (!isAllowed(fromStatus, toStatus)) {        
                results[index] = failure(        
                    requestId,        
                    INVALID_TRANSITION,        
                    String.format(        
                        System.Label.SR_MSG_20,        
                        new List<String>{ fromStatus, toStatus }        
                    )        
                );        
                continue;        
            }        
            if (toStatus == REJECTED && String.isBlank(input.rejectionReason)) {        
                results[index] = failure(        
                    requestId,        
                    REJECTION_REASON_REQUIRED,        
                    System.Label.SR_MSG_12        
                );        
                continue;        
            }        
            if (fromStatus != toStatus) {        
                currentRecord.Status__c = toStatus;        
                if (toStatus == AWAITING_GOODS) {
                    currentRecord.Goods_Due_Date__c = System.now().addDays(
                        SR_Config.goodsDueDays()
                    );
                }
                if (toStatus == REJECTED) {        
                    currentRecord.Rejection_Reason__c = input.rejectionReason.trim();        
                }        
                recordsToUpdate.add(currentRecord);        
                updateResultIndexes.add(index);        
            }        
            histories.add(new Return_Request_History__c(        
                Return_Request__c = requestId,        
                From_Status__c = fromStatus,        
                To_Status__c = toStatus,        
                Changed_By__c = UserInfo.getUserId(),        
                Changed_At__c = System.now(),        
                Note__c = input.note,        
                Correlation_Id__c = input.correlationId        
            ));        
            historyResultIndexes.add(index);        
            if (fromStatus == toStatus) {        
                results[index] = success(currentRecord);        
            }        
        }        
        if (!recordsToUpdate.isEmpty()) {        
            Set<Id> authorizedIds = new Map<Id, Return_Request__c>(recordsToUpdate).keySet();        
            SR_ReturnRequestTriggerHandler.authorizeStatusUpdates(authorizedIds);        
            try {        
                List<Database.SaveResult> saveResults = Database.update(    
                    recordsToUpdate,    
                    false,    
                    AccessLevel.SYSTEM_MODE    
                );        
                for (Integer i = 0; i < saveResults.size(); i++) {        
                    Integer resultIndex = updateResultIndexes[i];        
                    if (saveResults[i].isSuccess()) {        
                        results[resultIndex] = success(recordsToUpdate[i]);        
                    } else {        
                        results[resultIndex] = failure(        
                            recordsToUpdate[i].Id,        
                            INVALID_VALUE,        
                            firstError(saveResults[i].getErrors())        
                        );        
                    }        
                }        
            } finally {        
                SR_ReturnRequestTriggerHandler.revokeStatusUpdates(authorizedIds);        
            }        
        }        
        List<Return_Request_History__c> validHistories = new List<Return_Request_History__c>();        
        List<Integer> validHistoryResultIndexes = new List<Integer>();        
        for (Integer i = 0; i < histories.size(); i++) {        
            Integer resultIndex = historyResultIndexes[i];        
            if (results[resultIndex] != null && results[resultIndex].success == true) {        
                validHistories.add(histories[i]);        
                validHistoryResultIndexes.add(resultIndex);        
            }        
        }        
        if (!validHistories.isEmpty()) {        
            List<Database.SaveResult> historyResults = Database.insert(      
                validHistories,      
                false,      
                AccessLevel.SYSTEM_MODE      
            );        
            for (Integer i = 0; i < historyResults.size(); i++) {        
                if (!historyResults[i].isSuccess()) {        
                    Integer resultIndex = validHistoryResultIndexes[i];        
                    results[resultIndex] = failure(        
                        validHistories[i].Return_Request__c,        
                        INVALID_VALUE,        
                        firstError(historyResults[i].getErrors())        
                    );        
                }        
            }        
        }        
        Set<Id> successfulIds = new Set<Id>();        
        for (SR_ActionResultDTO result : results) {        
            if (result != null && result.success == true && result.recordId != null) {        
                successfulIds.add(result.recordId);        
            }        
        }        
        if (!successfulIds.isEmpty()) {        
            Map<Id, Return_Request__c> refreshedById =    
                new Map<Id, Return_Request__c>(    
                    (List<Return_Request__c>) Database.queryWithBinds(    
                        'SELECT Id, Name, Status__c, LastModifiedDate ' +  
                        'FROM Return_Request__c WHERE Id IN :successfulIds',    
                        new Map<String, Object>{    
                            'successfulIds' => successfulIds    
                        },    
                        AccessLevel.SYSTEM_MODE    
                    )    
                );        
            for (Integer i = 0; i < results.size(); i++) {        
                if (results[i] != null && results[i].success == true) {        
                    results[i] = success(refreshedById.get(results[i].recordId));        
                }        
            }        
        }        
        return results;        
    }        
    @TestVisible        
    static Boolean isAllowed(String fromStatus, String toStatus) {        
        return TRANSITIONS.containsKey(fromStatus) && TRANSITIONS.get(fromStatus).contains(toStatus);        
    }        
    private static Map<String, Set<String>> buildTransitions() {        
        Map<String, Set<String>> result = new Map<String, Set<String>>();        
        result.put(STATUS_NEW, new Set<String>{        
            REJECTED, PENDING_APPROVAL, AWAITING_GOODS, INSPECTING, CANCELLED        
        });        
        result.put(PENDING_APPROVAL, new Set<String>{        
            AWAITING_GOODS, INSPECTING, REJECTED, PENDING_APPROVAL, CANCELLED        
        });        
        result.put(AWAITING_GOODS, new Set<String>{ INSPECTING, CANCELLED });        
        result.put(INSPECTING, new Set<String>{ REFUND_PROCESSING, REJECTED });        
        result.put(REFUND_PROCESSING, new Set<String>{ COMPLETED, REFUND_FAILED });        
        result.put(REFUND_FAILED, new Set<String>{ COMPLETED });        
        result.put(COMPLETED, new Set<String>());        
        result.put(REJECTED, new Set<String>());        
        result.put(CANCELLED, new Set<String>());        
        return result;        
    }        
    private static SR_ActionResultDTO success(Return_Request__c requestRecord) {        
        SR_ActionResultDTO result = new SR_ActionResultDTO();        
        result.success = true;        
        result.recordId = requestRecord.Id;        
        result.requestNumber = requestRecord.Name;        
        result.status = requestRecord.Status__c;        
        result.versionToken = versionTokenOf(requestRecord.LastModifiedDate);        
        return result;        
    }        
    /** Canonical optimistic-lock token, independent of user time zone. */  
    @TestVisible  
    private static String versionTokenOf(Datetime value) {  
        return value == null ? null : String.valueOf(value.getTime());  
    }  
    private static SR_ActionResultDTO failure(Id requestId, String errorCode, String message) {        
        SR_ActionResultDTO result = new SR_ActionResultDTO();        
        result.success = false;        
        result.recordId = requestId;        
        result.errorCode = errorCode;        
        result.message = message;        
        return result;        
    }        
    private static String firstError(Database.Error[] errors) {        
        return errors == null || errors.isEmpty() ? 'Unknown DML error.' : errors[0].getMessage();        
    }        
    public static String labelOf(String status) {        
        if (String.isBlank(status)) {        
            return status;        
        }        
        if (statusLabelsByValue == null) {        
            statusLabelsByValue = new Map<String, String>();        
            for (        
                Schema.PicklistEntry entry:        
                Return_Request__c.Status__c.getDescribe().getPicklistValues()        
            ) {        
                statusLabelsByValue.put(        
                    entry.getValue(),        
                    entry.getLabel()        
                );        
            }        
        }        
        String normalizedStatus = status.trim().toUpperCase();        
        return statusLabelsByValue.containsKey(normalizedStatus)        
            ? statusLabelsByValue.get(normalizedStatus)        
            : status;        
    }        
}