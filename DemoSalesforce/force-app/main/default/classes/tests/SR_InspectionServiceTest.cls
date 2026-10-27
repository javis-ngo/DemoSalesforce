@IsTest(SeeAllData=false)
private class SR_InspectionServiceTest {
    private static final String STORE_CODE = 'DUC07';
    private static final String ACCOUNT_NAME = 'DUC-07 Inspection Customer';
    @TestSetup
    static void setupData() {
        SR_TestDataFactory.createStoreSetup(
            STORE_CODE,
            SR_TestDataFactory.REGION_SOUTH
        );
        Account account = SR_TestDataFactory.createAccount(
            ACCOUNT_NAME,
            '0907777001',
            false
        );
        Product2 appliance = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_APPLIANCE,
            'DUC07-AF',
            'DUC-07 Appliance',
            2490000
        );
        Product2 accessory = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_ACCESSORY,
            'DUC07-AC',
            'DUC-07 Accessory',
            350000
        );
        Store__c storeRow = [
            SELECT Id
            FROM Store__c
            WHERE Store_Code__c = :STORE_CODE
            LIMIT 1
        ];
        SR_TestDataFactory.OrderSpec orderSpec =
            new SR_TestDataFactory.OrderSpec(account.Id, storeRow.Id);
        orderSpec.deliveryDate = Date.today().addDays(-1);
        orderSpec.items.add(
            new SR_TestDataFactory.ItemSpec(appliance.Id, 1, 2490000)
        );
        orderSpec.items.add(
            new SR_TestDataFactory.ItemSpec(accessory.Id, 1, 350000)
        );
        SR_TestDataFactory.createOrder(orderSpec);
    }
    private static void seedConfig(Boolean payHubEnabled) {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
        SR_TestDataFactory.overrideConfig(
            SR_Setting__mdt.Enable_PayHub__c,
            payHubEnabled
        );
        // Job SR_RefundService chạy khi Test.stopTest: PayHub giả lập trả PENDING nên yêu cầu giữ REFUND_PROCESSING
        SR_PayHubClient.useMockOverride = true;
        SR_PayHubClient.mockScenarioOverride = SR_PayHubClient.SCENARIO_PENDING;
    }
    // Số job SR_RefundService đã xếp trong transaction hiện tại (gọi trước Test.stopTest)
    private static Integer queuedRefundJobs() {
        return Limits.getQueueableJobs();
    }
    private static Order baseOrder() {
        return [
            SELECT Id, AccountId, Store__c,
                   (SELECT Id, Product2Id, UnitPrice FROM OrderItems ORDER BY Id)
            FROM Order
            WHERE Account.Name = :ACCOUNT_NAME
            LIMIT 1
        ];
    }
    private static Return_Request__c createInspectionRequest(
        String status,
        Boolean completed,
        Integer lineCount
    ) {
        Order orderRow = baseOrder();
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = orderRow.AccountId;
        spec.orderId = orderRow.Id;
        spec.storeId = orderRow.Store__c;
        spec.channel = SR_TestDataFactory.CHANNEL_COUNTER;
        spec.status = status;
        Integer count = lineCount < orderRow.OrderItems.size()
            ? lineCount
            : orderRow.OrderItems.size();
        for (Integer i = 0; i < count; i++) {
            OrderItem orderItem = orderRow.OrderItems[i];
            SR_TestDataFactory.LineSpec line =
                new SR_TestDataFactory.LineSpec();
            line.orderItemId = orderItem.Id;
            line.productId = orderItem.Product2Id;
            line.quantity = 1;
            line.unitPrice = orderItem.UnitPrice;
            line.reason = 'NOT_SATISFIED';
            line.declaredCondition = 'SEALED';
            line.refundRate = 100;
            line.estimatedRefund = orderItem.UnitPrice;
            spec.lines.add(line);
        }
        Return_Request__c result =
            SR_TestDataFactory.createReturnRequest(spec);
        if (completed) {
            Database.update(
                new List<Return_Request__c>{
                    new Return_Request__c(
                        Id = result.Id,
                        Inspection_Completed_At__c = System.now()
                    )
                },
                false,
                AccessLevel.SYSTEM_MODE
            );
        }
        return reloadRequest(result.Id);
    }
    private static Return_Request__c reloadRequest(Id requestId) {
        return [
            SELECT Id, Name, Status__c, Actual_Refund__c,
                   Inspection_Completed_At__c, LastModifiedDate,
                   Rejection_Reason__c
            FROM Return_Request__c
            WHERE Id = :requestId
        ];
    }
    private static List<Return_Request_Line__c> requestLines(Id requestId) {
        return [
            SELECT Id, Reason__c, Declared_Condition__c,
                   Actual_Condition__c, Refund_Rate__c,
                   Actual_Refund__c, Inspection_Result__c,
                   Inspection_Note__c, Unit_Price__c
            FROM Return_Request_Line__c
            WHERE Return_Request__c = :requestId
            ORDER BY Id
        ];
    }
    private static SR_InspectionRequestDTO inspectionInput(
        Return_Request__c requestRow,
        List<Return_Request_Line__c> lines,
        List<String> results,
        List<String> actualConditions,
        List<String> notes
    ) {
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );
        for (Integer i = 0; i < lines.size(); i++) {
            SR_InspectionLineDTO line = new SR_InspectionLineDTO();
            line.lineId = lines[i].Id;
            line.inspectionResult = results[i];
            line.actualCondition = actualConditions[i];
            line.inspectionNote = notes[i];
            input.lines.add(line);
        }
        return input;
    }
    @IsTest
    static void complete_allPassed_payHubEnabled_transitionsAndEnqueues() {
        seedConfig(true);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            2
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED', 'PASSED' },
            new List<String>{ 'SEALED', 'SEALED' },
            new List<String>{ null, null }
        );
        Test.startTest();
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Integer queuedJobs = queuedRefundJobs();
        Test.stopTest();
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Assert.areEqual(SR_StatusMachine.REFUND_PROCESSING, results[0].status);
        Assert.areEqual(1, queuedJobs, 'Phải xếp 1 job SR_RefundService');
        Return_Request__c updated = reloadRequest(requestRow.Id);
        Assert.isNotNull(updated.Inspection_Completed_At__c);
        Assert.isTrue(updated.Actual_Refund__c > 0);
    }
    @IsTest
    static void complete_missingLineResult_returnsMissingField() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            2
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            new List<Return_Request_Line__c>{ lines[0] },
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
        Assert.isNull(reloadRequest(requestRow.Id).Inspection_Completed_At__c);
    }
    @IsTest
    static void complete_failedWithoutNote_returnsMissingField() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'FAILED' },
            new List<String>{ 'USED' },
            new List<String>{ ' ' }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }
    @IsTest
    static void complete_changedCondition_recalculatesActualRefund() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'OPENED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Return_Request_Line__c updatedLine = requestLines(requestRow.Id)[0];
        Assert.areEqual('OPENED', updatedLine.Actual_Condition__c);
        Assert.areEqual(80, updatedLine.Refund_Rate__c);
        Assert.areEqual(1992000, updatedLine.Actual_Refund__c);
    }
    @IsTest
    static void complete_mixedLines_refundsOnlyPassed() {
        seedConfig(true);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            2
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED', 'FAILED' },
            new List<String>{ 'SEALED', 'USED' },
            new List<String>{ null, 'Không đạt ngoại quan' }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        List<Return_Request_Line__c> updatedLines = requestLines(requestRow.Id);
        Assert.isTrue(updatedLines[0].Actual_Refund__c > 0);
        Assert.areEqual(0, updatedLines[1].Actual_Refund__c);
        Assert.areEqual('Không đạt ngoại quan', updatedLines[1].Inspection_Note__c);
    }
    @IsTest
    static void complete_allFailed_rejectsWithBusinessReason() {
        seedConfig(true);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            2
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'FAILED', 'FAILED' },
            new List<String>{ 'USED', 'USED' },
            new List<String>{ 'Fail 1', 'Fail 2' }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Return_Request__c updated = reloadRequest(requestRow.Id);
        Assert.areEqual(SR_StatusMachine.REJECTED, updated.Status__c);
        Assert.areEqual('Không đạt kiểm định', updated.Rejection_Reason__c);
        Assert.areEqual(0, queuedRefundJobs(), 'Yêu cầu bị từ chối không được gửi PayHub');
    }
    @IsTest
    static void complete_payHubDisabled_keepsInspectingAndMarksComplete() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Return_Request__c updated = reloadRequest(requestRow.Id);
        Assert.areEqual(SR_StatusMachine.INSPECTING, updated.Status__c);
        Assert.isNotNull(updated.Inspection_Completed_At__c);
        Assert.areEqual(
            0,
            queuedRefundJobs(),
            'PayHub disabled must not enqueue a refund job.'
        );
    }
    @IsTest
    static void complete_invalidStatus_returnsInvalidTransition() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_PENDING_APPROVAL,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isFalse(results[0].success);
        Assert.areEqual(
            SR_ErrorCode.INVALID_STATUS_TRANSITION,
            results[0].errorCode
        );
    }
    @IsTest
    static void complete_alreadyCompleted_isImmutable() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            true,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isFalse(results[0].success);
        Assert.areEqual(
            SR_ErrorCode.INVALID_STATUS_TRANSITION,
            results[0].errorCode
        );
    }
    @IsTest
    static void complete_bulkMixed_returnsPartialResults() {
        seedConfig(false);
        Return_Request__c validRequest = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(validRequest.Id);
        SR_InspectionRequestDTO validInput = inspectionInput(
            validRequest,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ validInput, null }
        );
        Assert.areEqual(2, results.size());
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Assert.isFalse(results[1].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[1].errorCode);
    }
    @IsTest
    static void complete_duplicateRequest_marksBothInvalid() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input, input }
        );
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[1].errorCode);
    }
    @IsTest
    static void complete_passedZeroRate_allowsZeroRefund() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        Return_Request_Line__c sourceLine = requestLines(requestRow.Id)[0];
        List<Database.SaveResult> setupResults = Database.update(
            new List<Return_Request_Line__c>{
                new Return_Request_Line__c(
                    Id = sourceLine.Id,
                    Reason__c = 'CUSTOMER_DAMAGE'
                )
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        Assert.isTrue(
            setupResults[0].isSuccess(),
            setupResults[0].isSuccess()
                ? 'Zero-rate setup succeeded.'
                : setupResults[0].getErrors()[0].getMessage()
        );
        requestRow = reloadRequest(requestRow.Id);
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'USED' },
            new List<String>{ null }
        );
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Assert.areEqual(
            Decimal.valueOf(0),
            requestLines(requestRow.Id)[0].Actual_Refund__c,
            'Passed zero-rate line must persist Actual_Refund__c = 0.'
        );
    }
    @IsTest
    static void complete_bulkFiftyValid_doesNotHitLimits() {
        seedConfig(false);
        Order orderRow = baseOrder();
        OrderItem orderItem = orderRow.OrderItems[0];
        List<SR_TestDataFactory.RequestSpec> specs =
            new List<SR_TestDataFactory.RequestSpec>();
        for (Integer i = 0; i < 50; i++) {
            SR_TestDataFactory.RequestSpec spec =
                new SR_TestDataFactory.RequestSpec();
            spec.accountId = orderRow.AccountId;
            spec.orderId = orderRow.Id;
            spec.storeId = orderRow.Store__c;
            spec.channel = SR_TestDataFactory.CHANNEL_COUNTER;
            spec.status = SR_TestDataFactory.STATUS_INSPECTING;
            SR_TestDataFactory.LineSpec line =
                new SR_TestDataFactory.LineSpec();
            line.orderItemId = orderItem.Id;
            line.productId = orderItem.Product2Id;
            line.quantity = 1;
            line.unitPrice = orderItem.UnitPrice;
            line.reason = 'NOT_SATISFIED';
            line.declaredCondition = 'SEALED';
            line.refundRate = 100;
            line.estimatedRefund = orderItem.UnitPrice;
            spec.lines.add(line);
            specs.add(spec);
        }
        List<Return_Request__c> requests =
            SR_TestDataFactory.createReturnRequests(specs);
        Set<Id> requestIds = new Map<Id, Return_Request__c>(requests).keySet();
        Map<Id, Return_Request__c> refreshed = new Map<Id, Return_Request__c>([
            SELECT Id, LastModifiedDate
            FROM Return_Request__c
            WHERE Id IN :requestIds
        ]);
        Map<Id, List<Return_Request_Line__c>> linesByRequestId =
            new Map<Id, List<Return_Request_Line__c>>();
        for (Return_Request_Line__c lineRow : [
            SELECT Id, Return_Request__c
            FROM Return_Request_Line__c
            WHERE Return_Request__c IN :requestIds
        ]) {
            linesByRequestId.put(
                lineRow.Return_Request__c,
                new List<Return_Request_Line__c>{ lineRow }
            );
        }
        List<SR_InspectionRequestDTO> inputs =
            new List<SR_InspectionRequestDTO>();
        for (Id requestId : requestIds) {
            inputs.add(inspectionInput(
                refreshed.get(requestId),
                linesByRequestId.get(requestId),
                new List<String>{ 'PASSED' },
                new List<String>{ 'SEALED' },
                new List<String>{ null }
            ));
        }
        Test.startTest();
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(inputs);
        Test.stopTest();
        Assert.areEqual(50, results.size());
        for (SR_ActionResultDTO result : results) {
            Assert.isTrue(
                result.success,
                'Bulk inspection failed: code=' + String.valueOf(result.errorCode)
                + ', message=' + String.valueOf(result.message)
            );
            Assert.areEqual(SR_StatusMachine.INSPECTING, result.status);
        }
    }
    @IsTest
    static void complete_moreThan200_rejectsBeforeQuery() {
        List<SR_InspectionRequestDTO> inputs =
            new List<SR_InspectionRequestDTO>();
        for (Integer i = 0; i < 201; i++) {
            inputs.add(new SR_InspectionRequestDTO());
        }
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(inputs);
        Integer usedQueries = Limits.getQueries() - beforeQueries;
        Test.stopTest();
        Assert.areEqual(201, results.size());
        Assert.areEqual(0, usedQueries);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
    }
    @IsTest
    static void complete_staleToken_returnsStaleRecord() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        input.versionToken = 'stale-token';
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );
        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.STALE_RECORD, results[0].errorCode);
    }
    @IsTest
    static void complete_nullAndEmptyInputs_returnEmpty() {
        Assert.areEqual(0, SR_InspectionService.complete(null).size());
        Assert.areEqual(
            0,
            SR_InspectionService.complete(
                new List<SR_InspectionRequestDTO>()
            ).size()
        );
    }

    @IsTest
    static void complete_missingRequestId_returnsMissingField() {
        seedConfig(false);
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }

    @IsTest
    static void complete_deletedRequest_returnsRequestNotFound() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );
        List<Database.DeleteResult> deleteResults = Database.delete(
            new List<Return_Request__c>{
                new Return_Request__c(Id = requestRow.Id)
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        Assert.isTrue(
            deleteResults[0].isSuccess(),
            deleteResults[0].isSuccess()
                ? 'Deleted request fixture.'
                : deleteResults[0].getErrors()[0].getMessage()
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.REQUEST_NOT_FOUND, results[0].errorCode);
    }

    @IsTest
    static void complete_requestWithoutLines_returnsInvalidValue() {
        seedConfig(false);
        Order orderRow = baseOrder();
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = orderRow.AccountId;
        spec.orderId = orderRow.Id;
        spec.storeId = orderRow.Store__c;
        spec.channel = SR_TestDataFactory.CHANNEL_COUNTER;
        spec.status = SR_TestDataFactory.STATUS_INSPECTING;
        Return_Request__c requestRow =
            SR_TestDataFactory.createReturnRequest(spec);
        requestRow = reloadRequest(requestRow.Id);
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
    }

    @IsTest
    static void complete_emptyLineSubmission_returnsMissingField() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }

    @IsTest
    static void complete_nullLineInput_returnsMissingField() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );
        input.lines.add(null);

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }

    @IsTest
    static void complete_duplicateLineId_returnsInvalidValue() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        Return_Request_Line__c persistedLine = requestLines(requestRow.Id)[0];
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );
        for (Integer i = 0; i < 2; i++) {
            SR_InspectionLineDTO lineInput = new SR_InspectionLineDTO();
            lineInput.lineId = persistedLine.Id;
            lineInput.inspectionResult = 'PASSED';
            lineInput.actualCondition = 'SEALED';
            input.lines.add(lineInput);
        }

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
    }

    @IsTest
    static void complete_invalidInspectionResult_returnsInvalidValue() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'UNKNOWN' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
    }

    @IsTest
    static void complete_missingRefundMapping_returnsConfigurationError() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        Return_Request_Line__c sourceLine = requestLines(requestRow.Id)[0];
        List<Database.SaveResult> setupResults = Database.update(
            new List<Return_Request_Line__c>{
                new Return_Request_Line__c(
                    Id = sourceLine.Id,
                    Reason__c = 'DEFECT'
                )
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        Assert.isTrue(setupResults[0].isSuccess(), 'Setup line update failed.');
        requestRow = reloadRequest(requestRow.Id);
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'USED' },
            new List<String>{ null }
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.CONFIGURATION_ERROR, results[0].errorCode);
    }

    @IsTest
    static void complete_refundEnqueueFailure_returnsInternalError() {
        seedConfig(true);
        SR_RefundService.forceEnqueueFailureForTest = true;
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ 'SEALED' },
            new List<String>{ null }
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.INTERNAL_ERROR, results[0].errorCode);
        Assert.isTrue(results[0].message.contains('Mock enqueue failure'));
    }

    @IsTest
    static void complete_lineWithoutId_returnsMissingField() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestRow.Id;
        input.versionToken = String.valueOf(
            requestRow.LastModifiedDate.getTime()
        );
        SR_InspectionLineDTO lineInput = new SR_InspectionLineDTO();
        lineInput.inspectionResult = 'PASSED';
        lineInput.actualCondition = 'SEALED';
        input.lines.add(lineInput);

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }

    @IsTest
    static void complete_lineFromDifferentRequest_returnsMissingField() {
        seedConfig(false);
        Return_Request__c firstRequest = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        Return_Request__c secondRequest = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        Return_Request_Line__c foreignLine = requestLines(secondRequest.Id)[0];
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = firstRequest.Id;
        input.versionToken = String.valueOf(
            firstRequest.LastModifiedDate.getTime()
        );
        SR_InspectionLineDTO lineInput = new SR_InspectionLineDTO();
        lineInput.lineId = foreignLine.Id;
        lineInput.inspectionResult = 'PASSED';
        lineInput.actualCondition = 'SEALED';
        input.lines.add(lineInput);

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isFalse(results[0].success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
    }

    @IsTest
    static void complete_blankActualCondition_usesDeclaredCondition() {
        seedConfig(false);
        Return_Request__c requestRow = createInspectionRequest(
            SR_TestDataFactory.STATUS_INSPECTING,
            false,
            1
        );
        List<Return_Request_Line__c> lines = requestLines(requestRow.Id);
        SR_InspectionRequestDTO input = inspectionInput(
            requestRow,
            lines,
            new List<String>{ 'PASSED' },
            new List<String>{ ' ' },
            new List<String>{ null }
        );

        List<SR_ActionResultDTO> results = SR_InspectionService.complete(
            new List<SR_InspectionRequestDTO>{ input }
        );

        Assert.isTrue(
            results[0].success,
            'Inspection failed: code=' + String.valueOf(results[0].errorCode)
            + ', message=' + String.valueOf(results[0].message)
        );
        Return_Request_Line__c updatedLine = requestLines(requestRow.Id)[0];
        Assert.areEqual('SEALED', updatedLine.Actual_Condition__c);
        Assert.areEqual(100, updatedLine.Refund_Rate__c);
    }

}