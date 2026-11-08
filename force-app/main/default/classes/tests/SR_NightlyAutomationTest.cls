@IsTest(SeeAllData=false)
private class SR_NightlyAutomationTest {

    private static final String STORE_CODE = 'DUC09';
    private static final String CUSTOMER_NAME = 'DUC-09 Automation Customer';

    @TestSetup
    static void setupData() {
        SR_TestDataFactory.StoreSetup setup =
            SR_TestDataFactory.createStoreSetup(
                STORE_CODE,
                SR_TestDataFactory.REGION_SOUTH
            );
        Account customer = SR_TestDataFactory.createAccount(
            CUSTOMER_NAME,
            '0909000009',
            false
        );
        Product2 product = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_PHONE,
            'DUC09-PHONE',
            'DUC-09 test phone',
            12000000
        );
        SR_TestDataFactory.OrderSpec orderSpec =
            new SR_TestDataFactory.OrderSpec(customer.Id, setup.store.Id);
        orderSpec.items.add(new SR_TestDataFactory.ItemSpec(product.Id, 1, 12000000));
        SR_TestDataFactory.createOrder(orderSpec);
        SR_TestDataFactory.createAccount(
            'DUC-09 stale risk customer',
            '0909000010',
            true
        );
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    @IsTest
    static void expiresOnlyAwaitingGoodsPastConfiguredDeadline() {
        Return_Request__c expired = createRequest(
            accountByName(CUSTOMER_NAME).Id,
            SR_TestDataFactory.STATUS_AWAITING_GOODS,
            'DUC09-EXPIRED',
            null,
            null
        );
        update new Return_Request__c(
            Id = expired.Id,
            Goods_Due_Date__c = System.now().addDays(-1)
        );
        Return_Request__c notExpired = createRequest(
            accountByName(CUSTOMER_NAME).Id,
            SR_TestDataFactory.STATUS_AWAITING_GOODS,
            'DUC09-NOT-EXPIRED',
            null,
            null
        );
        update new Return_Request__c(
            Id = notExpired.Id,
            Goods_Due_Date__c = System.now().addDays(1)
        );

        Test.startTest();
        Database.executeBatch(new SR_ExpireAwaitingGoodsBatch(), 50);
        Test.stopTest();

        Set<Id> requestIds = new Set<Id>{ expired.Id, notExpired.Id };
        Map<Id, Return_Request__c> saved = new Map<Id, Return_Request__c>([
            SELECT Id, Status__c
            FROM Return_Request__c
            WHERE Id IN :requestIds
        ]);
        Assert.areEqual(SR_StatusMachine.CANCELLED, saved.get(expired.Id).Status__c);
        Assert.areEqual(SR_StatusMachine.AWAITING_GOODS, saved.get(notExpired.Id).Status__c);
        Assert.areEqual(1, [
            SELECT COUNT()
            FROM Return_Request_History__c
            WHERE Return_Request__c = :expired.Id
              AND To_Status__c = :SR_StatusMachine.CANCELLED
        ]);
    }

    @IsTest
    static void recalculatesRiskForRequestCountAmountAndClearsStaleFlags() {
        Account countCustomer = accountByName(CUSTOMER_NAME);
        createRequests(countCustomer.Id, 3, 0);

        Account amountCustomer = SR_TestDataFactory.createAccount(
            'DUC-09 amount risk customer',
            '0909000011',
            false
        );
        createOrderFor(amountCustomer);
        createRequests(amountCustomer.Id, 1, 30000001);
        Account staleCustomer = accountByName('DUC-09 stale risk customer');

        Test.startTest();
        Database.executeBatch(new SR_RecalculateRiskBatch(), 50);
        Test.stopTest();

        Set<Id> accountIds = new Set<Id>{
            countCustomer.Id,
            amountCustomer.Id,
            staleCustomer.Id
        };
        Map<Id, Account> saved = new Map<Id, Account>([
            SELECT Id, Risk_Flag__c, Risk_Flag_Updated_At__c
            FROM Account
            WHERE Id IN :accountIds
        ]);
        Assert.isTrue(saved.get(countCustomer.Id).Risk_Flag__c);
        Assert.isNotNull(saved.get(countCustomer.Id).Risk_Flag_Updated_At__c);
        Assert.isTrue(saved.get(amountCustomer.Id).Risk_Flag__c);
        Assert.isFalse(saved.get(staleCustomer.Id).Risk_Flag__c);
        Assert.isNotNull(saved.get(staleCustomer.Id).Risk_Flag_Updated_At__c);
    }

