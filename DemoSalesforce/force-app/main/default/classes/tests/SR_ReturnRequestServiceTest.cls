@IsTest(SeeAllData=false)
private class SR_ReturnRequestServiceTest {
    @TestSetup
    static void setupData() {
        Store__c store = SR_TestDataFactory.createStore('SR-D04', SR_TestDataFactory.REGION_NORTH);
        Account customer = SR_TestDataFactory.createAccount('Khách DUC-04', '0901234567', false);
        Map<String, Product2> catalog = SR_TestDataFactory.createProductCatalog();

        SR_TestDataFactory.OrderSpec appliance = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        appliance.effectiveDate = Date.today().addDays(-3);
        appliance.deliveryDate = Date.today().addDays(-2);
        appliance.items.add(new SR_TestDataFactory.ItemSpec(catalog.get(SR_TestDataFactory.FAMILY_APPLIANCE).Id, 2, 2490000));

        SR_TestDataFactory.OrderSpec phoneExpired = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        phoneExpired.effectiveDate = Date.today().addDays(-40);
        phoneExpired.deliveryDate = Date.today().addDays(-31);
        phoneExpired.items.add(new SR_TestDataFactory.ItemSpec(catalog.get(SR_TestDataFactory.FAMILY_PHONE).Id, 1, 12000000));

        SR_TestDataFactory.OrderSpec prepaid = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        prepaid.effectiveDate = Date.today();
        prepaid.deliveryDate = Date.today();
        prepaid.items.add(new SR_TestDataFactory.ItemSpec(catalog.get(SR_TestDataFactory.FAMILY_PREPAID).Id, 1, 100000));

        SR_TestDataFactory.OrderSpec counterNoDelivery = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        counterNoDelivery.effectiveDate = Date.today().addDays(-1);
        counterNoDelivery.deliveryDate = null;
        counterNoDelivery.items.add(new SR_TestDataFactory.ItemSpec(catalog.get(SR_TestDataFactory.FAMILY_ACCESSORY).Id, 1, 350000));

        SR_TestDataFactory.createOrders(new List<SR_TestDataFactory.OrderSpec>{
            appliance, phoneExpired, prepaid, counterNoDelivery
        });
    }

    private static void applyConfig() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    private static Order orderForSku(String sku) {
        return [
            SELECT Id, OrderNumber, AccountId, Account.Phone, EffectiveDate, Delivery_Date__c, Store__c
            FROM Order
            WHERE Id IN (SELECT OrderId FROM OrderItem WHERE Product2.ProductCode = :sku)
            LIMIT 1
        ];
    }

    private static OrderItem itemForSku(String sku) {
        return [
            SELECT Id, OrderId, Product2Id, Product2.ProductCode, Quantity, UnitPrice
            FROM OrderItem
            WHERE Product2.ProductCode = :sku
            LIMIT 1
        ];
    }

    private static SR_CreateRequestDTO requestFor(
        String sku,
        Decimal quantity,
        String reason,
        String condition,
        String channel,
        String externalId
    ) {
        OrderItem item = itemForSku(sku);
        SR_CreateLineDTO line = new SR_CreateLineDTO();
        line.orderItemId = item.Id;
        line.sku = sku;
        line.quantity = quantity;
        line.reason = reason;
        line.condition = condition;

        SR_CreateRequestDTO request = new SR_CreateRequestDTO();
        request.orderId = item.OrderId;
        request.channel = channel;
        request.externalRequestId = externalId;
        request.lines = new List<SR_CreateLineDTO>{ line };
        return request;
    }

    @IsTest
    static void positive_lastDayEligibleAndCreateAutoInspecting() {
        applyConfig();
        OrderItem item = itemForSku('AF-PH-5L');
        Order orderRow = [SELECT Id, Delivery_Date__c FROM Order WHERE Id = :item.OrderId];
        orderRow.Delivery_Date__c = Date.today().addDays(-7);
        update orderRow;

        Test.startTest();
        SR_ReturnableOrderDTO returnable = SR_ReturnRequestService.getReturnableOrder(orderRow.Id);
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{
                requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', SR_ReturnRequestService.CHANNEL_COUNTER, null)
            }
        );
        Test.stopTest();

