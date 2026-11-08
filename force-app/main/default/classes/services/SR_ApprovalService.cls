public with sharing class SR_ApprovalService {  
    @AuraEnabled  
    public static SR_ApprovalPreviewResultDTO previewLevel(  
        SR_ApprovalPreviewDTO input  
    ) {  
        Store__c storeRow;  
        if (input != null && input.storeId != null) {  
            storeRow = SR_StoreSelector.selectByIds(new Set<Id>{ input.storeId }).get(input.storeId);  
        }  
        return previewLevel(input, storeRow);  
    }  
    // Overload nội bộ cho caller đã preload Store; tuyệt đối không query lại.  
    public static SR_ApprovalPreviewResultDTO previewLevel(  
        SR_ApprovalPreviewDTO input,  
        Store__c storeRow  
    ) {  
        return SR_ApprovalRouter.route(input, storeRow);  
    }  
    // API bulk để những caller mới không lặp previewLevel đơn trong loop.  
    public static List<SR_ApprovalPreviewResultDTO> previewLevels(  
        List<SR_ApprovalPreviewDTO> inputs  
    ) {  
        List<SR_ApprovalPreviewResultDTO> results =  
            new List<SR_ApprovalPreviewResultDTO>();  
        if (inputs == null || inputs.isEmpty()) {  
            return results;  
        }  
        Set<Id> storeIds = new Set<Id>();  
        for (SR_ApprovalPreviewDTO input : inputs) {  
            if (input != null && input.storeId != null) {  
                storeIds.add(input.storeId);  
            }  
        }  
        Map<Id, Store__c> storesById = SR_StoreSelector.selectByIds(storeIds);  
        for (SR_ApprovalPreviewDTO input : inputs) {  
            Store__c storeRow = input == null  
                ? null  
                : storesById.get(input.storeId);  
            results.add(SR_ApprovalRouter.route(input, storeRow));  
        }  
        return results;  
    }  
    @AuraEnabled  
    public static List<SR_ActionResultDTO> decide(  
        List<SR_ApprovalDecisionDTO> decisions  
    ) {  
        List<SR_ActionResultDTO> results = new List<SR_ActionResultDTO>();  
        if (decisions == null || decisions.isEmpty()) {  
            return results;  
        }  
        if (decisions.size() > 200) {  
            for (Integer i = 0; i < decisions.size(); i++) {  
                results.add(failure(  
                    null,  
                    SR_ErrorCode.INVALID_VALUE,  
                    'Tối đa 200 quyết định trong một lần gọi.'  
                ));  
            }  
            return results;  
        }  
        Set<Id> requestIds = new Set<Id>();  
        Set<Id> duplicatedIds = new Set<Id>();  
        for (SR_ApprovalDecisionDTO input : decisions) {  
            results.add(null);  
            if (input != null && input.requestId != null) {  
                if (!requestIds.add(input.requestId)) {  
                    duplicatedIds.add(input.requestId);  
                }  
            }  
        }  
        // Lock toàn bộ population trước khi validate business outcome.  
        Map<Id, Return_Request__c> requestsById =  
            SR_ReturnRequestSelector.selectForApprovalDecision(requestIds, true);  
        List<SR_StatusChangeDTO> changes = new List<SR_StatusChangeDTO>();  
        List<Integer> decisionIndexes = new List<Integer>();  
        Id actorId = UserInfo.getUserId();  
        for (Integer i = 0; i < decisions.size(); i++) {  
            SR_ApprovalDecisionDTO input = decisions[i];  
            if (input == null || input.requestId == null || input.approve == null) {  
                results[i] = failure(  
                    input == null ? null : input.requestId,  
                    SR_ErrorCode.MISSING_FIELD,  
                    'requestId và approve là bắt buộc.'  
                );  
                continue;  
            }  
            if (duplicatedIds.contains(input.requestId)) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.INVALID_VALUE,  
                    'Một request chỉ được xuất hiện một lần trong batch.'  
                );  
                continue;  
            }  
            Return_Request__c current = requestsById.get(input.requestId);  
            if (current == null) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.INVALID_VALUE,  
                    'Không tìm thấy yêu cầu trả hàng.'  
                );  
                continue;  
            }  
            if (current.Status__c != SR_StatusMachine.PENDING_APPROVAL) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.INVALID_STATUS_TRANSITION,  
                    'Yêu cầu không còn ở trạng thái chờ duyệt.'  
                );  
                continue;  
            }  
            if (current.Assigned_Approver__c != actorId) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.FORBIDDEN,  
                    'Chỉ người được giao duyệt mới được xử lý yêu cầu.'  
                );  
                continue;  
            }  
            if (current.CreatedById == actorId) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.FORBIDDEN,  
                    'Người tạo yêu cầu không được tự duyệt.'  
                );  
                continue;  
            }  
            if (input.approve == false && String.isBlank(input.reason)) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.MISSING_FIELD,  
                    'Bắt buộc nhập lý do từ chối.'  
                );  
                continue;  
            }  
            // Canonical token hiện tại của SR_StatusMachine là LastModifiedDate.  
            String currentVersion = versionTokenOf(current.LastModifiedDate);  
            if (String.isBlank(input.versionToken) ||  
                input.versionToken != currentVersion) {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.STALE_RECORD,  
                    'Yêu cầu đã được người khác cập nhật. Vui lòng tải lại.'  
                );  
                continue;  
            }  
            if (input.approve == true &&  
                current.Channel__c != 'APP' &&  
                current.Channel__c != 'COUNTER' &&  
                current.Channel__c != 'POS') {  
                results[i] = failure(  
                    input.requestId,  
                    SR_ErrorCode.INVALID_VALUE,  
                    'Channel của yêu cầu không hợp lệ.'  
                );  
                continue;  
            }  
            SR_StatusChangeDTO change = new SR_StatusChangeDTO();  
            change.requestId = input.requestId;  
            change.toStatus = input.approve == true  
                ? (current.Channel__c == 'APP'  
                    ? SR_StatusMachine.AWAITING_GOODS  
                    : SR_StatusMachine.INSPECTING)  
                : SR_StatusMachine.REJECTED;  
            change.rejectionReason = input.approve == true  
                ? null  
                : input.reason.trim();  
            change.note = input.approve == true  
                ? 'Approved by assigned approver'  
                : 'Rejected by assigned approver';  
            change.correlationId = SR_Correlation.newId();  
            changes.add(change);  
            decisionIndexes.add(i);  
        }  
        List<SR_ActionResultDTO> changeResults = SR_StatusMachine.change(changes);  
        for (Integer i = 0; i < changeResults.size(); i++) {  
            results[decisionIndexes[i]] = changeResults[i];  
        }  
        return results;  
    }  
    /** Canonical optimistic-lock token, independent of user time zone. */
    @TestVisible
    private static String versionTokenOf(Datetime value) {
        return value == null ? null : String.valueOf(value.getTime());
    }

    private static SR_ActionResultDTO failure(  
        Id requestId,  
        String errorCode,  
        String message  
    ) {  
        SR_ActionResultDTO result = new SR_ActionResultDTO();  
        result.success = false;  
        result.recordId = requestId;  
        result.errorCode = errorCode;  
        result.message = message;  
        return result;  
    }  
}  