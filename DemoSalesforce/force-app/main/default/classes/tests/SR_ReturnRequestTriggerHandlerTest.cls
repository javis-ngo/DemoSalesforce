@IsTest(SeeAllData=false)
private class SR_ReturnRequestTriggerHandlerTest {
    private static final String STORE_CODE = 'DUC05';
    private static final String CUSTOMER_NAME = 'DUC-05 Handler Customer';

    private class Fixture {
        Id accountId;
        Id orderId;
        Id storeId;
    }

    @TestSetup
    static void setupDataGraph() {
        SR_TestDataFactory.StoreSetup storeSetup =
            SR_TestDataFactory.createStoreSetup(
                STORE_CODE,
                SR_TestDataFactory.REGION_SOUTH
            );

        Account account = SR_TestDataFactory.createAccount(
            CUSTOMER_NAME,
            '0905000051',
            false
        );

        Product2 product = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_PHONE,
            'DUC05-HANDLER-PHONE',
            'DUC-05 Handler Test Phone',
            1000000
        );

        SR_TestDataFactory.OrderSpec orderSpec =
            new SR_TestDataFactory.OrderSpec(
                account.Id,
                storeSetup.store.Id
            );
        orderSpec.deliveryDate = Date.today();
        orderSpec.items.add(
            new SR_TestDataFactory.ItemSpec(product.Id, 250, 1000000)
        );
        SR_TestDataFactory.createOrder(orderSpec);
    }

    private static Fixture fixture() {
        Fixture value = new Fixture();

        Store__c storeRow = [
            SELECT Id
            FROM Store__c
            WHERE Store_Code__c = :STORE_CODE
            LIMIT 1
        ];
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = :CUSTOMER_NAME
            LIMIT 1
        ];
        Order orderRow = [
            SELECT Id
            FROM Order
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        value.accountId = account.Id;
        value.orderId = orderRow.Id;
        value.storeId = storeRow.Id;
        return value;
    }

    private static SR_TestDataFactory.RequestSpec requestSpec(
        Fixture data,
        String status
    ) {
        SR_TestDataFactory.RequestSpec spec =
            new SR_TestDataFactory.RequestSpec();
        spec.accountId = data.accountId;
        spec.orderId = data.orderId;
        spec.storeId = data.storeId;
        spec.channel = SR_TestDataFactory.CHANNEL_COUNTER;
        spec.status = status;
        spec.externalRequestId = null;

        if (status == SR_StatusMachine.REJECTED) {
            spec.rejectionReason = 'Initial rejected test record';
        }
        return spec;
    }

    private static Return_Request__c createRequest(String status) {
        return SR_TestDataFactory.createReturnRequest(
            requestSpec(fixture(), status)
        );
    }

    private static SR_StatusChangeDTO statusChange(
        Id requestId,
        String toStatus
    ) {
        SR_StatusChangeDTO input = new SR_StatusChangeDTO();
        input.requestId = requestId;
        input.toStatus = toStatus;
        input.note = 'Trigger handler unit test';
        input.correlationId = 'DUC05-HANDLER-TEST';
        if (toStatus == SR_StatusMachine.REJECTED) {
            input.rejectionReason = 'Rejected by handler test';
        }
        return input;
    }

    @IsTest
    static void afterInsert_singleRequest_createsCompleteInitialHistory() {
        Fixture data = fixture();
        SR_TestDataFactory.RequestSpec spec = requestSpec(
            data,
            SR_StatusMachine.STATUS_NEW
        );

        Test.startTest();
        Return_Request__c requestRow =
            SR_TestDataFactory.createReturnRequest(spec);
        Test.stopTest();

        List<Return_Request_History__c> histories = [
            SELECT Return_Request__c,
                   From_Status__c,
                   To_Status__c,
                   Changed_By__c,
                   Changed_At__c,
                   Note__c
            FROM Return_Request_History__c
            WHERE Return_Request__c = :requestRow.Id
        ];

        Assert.areEqual(
            1,
            histories.size(),
            'Insert must create exactly one initial history record.'
        );
        Return_Request_History__c initialHistory = histories[0];
        Assert.areEqual(requestRow.Id, initialHistory.Return_Request__c);
        Assert.isNull(
            initialHistory.From_Status__c,
            'Initial history must not have a previous status.'
        );
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            initialHistory.To_Status__c
        );
        Assert.areEqual(UserInfo.getUserId(), initialHistory.Changed_By__c);
        Assert.isNotNull(initialHistory.Changed_At__c);
    }

    @IsTest
    static void afterInsert_bulk200_createsOneInitialHistoryPerRequest() {
        Fixture data = fixture();
        List<SR_TestDataFactory.RequestSpec> specs =
            new List<SR_TestDataFactory.RequestSpec>();

        for (Integer index = 0; index < 200; index++) {
            specs.add(
                requestSpec(data, SR_StatusMachine.STATUS_NEW)
            );
        }

        Test.startTest();
        List<Return_Request__c> requests =
            SR_TestDataFactory.createReturnRequests(specs);
        Test.stopTest();

        Set<Id> requestIds =
            new Map<Id, Return_Request__c>(requests).keySet();
        List<Return_Request_History__c> histories = [
            SELECT Return_Request__c,
                   From_Status__c,
                   To_Status__c,
                   Changed_By__c,
                   Changed_At__c
            FROM Return_Request_History__c
            WHERE Return_Request__c IN :requestIds
        ];

        Assert.areEqual(200, requests.size());
        Assert.areEqual(
            200,
            histories.size(),
            'Bulk insert must create exactly one history per request.'
        );

        Set<Id> historyRequestIds = new Set<Id>();
        for (Return_Request_History__c history : histories) {
            Assert.isNull(history.From_Status__c);
            Assert.areEqual(
                SR_StatusMachine.STATUS_NEW,
                history.To_Status__c
            );
            Assert.isNotNull(history.Changed_By__c);
            Assert.isNotNull(history.Changed_At__c);
            historyRequestIds.add(history.Return_Request__c);
        }
        Assert.areEqual(
            requestIds,
            historyRequestIds,
            'Every inserted request must have an initial history.'
        );
    }

    @IsTest
    static void beforeUpdate_directStatusChange_isRejected() {
        Return_Request__c requestRow = createRequest(
            SR_StatusMachine.STATUS_NEW
        );
        Integer historyCountBefore = [
            SELECT COUNT()
            FROM Return_Request_History__c
            WHERE Return_Request__c = :requestRow.Id
        ];

        requestRow.Status__c = SR_StatusMachine.COMPLETED;

        Test.startTest();
        Database.SaveResult saveResult = Database.update(
            requestRow,
            false
        );
        Test.stopTest();

        Assert.isFalse(
            saveResult.isSuccess(),
            'Direct Status__c update must be rejected by the trigger.'
        );
        Assert.isTrue(
            saveResult.getErrors().size() > 0,
            'The rejected update must return a DML error.'
        );

        Return_Request__c persisted = [
            SELECT Status__c
            FROM Return_Request__c
            WHERE Id = :requestRow.Id
        ];
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            persisted.Status__c,
            'Rejected direct update must not change the persisted status.'
        );
        Assert.areEqual(
            historyCountBefore,
            [
                SELECT COUNT()
                FROM Return_Request_History__c
                WHERE Return_Request__c = :requestRow.Id
            ],
            'Rejected direct update must not create history.'
        );
    }

    @IsTest
    static void beforeUpdate_nonStatusChange_isAllowed() {
        Return_Request__c requestRow = createRequest(
            SR_StatusMachine.STATUS_NEW
        );
        requestRow.Internal_Note__c = 'Allowed non-status update';

        Test.startTest();
        Database.SaveResult saveResult = Database.update(
            requestRow,
            false
        );
        Test.stopTest();

        Assert.isTrue(
            saveResult.isSuccess(),
            saveResult.isSuccess()
                ? 'None'
                : saveResult.getErrors()[0].getMessage()
        );

        Return_Request__c persisted = [
            SELECT Status__c, Internal_Note__c
            FROM Return_Request__c
            WHERE Id = :requestRow.Id
        ];
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            persisted.Status__c
        );
        Assert.areEqual(
            'Allowed non-status update',
            persisted.Internal_Note__c
        );
    }

    @IsTest
    static void beforeUpdate_mixedBulkUpdate_blocksOnlyUnauthorizedStatusRows() {
        Return_Request__c firstRequest = createRequest(
            SR_StatusMachine.STATUS_NEW
        );
        Return_Request__c secondRequest = createRequest(
            SR_StatusMachine.STATUS_NEW
        );
        Return_Request__c thirdRequest = createRequest(
            SR_StatusMachine.STATUS_NEW
        );

        firstRequest.Status__c = SR_StatusMachine.COMPLETED;
        secondRequest.Status__c = SR_StatusMachine.CANCELLED;
        thirdRequest.Internal_Note__c = 'Bulk allowed row';

        Test.startTest();
        List<Database.SaveResult> saveResults = Database.update(
            new List<Return_Request__c>{
                firstRequest,
                secondRequest,
                thirdRequest
            },
            false
        );
        Test.stopTest();

        Assert.areEqual(3, saveResults.size());
        Assert.isFalse(saveResults[0].isSuccess());
        Assert.isFalse(saveResults[1].isSuccess());
        Assert.isTrue(
            saveResults[2].isSuccess(),
            saveResults[2].isSuccess()
                ? 'None'
                : saveResults[2].getErrors()[0].getMessage()
        );

        Set<Id> requestIds = new Set<Id>{
            firstRequest.Id,
            secondRequest.Id,
            thirdRequest.Id
        };
        Map<Id, Return_Request__c> persistedById =
            new Map<Id, Return_Request__c>([
                SELECT Id, Status__c, Internal_Note__c
                FROM Return_Request__c
                WHERE Id IN :requestIds
            ]);

        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            persistedById.get(firstRequest.Id).Status__c
        );
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            persistedById.get(secondRequest.Id).Status__c
        );
        Assert.areEqual(
            'Bulk allowed row',
            persistedById.get(thirdRequest.Id).Internal_Note__c
        );
    }

    @IsTest
    static void statusMachine_authorizedUpdate_passesGuardAndCreatesHistory() {
        Return_Request__c requestRow = createRequest(
            SR_StatusMachine.STATUS_NEW
        );

        Test.startTest();
        List<SR_ActionResultDTO> results = SR_StatusMachine.change(
            new List<SR_StatusChangeDTO>{
                statusChange(
                    requestRow.Id,
                    SR_StatusMachine.INSPECTING
                )
            }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(
            results[0].success,
            'Authorized state-machine update should succeed. Result error: '
                + (String.isBlank(results[0].message)
                    ? 'none'
                    : results[0].message)
        );
        Assert.areEqual(
            SR_StatusMachine.INSPECTING,
            results[0].status
        );

        Return_Request__c persisted = [
            SELECT Status__c
            FROM Return_Request__c
            WHERE Id = :requestRow.Id
        ];
        Assert.areEqual(
            SR_StatusMachine.INSPECTING,
            persisted.Status__c
        );

        List<Return_Request_History__c> histories = [
            SELECT From_Status__c,
                   To_Status__c,
                   Changed_By__c,
                   Changed_At__c,
                   Note__c,
                   Correlation_Id__c
            FROM Return_Request_History__c
            WHERE Return_Request__c = :requestRow.Id
            ORDER BY Changed_At__c ASC
        ];
        Assert.areEqual(
            2,
            histories.size(),
            'Request must have initial and transition histories.'
        );
        Assert.isNull(histories[0].From_Status__c);
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            histories[0].To_Status__c
        );
        Assert.areEqual(
            SR_StatusMachine.STATUS_NEW,
            histories[1].From_Status__c
        );
        Assert.areEqual(
            SR_StatusMachine.INSPECTING,
            histories[1].To_Status__c
        );
        Assert.areEqual(
            'Trigger handler unit test',
            histories[1].Note__c
        );
        Assert.areEqual(
            'DUC05-HANDLER-TEST',
            histories[1].Correlation_Id__c
        );
    }

    @IsTest
    static void statusMachine_invalidTransition_doesNotChangeStatusOrHistory() {
        Return_Request__c requestRow = createRequest(
            SR_StatusMachine.COMPLETED
        );
        Integer historyCountBefore = [
            SELECT COUNT()
            FROM Return_Request_History__c
            WHERE Return_Request__c = :requestRow.Id
        ];

        Test.startTest();
        List<SR_ActionResultDTO> results = SR_StatusMachine.change(
            new List<SR_StatusChangeDTO>{
                statusChange(
                    requestRow.Id,
                    SR_StatusMachine.INSPECTING
                )
            }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isFalse(results[0].success);
        Assert.areEqual(
            'INVALID_STATUS_TRANSITION',
            results[0].errorCode
        );
        Assert.areEqual(
            SR_StatusMachine.COMPLETED,
            [
                SELECT Status__c
                FROM Return_Request__c
                WHERE Id = :requestRow.Id
            ].Status__c
        );
        Assert.areEqual(
            historyCountBefore,
            [
                SELECT COUNT()
                FROM Return_Request_History__c
                WHERE Return_Request__c = :requestRow.Id
            ]
        );
    }
}