    @IsTest
    static void escalatesOverdueApprovalWithoutChangingStatus() {
        Store__c store = storeRecord();
        Return_Request__c requestRecord = createRequest(
            accountByName(CUSTOMER_NAME).Id,
            SR_TestDataFactory.STATUS_PENDING_APPROVAL,
            'DUC09-OVERDUE',
            'CHT',
            System.now().addHours(-25)
        );

        Test.startTest();
        Database.executeBatch(new SR_EscalateApprovalBatch(), 10);
        Test.stopTest();

        Return_Request__c saved = [
            SELECT Status__c, Approval_Level__c, Assigned_Approver__c
            FROM Return_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Assert.areEqual(SR_StatusMachine.PENDING_APPROVAL, saved.Status__c);
        Assert.areEqual('QLV', saved.Approval_Level__c);
        Assert.areEqual(store.Regional_Manager__c, saved.Assigned_Approver__c);
    }

    @IsTest
    static void resumesCompletedInspectionOnlyWhenPayHubEnabled() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Return_Request__c requestRecord = createRequest(
            accountByName(CUSTOMER_NAME).Id,
            SR_StatusMachine.INSPECTING,
            'DUC09-INSPECTED',
            null,
            null
        );
        update new Return_Request__c(
            Id = requestRecord.Id,
            Inspection_Completed_At__c = System.now()
        );
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_PayHub__c, false);

