@IsTest(SeeAllData=false)          
private class SR_ReturnRequestServiceTest {          
    @TestSetup          
    static void setupData() {          
        Store__c store = SR_TestDataFactory.createStore(        
            'SR-D04',        
            SR_TestDataFactory.REGION_NORTH,        
            UserInfo.getUserId(),        
            UserInfo.getUserId()        
        );          
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
    @IsTest      
    static void negative_publicApiGuardsAndBatchLimit() {      
        applyConfig();      
        List<SR_CreateRequestDTO> overLimit = new List<SR_CreateRequestDTO>();      
        for (Integer i = 0; i < 201; i++) {      
            overLimit.add(new SR_CreateRequestDTO());      
        }      
        Test.startTest();      
        SR_ReturnableOrderDTO nullOrder = SR_ReturnRequestService.getReturnableOrder(null);      
        List<SR_ReturnableLineDTO> nullLines = SR_ReturnRequestService.getReturnableLines(null);      
        SR_ApprovalPreviewResultDTO nullPreview = SR_ReturnRequestService.previewCreate(null);      
        List<SR_CreateResultDTO> nullBatch = SR_ReturnRequestService.createRequests(null);      
        List<SR_CreateResultDTO> emptyBatch = SR_ReturnRequestService.createRequests(new List<SR_CreateRequestDTO>());      
        List<SR_CreateResultDTO> oversizedBatch = SR_ReturnRequestService.createRequests(overLimit);      
        Decimal calculated = SR_ReturnRequestService.calcLineRefund(1234567, 2, 80);      
        Test.stopTest();      
        Assert.isNull(nullOrder.orderId);      
        Assert.areEqual(0, nullOrder.lines.size());      
        Assert.areEqual(0, nullLines.size());      
        Assert.isFalse(nullPreview.success);      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, nullPreview.errorCode);      
        Assert.areEqual(0, nullBatch.size());      
        Assert.areEqual(0, emptyBatch.size());      
        Assert.areEqual(201, oversizedBatch.size());      
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, oversizedBatch[0].errors[0].code);      
        Assert.isTrue(calculated > 0);      
    }      
    @IsTest      
    static void negative_envelopeAndNullRequestValidation() {      
        applyConfig();      
        SR_CreateRequestDTO blankChannel = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', ' ', null);      
        SR_CreateRequestDTO invalidChannel = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'EMAIL', null);      
        SR_CreateRequestDTO missingOrder = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null);      
        missingOrder.orderId = null;      
        missingOrder.orderNumber = null;      
        SR_CreateRequestDTO missingLines = requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null);      
        missingLines.lines = new List<SR_CreateLineDTO>();      
        Test.startTest();      
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(      
            new List<SR_CreateRequestDTO>{ null, blankChannel, invalidChannel, missingOrder, missingLines }      
        );      
        Test.stopTest();      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[1].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[2].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[3].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[4].errors[0].code);      
    }      
    @IsTest      
    static void positive_orderNumberStoreCodeSkuAndNormalizedPhone() {      
        applyConfig();      
        Order orderRow = orderForSku('PK-CB-001');      
        SR_CreateRequestDTO request = requestFor(      
            'PK-CB-001', 1, 'DEFECT', 'SEALED', ' pos ', ' POS-BY-NUMBER '      
        );      
        request.orderId = null;      
        request.orderNumber = orderRow.OrderNumber;      
        request.storeCode = ' SR-D04 ';      
        request.customerPhone = '090 123-4567';      
        request.lines[0].orderItemId = null;      
        Test.startTest();      
        SR_CreateResultDTO result = SR_ReturnRequestService.createRequests(      
            new List<SR_CreateRequestDTO>{ request }      
        )[0];      
        Test.stopTest();      
        Assert.isTrue(result.success, JSON.serialize(result.errors));      
        Assert.areEqual(1, result.lines.size());      
        Assert.areEqual('PK-CB-001', result.lines[0].sku);      
        Assert.areEqual(350000, result.estimatedRefund);      
        Assert.areEqual(SR_ReturnRequestService.CHANNEL_POS,      
            [SELECT Channel__c FROM Return_Request__c WHERE Id = :result.requestId].Channel__c);      
    }      
    @IsTest      
    static void negative_lineValidationAndReservationRollback() {      
        applyConfig();      
        SR_CreateRequestDTO partiallyAccepted = requestFor(      
            'AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null      
        );      
        partiallyAccepted.lines.add(null);      
        SR_CreateRequestDTO fullQuantityAfterRollback = requestFor(      
            'AF-PH-5L', 2, 'DEFECT', 'SEALED', 'COUNTER', null      
        );      
        SR_CreateRequestDTO zeroQuantity = requestFor(      
            'PK-CB-001', 0, 'DEFECT', 'SEALED', 'COUNTER', null      
        );      
        SR_CreateRequestDTO invalidReason = requestFor(      
            'PK-CB-001', 1, 'UNKNOWN', 'SEALED', 'COUNTER', null      
        );      
        SR_CreateRequestDTO invalidCondition = requestFor(      
            'PK-CB-001', 1, 'DEFECT', 'BROKEN', 'COUNTER', null      
        );      
        Test.startTest();      
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(      
            new List<SR_CreateRequestDTO>{      
                partiallyAccepted,      
                fullQuantityAfterRollback,      
                zeroQuantity,      
                invalidReason,      
                invalidCondition      
            }      
        );      
        Test.stopTest();      
        Assert.areEqual(SR_ErrorCode.MISSING_FIELD, results[0].errors[0].code);      
        Assert.isTrue(results[1].success, JSON.serialize(results[1].errors));      
        Assert.areEqual(2, results[1].lines[0].quantity);      
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[2].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[3].errors[0].code);      
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[4].errors[0].code);      
        Assert.areEqual(1, [SELECT COUNT() FROM Return_Request__c]);      
    }      
    @IsTest      
    static void negative_missingApproverConfiguration() {      
        applyConfig();      
        Store__c storeWithoutApprovers = SR_TestDataFactory.createStore(      
            'SR-NO-MGR', SR_TestDataFactory.REGION_NORTH      
        );      
        Account customer = [SELECT Id FROM Account WHERE Phone = '0901234567' LIMIT 1];      
        Product2 appliance = [SELECT Id FROM Product2 WHERE ProductCode = 'AF-PH-5L' LIMIT 1];      
        SR_TestDataFactory.OrderSpec spec = new SR_TestDataFactory.OrderSpec(      
            customer.Id, storeWithoutApprovers.Id      
        );      
        spec.effectiveDate = Date.today().addDays(-2);      
        spec.deliveryDate = Date.today().addDays(-1);      
        spec.items.add(new SR_TestDataFactory.ItemSpec(appliance.Id, 1, 2490000));      
        Order orderRow = SR_TestDataFactory.createOrder(spec);      
        OrderItem item = [SELECT Id FROM OrderItem WHERE OrderId = :orderRow.Id LIMIT 1];      
        SR_CreateLineDTO line = new SR_CreateLineDTO();      
        line.orderItemId = item.Id;      
        line.sku = 'AF-PH-5L';      
        line.quantity = 1;      
        line.reason = 'DEFECT';      
        line.condition = 'SEALED';      
        SR_CreateRequestDTO request = new SR_CreateRequestDTO();      
        request.orderId = orderRow.Id;      
        request.storeCode = 'SR-NO-MGR';      
        request.channel = 'POS';      
        request.externalRequestId = 'POS-NO-MANAGER';      
        request.lines = new List<SR_CreateLineDTO>{ line };      
        Test.startTest();      
        SR_CreateResultDTO result = SR_ReturnRequestService.createRequests(      
            new List<SR_CreateRequestDTO>{ request }      
        )[0];      
        Test.stopTest();      
        Assert.isFalse(result.success);      
        Assert.areEqual(SR_ErrorCode.CONFIGURATION_ERROR, result.errors[0].code);      
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c WHERE Order__c = :orderRow.Id]);      
    }      
    @IsTest      
    static void positive_riskAmountThresholdAndPersistedFields() {      
        applyConfig();      
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Risk_Request_Count__c, 999);      
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Risk_Total_Amount__c, 1000000);      
        Test.startTest();      
        SR_CreateResultDTO result = SR_ReturnRequestService.createRequests(      
            new List<SR_CreateRequestDTO>{      
                requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null)      
            }      
        )[0];      
        Test.stopTest();      
        Assert.isTrue(result.success, JSON.serialize(result.errors));      
        Assert.areEqual('QLV', result.approvalLevel);      
        Return_Request__c saved = [      
            SELECT Assigned_Approver__c, Submitted_At__c,      
                   Approval_Due_At__c, Version_Token__c      
            FROM Return_Request__c      
            WHERE Id = :result.requestId      
        ];      
        Account customer = [SELECT Risk_Flag__c FROM Account WHERE Phone = '0901234567'];      
        Assert.isTrue(customer.Risk_Flag__c);      
        Assert.isNotNull(saved.Assigned_Approver__c);      
        Assert.isNotNull(saved.Submitted_At__c);      
        Assert.isNotNull(saved.Approval_Due_At__c);      
        Assert.isNotNull(saved.Version_Token__c);      
    }      
    @IsTest    
    static void negative_missingOrderLookupAndPreviewErrors() {    
        applyConfig();    
        Account customer = [SELECT Id FROM Account WHERE Phone = '0901234567' LIMIT 1];    
        SR_CreateRequestDTO invalidChannel = requestFor(    
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'EMAIL', null    
        );    
        SR_CreateRequestDTO missingOrder = requestFor(    
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null    
        );    
        missingOrder.orderId = customer.Id;    
        Test.startTest();    
        SR_ReturnableOrderDTO notAnOrder = SR_ReturnRequestService.getReturnableOrder(customer.Id);    
        SR_ApprovalPreviewResultDTO invalidChannelPreview =    
            SR_ReturnRequestService.previewCreate(invalidChannel);    
        SR_ApprovalPreviewResultDTO missingOrderPreview =    
            SR_ReturnRequestService.previewCreate(missingOrder);    
        Test.stopTest();    
        Assert.isNull(notAnOrder.orderId);    
        Assert.areEqual(0, notAnOrder.lines.size());    
        Assert.isFalse(invalidChannelPreview.success);    
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, invalidChannelPreview.errorCode);    
        Assert.isFalse(missingOrderPreview.success);    
        Assert.areEqual(SR_ErrorCode.ORDER_NOT_FOUND, missingOrderPreview.errorCode);    
    }    
    @IsTest    
    static void negative_missingStoreAndRefundRateConfiguration() {    
        applyConfig();    
        Account customer = [SELECT Id FROM Account WHERE Phone = '0901234567' LIMIT 1];    
        Product2 accessory = [SELECT Id FROM Product2 WHERE ProductCode = 'PK-CB-001' LIMIT 1];    
        SR_TestDataFactory.OrderSpec noStoreSpec =    
            new SR_TestDataFactory.OrderSpec(customer.Id, null);    
        noStoreSpec.effectiveDate = Date.today().addDays(-1);    
        noStoreSpec.deliveryDate = null;    
        noStoreSpec.items.add(new SR_TestDataFactory.ItemSpec(accessory.Id, 1, 350000));    
        Order noStoreOrder = SR_TestDataFactory.createOrder(noStoreSpec);    
        OrderItem noStoreItem = [    
            SELECT Id FROM OrderItem WHERE OrderId = :noStoreOrder.Id LIMIT 1    
        ];    
        SR_CreateLineDTO noStoreLine = new SR_CreateLineDTO();    
        noStoreLine.orderItemId = noStoreItem.Id;    
        noStoreLine.sku = 'PK-CB-001';    
        noStoreLine.quantity = 1;    
        noStoreLine.reason = 'DEFECT';    
        noStoreLine.condition = 'SEALED';    
        SR_CreateRequestDTO noStoreRequest = new SR_CreateRequestDTO();    
        noStoreRequest.orderId = noStoreOrder.Id;    
        noStoreRequest.channel = 'POS';    
        noStoreRequest.externalRequestId = 'POS-NO-STORE';    
        noStoreRequest.lines = new List<SR_CreateLineDTO>{ noStoreLine };    
        SR_CreateRequestDTO missingRate = requestFor(    
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null    
        );    
        SR_Config.setRefundRateOverrides(new Map<String, Decimal>{    
            'NOT_SATISFIED|OPENED' => 80    
        });    
        Test.startTest();    
        SR_ApprovalPreviewResultDTO noStorePreview =    
            SR_ReturnRequestService.previewCreate(noStoreRequest);    
        List<SR_CreateResultDTO> noStoreResults = SR_ReturnRequestService.createRequests(    
            new List<SR_CreateRequestDTO>{ noStoreRequest }    
        );    
        List<SR_CreateResultDTO> missingRateResults = SR_ReturnRequestService.createRequests(    
            new List<SR_CreateRequestDTO>{ missingRate }    
        );    
        Test.stopTest();    
        Assert.isFalse(noStorePreview.success);    
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, noStorePreview.errorCode);    
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, noStoreResults[0].errors[0].code);    
        Assert.areEqual(    
            SR_ErrorCode.CONFIGURATION_ERROR,    
            missingRateResults[0].errors[0].code    
        );    
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);    
    }    
    @IsTest    
    static void negative_parentDmlFailureDoesNotBlockValidSibling() {    
        applyConfig();    
        String oversizedExternalId = '';    
        for (Integer i = 0; i < 300; i++) {    
            oversizedExternalId += 'X';    
        }    
        SR_CreateRequestDTO invalidParent = requestFor(    
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'POS', oversizedExternalId    
        );    
        SR_CreateRequestDTO validSibling = requestFor(    
            'AF-PH-5L', 1, 'DEFECT', 'SEALED', 'POS', 'POS-VALID-SIBLING'    
        );    
        Test.startTest();    
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(    
            new List<SR_CreateRequestDTO>{ invalidParent, validSibling }    
        );    
        Test.stopTest();    
        Assert.isFalse(results[0].success);    
        Assert.areEqual(SR_ErrorCode.INVALID_VALUE, results[0].errors[0].code);    
        Assert.isTrue(results[1].success, JSON.serialize(results[1].errors));    
        Assert.areEqual(1, [    
            SELECT COUNT() FROM Return_Request__c    
            WHERE External_Request_Id__c = 'POS-VALID-SIBLING'    
        ]);    
    }    
    @IsTest    
    static void positive_autoRouteAndSameBatchRiskAccumulation() {    
        applyConfig();    
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Risk_Request_Count__c, 2);    
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Risk_Total_Amount__c, 999999999);    
        SR_CreateRequestDTO autoRequest = requestFor(    
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null    
        );    
        SR_CreateRequestDTO batchRiskRequest = requestFor(    
            'AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null    
        );    
        Test.startTest();    
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(    
            new List<SR_CreateRequestDTO>{ autoRequest, batchRiskRequest }    
        );    
        Test.stopTest();    
        Assert.isTrue(results[0].success, JSON.serialize(results[0].errors));    
        Assert.areEqual('AUTO', results[0].approvalLevel);    
        Assert.areEqual(SR_StatusMachine.INSPECTING, results[0].status);    
        Assert.isTrue(results[1].success, JSON.serialize(results[1].errors));    
        Assert.areEqual('QLV', results[1].approvalLevel);    
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, results[1].status);    
        Set<Id> savedIds = new Set<Id>{ results[0].requestId, results[1].requestId };    
        Map<Id, Return_Request__c> savedById = new Map<Id, Return_Request__c>([    
            SELECT Id, Assigned_Approver__c, Submitted_At__c, Approval_Due_At__c    
            FROM Return_Request__c    
            WHERE Id IN :savedIds    
        ]);    
        Return_Request__c autoSaved = savedById.get(results[0].requestId);    
        Return_Request__c riskSaved = savedById.get(results[1].requestId);    
        Assert.isNull(autoSaved.Assigned_Approver__c);    
        Assert.isNull(autoSaved.Submitted_At__c);    
        Assert.isNull(autoSaved.Approval_Due_At__c);    
        Assert.isNotNull(riskSaved.Assigned_Approver__c);    
        Assert.isNotNull(riskSaved.Submitted_At__c);    
        Assert.isNotNull(riskSaved.Approval_Due_At__c);    
    }    
    @IsTest  
    static void negative_unexpectedConfigurationExceptionRollsBackBatch() {  
        applyConfig();  
        SR_CreateRequestDTO first = requestFor(  
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'POS', 'POS-CONFIG-FAIL-1'  
        );  
        SR_CreateRequestDTO second = requestFor(  
            'AF-PH-5L', 1, 'DEFECT', 'SEALED', 'POS', 'POS-CONFIG-FAIL-2'  
        );  
        SR_TestDataFactory.overrideConfig(  
            SR_Setting__mdt.Risk_Window_Days__c,  
            null  
        );  
        Test.startTest();  
        List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(  
            new List<SR_CreateRequestDTO>{ first, second }  
        );  
        Test.stopTest();  
        Assert.areEqual(2, results.size());  
        Assert.isFalse(results[0].success);  
        Assert.isFalse(results[1].success);  
        Assert.areEqual(SR_ErrorCode.INTERNAL_ERROR, results[0].errors[0].code);  
        Assert.areEqual(SR_ErrorCode.INTERNAL_ERROR, results[1].errors[0].code);  
        Assert.isNotNull(results[0].correlationId);  
        Assert.areEqual(results[0].correlationId, results[1].correlationId);  
        Assert.isTrue(results[0].errors[0].message.contains(results[0].correlationId));  
        Assert.areEqual(0, [  
            SELECT COUNT()  
            FROM Return_Request__c  
            WHERE External_Request_Id__c IN ('POS-CONFIG-FAIL-1', 'POS-CONFIG-FAIL-2')  
        ]);  
    }  
    @IsTest  
    static void positive_previewByOrderNumberStoreCodeAndSku() {  
        applyConfig();  
        Order orderRow = orderForSku('PK-CB-001');  
        SR_CreateRequestDTO request = requestFor(  
            'PK-CB-001', 1, 'DEFECT', 'SEALED', ' app ', 'APP-PREVIEW-BY-NUMBER'  
        );  
        request.orderId = null;  
        request.orderNumber = orderRow.OrderNumber;  
        request.storeCode = ' SR-D04 ';  
        request.customerPhone = '(090) 123 4567';  
        request.lines[0].orderItemId = null;  
        Test.startTest();  
        SR_ApprovalPreviewResultDTO preview =  
            SR_ReturnRequestService.previewCreate(request);  
        Test.stopTest();  
        Assert.isTrue(preview.success, JSON.serialize(preview.errors));  
        Assert.areEqual('AUTO', preview.approvalLevel);  
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, preview.targetStatus);  
        Assert.areEqual(350000, preview.estimatedRefund);  
        Assert.isFalse(preview.riskFlag);  
        Assert.areEqual(1, preview.lines.size());  
        Assert.areEqual('PK-CB-001', preview.lines[0].sku);  
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);  
    }  
    @IsTest  
    static void positive_persistedHistoryContributesToRiskCount() {  
        applyConfig();  
        SR_TestDataFactory.overrideConfig(  
            SR_Setting__mdt.Risk_Request_Count__c,  
            2  
        );  
        SR_TestDataFactory.overrideConfig(  
            SR_Setting__mdt.Risk_Total_Amount__c,  
            999999999  
        );  
        Order historicalOrder = orderForSku('DT-PH-001');  
        OrderItem historicalItem = itemForSku('DT-PH-001');  
        SR_TestDataFactory.RequestSpec historical =  
            new SR_TestDataFactory.RequestSpec();  
        historical.accountId = historicalOrder.AccountId;  
        historical.orderId = historicalOrder.Id;  
        historical.storeId = historicalOrder.Store__c;  
        historical.channel = SR_TestDataFactory.CHANNEL_COUNTER;  
        historical.status = SR_StatusMachine.STATUS_NEW;  
        historical.externalRequestId = 'HISTORICAL-RISK-COUNT';  
        SR_TestDataFactory.LineSpec historicalLine =  
            new SR_TestDataFactory.LineSpec();  
        historicalLine.orderItemId = historicalItem.Id;  
        historicalLine.productId = historicalItem.Product2Id;  
        historicalLine.quantity = 1;  
        historicalLine.unitPrice = historicalItem.UnitPrice;  
        historicalLine.refundRate = 100;  
        historicalLine.estimatedRefund = historicalItem.UnitPrice;  
        historical.lines.add(historicalLine);  
        SR_TestDataFactory.createReturnRequest(historical);  
        Test.startTest();  
        SR_CreateResultDTO result = SR_ReturnRequestService.createRequests(  
            new List<SR_CreateRequestDTO>{  
                requestFor('AF-PH-5L', 1, 'DEFECT', 'SEALED', 'COUNTER', null)  
            }  
        )[0];  
        Test.stopTest();  
        Assert.isTrue(result.success, JSON.serialize(result.errors));  
        Assert.areEqual('QLV', result.approvalLevel);  
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, result.status);  
        Account customer = [  
            SELECT Risk_Flag__c, Risk_Flag_Updated_At__c  
            FROM Account  
            WHERE Phone = '0901234567'  
        ];  
        Assert.isTrue(customer.Risk_Flag__c);  
        Assert.isNotNull(customer.Risk_Flag_Updated_At__c);  
    }  


    @IsTest
    static void positive_counterUsesRunningUserStoreBeforeRequestStore() {
        applyConfig();
        User currentUser = [
            SELECT Id, Store_Code__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        currentUser.Store_Code__c = 'SR-D04';
        update currentUser;
        SR_CreateRequestDTO request = requestFor(
            'PK-CB-001', 1, 'DEFECT', 'SEALED', 'COUNTER', null
        );
        request.storeCode = 'STORE-CODE-THAT-DOES-NOT-EXIST';

        Test.startTest();
        SR_ApprovalPreviewResultDTO preview =
            SR_ReturnRequestService.previewCreate(request);
        Test.stopTest();

        Assert.isTrue(preview.success, JSON.serialize(preview.errors));
        Assert.areEqual('AUTO', preview.approvalLevel);
        Assert.areEqual(SR_StatusMachine.INSPECTING, preview.targetStatus);
        Assert.areEqual(350000, preview.estimatedRefund);
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);
    }

    @IsTest
    static void positive_returnableOrderWithoutStoreMapsNullStoreFields() {
        applyConfig();
        Account customer = SR_TestDataFactory.createAccount(
            'Customer Without Store Order',
            null,
            false
        );
        Product2 accessory = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_ACCESSORY,
            'PK-NO-STORE-001',
            'Accessory Without Store',
            125000
        );
        SR_TestDataFactory.OrderSpec spec =
            new SR_TestDataFactory.OrderSpec(customer.Id, null);
        spec.effectiveDate = Date.today().addDays(-1);
        spec.deliveryDate = null;
        spec.items.add(new SR_TestDataFactory.ItemSpec(accessory.Id, 1, 125000));
        Order orderRow = SR_TestDataFactory.createOrder(spec);

        Test.startTest();
        SR_ReturnableOrderDTO result =
            SR_ReturnRequestService.getReturnableOrder(orderRow.Id);
        Test.stopTest();

        Assert.areEqual(orderRow.Id, result.orderId);
        Assert.areEqual('Customer Without Store Order', result.customerName);
        Assert.isNull(result.customerPhone);
        Assert.isNull(result.storeId);
        Assert.isNull(result.storeCode);
        Assert.isNull(result.storeName);
        Assert.areEqual(1, result.lines.size());
        Assert.areEqual('PK-NO-STORE-001', result.lines[0].sku);
        Assert.isNull(result.lines[0].storeId);
        Assert.isNull(result.lines[0].storeCode);
        Assert.isNull(result.lines[0].storeName);
        Assert.areEqual(Date.today().addDays(6), result.lines[0].returnDeadline);
        Assert.isTrue(result.lines[0].eligible);
    }

    @IsTest
    static void positive_appAutoCreateUsesAwaitingGoodsWithoutApprovalDeadline() {
        applyConfig();
        SR_CreateRequestDTO request = requestFor(
            'PK-CB-001',
            1,
            'DEFECT',
            'SEALED',
            'APP',
            'APP-AUTO-AWAITING-GOODS'
        );

        Test.startTest();
        SR_CreateResultDTO result = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{ request }
        )[0];
        Test.stopTest();

        Assert.isTrue(result.success, JSON.serialize(result.errors));
        Assert.areEqual('AUTO', result.approvalLevel);
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, result.status);
        Assert.areEqual(350000, result.estimatedRefund);
        Return_Request__c saved = [
            SELECT Channel__c, Assigned_Approver__c, Submitted_At__c,
                   Approval_Due_At__c, Status__c
            FROM Return_Request__c
            WHERE Id = :result.requestId
        ];
        Assert.areEqual(SR_ReturnRequestService.CHANNEL_APP, saved.Channel__c);
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, saved.Status__c);
        Assert.isNull(saved.Assigned_Approver__c);
        Assert.isNull(saved.Submitted_At__c);
        Assert.isNull(saved.Approval_Due_At__c);
    }

}