@IsTest(SeeAllData=false)
private class SR_ApprovalServiceTest {
    private static final String STORE_CODE = 'DUC06';
    private static final String FORBIDDEN = 'FORBIDDEN';
    private static final String STALE_RECORD = 'STALE_RECORD';
    private static final String INVALID_STATUS_TRANSITION =
        'INVALID_STATUS_TRANSITION';
    private class Fixture {
        Store__c store;
        User staff;
        User storeManager;
        User regionalManager;
        Account account;
        Order orderRow;
    }
    @TestSetup
    static void setupDataGraph() {
        SR_TestDataFactory.StoreSetup storeSetup =
            SR_TestDataFactory.createStoreSetup(
                STORE_CODE,
                SR_TestDataFactory.REGION_SOUTH
            );
        Account account = SR_TestDataFactory.createAccount(
            'DUC-06 Approval Customer',
            '0908888001',
            false
        );
        Product2 product = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_PHONE,
            'DUC06-PHONE',
            'DUC-06 Test Phone',
            12000000
        );
        SR_TestDataFactory.OrderSpec orderSpec =
            new SR_TestDataFactory.OrderSpec(account.Id, storeSetup.store.Id);
        orderSpec.deliveryDate = Date.today().addDays(-1);
        orderSpec.items.add(
            new SR_TestDataFactory.ItemSpec(product.Id, 1, 12000000)
        );
        SR_TestDataFactory.createOrder(orderSpec);
    }
    private static void seedConfig() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }
    private static Fixture fixture() {
        Fixture value = new Fixture();
        List<Store__c> stores = (List<Store__c>) Database.queryWithBinds(
            'SELECT Id, Store_Code__c,'
            + ' Store_Manager__c, Regional_Manager__c'
            + ' FROM Store__c'
            + ' WHERE Store_Code__c =:storeCode'
            + ' LIMIT 1',
            new Map<String, Object>{
                'storeCode' => STORE_CODE
            },
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual(
            1,
            stores.size(),
            'Không tìm thấy Store do TestDataFactory tạo.'
        );
        value.store = stores[0];
        Assert.isNotNull(
            value.store.Store_Manager__c,
            'Factory Store phải có Store Manager.'
        );
        Assert.isNotNull(
            value.store.Regional_Manager__c,
            'Factory Store phải có Regional Manager.'
        );
        // Không query User: System.runAs chỉ cần Id.
        value.storeManager = new User(
            Id = value.store.Store_Manager__c
        );
        value.regionalManager = new User(
            Id = value.store.Regional_Manager__c
        );
        value.staff = findFactoryUser(
            SR_TestDataFactory.ROLE_STORE_STAFF
        );
        List<Account> accounts = (List<Account>) Database.queryWithBinds(
            'SELECT Id, Phone, Risk_Flag__c'
            + ' FROM Account'
            + ' WHERE Name =:accountName'
            + ' LIMIT 1',
            new Map<String, Object>{
                'accountName' => 'DUC-06 Approval Customer'
            },
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual(
            1,
            accounts.size(),
            'Không tìm thấy Account do TestDataFactory tạo.'
        );
        value.account = accounts[0];
        List<Order> orders = (List<Order>) Database.queryWithBinds(
            'SELECT Id, AccountId, Store__c, Status'
            + ' FROM Order'
            + ' WHERE AccountId =:accountId'
            + ' AND Store__c =:storeId'
            + ' LIMIT 1',
            new Map<String, Object>{
                'accountId' => value.account.Id,
                'storeId' => value.store.Id
            },
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual(
            1,
            orders.size(),
            'Không tìm thấy Order do TestDataFactory tạo.'
        );
        value.orderRow = orders[0];
        return value;
    }
    private static Return_Request__c createPendingRequest(
        Fixture data,
        String channel,
        User creator,
        Id assignedApproverId
    ) {
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = data.account.Id;
        spec.orderId = data.orderRow.Id;
        spec.storeId = data.store.Id;
        spec.channel = channel;
        spec.status = SR_TestDataFactory.STATUS_PENDING_APPROVAL;
        spec.approvalLevel = SR_ApprovalRouter.LEVEL_CHT;
        spec.assignedApproverId = assignedApproverId;
        spec.submittedAt = System.now();
        spec.approvalDueAt = System.now().addHours(24);
        Return_Request__c created;
        System.runAs(creator) {
            created = SR_TestDataFactory.createReturnRequest(spec);
        }
        return [
            SELECT Id, Name, Status__c, Channel__c, Approval_Level__c,
                   Assigned_Approver__c, CreatedById, LastModifiedDate,
                   Rejection_Reason__c
            FROM Return_Request__c
            WHERE Id = :created.Id
        ];
    }
    private static String versionToken(Return_Request__c requestRow) {
        return requestRow == null || requestRow.LastModifiedDate == null
            ? null
            : String.valueOf(requestRow.LastModifiedDate.getTime());
    }
    private static SR_ApprovalDecisionDTO decision(
        Return_Request__c requestRow,
        Boolean approve,
        String reason,
        String versionToken
    ) {
        SR_ApprovalDecisionDTO value = new SR_ApprovalDecisionDTO();
        value.requestId = requestRow.Id;
        value.approve = approve;
        value.reason = reason;
        value.versionToken = versionToken;
        return value;
    }
    @IsTest
    static void previewLevel_preloadedStore_delegatesWithoutQuery() {
        seedConfig();
        Fixture data = fixture();
        SR_ApprovalPreviewDTO input = new SR_ApprovalPreviewDTO();
        input.estimatedRefund = 3000000;
        input.riskFlag = false;
        input.channel = SR_TestDataFactory.CHANNEL_COUNTER;
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        SR_ApprovalPreviewResultDTO result =
            SR_ApprovalService.previewLevel(input, data.store);
        Integer usedQueries = Limits.getQueries() - beforeQueries;
        Test.stopTest();
        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_CHT, result.approvalLevel);
        Assert.areEqual(data.storeManager.Id, result.assignedApproverId);
        Assert.areEqual(0, usedQueries, 'Preloaded overload must not query.');
    }
    @IsTest
    static void previewLevel_byStoreId_loadsFactoryStore() {
        seedConfig();
        Fixture data = fixture();
        SR_ApprovalPreviewDTO input = new SR_ApprovalPreviewDTO();
        input.estimatedRefund = 3000000;
        input.riskFlag = false;
        input.channel = SR_TestDataFactory.CHANNEL_POS;
        input.storeId = data.store.Id;
        SR_ApprovalPreviewResultDTO result =
            SR_ApprovalService.previewLevel(input);
        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_CHT, result.approvalLevel);
        Assert.areEqual(data.storeManager.Id, result.assignedApproverId);
    }
    @IsTest
    static void previewLevels_nullAndEmpty_returnEmpty() {
        Assert.areEqual(0, SR_ApprovalService.previewLevels(null).size());
        Assert.areEqual(
            0,
            SR_ApprovalService.previewLevels(
                new List<SR_ApprovalPreviewDTO>()
            ).size()
        );
    }
    @IsTest
    static void previewLevels_200AutoInputs_returnsOrderedResults() {
        seedConfig();
        List<SR_ApprovalPreviewDTO> inputs =
            new List<SR_ApprovalPreviewDTO>();
        for (Integer i = 0; i < 200; i++) {
            SR_ApprovalPreviewDTO input = new SR_ApprovalPreviewDTO();
            input.estimatedRefund = i + 1;
            input.riskFlag = false;
            input.channel = Math.mod(i, 2) == 0
                ? SR_TestDataFactory.CHANNEL_APP
                : SR_TestDataFactory.CHANNEL_POS;
            inputs.add(input);
        }
        Test.startTest();
        List<SR_ApprovalPreviewResultDTO> results =
            SR_ApprovalService.previewLevels(inputs);
        Test.stopTest();
        Assert.areEqual(200, results.size());
        for (Integer i = 0; i < results.size(); i++) {
            Assert.isTrue(results[i].success, 'Result ' + i + ' should succeed.');
            Assert.areEqual(SR_ApprovalRouter.LEVEL_AUTO, results[i].approvalLevel);
            Assert.areEqual(
                Math.mod(i, 2) == 0
                    ? SR_StatusMachine.AWAITING_GOODS
                    : SR_StatusMachine.INSPECTING,
                results[i].targetStatus
            );
        }
    }
    @IsTest
    static void previewLevels_withStoreId_preloadsStoreOnce() {
        seedConfig();
        Fixture data = fixture();
        SR_ApprovalPreviewDTO input = new SR_ApprovalPreviewDTO();
        input.estimatedRefund = 3000000;
        input.riskFlag = false;
        input.channel = SR_TestDataFactory.CHANNEL_POS;
        input.storeId = data.store.Id;
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        List<SR_ApprovalPreviewResultDTO> results =
            SR_ApprovalService.previewLevels(
                new List<SR_ApprovalPreviewDTO>{ input }
            );
        Integer usedQueries = Limits.getQueries() - beforeQueries;
        Test.stopTest();
        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_CHT, results[0].approvalLevel);
        Assert.areEqual(data.storeManager.Id, results[0].assignedApproverId);
        // 3.000.000đ > ngưỡng tự duyệt: chờ CHT duyệt (BR-08, Phụ lục C New → Pending Approval);
        // INSPECTING chỉ đến sau khi CHT duyệt
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, results[0].targetStatus);
        Assert.areEqual(
            1,
            usedQueries,
            'Bulk preview must preload all referenced stores in one query.'
        );
    }
    @IsTest
    static void decide_nullAndEmpty_returnEmpty() {
        Assert.areEqual(0, SR_ApprovalService.decide(null).size());
        Assert.areEqual(
            0,
            SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>()
            ).size()
        );
    }
    @IsTest
    static void decide_moreThan200_returnsPerItemErrorsWithoutQuery() {
        List<SR_ApprovalDecisionDTO> inputs =
            new List<SR_ApprovalDecisionDTO>();
        for (Integer i = 0; i < 201; i++) {
            inputs.add(new SR_ApprovalDecisionDTO());
        }
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        List<SR_ActionResultDTO> results = SR_ApprovalService.decide(inputs);
        Integer usedQueries = Limits.getQueries() - beforeQueries;
        Test.stopTest();
        Assert.areEqual(201, results.size());
        Assert.areEqual(0, usedQueries, 'Oversized batch must fail before query.');
        for (SR_ActionResultDTO result : results) {
            Assert.isFalse(result.success);
            Assert.areEqual(SR_ErrorCode.INVALID_VALUE, result.errorCode);
        }
    }
    @IsTest
    static void decide_approveApp_updatesStatusAndHistory() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_APP,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            Test.startTest();
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Test.stopTest();
            Assert.areEqual(1, results.size());
            Assert.isTrue(
                results[0].success,
                'Approve APP failed: code=' + results[0].errorCode
                + ', message=' + results[0].message
            );
            Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, results[0].status);
        }
        Return_Request__c updated = [
            SELECT Status__c
            FROM Return_Request__c
            WHERE Id = :requestRow.Id
        ];
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, updated.Status__c);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Return_Request_History__c
             WHERE Return_Request__c = :requestRow.Id
             AND To_Status__c = :SR_StatusMachine.AWAITING_GOODS]
        );
    }
    @IsTest
    static void decide_reject_trimsAndStoresReason() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_COUNTER,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            false,
            '  Damaged packaging  ',
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isTrue(
                results[0].success,
                'Reject failed: code=' + results[0].errorCode
                + ', message=' + results[0].message
            );
            Assert.areEqual(SR_StatusMachine.REJECTED, results[0].status);
        }
        Return_Request__c updated = [
            SELECT Status__c, Rejection_Reason__c
            FROM Return_Request__c
            WHERE Id = :requestRow.Id
        ];
        Assert.areEqual(SR_StatusMachine.REJECTED, updated.Status__c);
        Assert.areEqual('Damaged packaging', updated.Rejection_Reason__c);
    }
    @IsTest
    static void decide_rejectWithoutReason_returnsMissingField() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_COUNTER,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            false,
            ' ',
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isFalse(results[0].success);
            Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errorCode);
        }
    }
    @IsTest
    static void decide_unassignedUser_returnsForbidden() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_POS,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.regionalManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isFalse(results[0].success);
            Assert.areEqual(FORBIDDEN, results[0].errorCode);
        }
    }
    @IsTest
    static void decide_creatorCannotSelfApprove() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_APP,
            data.storeManager,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isFalse(results[0].success);
            Assert.areEqual(FORBIDDEN, results[0].errorCode);
        }
    }
    @IsTest
    static void decide_staleToken_returnsStaleRecord() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_APP,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            'stale-token'
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isFalse(results[0].success);
            Assert.areEqual(STALE_RECORD, results[0].errorCode);
        }
    }
    @IsTest
    static void decide_missingRequest_returnsInvalidValue() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_APP,
            data.staff,
            data.storeManager.Id
        );
        Database.DeleteResult deleteResult = Database.delete(
            requestRow,
            false,
            AccessLevel.SYSTEM_MODE
        );
        Assert.isTrue(
            deleteResult.isSuccess(),
            'The fixture request must be deleted to simulate a stale client ID.'
        );
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            Test.startTest();
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Test.stopTest();
            Assert.areEqual(1, results.size());
            Assert.isFalse(results[0].success);
            Assert.areEqual(requestRow.Id, results[0].recordId);
            Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
        }
    }
    @IsTest
    // Channel__c là restricted picklist (COUNTER/POS/APP – Phụ lục E.1) nên không thể tạo yêu cầu có kênh lạ
    // để chạy nhánh "Channel không hợp lệ" của SR_ApprovalService.decide; test bất biến mà nhánh đó phòng vệ
    static void channelPicklist_rejectsUnsupportedValue() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_COUNTER,
            data.staff,
            data.storeManager.Id
        );

        Test.startTest();
        List<Database.SaveResult> saveResults = Database.update(
            new List<Return_Request__c>{
                new Return_Request__c(
                    Id = requestRow.Id,
                    Channel__c = 'UNSUPPORTED'
                )
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        Test.stopTest();

        Assert.isFalse(saveResults[0].isSuccess());
        Assert.areEqual(
            StatusCode.INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST,
            saveResults[0].getErrors()[0].getStatusCode()
        );
        Assert.areEqual(
            SR_TestDataFactory.CHANNEL_COUNTER,
            [SELECT Channel__c FROM Return_Request__c WHERE Id = :requestRow.Id].Channel__c
        );
    }
    @IsTest
    static void decide_requestNoLongerPending_returnsInvalidTransition() {
        seedConfig();
        Fixture data = fixture();
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = data.account.Id;
        spec.orderId = data.orderRow.Id;
        spec.storeId = data.store.Id;
        spec.channel = SR_TestDataFactory.CHANNEL_APP;
        spec.status = SR_TestDataFactory.STATUS_AWAITING_GOODS;
        spec.approvalLevel = SR_ApprovalRouter.LEVEL_AUTO;
        Return_Request__c created;
        System.runAs(data.staff) {
            created = SR_TestDataFactory.createReturnRequest(spec);
        }
        Return_Request__c requestRow = [
            SELECT Id, LastModifiedDate
            FROM Return_Request__c
            WHERE Id = :created.Id
        ];
        SR_ApprovalDecisionDTO input = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ input }
            );
            Assert.isFalse(results[0].success);
            Assert.areEqual(INVALID_STATUS_TRANSITION, results[0].errorCode);
        }
    }
    @IsTest
    static void decide_mixedValidAndInvalid_returnsPartialSuccess() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_POS,
            data.staff,
            data.storeManager.Id
        );
        SR_ApprovalDecisionDTO valid = decision(
            requestRow,
            true,
            null,
            versionToken(requestRow)
        );
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(
                new List<SR_ApprovalDecisionDTO>{ valid, null }
            );
            Assert.areEqual(2, results.size());
            Assert.isTrue(
                results[0].success,
                'Partial-success valid item failed: code=' + results[0].errorCode
                + ', message=' + results[0].message
            );
            Assert.areEqual(SR_StatusMachine.INSPECTING, results[0].status);
            Assert.isFalse(results[1].success);
            Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[1].errorCode);
        }
    }
    @IsTest
    static void decide_duplicateId_marksBothInputsInvalid() {
        seedConfig();
        Fixture data = fixture();
        Return_Request__c requestRow = createPendingRequest(
            data,
            SR_TestDataFactory.CHANNEL_COUNTER,
            data.staff,
            data.storeManager.Id
        );
        String token = versionToken(requestRow);
        List<SR_ApprovalDecisionDTO> inputs =
            new List<SR_ApprovalDecisionDTO>{
                decision(requestRow, true, null, token),
                decision(requestRow, false, 'duplicate', token)
            };
        System.runAs(data.storeManager) {
            List<SR_ActionResultDTO> results = SR_ApprovalService.decide(inputs);
            Assert.areEqual(2, results.size());
            Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errorCode);
            Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[1].errorCode);
        }
    }
    private static User findFactoryUser(String role) {
        String usernamePattern =
            'sr.'
            + role.toLowerCase()
            + '.%@smartreturn.test';
        List<User> users = (List<User>) Database.queryWithBinds(
            'SELECT Id'
            + ' FROM User'
            + ' WHERE Username LIKE:usernamePattern'
            + ' LIMIT 1',
            new Map<String, Object>{
                'usernamePattern' => usernamePattern
            },
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual(
            1,
            users.size(),
            'Không tìm thấy factory user cho role ' + role
        );
        return users[0];
    }
}