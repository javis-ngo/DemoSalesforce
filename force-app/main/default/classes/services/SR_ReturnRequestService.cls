public with sharing class SR_ReturnRequestService {
    public static final String CHANNEL_COUNTER = 'COUNTER';
    public static final String CHANNEL_POS = 'POS';
    public static final String CHANNEL_APP = 'APP';

    private static final Set<String> CHANNELS = new Set<String>{ CHANNEL_COUNTER, CHANNEL_POS, CHANNEL_APP };
    private static final Set<String> REASONS = new Set<String>{ 'DEFECT', 'WRONG_ITEM', 'NOT_SATISFIED', 'CUSTOMER_DAMAGE' };
    private static final Set<String> CONDITIONS = new Set<String>{ 'SEALED', 'OPENED', 'USED' };

    private class WorkItem {
        Integer index;
        SR_CreateRequestDTO input;
        SR_CreateResultDTO result;
        Order orderRow;
        Store__c storeRow;
        Return_Request__c requestRow;
        List<Return_Request_Line__c> lineRows = new List<Return_Request_Line__c>();
        List<SR_LineCreateResultDTO> lineResults = new List<SR_LineCreateResultDTO>();
        Decimal total = 0;
        Boolean risk;
        SR_ApprovalPreviewResultDTO route;
    }

    @AuraEnabled(cacheable=true)
    public static List<SR_ReturnableLineDTO> getReturnableLines(Id orderId) {
        return getReturnableOrder(orderId).lines;
    }

    @AuraEnabled(cacheable=true)
    public static SR_ReturnableOrderDTO getReturnableOrder(Id orderId) {
        SR_ReturnableOrderDTO result = new SR_ReturnableOrderDTO();
        if (orderId == null) {
            return result;
        }
        Order orderRow = SR_OrderSelector.selectByIds(new Set<Id>{ orderId }, false).get(orderId);
        if (orderRow == null) {
            return result;
        }

        result.orderId = orderRow.Id;
        result.orderNumber = orderRow.OrderNumber;
        result.customerName = orderRow.Account == null ? null : orderRow.Account.Name;
        result.customerPhone = orderRow.Account == null ? null : orderRow.Account.Phone;
        result.purchaseDate = orderRow.EffectiveDate;
        result.deliveryDate = orderRow.Delivery_Date__c;
        result.storeId = orderRow.Store__c;
        result.storeCode = orderRow.Store__r == null ? null : orderRow.Store__r.Store_Code__c;
        result.storeName = orderRow.Store__r == null ? null : orderRow.Store__r.Name;

        Set<Id> itemIds = new Set<Id>();
        for (OrderItem item : orderRow.OrderItems) {
            itemIds.add(item.Id);
        }
        Map<Id, Decimal> reserved = SR_ReturnRequestSelector.sumReservedQuantity(itemIds);
        Date todayValue = Date.today();

        for (OrderItem item : orderRow.OrderItems) {
            SR_ReturnableLineDTO dto = baseLine(orderRow, item);
            SR_ReturnEligibilityService.populateLine(dto, orderRow, item, reserved, todayValue);
            result.lines.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static SR_ApprovalPreviewResultDTO previewCreate(SR_CreateRequestDTO request) {
        WorkItem item = prepareWorkItem(request, false);
        SR_ApprovalPreviewResultDTO preview = new SR_ApprovalPreviewResultDTO();
        if (item.result.errors.isEmpty() != true) {
            preview.success = false;
            preview.errorCode = item.result.errors[0].code;
            preview.message = item.result.errors[0].message;
            preview.errors.addAll(item.result.errors);
            return preview;
        }
        preview.success = true;
        preview.approvalLevel = item.route.approvalLevel;
        preview.assignedApproverId = item.route.assignedApproverId;
        preview.targetStatus = item.route.targetStatus;
        preview.estimatedRefund = item.total;
        preview.riskFlag = item.risk;
        preview.lines.addAll(item.lineResults);
        return preview;
    }

    @AuraEnabled
    public static List<SR_CreateResultDTO> createRequests(List<SR_CreateRequestDTO> requests) {
        Savepoint unexpectedFailureBoundary = Database.setSavepoint();
        SR_Logger logger = SR_Logger.getInstance();
        try {
            return doCreateRequests(requests);
        } catch (Exception ex) {
            Database.rollback(unexpectedFailureBoundary);
            String correlationId = SR_Correlation.newId();
            logger.error(
                'SR_ReturnRequestService.createRequests',
                'createRequests',
                correlationId,
                'requestCount=' + (requests == null ? 0 : requests.size()) + ' | ' + ex.getMessage(),
                null,
                ex.getStackTraceString()
            );
            List<SR_CreateResultDTO> failures = new List<SR_CreateResultDTO>();
            Integer resultCount = requests == null || requests.isEmpty() ? 1 : requests.size();
            for (Integer i = 0; i < resultCount; i++) {
                SR_CreateResultDTO failure = new SR_CreateResultDTO();
                failure.correlationId = correlationId;
                addError(
                    failure,
                    null,
                    SR_ErrorCode.INTERNAL_ERROR,
                    SR_ErrorCode.message(SR_ErrorCode.INTERNAL_ERROR) + ' Mã log: ' + correlationId
                );
                failures.add(failure);
            }
            return failures;
        } finally {
            logger.push();
        }
    }

    private static List<SR_CreateResultDTO> doCreateRequests(List<SR_CreateRequestDTO> requests) {
        List<SR_CreateResultDTO> results = new List<SR_CreateResultDTO>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        if (requests.size() > 200) {
            for (Integer i = 0; i < requests.size(); i++) {
                SR_CreateResultDTO tooMany = new SR_CreateResultDTO();
                addError(tooMany, null, SR_ErrorCode.INVALID_VALUE, 'Tối đa 200 yêu cầu mỗi lần gọi.');
                results.add(tooMany);
            }
            return results;
        }

        List<WorkItem> work = new List<WorkItem>();
        Set<Id> orderIds = new Set<Id>();
        Set<String> orderNumbers = new Set<String>();
        Set<String> externalIds = new Set<String>();
        Set<String> storeCodes = new Set<String>();
        for (Integer i = 0; i < requests.size(); i++) {
            WorkItem item = new WorkItem();
            item.index = i;
            item.input = requests[i];
            item.result = new SR_CreateResultDTO();
            work.add(item);
            results.add(item.result);
            if (item.input == null) {
                continue;
            }
            if (item.input.orderId != null) {
                orderIds.add(item.input.orderId);
            }
            if (!String.isBlank(item.input.orderNumber)) {
                orderNumbers.add(item.input.orderNumber.trim());
            }
            if (!String.isBlank(item.input.externalRequestId)) {
                externalIds.add(item.input.externalRequestId.trim());
            }
            if (!String.isBlank(item.input.storeCode)) {
                storeCodes.add(item.input.storeCode.trim());
            }
        }

        Map<String, Return_Request__c> duplicateByExternal = SR_ReturnRequestSelector.selectByExternalIds(externalIds);
        Map<Id, Order> ordersById = SR_OrderSelector.selectByIds(orderIds, true);
        Map<String, Order> ordersByNumber = SR_OrderSelector.selectByNumbers(orderNumbers, true);
        Map<String, Store__c> storesByCode = SR_StoreSelector.selectByCodes(storeCodes);
        User currentUser = SR_UserSelector.selectCurrentUser();
        if (!String.isBlank(currentUser.Store_Code__c)) {
            storeCodes.add(currentUser.Store_Code__c);
        }
        if (!storeCodes.isEmpty()) {
            storesByCode.putAll(SR_StoreSelector.selectByCodes(storeCodes));
        }

        for (WorkItem item : work) {
            if (item.input == null) {
                addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Request không được null.');
                continue;
            }
            Return_Request__c duplicate = String.isBlank(item.input.externalRequestId)
                ? null
                : duplicateByExternal.get(item.input.externalRequestId.trim());
            if (duplicate != null) {
                mapDuplicate(item.result, duplicate);
                continue;
            }
            validateEnvelope(item);
            if (!item.result.errors.isEmpty()) {
                continue;
            }
            item.orderRow = item.input.orderId != null
                ? ordersById.get(item.input.orderId)
                : ordersByNumber.get(item.input.orderNumber.trim());
            if (item.orderRow == null || !phoneMatches(item.input.customerPhone, item.orderRow.Account == null ? null : item.orderRow.Account.Phone)) {
                addError(item.result, null, SR_ErrorCode.ORDER_NOT_FOUND, SR_ErrorCode.message(SR_ErrorCode.ORDER_NOT_FOUND));
                continue;
            }
            item.storeRow = resolveStore(item.input, item.orderRow, currentUser, storesByCode);
            if (item.storeRow == null) {
                addError(item.result, null, SR_ErrorCode.INVALID_VALUE, 'Không xác định được cửa hàng xử lý.');
            }
        }

        Set<Id> allOrderItemIds = new Set<Id>();
        for (WorkItem item : work) {
            if (item.orderRow != null) {
                for (OrderItem oi : item.orderRow.OrderItems) {
                    allOrderItemIds.add(oi.Id);
                }
            }
        }
        Map<Id, Decimal> reserved = SR_ReturnRequestSelector.sumReservedQuantity(allOrderItemIds);
        Map<Id, Decimal> inBatchReserved = new Map<Id, Decimal>();
        Set<Id> accountIds = new Set<Id>();
        for (WorkItem item : work) {
            if (item.orderRow != null && item.orderRow.AccountId != null) {
                accountIds.add(item.orderRow.AccountId);
            }
        }
        DateTime riskSince = System.now().addDays(-SR_Config.riskWindowDays());
        Map<Id, SR_ReturnRequestSelector.RiskAggregate> riskByAccount = SR_ReturnRequestSelector.aggregateRisk(accountIds, riskSince);
        Map<Id, Integer> batchRiskCount = new Map<Id, Integer>();
        Map<Id, Decimal> batchRiskAmount = new Map<Id, Decimal>();

        for (WorkItem item : work) {
            if (!item.result.errors.isEmpty() || item.result.isDuplicate) {
                continue;
            }
            validateAndBuildLines(item, reserved, inBatchReserved);
            if (!item.result.errors.isEmpty()) {
                continue;
            }
            applyRiskAndRoute(item, riskByAccount, batchRiskCount, batchRiskAmount);
        }

        List<WorkItem> insertable = new List<WorkItem>();
        List<Return_Request__c> parents = new List<Return_Request__c>();
        for (WorkItem item : work) {
            if (item.requestRow != null && item.result.errors.isEmpty()) {
                insertable.add(item);
                parents.add(item.requestRow);
            }
        }
        Database.SaveResult[] parentSaves = Database.insert(parents, false);
        Set<String> duplicateRaceIds = new Set<String>();
        for (Integer i = 0; i < parentSaves.size(); i++) {
            WorkItem item = insertable[i];
            if (!parentSaves[i].isSuccess()) {
                Boolean duplicateRace = false;
                for (Database.Error errorValue : parentSaves[i].getErrors()) {
                    if (errorValue.getStatusCode() == StatusCode.DUPLICATE_VALUE &&
                        !String.isBlank(item.input.externalRequestId)) {
                        duplicateRace = true;
                        duplicateRaceIds.add(item.input.externalRequestId.trim());
                    }
                }
                if (!duplicateRace) {
                    addDmlErrors(item.result, null, parentSaves[i].getErrors());
                }
                item.requestRow = null;
            } else {
                item.requestRow.Id = parentSaves[i].getId();
                for (Return_Request_Line__c line : item.lineRows) {
                    line.Return_Request__c = item.requestRow.Id;
                }
            }
        }
        if (!duplicateRaceIds.isEmpty()) {
            Map<String, Return_Request__c> racedDuplicates = SR_ReturnRequestSelector.selectByExternalIds(duplicateRaceIds);
            for (WorkItem item : insertable) {
                if (item.requestRow == null && !String.isBlank(item.input.externalRequestId) &&
                    racedDuplicates.containsKey(item.input.externalRequestId.trim())) {
                    mapDuplicate(item.result, racedDuplicates.get(item.input.externalRequestId.trim()));
                }
            }
        }

        List<Return_Request_Line__c> allLines = new List<Return_Request_Line__c>();
        List<WorkItem> lineOwner = new List<WorkItem>();
        List<SR_LineCreateResultDTO> lineDtoOrder = new List<SR_LineCreateResultDTO>();
        for (WorkItem item : insertable) {
            if (item.requestRow != null) {
                for (Integer j = 0; j < item.lineRows.size(); j++) {
                    allLines.add(item.lineRows[j]);
                    lineOwner.add(item);
                    lineDtoOrder.add(item.lineResults[j]);
                }
            }
        }
        Database.SaveResult[] lineSaves = Database.insert(allLines, false);
        Set<Id> parentsToDelete = new Set<Id>();
        for (Integer i = 0; i < lineSaves.size(); i++) {
            if (lineSaves[i].isSuccess()) {
                lineDtoOrder[i].lineId = lineSaves[i].getId();
            } else {
                parentsToDelete.add(lineOwner[i].requestRow.Id);
                addDmlErrors(lineOwner[i].result, lineDtoOrder[i].sku, lineSaves[i].getErrors());
            }
        }
        if (!parentsToDelete.isEmpty()) {
            deleteParents(parentsToDelete);
        }

        List<SR_StatusChangeDTO> changes = new List<SR_StatusChangeDTO>();
        List<WorkItem> statusOwners = new List<WorkItem>();
        for (WorkItem item : insertable) {
            if (item.requestRow == null || parentsToDelete.contains(item.requestRow.Id) || !item.result.errors.isEmpty()) {
                continue;
            }
            SR_StatusChangeDTO change = new SR_StatusChangeDTO();
            change.requestId = item.requestRow.Id;
            change.toStatus = item.route.targetStatus;
            change.note = 'Created by SR_ReturnRequestService';
            change.correlationId = item.result.correlationId;
            changes.add(change);
            statusOwners.add(item);
        }
        List<SR_ActionResultDTO> statusResults = SR_StatusMachine.change(changes);
        Set<Id> successfulRiskAccounts = new Set<Id>();
        Set<Id> statusFailedParents = new Set<Id>();
        for (Integer i = 0; i < statusResults.size(); i++) {
            WorkItem item = statusOwners[i];
            SR_ActionResultDTO statusResult = statusResults[i];
            if (statusResult.success != true) {
                addError(item.result, null, statusResult.errorCode, statusResult.message);
                statusFailedParents.add(item.requestRow.Id);
                continue;
            }
            item.result.success = true;
            item.result.requestId = item.requestRow.Id;
            item.result.requestNumber = statusResult.requestNumber;
            item.result.status = statusResult.status;
            item.result.approvalLevel = item.route.approvalLevel;
            item.result.estimatedRefund = item.total;
            item.result.lines.addAll(item.lineResults);
            if (item.risk == true) {
                successfulRiskAccounts.add(item.orderRow.AccountId);
            }
        }
        if (!statusFailedParents.isEmpty()) {
            deleteParents(statusFailedParents);
        }
        updateRiskFlags(successfulRiskAccounts);
        return results;
    }

    private static WorkItem prepareWorkItem(SR_CreateRequestDTO request, Boolean lockOrders) {
        WorkItem item = new WorkItem();
        item.input = request;
        item.result = new SR_CreateResultDTO();
        if (request == null) {
            addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Request không được null.');
            return item;
        }
        validateEnvelope(item);
        if (!item.result.errors.isEmpty()) {
            return item;
        }

        Set<Id> orderIds = new Set<Id>();
        Set<String> orderNumbers = new Set<String>();
        Set<String> storeCodes = new Set<String>();
        if (request.orderId != null) {
            orderIds.add(request.orderId);
        }
        if (!String.isBlank(request.orderNumber)) {
            orderNumbers.add(request.orderNumber.trim());
        }
        if (!String.isBlank(request.storeCode)) {
            storeCodes.add(request.storeCode.trim());
        }
        Map<Id, Order> ordersById = SR_OrderSelector.selectByIds(orderIds, lockOrders);
        Map<String, Order> ordersByNumber = SR_OrderSelector.selectByNumbers(orderNumbers, lockOrders);
        User currentUser = SR_UserSelector.selectCurrentUser();
        if (!String.isBlank(currentUser.Store_Code__c)) {
            storeCodes.add(currentUser.Store_Code__c);
        }
        Map<String, Store__c> storesByCode = SR_StoreSelector.selectByCodes(storeCodes);
        item.orderRow = request.orderId != null
            ? ordersById.get(request.orderId)
            : ordersByNumber.get(request.orderNumber.trim());
        if (item.orderRow == null || !phoneMatches(request.customerPhone, item.orderRow.Account == null ? null : item.orderRow.Account.Phone)) {
            addError(item.result, null, SR_ErrorCode.ORDER_NOT_FOUND, SR_ErrorCode.message(SR_ErrorCode.ORDER_NOT_FOUND));
            return item;
        }
        item.storeRow = resolveStore(request, item.orderRow, currentUser, storesByCode);
        if (item.storeRow == null) {
            addError(item.result, null, SR_ErrorCode.INVALID_VALUE, 'Không xác định được cửa hàng xử lý.');
            return item;
        }

        Set<Id> itemIds = new Set<Id>();
        for (OrderItem oi : item.orderRow.OrderItems) {
            itemIds.add(oi.Id);
        }
        validateAndBuildLines(item, SR_ReturnRequestSelector.sumReservedQuantity(itemIds), new Map<Id, Decimal>());
        if (!item.result.errors.isEmpty()) {
            return item;
        }
        Map<Id, SR_ReturnRequestSelector.RiskAggregate> riskByAccount = SR_ReturnRequestSelector.aggregateRisk(
            new Set<Id>{ item.orderRow.AccountId },
            System.now().addDays(-SR_Config.riskWindowDays())
        );
        applyRiskAndRoute(item, riskByAccount, new Map<Id, Integer>(), new Map<Id, Decimal>());
        return item;
    }

    private static void applyRiskAndRoute(
        WorkItem item,
        Map<Id, SR_ReturnRequestSelector.RiskAggregate> riskByAccount,
        Map<Id, Integer> batchRiskCount,
        Map<Id, Decimal> batchRiskAmount
    ) {
        Id accountId = item.orderRow.AccountId;
        SR_ReturnRequestSelector.RiskAggregate prior = riskByAccount.get(accountId);
        Integer countIncludingCurrent = (prior == null ? 0 : prior.requestCount) + valueOrZero(batchRiskCount.get(accountId)) + 1;
        Decimal amountIncludingCurrent = (prior == null || prior.totalAmount == null ? 0 : prior.totalAmount)
            + decimalOrZero(batchRiskAmount.get(accountId))
            + item.total;
        item.risk = countIncludingCurrent >= SR_Config.riskRequestCount()
            || amountIncludingCurrent > SR_Config.riskTotalAmount();
        batchRiskCount.put(accountId, valueOrZero(batchRiskCount.get(accountId)) + 1);
        batchRiskAmount.put(accountId, decimalOrZero(batchRiskAmount.get(accountId)) + item.total);

        SR_ApprovalPreviewDTO preview = new SR_ApprovalPreviewDTO();
        preview.estimatedRefund = item.total;
        preview.riskFlag = item.risk;
        preview.channel = item.input.channel;
        preview.storeId = item.storeRow.Id;
        item.route = SR_ApprovalService.previewLevel(preview, item.storeRow);
        if (item.route == null || item.route.success != true) {
            addError(
                item.result,
                null,
                SR_ErrorCode.CONFIGURATION_ERROR,
                item.route == null ? 'Không định tuyến được cấp duyệt.' : item.route.message
            );
            return;
        }
                
        Boolean pendingApproval =
            item.route.targetStatus == SR_StatusMachine.PENDING_APPROVAL;
        Datetime submittedAt = pendingApproval ? System.now() : null;

        item.requestRow = new Return_Request__c(
            Account__c = accountId,
            Order__c = item.orderRow.Id,
            Store__c = item.storeRow.Id,
            Channel__c = item.input.channel,
            External_Request_Id__c = String.isBlank(item.input.externalRequestId)
                ? null
                : item.input.externalRequestId.trim(),
            Status__c = SR_StatusMachine.STATUS_NEW,
            Approval_Level__c = item.route.approvalLevel,
            Assigned_Approver__c = item.route.assignedApproverId,
            Submitted_At__c = submittedAt,
            Approval_Due_At__c = pendingApproval
                ? submittedAt.addHours(SR_Config.approvalSlaHours())
                : null,
            Version_Token__c = SR_Correlation.newId()
        );

    }

    private static void validateAndBuildLines(WorkItem item, Map<Id, Decimal> persistedReserved, Map<Id, Decimal> inBatchReserved) {
        Map<Id, OrderItem> byId = new Map<Id, OrderItem>();
        Map<String, OrderItem> bySku = new Map<String, OrderItem>();
        for (OrderItem oi : item.orderRow.OrderItems) {
            byId.put(oi.Id, oi);
            if (oi.Product2 != null && !String.isBlank(oi.Product2.ProductCode)) {
                bySku.put(oi.Product2.ProductCode, oi);
            }
        }
        Date todayValue = Date.today();
        for (SR_CreateLineDTO inputLine : item.input.lines) {
            String sku = inputLine == null ? null : inputLine.sku;
            if (inputLine == null) {
                addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Line không được null.');
                continue;
            }
            OrderItem oi = inputLine.orderItemId != null ? byId.get(inputLine.orderItemId) : bySku.get(inputLine.sku);
            if (oi == null) {
                addError(item.result, sku, SR_ErrorCode.SKU_NOT_IN_ORDER, SR_ErrorCode.message(SR_ErrorCode.SKU_NOT_IN_ORDER));
                continue;
            }
            sku = oi.Product2 == null ? sku : oi.Product2.ProductCode;
            if (inputLine.quantity == null || inputLine.quantity <= 0) {
                addError(item.result, sku, SR_ErrorCode.INVALID_VALUE, 'Số lượng phải lớn hơn 0.');
                continue;
            }
            if (!REASONS.contains(inputLine.reason) || !CONDITIONS.contains(inputLine.condition)) {
                addError(item.result, sku, SR_ErrorCode.INVALID_VALUE, 'Lý do hoặc tình trạng không hợp lệ.');
                continue;
            }
            SR_CategoryPolicy policy = SR_Config.getCategoryPolicy(oi.Product2 == null ? null : oi.Product2.Family);
            if (!SR_ReturnEligibilityService.isCategoryReturnable(policy)) {
                addError(item.result, sku, SR_ErrorCode.NOT_RETURNABLE, SR_ErrorCode.message(SR_ErrorCode.NOT_RETURNABLE));
                continue;
            }
            Date deadline = SR_ReturnEligibilityService.resolveDeadline(
                SR_ReturnEligibilityService.resolveAnchorDate(item.orderRow),
                policy
            );
            if (!SR_ReturnEligibilityService.isWithinReturnWindow(todayValue, deadline)) {
                addError(item.result, sku, SR_ErrorCode.RETURN_WINDOW_EXPIRED, SR_ErrorCode.message(SR_ErrorCode.RETURN_WINDOW_EXPIRED));
                continue;
            }
            Decimal used = SR_ReturnEligibilityService.reservedQuantity(oi.Id, persistedReserved)
                + SR_ReturnEligibilityService.reservedQuantity(oi.Id, inBatchReserved);
            Decimal remaining = SR_ReturnEligibilityService.remainingQuantity(oi.Quantity, used);
            if (inputLine.quantity > remaining) {
                addError(item.result, sku, SR_ErrorCode.QUANTITY_EXCEEDED, SR_ErrorCode.message(SR_ErrorCode.QUANTITY_EXCEEDED));
                continue;
            }
            Decimal rate = SR_RefundCalculator.rateFor(inputLine.reason, inputLine.condition);
            if (rate == null) {
                addError(item.result, sku, SR_ErrorCode.CONFIGURATION_ERROR, 'Không có cấu hình tỷ lệ hoàn.');
                continue;
            }
            if (rate <= 0) {
                addError(item.result, sku, SR_ErrorCode.NOT_RETURNABLE, 'Tỷ lệ hoàn bằng 0%; sản phẩm bị từ chối theo MSG-05.');
                continue;
            }
            Decimal refund = SR_RefundCalculator.lineAmount(oi.UnitPrice, inputLine.quantity, rate);
            item.lineRows.add(new Return_Request_Line__c(
                Order_Product__c = oi.Id,
                Product__c = oi.Product2Id,
                Quantity__c = inputLine.quantity,
                Unit_Price__c = oi.UnitPrice,
                Reason__c = inputLine.reason,
                Declared_Condition__c = inputLine.condition,
                Refund_Rate__c = rate,
                Estimated_Refund__c = refund,
                Inspection_Result__c = 'NOT_INSPECTED'
            ));
            SR_LineCreateResultDTO lineResult = new SR_LineCreateResultDTO();
            lineResult.orderItemId = oi.Id;
            lineResult.sku = sku;
            lineResult.quantity = inputLine.quantity;
            lineResult.unitPrice = oi.UnitPrice;
            lineResult.refundRate = rate;
            lineResult.refundAmount = refund;
            item.lineResults.add(lineResult);
            item.total += refund;
            inBatchReserved.put(oi.Id, used + inputLine.quantity);
        }
        if (item.lineRows.isEmpty() && item.result.errors.isEmpty()) {
            addError(item.result, null, SR_ErrorCode.VALIDATION_FAILED, 'Không có dòng nào có số lượng lớn hơn 0 (MSG-06).');
        }
        if (!item.result.errors.isEmpty()) {
            for (SR_LineCreateResultDTO accepted : item.lineResults) {
                inBatchReserved.put(
                    accepted.orderItemId,
                    decimalOrZero(inBatchReserved.get(accepted.orderItemId)) - accepted.quantity
                );
            }
            item.lineRows.clear();
            item.lineResults.clear();
            item.total = 0;
        }
    }

    public static Decimal calcLineRefund(Decimal unitPrice, Decimal quantity, Decimal refundRate) {
        return SR_RefundCalculator.lineAmount(unitPrice, quantity, refundRate);
    }

    private static void validateEnvelope(WorkItem item) {
        SR_CreateRequestDTO input = item.input;
        if (String.isBlank(input.channel)) {
            addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Thiếu channel.');
        } else {
            input.channel = input.channel.trim().toUpperCase();
            if (!CHANNELS.contains(input.channel)) {
                addError(item.result, null, SR_ErrorCode.INVALID_VALUE, 'channel phải là COUNTER, POS hoặc APP.');
            }
        }
        if (input.orderId == null && String.isBlank(input.orderNumber)) {
            addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Thiếu orderId/orderNumber.');
        }
        if ((input.channel == CHANNEL_POS || input.channel == CHANNEL_APP) && String.isBlank(input.externalRequestId)) {
            addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Thiếu externalRequestId.');
        }
        if (input.lines == null || input.lines.isEmpty()) {
            addError(item.result, null, SR_ErrorCode.MISSING_FIELD, 'Thiếu lines.');
        }
    }

    private static Store__c resolveStore(SR_CreateRequestDTO input, Order orderRow, User currentUser, Map<String, Store__c> byCode) {
        if (input.channel == CHANNEL_COUNTER && !String.isBlank(currentUser.Store_Code__c)) {
            return byCode.get(currentUser.Store_Code__c);
        }
        if (!String.isBlank(input.storeCode)) {
            return byCode.get(input.storeCode.trim());
        }
        if (orderRow.Store__c == null) {
            return null;
        }
        return new Store__c(
            Id = orderRow.Store__c,
            Name = orderRow.Store__r == null ? null : orderRow.Store__r.Name,
            Store_Code__c = orderRow.Store__r == null ? null : orderRow.Store__r.Store_Code__c,
            Store_Manager__c = orderRow.Store__r == null ? null : orderRow.Store__r.Store_Manager__c,
            Regional_Manager__c = orderRow.Store__r == null ? null : orderRow.Store__r.Regional_Manager__c
        );
    }

    private static SR_ReturnableLineDTO baseLine(Order orderRow, OrderItem item) {
        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();
        dto.orderId = orderRow.Id;
        dto.orderNumber = orderRow.OrderNumber;
        dto.customerName = orderRow.Account == null ? null : orderRow.Account.Name;
        dto.customerPhone = orderRow.Account == null ? null : orderRow.Account.Phone;
        dto.purchaseDate = orderRow.EffectiveDate;
        dto.deliveryDate = orderRow.Delivery_Date__c;
        dto.storeId = orderRow.Store__c;
        dto.storeCode = orderRow.Store__r == null ? null : orderRow.Store__r.Store_Code__c;
        dto.storeName = orderRow.Store__r == null ? null : orderRow.Store__r.Name;
        dto.orderItemId = item.Id;
        dto.productId = item.Product2Id;
        dto.productName = item.Product2 == null ? null : item.Product2.Name;
        dto.sku = item.Product2 == null ? null : item.Product2.ProductCode;
        dto.category = item.Product2 == null ? null : item.Product2.Family;
        dto.unitPrice = item.UnitPrice;
        dto.purchasedQuantity = item.Quantity;
        return dto;
    }

    private static Boolean phoneMatches(String supplied, String expected) {
        if (String.isBlank(supplied)) {
            return true;
        }
        return normalizePhone(supplied) == normalizePhone(expected);
    }

    private static String normalizePhone(String value) {
        return String.isBlank(value) ? '' : value.replaceAll('[^0-9]', '');
    }

    private static Decimal decimalOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Integer valueOrZero(Integer value) {
        return value == null ? 0 : value;
    }

    private static void mapDuplicate(SR_CreateResultDTO out, Return_Request__c row) {
        out.success = true;
        out.isDuplicate = true;
        out.requestId = row.Id;
        out.requestNumber = row.Name;
        out.status = row.Status__c;
        out.approvalLevel = row.Approval_Level__c;
        out.estimatedRefund = row.Estimated_Refund__c;
        for (Return_Request_Line__c line : row.Return_Request_Lines__r) {
            SR_LineCreateResultDTO dto = new SR_LineCreateResultDTO();
            dto.lineId = line.Id;
            dto.orderItemId = line.Order_Product__c;
            dto.sku = line.Product__r == null ? null : line.Product__r.ProductCode;
            dto.quantity = line.Quantity__c;
            dto.unitPrice = line.Unit_Price__c;
            dto.refundRate = line.Refund_Rate__c;
            dto.refundAmount = line.Estimated_Refund__c;
            out.lines.add(dto);
        }
    }

    private static void addError(SR_CreateResultDTO result, String sku, String code, String message) {
        result.errors.add(new SR_ErrorDetailDTO(sku, code, message));
    }

    private static void addDmlErrors(SR_CreateResultDTO result, String sku, Database.Error[] errors) {
        for (Database.Error errorValue : errors) {
            addError(result, sku, SR_ErrorCode.INVALID_VALUE, errorValue.getMessage());
        }
    }

    private static void deleteParents(Set<Id> parentIds) {
        if (parentIds == null || parentIds.isEmpty()) {
            return;
        }
        List<Return_Request__c> failedParents = new List<Return_Request__c>();
        for (Id failedParentId : parentIds) {
            failedParents.add(new Return_Request__c(Id = failedParentId));
        }
        Database.delete(failedParents, false);
    }

    private static void updateRiskFlags(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        List<Account> updates = new List<Account>();
        for (Id accountId : accountIds) {
            updates.add(new Account(
                Id = accountId,
                Risk_Flag__c = true,
                Risk_Flag_Updated_At__c = System.now()
            ));
        }
        Database.update(updates, false);
    }
}
