public with sharing class SR_InspectionService {
    private static final String RESULT_PASSED = 'PASSED';
    private static final String RESULT_FAILED = 'FAILED';
    private static final String ALL_FAILED_REASON = 'Không đạt kiểm định';
    private static final Integer MAX_BATCH_SIZE = 200;
    private class WorkItem {
        Integer index;
        SR_InspectionRequestDTO input;
        SR_ActionResultDTO result;
        Return_Request__c requestRow;
        List<Return_Request_Line__c> lineUpdates =
            new List<Return_Request_Line__c>();
        Integer passedCount = 0;
        String targetStatus;
        String rejectionReason;
        Boolean needsRefundEnqueue = false;
    }
    @AuraEnabled
    public static List<SR_ActionResultDTO> complete(
        List<SR_InspectionRequestDTO> inputs
    ) {
        List<SR_ActionResultDTO> results = new List<SR_ActionResultDTO>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        if (inputs.size() > MAX_BATCH_SIZE) {
            for (Integer i = 0; i < inputs.size(); i++) {
                results.add(failure(
                    null,
                    SR_ErrorCode.INVALID_VALUE,
                    'Tối đa 200 yêu cầu kiểm định mỗi lần gọi.'
                ));
            }
            return results;
        }
        List<WorkItem> work = new List<WorkItem>();
        Set<Id> requestIds = new Set<Id>();
        Set<Id> duplicateRequestIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            WorkItem item = new WorkItem();
            item.index = i;
            item.input = inputs[i];
            item.result = null;
            work.add(item);
            results.add(null);
            if (item.input != null && item.input.requestId != null) {
                if (!requestIds.add(item.input.requestId)) {
                    duplicateRequestIds.add(item.input.requestId);
                }
            }
        }
        Map<Id, Return_Request__c> requestsById =
            SR_ReturnRequestSelector.selectForInspection(requestIds, true);
        Map<Id, List<Return_Request_Line__c>> linesByRequestId =
            SR_ReturnRequestSelector.selectInspectionLines(requestIds);
        Boolean payHubEnabled = SR_Config.isPayHubEnabled();
        for (WorkItem item : work) {
            validateAndPrepare(
                item,
                duplicateRequestIds,
                requestsById,
                linesByRequestId,
                payHubEnabled
            );
            if (item.result != null) {
                results[item.index] = item.result;
            }
        }
        List<Return_Request_Line__c> allLineUpdates =
            new List<Return_Request_Line__c>();
        List<WorkItem> lineOwners = new List<WorkItem>();
        for (WorkItem item : work) {
            if (item.result != null) {
                continue;
            }
            for (Return_Request_Line__c lineRow : item.lineUpdates) {
                allLineUpdates.add(lineRow);
                lineOwners.add(item);
            }
        }
        if (!allLineUpdates.isEmpty()) {
            List<Database.SaveResult> lineResults =
                updateInspectionLines(allLineUpdates);
            for (Integer i = 0; i < lineResults.size(); i++) {
                if (!lineResults[i].isSuccess()) {
                    WorkItem owner = lineOwners[i];
                    if (owner.result == null) {
                        owner.result = failure(
                            owner.input.requestId,
                            SR_ErrorCode.INVALID_VALUE,
                            firstError(lineResults[i].getErrors())
                        );
                        results[owner.index] = owner.result;
                    }
                }
            }
        }
        List<Return_Request__c> requestUpdates =
            new List<Return_Request__c>();
        List<WorkItem> requestUpdateOwners = new List<WorkItem>();
        Datetime completionTime = System.now();
        for (WorkItem item : work) {
            if (
                item.result != null
                || !String.isBlank(item.targetStatus)
            ) {
                continue;
            }
            requestUpdates.add(new Return_Request__c(
                Id = item.input.requestId,
                Inspection_Completed_At__c = completionTime
            ));
            requestUpdateOwners.add(item);
        }
        if (!requestUpdates.isEmpty()) {
            List<Database.SaveResult> updateResults =
                updateInspectionCompletionTimestamps(requestUpdates);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (!updateResults[i].isSuccess()) {
                    WorkItem owner = requestUpdateOwners[i];
                    owner.result = failure(
                        owner.input.requestId,
                        SR_ErrorCode.INVALID_VALUE,
                        firstError(updateResults[i].getErrors())
                    );
                    results[owner.index] = owner.result;
                }
            }
        }
        Set<Id> noTransitionIds = new Set<Id>();
        for (WorkItem item : work) {
            if (item.result == null && String.isBlank(item.targetStatus)) {
                noTransitionIds.add(item.input.requestId);
            }
        }
        if (!noTransitionIds.isEmpty()) {
            Map<Id, Return_Request__c> refreshedById =
                SR_ReturnRequestSelector.selectInspectionCompletionState(
                    noTransitionIds
                );
            for (WorkItem item : work) {
                if (
                    item.result != null
                    || item.input == null
                    || item.input.requestId == null
                    || !noTransitionIds.contains(item.input.requestId)
                ) {
                    continue;
                }
                Return_Request__c refreshed =
                    refreshedById.get(item.input.requestId);
                if (refreshed == null) {
                    item.result = failure(
                        item.input.requestId,
                        SR_ErrorCode.INTERNAL_ERROR,
                        'Không thể tải trạng thái yêu cầu sau khi hoàn tất kiểm định.'
                    );
                    results[item.index] = item.result;
                } else {
                    item.requestRow = refreshed;
                }
            }
        }
        List<SR_StatusChangeDTO> changes = new List<SR_StatusChangeDTO>();
        List<WorkItem> statusOwners = new List<WorkItem>();
        for (WorkItem item : work) {
            if (item.result != null || String.isBlank(item.targetStatus)) {
                continue;
            }
            SR_StatusChangeDTO change = new SR_StatusChangeDTO();
            change.requestId = item.input.requestId;
            change.toStatus = item.targetStatus;
            change.rejectionReason = item.rejectionReason;
            change.note = item.targetStatus == SR_StatusMachine.REJECTED
                ? ALL_FAILED_REASON
                : 'Inspection completed';
            change.correlationId = SR_Correlation.newId();
            changes.add(change);
            statusOwners.add(item);
        }
        List<SR_ActionResultDTO> statusResults =
            SR_StatusMachine.change(changes);
        List<Return_Request__c> transitionedCompletionUpdates =
            new List<Return_Request__c>();
        List<WorkItem> transitionedOwners = new List<WorkItem>();
        for (Integer i = 0; i < statusResults.size(); i++) {
            WorkItem item = statusOwners[i];
            SR_ActionResultDTO statusResult = statusResults[i];
            results[item.index] = statusResult;
            item.result = statusResult;
            if (statusResult.success == true) {
                transitionedCompletionUpdates.add(new Return_Request__c(
                    Id = item.input.requestId,
                    Inspection_Completed_At__c = completionTime
                ));
                transitionedOwners.add(item);
            }
        }
        Set<Id> refundRequestIds = new Set<Id>();
        if (!transitionedCompletionUpdates.isEmpty()) {
            List<Database.SaveResult> completionResults =
                updateInspectionCompletionTimestamps(
                    transitionedCompletionUpdates
                );
            Set<Id> completedTransitionIds = new Set<Id>();
            for (Integer i = 0; i < completionResults.size(); i++) {
                WorkItem item = transitionedOwners[i];
                if (!completionResults[i].isSuccess()) {
                    item.result = failure(
                        item.input.requestId,
                        SR_ErrorCode.INVALID_VALUE,
                        firstError(completionResults[i].getErrors())
                    );
                    results[item.index] = item.result;
                } else {
                    completedTransitionIds.add(item.input.requestId);
                    if (item.needsRefundEnqueue == true) {
                        refundRequestIds.add(item.input.requestId);
                    }
                }
            }
            if (!completedTransitionIds.isEmpty()) {
                Map<Id, Return_Request__c> refreshedById =
                    SR_ReturnRequestSelector.selectInspectionCompletionState(
                        completedTransitionIds
                    );
                for (WorkItem item : transitionedOwners) {
                    if (
                        !completedTransitionIds.contains(item.input.requestId)
                        || results[item.index].success != true
                    ) {
                        continue;
                    }
                    Return_Request__c refreshed =
                        refreshedById.get(item.input.requestId);
                    if (refreshed == null) {
                        item.result = failure(
                            item.input.requestId,
                            SR_ErrorCode.INTERNAL_ERROR,
                            'Không thể tải version token sau khi hoàn tất kiểm định.'
                        );
                        results[item.index] = item.result;
                        refundRequestIds.remove(item.input.requestId);
                        continue;
                    }
                    results[item.index].versionToken = versionTokenOf(
                        refreshed.LastModifiedDate
                    );
                }
            }
        }
        for (WorkItem item : work) {
            if (item.result != null) {
                continue;
            }
            item.result = successWithoutTransition(item.requestRow);
            results[item.index] = item.result;
        }
        if (!refundRequestIds.isEmpty()) {
            try {
                // FR-11 / B5: gửi PayHub bất đồng bộ (Queueable của Dev B), người dùng không phải chờ (NFR-04)
                SR_RefundService.enqueue(refundRequestIds);
            } catch (Exception ex) {
                for (WorkItem item : work) {
                    if (
                        refundRequestIds.contains(item.input.requestId)
                        && results[item.index].success == true
                    ) {
                        results[item.index] = failure(
                            item.input.requestId,
                            SR_ErrorCode.INTERNAL_ERROR,
                            'Không thể xếp hàng hoàn tiền: ' + ex.getMessage()
                        );
                    }
                }
            }
        }
        return results;
    }
    private static void validateAndPrepare(
        WorkItem item,
        Set<Id> duplicateRequestIds,
        Map<Id, Return_Request__c> requestsById,
        Map<Id, List<Return_Request_Line__c>> linesByRequestId,
        Boolean payHubEnabled
    ) {
        if (item.input == null || item.input.requestId == null) {
            item.result = failure(
                item.input == null ? null : item.input.requestId,
                SR_ErrorCode.MISSING_FIELD,
                'requestId là bắt buộc.'
            );
            return;
        }
        if (duplicateRequestIds.contains(item.input.requestId)) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.INVALID_VALUE,
                'Một request chỉ được kiểm định một lần trong batch.'
            );
            return;
        }
        item.requestRow = requestsById.get(item.input.requestId);
        if (item.requestRow == null) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.REQUEST_NOT_FOUND,
                'Không tìm thấy yêu cầu trả hàng.'
            );
            return;
        }
        if (item.requestRow.Status__c != SR_StatusMachine.INSPECTING) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.INVALID_STATUS_TRANSITION,
                'Chỉ yêu cầu ở trạng thái INSPECTING mới được hoàn tất kiểm định.'
            );
            return;
        }
        if (item.requestRow.Inspection_Completed_At__c != null) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.INVALID_STATUS_TRANSITION,
                'Kiểm định đã hoàn tất và không thể sửa lại.'
            );
            return;
        }
        if (
            String.isBlank(item.input.versionToken)
            || item.input.versionToken
                != versionTokenOf(item.requestRow.LastModifiedDate)
        ) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.STALE_RECORD,
                'Yêu cầu đã được người khác cập nhật. Vui lòng tải lại.'
            );
            return;
        }
        List<Return_Request_Line__c> persistedLines =
            linesByRequestId.get(item.input.requestId);
        if (persistedLines == null || persistedLines.isEmpty()) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.INVALID_VALUE,
                'Yêu cầu không có dòng sản phẩm để kiểm định.'
            );
            return;
        }
        if (item.input.lines == null || item.input.lines.isEmpty()) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.MISSING_FIELD,
                'Mọi dòng phải có kết quả kiểm định (MSG-22).'
            );
            return;
        }
        Map<Id, SR_InspectionLineDTO> inputByLineId =
            new Map<Id, SR_InspectionLineDTO>();
        for (SR_InspectionLineDTO lineInput : item.input.lines) {
            if (lineInput == null || lineInput.lineId == null) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.MISSING_FIELD,
                    'lineId là bắt buộc.'
                );
                return;
            }
            if (inputByLineId.containsKey(lineInput.lineId)) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.INVALID_VALUE,
                    'Một dòng chỉ được xuất hiện một lần trong kết quả kiểm định.'
                );
                return;
            }
            inputByLineId.put(lineInput.lineId, lineInput);
        }
        if (inputByLineId.size() != persistedLines.size()) {
            item.result = failure(
                item.input.requestId,
                SR_ErrorCode.MISSING_FIELD,
                'Mọi dòng phải có kết quả kiểm định (MSG-22).'
            );
            return;
        }
        for (Return_Request_Line__c persistedLine : persistedLines) {
            SR_InspectionLineDTO lineInput = inputByLineId.get(persistedLine.Id);
            if (lineInput == null) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.MISSING_FIELD,
                    'Mọi dòng phải có kết quả kiểm định (MSG-22).'
                );
                return;
            }
            String inspectionResult = normalize(lineInput.inspectionResult);
            if (
                inspectionResult != RESULT_PASSED
                && inspectionResult != RESULT_FAILED
            ) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.INVALID_VALUE,
                    'Kết quả kiểm định phải là PASSED hoặc FAILED.'
                );
                return;
            }
            if (
                inspectionResult == RESULT_FAILED
                && String.isBlank(lineInput.inspectionNote)
            ) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.MISSING_FIELD,
                    'Dòng không đạt phải có ghi chú (MSG-21).'
                );
                return;
            }
            String actualCondition = String.isBlank(lineInput.actualCondition)
                ? persistedLine.Declared_Condition__c
                : normalize(lineInput.actualCondition);
            Decimal rate = persistedLine.Refund_Rate__c;
            if (
                inspectionResult == RESULT_PASSED
                && actualCondition != persistedLine.Declared_Condition__c
            ) {
                rate = SR_RefundCalculator.rateFor(
                    persistedLine.Reason__c,
                    actualCondition
                );
            }
            if (inspectionResult == RESULT_PASSED && rate == null) {
                item.result = failure(
                    item.input.requestId,
                    SR_ErrorCode.CONFIGURATION_ERROR,
                    'Không có cấu hình tỷ lệ hoàn cho tình trạng thực tế.'
                );
                return;
            }
            Decimal actualRefund = inspectionResult == RESULT_PASSED
                ? SR_RefundCalculator.lineAmount(
                    persistedLine.Unit_Price__c,
                    persistedLine.Quantity__c,
                    rate
                )
                : 0;
            if (inspectionResult == RESULT_PASSED) {
                item.passedCount++;
            }
            item.lineUpdates.add(new Return_Request_Line__c(
                Id = persistedLine.Id,
                Actual_Condition__c = actualCondition,
                Refund_Rate__c = rate,
                Actual_Refund__c = actualRefund,
                Inspection_Result__c = inspectionResult,
                Inspection_Note__c = String.isBlank(lineInput.inspectionNote)
                    ? null
                    : lineInput.inspectionNote.trim()
            ));
        }
        if (item.passedCount == 0) {
            item.targetStatus = SR_StatusMachine.REJECTED;
            item.rejectionReason = ALL_FAILED_REASON;
        } else if (payHubEnabled) {
            item.targetStatus = SR_StatusMachine.REFUND_PROCESSING;
            item.needsRefundEnqueue = true;
        }
    }
    /**
     * Persists validated inspection outcomes using elevated field access.
     *
     * SYSTEM_MODE is intentional because Actual_Condition__c,
     * Refund_Rate__c, Actual_Refund__c, Inspection_Result__c and
     * Inspection_Note__c are workflow-controlled fields. They are written only
     * after the service has loaded the authorized request through sharing,
     * locked its canonical state, validated the optimistic-lock token and
     * confirmed that every persisted line has exactly one inspection result.
     * Direct user FLS must not partially apply or alter the domain calculation.
     */
    private static List<Database.SaveResult> updateInspectionLines(
        List<Return_Request_Line__c> lineUpdates
    ) {
        return Database.update(
            lineUpdates,
            false,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Persists the workflow-controlled inspection completion timestamp.
     *
     * SYSTEM_MODE is intentional because Inspection_Completed_At__c is managed
     * exclusively by the validated inspection workflow and must be written
     * consistently even when the inspector does not have direct edit FLS for
     * that technical field. The request has already been loaded under the
     * service's sharing context and passed status and concurrency validation.
     */
    private static List<Database.SaveResult>
        updateInspectionCompletionTimestamps(
            List<Return_Request__c> requestUpdates
        ) {
        return Database.update(
            requestUpdates,
            false,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static SR_ActionResultDTO successWithoutTransition(
        Return_Request__c requestRow
    ) {
        return SR_ActionResultDTO.successResult(
            requestRow.Id,
            requestRow.Name,
            SR_StatusMachine.INSPECTING,
            versionTokenOf(requestRow.LastModifiedDate)
        );
    }
    private static SR_ActionResultDTO failure(
        Id requestId,
        String errorCode,
        String message
    ) {
        return SR_ActionResultDTO.errorResult(
            requestId,
            null,
            errorCode,
            message,
            SR_Correlation.newId(),
            null
        );
    }
    private static String normalize(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }
    private static String versionTokenOf(Datetime value) {
        return value == null ? null : String.valueOf(value.getTime());
    }
    private static String firstError(Database.Error[] errors) {
        return errors == null || errors.isEmpty()
            ? 'Unknown DML error.'
            : errors[0].getMessage();
    }
}