        SR_ResumeRefundBatch batch = new SR_ResumeRefundBatch();
        batch.execute(null, new List<Return_Request__c>{ requestRecord });
        Assert.areEqual(
            SR_StatusMachine.INSPECTING,
            [SELECT Status__c FROM Return_Request__c WHERE Id = :requestRecord.Id].Status__c
        );

        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_PayHub__c, true);
        batch.execute(null, new List<Return_Request__c>{ requestRecord });
        Assert.areEqual(1, Limits.getQueueableJobs());
        Assert.areEqual(
            SR_StatusMachine.REFUND_PROCESSING,
            [SELECT Status__c FROM Return_Request__c WHERE Id = :requestRecord.Id].Status__c
        );
    }

    @IsTest
    static void statusMachineSetsGoodsDeadlineOnAwaitingTransition() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Return_Request__c requestRecord = createRequest(
            accountByName(CUSTOMER_NAME).Id,
            SR_TestDataFactory.STATUS_NEW,
            'DUC09-GOODS-DEADLINE',
            null,
            null
        );
        Datetime beforeTransition = System.now();
        SR_StatusChangeDTO change = new SR_StatusChangeDTO();
        change.requestId = requestRecord.Id;
        change.toStatus = SR_StatusMachine.AWAITING_GOODS;
        change.note = 'Approved';
        List<SR_ActionResultDTO> results =
            SR_StatusMachine.change(new List<SR_StatusChangeDTO>{ change });

        Assert.isTrue(results[0].success);
        Return_Request__c saved = [
            SELECT Goods_Due_Date__c
            FROM Return_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Assert.isTrue(
            saved.Goods_Due_Date__c >= beforeTransition.addDays(7).addSeconds(-1)
        );
        Assert.isTrue(saved.Goods_Due_Date__c <= System.now().addDays(7));
    }

    @IsTest
    static void schedulesDailyJobAtOneAmForVietnamTimezone() {
        User scheduler = SR_TestDataFactory.createUser(
            SR_TestDataFactory.ROLE_ADMIN,
            null
        );
        System.runAs(scheduler) {
            Id jobId = SR_NightlyJob.scheduleDaily();
            CronTrigger job = [
                SELECT Id, CronExpression
                FROM CronTrigger
                WHERE Id = :jobId
            ];
            Assert.areEqual('0 0 1 * * ?', job.CronExpression);
            SR_NightlyJob.unschedule();
            Assert.areEqual(0, [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = 'SR SmartReturn nightly automation'
            ]);
        }
    }

    private static Return_Request__c createRequest(
        Id accountId,
        String status,
        String externalId,
        String approvalLevel,
        Datetime approvalDueAt
    ) {
        Order orderRecord = [
            SELECT Id, AccountId, Store__c
            FROM Order
            WHERE AccountId = :accountId
            LIMIT 1
        ];
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = accountId;
        spec.orderId = orderRecord.Id;
        spec.storeId = orderRecord.Store__c;
        spec.channel = SR_TestDataFactory.CHANNEL_POS;
        spec.status = status;
        spec.externalRequestId = externalId + '-' + randomSuffix();
        spec.approvalLevel = approvalLevel;
        spec.approvalDueAt = approvalDueAt;
        return SR_TestDataFactory.createReturnRequest(spec);
    }

    private static void createRequests(
        Id accountId,
        Integer count,
        Decimal estimatedRefund
    ) {
        Order orderRecord = [
            SELECT Id, AccountId, Store__c
            FROM Order
            WHERE AccountId = :accountId
            LIMIT 1
        ];
        List<SR_TestDataFactory.RequestSpec> specs =
            SR_TestDataFactory.requestSpecsForOrders(
                new List<Order>{ orderRecord },
                SR_TestDataFactory.STATUS_NEW,
                SR_TestDataFactory.CHANNEL_POS
            );
        SR_TestDataFactory.RequestSpec template = specs[0];
        List<SR_TestDataFactory.RequestSpec> requests =
            new List<SR_TestDataFactory.RequestSpec>();
        for (Integer i = 0; i < count; i++) {
            SR_TestDataFactory.RequestSpec spec =
                new SR_TestDataFactory.RequestSpec();
            spec.accountId = accountId;
            spec.orderId = orderRecord.Id;
            spec.storeId = orderRecord.Store__c;
            spec.channel = template.channel;
            spec.status = template.status;
            spec.externalRequestId = 'DUC09-RISK-' + randomSuffix();
            for (SR_TestDataFactory.LineSpec templateLine : template.lines) {
                SR_TestDataFactory.LineSpec line =
                    new SR_TestDataFactory.LineSpec();
                line.orderItemId = templateLine.orderItemId;
                line.productId = templateLine.productId;
                line.quantity = templateLine.quantity;
                line.unitPrice = templateLine.unitPrice;
                line.estimatedRefund = estimatedRefund;
                spec.lines.add(line);
            }
            requests.add(spec);
        }
        SR_TestDataFactory.createReturnRequests(requests);
    }

    private static void createOrderFor(Account customer) {
        Store__c store = storeRecord();
        Product2 product = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'DUC09-PHONE'
            LIMIT 1
        ];
        SR_TestDataFactory.OrderSpec orderSpec =
            new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        orderSpec.items.add(new SR_TestDataFactory.ItemSpec(product.Id, 1, 12000000));
        SR_TestDataFactory.createOrder(orderSpec);
    }

    private static Store__c storeRecord() {
        return [
            SELECT Id, Regional_Manager__c
            FROM Store__c
            WHERE Store_Code__c = :STORE_CODE
            LIMIT 1
        ];
    }

    private static Account accountByName(String accountName) {
        return [
            SELECT Id
            FROM Account
            WHERE Name = :accountName
            LIMIT 1
        ];
    }

    private static String randomSuffix() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }
}
