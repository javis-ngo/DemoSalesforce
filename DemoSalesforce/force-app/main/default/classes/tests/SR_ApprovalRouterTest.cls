@IsTest(SeeAllData=false)
private class SR_ApprovalRouterTest {
    private static final String STORE_CODE = 'DUC06';
    private static final Decimal AUTO_THRESHOLD = 2000000;
    private static final Decimal CHT_THRESHOLD = 20000000;

    @TestSetup
    static void setupStorePersonas() {
        SR_TestDataFactory.createStoreSetup(
            STORE_CODE,
            SR_TestDataFactory.REGION_SOUTH
        );
    }

    private static void seedConfig() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    private static SR_ApprovalPreviewDTO input(
        Decimal amount,
        Boolean risk,
        String channel
    ) {
        SR_ApprovalPreviewDTO value = new SR_ApprovalPreviewDTO();
        value.estimatedRefund = amount;
        value.riskFlag = risk;
        value.channel = channel;
        return value;
    }

    private static Store__c configuredStore() {
        return [
            SELECT Id, Store_Code__c, Region__c,
                   Store_Manager__c, Regional_Manager__c
            FROM Store__c
            WHERE Store_Code__c = :STORE_CODE
            LIMIT 1
        ];
    }

    private static Store__c routingStore(Id storeManagerId, Id regionalManagerId) {
        return new Store__c(
            Store_Manager__c = storeManagerId,
            Regional_Manager__c = regionalManagerId
        );
    }

    @IsTest
    static void route_nullInput_returnsMissingField() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(null, null);

        Assert.isFalse(result.success, 'Null input must fail.');
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, result.errorCode);
    }

    @IsTest
    static void route_nullAmount_returnsMissingField() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(null, false, SR_TestDataFactory.CHANNEL_APP),
            null
        );

        Assert.isFalse(result.success);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, result.errorCode);
    }

    @IsTest
    static void route_negativeAmount_returnsInvalidValue() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(-1, false, SR_TestDataFactory.CHANNEL_APP),
            null
        );

        Assert.isFalse(result.success);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, result.errorCode);
    }

    @IsTest
    static void route_invalidChannel_returnsInvalidValue() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(1000, false, 'WEB'),
            null
        );

        Assert.isFalse(result.success);
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, result.errorCode);
    }

    @IsTest
    static void route_autoBoundary_appGoesAwaitingGoods() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(AUTO_THRESHOLD, false, ' app '),
            null
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_AUTO, result.approvalLevel);
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, result.targetStatus);
        Assert.areEqual(null, result.assignedApproverId);
    }

    @IsTest
    static void route_autoBoundary_counterAndPosGoInspecting() {
        seedConfig();

        for (String channel : new List<String>{
            SR_TestDataFactory.CHANNEL_COUNTER,
            SR_TestDataFactory.CHANNEL_POS
        }) {
            SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
                input(AUTO_THRESHOLD, false, channel),
                null
            );

            Assert.isTrue(result.success, channel + ' should auto approve.');
            Assert.areEqual(SR_ApprovalRouter.LEVEL_AUTO, result.approvalLevel);
            Assert.areEqual(SR_StatusMachine.INSPECTING, result.targetStatus);
        }
    }

    @IsTest
    static void route_autoDisabled_routesToCht() {
        seedConfig();
        SR_TestDataFactory.overrideConfig(
            SR_Setting__mdt.Enable_Auto_Approval__c,
            false
        );
        Store__c storeRow = configuredStore();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(1000, false, SR_TestDataFactory.CHANNEL_APP),
            storeRow
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_CHT, result.approvalLevel);
        Assert.areEqual(storeRow.Store_Manager__c, result.assignedApproverId);
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, result.targetStatus);
    }

    @IsTest
    static void route_chtUpperBoundary_routesToCht() {
        seedConfig();
        Store__c storeRow = configuredStore();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(CHT_THRESHOLD, false, SR_TestDataFactory.CHANNEL_COUNTER),
            storeRow
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_CHT, result.approvalLevel);
        Assert.areEqual(storeRow.Store_Manager__c, result.assignedApproverId);
    }

    @IsTest
    static void route_aboveChtThreshold_routesToQlv() {
        seedConfig();
        Store__c storeRow = configuredStore();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(CHT_THRESHOLD + 1, false, SR_TestDataFactory.CHANNEL_COUNTER),
            storeRow
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_QLV, result.approvalLevel);
        Assert.areEqual(storeRow.Regional_Manager__c, result.assignedApproverId);
    }

    @IsTest
    static void route_riskOverridesLowAmount() {
        seedConfig();
        Store__c storeRow = configuredStore();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(1, true, SR_TestDataFactory.CHANNEL_APP),
            storeRow
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_QLV, result.approvalLevel);
        Assert.areEqual(storeRow.Regional_Manager__c, result.assignedApproverId);
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, result.targetStatus);
    }

    @IsTest
    static void route_missingCht_fallsBackToQlv() {
        seedConfig();
        Store__c persisted = configuredStore();
        Store__c routeOnly = routingStore(null, persisted.Regional_Manager__c);

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(AUTO_THRESHOLD + 1, false, SR_TestDataFactory.CHANNEL_POS),
            routeOnly
        );

        Assert.isTrue(result.success);
        Assert.areEqual(SR_ApprovalRouter.LEVEL_QLV, result.approvalLevel);
        Assert.areEqual(persisted.Regional_Manager__c, result.assignedApproverId);
    }

    @IsTest
    static void route_missingRequiredApprover_returnsConfigError() {
        seedConfig();

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(AUTO_THRESHOLD + 1, false, SR_TestDataFactory.CHANNEL_POS),
            routingStore(null, null)
        );

        Assert.isFalse(result.success);
        Assert.areEqual(SR_ErrorCode.CONFIGURATION_ERROR, result.errorCode);
    }

    @IsTest
    static void route_invalidThresholdConfiguration_returnsConfigError() {
        seedConfig();
        SR_TestDataFactory.overrideConfig(
            SR_Setting__mdt.Auto_Approval_Threshold__c,
            CHT_THRESHOLD + 1
        );
        SR_TestDataFactory.overrideConfig(
            SR_Setting__mdt.Store_Manager_Max_Threshold__c,
            CHT_THRESHOLD
        );

        SR_ApprovalPreviewResultDTO result = SR_ApprovalRouter.route(
            input(1000, false, SR_TestDataFactory.CHANNEL_APP),
            null
        );

        Assert.isFalse(result.success);
        Assert.areEqual(SR_ErrorCode.CONFIGURATION_ERROR, result.errorCode);
    }
}
