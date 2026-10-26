@IsTest(SeeAllData=false)
private class SR_ReturnEligibilityServiceTest {
    private static final String STORE_CODE = 'DUC-05';
    private static final String CUSTOMER_NAME = 'Eligibility Test Customer';
    private static final String PHONE_SKU = 'ELIG-PHONE';
    private static final String ACCESSORY_SKU = 'ELIG-ACCESSORY';

    @TestSetup
    static void setupData() {
        Store__c store = SR_TestDataFactory.createStore(
            STORE_CODE,
            SR_TestDataFactory.REGION_NORTH
        );
        Account customer = SR_TestDataFactory.createAccount(
            CUSTOMER_NAME,
            '0907360001',
            false
        );
        Product2 phone = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_PHONE,
            PHONE_SKU,
            'Eligibility Phone',
            1000000
        );
        Product2 accessory = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_ACCESSORY,
            ACCESSORY_SKU,
            'Eligibility Accessory',
            200000
        );

        SR_TestDataFactory.OrderSpec deliveredOrder =
            new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        deliveredOrder.effectiveDate = Date.today().addDays(-10);
        deliveredOrder.deliveryDate = Date.today().addDays(-5);
        deliveredOrder.items.add(
            new SR_TestDataFactory.ItemSpec(phone.Id, 5, 1000000)
        );

        SR_TestDataFactory.OrderSpec counterOrder =
            new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        counterOrder.effectiveDate = Date.today().addDays(-2);
        counterOrder.deliveryDate = null;
        counterOrder.items.add(
            new SR_TestDataFactory.ItemSpec(accessory.Id, 3, 200000)
        );

        SR_TestDataFactory.createOrders(
            new List<SR_TestDataFactory.OrderSpec>{
                deliveredOrder,
                counterOrder
            }
        );
    }

    private static void applyDefaultConfig() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    private static Order orderForSku(String sku) {
        return [
            SELECT Id, EffectiveDate, Delivery_Date__c
            FROM Order
            WHERE Id IN (
                SELECT OrderId
                FROM OrderItem
                WHERE Product2.ProductCode = :sku
            )
            LIMIT 1
        ];
    }

    private static OrderItem itemForSku(String sku) {
        return [
            SELECT Id,
                   OrderId,
                   Product2Id,
                   Product2.Family,
                   Product2.ProductCode,
                   Quantity,
                   UnitPrice
            FROM OrderItem
            WHERE Product2.ProductCode = :sku
            LIMIT 1
        ];
    }

    private static SR_CategoryPolicy policy(
        String family,
        Boolean returnable,
        Integer windowDays,
        Boolean active
    ) {
        return new SR_CategoryPolicy(
            family,
            returnable,
            windowDays,
            active
        );
    }

    private static SR_ReturnableLineDTO lineDto(
        Decimal returnableQuantity,
        Date deadline
    ) {
        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();
        dto.returnableQuantity = returnableQuantity;
        dto.returnDeadline = deadline;
        return dto;
    }

    @IsTest
    static void resolveAnchorDate_coversNullDeliveryAndEffectiveFallback() {
        Assert.isNull(
            SR_ReturnEligibilityService.resolveAnchorDate(null),
            'Null order must produce a null anchor date.'
        );

        Order delivered = new Order(
            EffectiveDate = Date.newInstance(2026, 10, 1),
            Delivery_Date__c = Date.newInstance(2026, 10, 5)
        );
        Assert.areEqual(
            Date.newInstance(2026, 10, 5),
            SR_ReturnEligibilityService.resolveAnchorDate(delivered),
            'Delivery date must take priority over EffectiveDate.'
        );

        Order counterOrder = new Order(
            EffectiveDate = Date.newInstance(2026, 10, 2),
            Delivery_Date__c = null
        );
        Assert.areEqual(
            Date.newInstance(2026, 10, 2),
            SR_ReturnEligibilityService.resolveAnchorDate(counterOrder),
            'EffectiveDate must be used when delivery date is absent.'
        );

        Assert.isNull(
            SR_ReturnEligibilityService.resolveAnchorDate(new Order()),
            'An order without either date must produce a null anchor.'
        );
    }

    @IsTest
    static void resolveDeadline_coversMissingInputsZeroAndPositiveWindow() {
        Date anchor = Date.newInstance(2026, 10, 1);
        SR_CategoryPolicy sevenDays = policy('Phone', true, 7, true);

        Assert.isNull(
            SR_ReturnEligibilityService.resolveDeadline(null, sevenDays),
            'Missing anchor date must return null.'
        );
        Assert.isNull(
            SR_ReturnEligibilityService.resolveDeadline(anchor, null),
            'Missing policy must return null.'
        );
        Assert.isNull(
            SR_ReturnEligibilityService.resolveDeadline(
                anchor,
                policy('Phone', true, null, true)
            ),
            'Missing return window must return null.'
        );
        Assert.areEqual(
            anchor,
            SR_ReturnEligibilityService.resolveDeadline(
                anchor,
                policy('Phone', true, 0, true)
            ),
            'Zero-day policy must expire on the anchor date.'
        );
        Assert.areEqual(
            Date.newInstance(2026, 10, 8),
            SR_ReturnEligibilityService.resolveDeadline(anchor, sevenDays),
            'Deadline must include the configured number of days.'
        );
    }

    @IsTest
    static void reservedQuantity_coversNullMissingNegativeNullAndPositiveValues() {
        OrderItem phoneItem = itemForSku(PHONE_SKU);

        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.reservedQuantity(null, new Map<Id, Decimal>()),
            'Null OrderItem Id must reserve zero.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.reservedQuantity(phoneItem.Id, null),
            'Null reservation map must reserve zero.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.reservedQuantity(
                phoneItem.Id,
                new Map<Id, Decimal>()
            ),
            'Missing map entry must reserve zero.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.reservedQuantity(
                phoneItem.Id,
                new Map<Id, Decimal>{ phoneItem.Id => null }
            ),
            'Null reservation value must normalize to zero.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.reservedQuantity(
                phoneItem.Id,
                new Map<Id, Decimal>{ phoneItem.Id => -2 }
            ),
            'Negative reservation value must normalize to zero.'
        );
        Assert.areEqual(
            2.5,
            SR_ReturnEligibilityService.reservedQuantity(
                phoneItem.Id,
                new Map<Id, Decimal>{ phoneItem.Id => 2.5 }
            ),
            'Positive reservation value must be returned unchanged.'
        );
    }

    @IsTest
    static void remainingQuantity_coversNullZeroPositiveAndOversubscribedValues() {
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.remainingQuantity(null, null),
            'Null purchased and reserved quantities must return zero.'
        );
        Assert.areEqual(
            5,
            SR_ReturnEligibilityService.remainingQuantity(5, null),
            'Null reserved quantity must be treated as zero.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.remainingQuantity(null, 2),
            'Null purchased quantity must be treated as zero and floored.'
        );
        Assert.areEqual(
            3,
            SR_ReturnEligibilityService.remainingQuantity(5, 2),
            'Remaining quantity must be purchased minus reserved.'
        );
        Assert.areEqual(
            0,
            SR_ReturnEligibilityService.remainingQuantity(2, 5),
            'Oversubscribed quantity must be floored at zero.'
        );
    }

    @IsTest
    static void categoryReturnability_coversEveryPolicyState() {
        Assert.isFalse(
            SR_ReturnEligibilityService.isCategoryReturnable(null),
            'Missing policy cannot be returnable.'
        );
        Assert.isFalse(
            SR_ReturnEligibilityService.isCategoryReturnable(
                policy('Phone', true, 7, false)
            ),
            'Inactive policy cannot be returnable.'
        );
        Assert.isFalse(
            SR_ReturnEligibilityService.isCategoryReturnable(
                policy('Phone', false, 7, true)
            ),
            'Non-returnable category must return false.'
        );
        Assert.isTrue(
            SR_ReturnEligibilityService.isCategoryReturnable(
                policy('Phone', true, 7, true)
            ),
            'Active returnable category must return true.'
        );
    }

    @IsTest
    static void returnWindow_coversNullPastBoundaryAndFutureDates() {
        Date todayValue = Date.newInstance(2026, 10, 25);

        Assert.isFalse(
            SR_ReturnEligibilityService.isWithinReturnWindow(null, todayValue),
            'Null today value must return false.'
        );
        Assert.isFalse(
            SR_ReturnEligibilityService.isWithinReturnWindow(todayValue, null),
            'Null deadline must return false.'
        );
        Assert.isFalse(
            SR_ReturnEligibilityService.isWithinReturnWindow(
                todayValue,
                todayValue.addDays(-1)
            ),
            'A past deadline must be expired.'
        );
        Assert.isTrue(
            SR_ReturnEligibilityService.isWithinReturnWindow(
                todayValue,
                todayValue
            ),
            'The exact deadline date must remain eligible.'
        );
        Assert.isTrue(
            SR_ReturnEligibilityService.isWithinReturnWindow(
                todayValue,
                todayValue.addDays(1)
            ),
            'A future deadline must remain eligible.'
        );
    }

    @IsTest
    static void applyLock_coversNullMissingInactiveAndNotReturnablePolicies() {
        SR_ReturnEligibilityService.applyLock(null, null, Date.today());

        SR_ReturnableLineDTO missingPolicy = lineDto(1, Date.today());
        SR_ReturnEligibilityService.applyLock(
            missingPolicy,
            null,
            Date.today()
        );
        Assert.isFalse(missingPolicy.eligible);
        Assert.areEqual(
            SR_ErrorCode.CONFIGURATION_ERROR,
            missingPolicy.lockCode
        );
        Assert.areEqual(
            'Không tìm thấy policy ngành hàng.',
            missingPolicy.lockMessage
        );

        SR_ReturnableLineDTO inactivePolicy = lineDto(1, Date.today());
        SR_ReturnEligibilityService.applyLock(
            inactivePolicy,
            policy('Phone', true, 7, false),
            Date.today()
        );
        Assert.isFalse(inactivePolicy.eligible);
        Assert.areEqual(
            SR_ErrorCode.CONFIGURATION_ERROR,
            inactivePolicy.lockCode
        );

        SR_ReturnableLineDTO prohibited = lineDto(1, Date.today());
        SR_ReturnEligibilityService.applyLock(
            prohibited,
            policy('Prepaid', false, 0, true),
            Date.today()
        );
        Assert.isFalse(prohibited.eligible);
        Assert.areEqual(SR_ErrorCode.NOT_RETURNABLE, prohibited.lockCode);
        Assert.areEqual(
            SR_ErrorCode.message(SR_ErrorCode.NOT_RETURNABLE),
            prohibited.lockMessage
        );
    }

    @IsTest
    static void applyLock_coversExpiredQuantityAndEligibleBranches() {
        SR_CategoryPolicy validPolicy = policy('Phone', true, 7, true);
        Date todayValue = Date.today();

        SR_ReturnableLineDTO expired = lineDto(
            1,
            todayValue.addDays(-1)
        );
        SR_ReturnEligibilityService.applyLock(
            expired,
            validPolicy,
            todayValue
        );
        Assert.isFalse(expired.eligible);
        Assert.areEqual(
            SR_ErrorCode.RETURN_WINDOW_EXPIRED,
            expired.lockCode
        );

        SR_ReturnableLineDTO nullQuantity = lineDto(null, todayValue);
        SR_ReturnEligibilityService.applyLock(
            nullQuantity,
            validPolicy,
            todayValue
        );
        Assert.isFalse(nullQuantity.eligible);
        Assert.areEqual(
            SR_ErrorCode.QUANTITY_EXCEEDED,
            nullQuantity.lockCode
        );

        SR_ReturnableLineDTO zeroQuantity = lineDto(0, todayValue);
        SR_ReturnEligibilityService.applyLock(
            zeroQuantity,
            validPolicy,
            todayValue
        );
        Assert.isFalse(zeroQuantity.eligible);
        Assert.areEqual(
            SR_ErrorCode.QUANTITY_EXCEEDED,
            zeroQuantity.lockCode
        );

        SR_ReturnableLineDTO eligible = lineDto(
            2,
            todayValue.addDays(1)
        );
        eligible.eligible = false;
        eligible.lockCode = 'STALE_CODE';
        eligible.lockMessage = 'Stale message';
        SR_ReturnEligibilityService.applyLock(
            eligible,
            validPolicy,
            todayValue
        );
        Assert.isTrue(eligible.eligible);
        Assert.isNull(eligible.lockCode);
        Assert.isNull(eligible.lockMessage);
    }

    @IsTest
    static void populateLine_nullGuards_leaveInputsUnchanged() {
        applyDefaultConfig();
        Order phoneOrder = orderForSku(PHONE_SKU);
        OrderItem phoneItem = itemForSku(PHONE_SKU);

        SR_ReturnEligibilityService.populateLine(
            null,
            phoneOrder,
            phoneItem,
            null,
            Date.today()
        );

        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();
        dto.eligible = false;
        dto.lockCode = 'UNCHANGED';
        SR_ReturnEligibilityService.populateLine(
            dto,
            phoneOrder,
            null,
            null,
            Date.today()
        );
        Assert.isFalse(dto.eligible);
        Assert.areEqual('UNCHANGED', dto.lockCode);
    }

    @IsTest
    static void populateLine_deliveryDateAndReservations_populatesEligibleLine() {
        applyDefaultConfig();
        Order phoneOrder = orderForSku(PHONE_SKU);
        OrderItem phoneItem = itemForSku(PHONE_SKU);
        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();

        Test.startTest();
        SR_ReturnEligibilityService.populateLine(
            dto,
            phoneOrder,
            phoneItem,
            new Map<Id, Decimal>{ phoneItem.Id => 2 },
            Date.today()
        );
        Test.stopTest();

        Assert.areEqual(2, dto.previouslyReturnedQuantity);
        Assert.areEqual(3, dto.returnableQuantity);
        Assert.areEqual(
            phoneOrder.Delivery_Date__c.addDays(30),
            dto.returnDeadline
        );
        Assert.isTrue(dto.eligible);
        Assert.isNull(dto.lockCode);
        Assert.isNull(dto.lockMessage);
    }

    @IsTest
    static void populateLine_effectiveDateFallbackAndFullReservation_locksQuantity() {
        applyDefaultConfig();
        Order counterOrder = orderForSku(ACCESSORY_SKU);
        OrderItem accessoryItem = itemForSku(ACCESSORY_SKU);
        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();

        SR_ReturnEligibilityService.populateLine(
            dto,
            counterOrder,
            accessoryItem,
            new Map<Id, Decimal>{ accessoryItem.Id => 3 },
            Date.today()
        );

        Assert.areEqual(3, dto.previouslyReturnedQuantity);
        Assert.areEqual(0, dto.returnableQuantity);
        Assert.areEqual(
            counterOrder.EffectiveDate.addDays(7),
            dto.returnDeadline,
            'Counter order must fall back to EffectiveDate.'
        );
        Assert.isFalse(dto.eligible);
        Assert.areEqual(
            SR_ErrorCode.QUANTITY_EXCEEDED,
            dto.lockCode
        );
    }

    @IsTest
    static void populateLine_missingFamilyPolicy_returnsConfigurationError() {
        SR_TestDataFactory.resetConfig();
        SR_Config.setCategoryPolicyOverrides(
            new Map<String, SR_CategoryPolicy>{
                SR_TestDataFactory.FAMILY_PHONE => policy(
                    SR_TestDataFactory.FAMILY_PHONE,
                    true,
                    30,
                    true
                )
            }
        );

        Order counterOrder = orderForSku(ACCESSORY_SKU);
        OrderItem accessoryItem = itemForSku(ACCESSORY_SKU);
        SR_ReturnableLineDTO dto = new SR_ReturnableLineDTO();

        SR_ReturnEligibilityService.populateLine(
            dto,
            counterOrder,
            accessoryItem,
            null,
            Date.today()
        );

        Assert.areEqual(0, dto.previouslyReturnedQuantity);
        Assert.areEqual(3, dto.returnableQuantity);
        Assert.isNull(
            dto.returnDeadline,
            'A missing policy cannot produce a deadline.'
        );
        Assert.isFalse(dto.eligible);
        Assert.areEqual(
            SR_ErrorCode.CONFIGURATION_ERROR,
            dto.lockCode
        );
    }
}