        Assert.isTrue(returnable.lines[0].eligible, 'Ngày cuối cửa sổ vẫn được trả.');
        Assert.areEqual(Date.today(), returnable.lines[0].returnDeadline);
        Assert.isTrue(results[0].success, JSON.serialize(results[0].errors));
        Assert.areEqual(2490000, results[0].estimatedRefund);
        Assert.areEqual('CHT', results[0].approvalLevel);
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, results[0].status);
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Return_Request_History__c WHERE Return_Request__c = :results[0].requestId]
        );
    }

    @IsTest
    static void negative_expiredCategoryQuantityAndSku() {
        applyConfig();
        Order expired = orderForSku('DT-PH-001');
        SR_ReturnableOrderDTO expiredLines = SR_ReturnRequestService.getReturnableOrder(expired.Id);
        Assert.isFalse(expiredLines.lines[0].eligible);
        Assert.areEqual(SR_ErrorCode.RETURN_WINDOW_EXPIRED, expiredLines.lines[0].lockCode);

        Order prepaid = orderForSku('TC-VT-100K');
        SR_ReturnableOrderDTO prepaidLines = SR_ReturnRequestService.getReturnableOrder(prepaid.Id);
        Assert.isFalse(prepaidLines.lines[0].eligible);
        Assert.areEqual(SR_ErrorCode.NOT_RETURNABLE, prepaidLines.lines[0].lockCode);

        SR_CreateRequestDTO unknownSku = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null);
        unknownSku.lines[0].orderItemId = null;
        unknownSku.lines[0].sku = 'SKU-KHONG-CO';

        SR_CreateRequestDTO tooMany = requestFor('AF-PH-5L', 9, 'DEFECT', 'SEALED', 'COUNTER', null);
        SR_CreateRequestDTO expiredCreate = requestFor('DT-PH-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null);
        SR_CreateRequestDTO prepaidCreate = requestFor('TC-VT-100K', 1, 'DEFECT', 'SEALED', 'COUNTER', null);
        SR_CreateRequestDTO zeroRate = requestFor('AF-PH-5L', 1, 'CUSTOMER_DAMAGE', 'USED', 'COUNTER', null);
        SR_CreateRequestDTO missing = new SR_CreateRequestDTO();

        Test.startTest();
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{ unknownSku, tooMany, expiredCreate, prepaidCreate, zeroRate, missing }
        );
        Test.stopTest();

        Assert.areEqual(SR_ErrorCode.SKU_NOT_IN_ORDER, results[0].errors[0].code);
        Assert.areEqual(SR_ErrorCode.QUANTITY_EXCEEDED, results[1].errors[0].code);
        Assert.areEqual(SR_ErrorCode.RETURN_WINDOW_EXPIRED, results[2].errors[0].code);
        Assert.areEqual(SR_ErrorCode.NOT_RETURNABLE, results[3].errors[0].code);
        Assert.areEqual(SR_ErrorCode.NOT_RETURNABLE, results[4].errors[0].code);
        Assert.isFalse(results[5].success);
    }

    @IsTest
    static void positive_partialReturnThenRemainingQuantity() {
        applyConfig();
        Test.startTest();
        SR_CreateResultDTO first = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{
                requestFor('AF-PH-5L', 1, 'NOT_SATISFIED', 'OPENED', 'COUNTER', null)
            }
        )[0];
        SR_ReturnableOrderDTO afterFirst = SR_ReturnRequestService.getReturnableOrder(itemForSku('AF-PH-5L').OrderId);
        SR_CreateResultDTO secondExceeded = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{
                requestFor('AF-PH-5L', 2, 'DEFECT', 'SEALED', 'COUNTER', null)
            }
        )[0];
        Test.stopTest();

        Assert.isTrue(first.success, JSON.serialize(first.errors));
        Assert.areEqual(1992000, first.estimatedRefund);
        Assert.areEqual(1, afterFirst.lines[0].previouslyReturnedQuantity);
        Assert.areEqual(1, afterFirst.lines[0].returnableQuantity);
        Assert.areEqual(SR_ErrorCode.QUANTITY_EXCEEDED, secondExceeded.errors[0].code);
    }

    @IsTest
    static void positive_duplicateExternalIdAndSameBatchOversubscribe() {
        applyConfig();
        SR_CreateRequestDTO first = requestFor('PK-CB-001', 1, 'DEFECT', 'SEALED', 'POS', 'POS-EXT-1');
        SR_CreateRequestDTO duplicate = requestFor('PK-CB-001', 1, 'DEFECT', 'SEALED', 'POS', 'POS-EXT-1');
        SR_CreateRequestDTO batchA = requestFor('AF-PH-5L', 2, 'DEFECT', 'SEALED', 'POS', 'POS-EXT-A');
        SR_CreateRequestDTO batchB = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'POS', 'POS-EXT-B');

        Test.startTest();
        SR_CreateResultDTO created = SR_ReturnRequestService.createRequests(new List<SR_CreateRequestDTO>{ first })[0];
        SR_CreateResultDTO replayed = SR_ReturnRequestService.createRequests(new List<SR_CreateRequestDTO>{ duplicate })[0];
        List<SR_CreateResultDTO> sameBatch = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{ batchA, batchB }
        );
        Test.stopTest();

        Assert.isTrue(created.success, JSON.serialize(created.errors));
        Assert.isTrue(replayed.isDuplicate);
        Assert.areEqual(created.requestId, replayed.requestId);
        Assert.isTrue(sameBatch[0].success, JSON.serialize(sameBatch[0].errors));
        Assert.areEqual(SR_ErrorCode.QUANTITY_EXCEEDED, sameBatch[1].errors[0].code);
    }

    @IsTest
    static void positive_riskCountAndAmountThresholds() {
        applyConfig();
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Risk_Request_Count__c, 1);
        Test.startTest();
        SR_CreateResultDTO flagged = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{
                requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null)
            }
        )[0];
        Test.stopTest();

        Assert.isTrue(flagged.success, JSON.serialize(flagged.errors));
        Assert.areEqual('QLV', flagged.approvalLevel);
        Account customer = [SELECT Risk_Flag__c FROM Account WHERE Phone = '0901234567'];
        Assert.isTrue(customer.Risk_Flag__c);
    }

    @IsTest
    static void negative_phoneMismatchAndMissingExternalId() {
        applyConfig();
        SR_CreateRequestDTO mismatch = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'APP', 'APP-1');
        mismatch.customerPhone = '0000000000';
        SR_CreateRequestDTO missingExt = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'POS', null);

        Test.startTest();
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{ mismatch, missingExt }
        );
        Test.stopTest();

        Assert.areEqual(SR_ErrorCode.ORDER_NOT_FOUND, results[0].errors[0].code);
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[1].errors[0].code);
    }

    @IsTest
    static void positive_previewDoesNotInsert() {
        applyConfig();
        Test.startTest();
        SR_ApprovalPreviewResultDTO preview = SR_ReturnRequestService.previewCreate(
            requestFor('PK-CB-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null)
        );
        Test.stopTest();

        Assert.isTrue(preview.success);
        Assert.areEqual(350000, preview.estimatedRefund);
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);
    }

    @IsTest
    static void bulk_twoHundredRequestsWithMixedValidity() {
        applyConfig();
        List<SR_CreateRequestDTO> requests = new List<SR_CreateRequestDTO>();
        requests.add(requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null));
        for (Integer i = 0; i < 199; i++) {
            SR_CreateRequestDTO invalid = new SR_CreateRequestDTO();
            invalid.channel = 'COUNTER';
            invalid.orderId = requests[0].orderId;
            requests.add(invalid);
        }

        Test.startTest();
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(requests);
        Test.stopTest();

        Assert.areEqual(200, results.size());
        Assert.isTrue(results[0].success, JSON.serialize(results[0].errors));
        Integer failed = 0;
        for (Integer i = 1; i < results.size(); i++) {
            if (results[i].success != true) {
                failed++;
            }
        }
        Assert.areEqual(199, failed);
        Assert.areEqual(1, [SELECT COUNT() FROM Return_Request__c]);
    }
}
