/**
 * Test cho SR_RefundService: xếp job, công tắc B.4, chia lô 10 yêu cầu và luồng hoàn tiền đầy đủ qua PayHub giả lập
 * (FR-11, FR-14; BR-12, BR-13, BR-15; NFR-04; UAT-06). Bảng xử lý kết quả PayHub được test chi tiết ở SR_RefundDomainTest.
 * Dữ liệu dựng bằng SR_TestDataFactory (Dev A); cấu hình bằng seedSmartReturnTestConfig + overrideConfig.
 * Chạy: sf apex run test --class-names SR_RefundServiceTest --result-format human
 */
@IsTest
private class SR_RefundServiceTest {

    private static final String STORE_CODE = 'HCM-RF1';
    private static final String CUSTOMER_PHONE = '0907000111';

    // Đơn nồi chiên 2.490.000đ; yêu cầu tạo theo từng test với trạng thái cần thiết
    @TestSetup
    static void setup() {
        Store__c store = SR_TestDataFactory.createStore(
            STORE_CODE, SR_TestDataFactory.REGION_SOUTH, UserInfo.getUserId(), UserInfo.getUserId());
        Account customer = SR_TestDataFactory.createAccount('Khách hoàn tiền', CUSTOMER_PHONE, false);
        Product2 fryer = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_APPLIANCE, 'AF-RF-001', 'Nồi chiên SR Refund', 2490000);
        SR_TestDataFactory.OrderSpec spec = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        spec.deliveryDate = Date.today().addDays(-2);
        spec.items.add(new SR_TestDataFactory.ItemSpec(fryer.Id, 1));
        SR_TestDataFactory.createOrder(spec);
    }

    private static void useConfig(String mockScenario) {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        SR_PayHubClient.useMockOverride = true;
        SR_PayHubClient.mockScenarioOverride = mockScenario;
    }

    // Yêu cầu đang ở trạng thái status, đã có tiền thực hoàn: Actual_Refund__c (roll-up) = 1.992.000đ
    private static Return_Request__c createRequest(String status, Decimal refundAttempts) {
        Order ord = [SELECT Id, AccountId, Store__c FROM Order LIMIT 1];
        SR_TestDataFactory.RequestSpec spec = SR_TestDataFactory.requestSpecsForOrders(
            new List<Order>{ ord }, status, SR_TestDataFactory.CHANNEL_POS)[0];
        for (SR_TestDataFactory.LineSpec line : spec.lines) {
            line.refundRate = 80;
            line.estimatedRefund = 1992000;
            line.actualRefund = 1992000;
        }
        Return_Request__c r = SR_TestDataFactory.createReturnRequest(spec);
        if (refundAttempts != null) {
            // Field hoàn tiền, không đổi Status__c nên trigger của Dev A không chặn
            update new Return_Request__c(Id = r.Id, Refund_Attempts__c = refundAttempts);
        }
        return r;
    }

    private static Return_Request__c reload(Id requestId) {
        return [
            SELECT Status__c, Refund_Attempts__c, Next_Retry_At__c, PayHub_Refund_Id__c, Last_Refund_Error__c
            FROM Return_Request__c WHERE Id = :requestId
        ];
    }

    private static Integer historyCount(Id requestId, String toStatus) {
        return [
            SELECT COUNT() FROM Return_Request_History__c
            WHERE Return_Request__c = :requestId AND To_Status__c = :toStatus
        ];
    }

    private static Id fakeId(Integer i) {
        return Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(i).leftPad(12, '0');
    }

    private static Set<Id> fakeIds(Integer count) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 1; i <= count; i++) {
            ids.add(fakeId(i));
        }
        return ids;
    }

    // ---------- Xếp job ----------

    @IsTest
    static void enqueueSkipsEmptyInput() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Assert.isNull(SR_RefundService.enqueue(null));
        Assert.isNull(SR_RefundService.enqueue(new Set<Id>()));
    }

    // Công tắc B.4 "Gửi PayHub" tắt: không xếp job
    @IsTest
    static void enqueueSkipsWhenPayHubDisabled() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_PayHub__c, false);
        Test.startTest();
        Assert.isNull(SR_RefundService.enqueue(fakeIds(1)));
        Assert.areEqual(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void forcedEnqueueFailureThrows() {
        SR_RefundService.forceEnqueueFailureForTest = true;
        try {
            SR_RefundService.enqueue(fakeIds(1));
            Assert.fail('Phải ném lỗi khi ép lỗi xếp job');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('Forced enqueue failure'));
        }
    }

    // Yêu cầu không tồn tại / không ở REFUND_PROCESSING: không gọi PayHub, không lỗi
    @IsTest
    static void jobWithNothingSendableDoesNothing() {
        useConfig(SR_PayHubClient.SCENARIO_SUCCESS);
        Test.startTest();
        Id jobId = SR_RefundService.enqueue(fakeIds(SR_RefundService.BATCH_SIZE + 5));
        Test.stopTest();
        Assert.isNotNull(jobId);
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status);
        Assert.areEqual(0, job.NumberOfErrors);
    }

    // ---------- Luồng đầy đủ (Phụ lục E.3) ----------

    // 200 + SUCCESS → COMPLETED, có dòng lịch sử, lưu refundId
    @IsTest
    static void successCompletesRequest() {
        useConfig(SR_PayHubClient.SCENARIO_SUCCESS);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_REFUND_PROCESSING, null);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, after.Status__c);
        Assert.areEqual(1, after.Refund_Attempts__c);
        Assert.isNotNull(after.PayHub_Refund_Id__c);
        Assert.areEqual(1, historyCount(r.Id, SR_RefundDomain.STATUS_COMPLETED));
    }

    // 200 + PENDING → giữ REFUND_PROCESSING, chờ INT-04
    @IsTest
    static void pendingKeepsProcessing() {
        useConfig(SR_PayHubClient.SCENARIO_PENDING);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_REFUND_PROCESSING, null);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_PROCESSING, after.Status__c);
        Assert.isNotNull(after.PayHub_Refund_Id__c);
        Assert.isNull(after.Next_Retry_At__c);
    }

    // 422 → REFUND_FAILED ngay, không hẹn thử lại
    @IsTest
    static void rejectedFailsWithoutRetry() {
        useConfig(SR_PayHubClient.SCENARIO_INVALID);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_REFUND_PROCESSING, null);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, after.Status__c);
        Assert.isNull(after.Next_Retry_At__c);
        Assert.isNotNull(after.Last_Refund_Error__c);
        Assert.areEqual(1, historyCount(r.Id, SR_RefundDomain.STATUS_REFUND_FAILED));
    }

    // 5xx lần 1 → giữ REFUND_PROCESSING, hẹn gửi lại sau 15 phút (BR-12)
    @IsTest
    static void serverErrorSchedulesRetry() {
        useConfig(SR_PayHubClient.SCENARIO_ERROR);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_REFUND_PROCESSING, null);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_PROCESSING, after.Status__c);
        Assert.areEqual(1, after.Refund_Attempts__c);
        Assert.isNotNull(after.Next_Retry_At__c);
    }

    // UAT-06: 5xx ở lần thứ 3 → REFUND_FAILED (Kế toán được báo; thiếu group/notification thì chỉ ghi log)
    @IsTest
    static void thirdServerErrorFailsRequest() {
        useConfig(SR_PayHubClient.SCENARIO_ERROR);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_REFUND_PROCESSING, 2);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, after.Status__c);
        Assert.areEqual(3, after.Refund_Attempts__c);
        Assert.isNull(after.Next_Retry_At__c);
        Assert.isTrue(after.Last_Refund_Error__c.startsWith('Lần 3/3'), after.Last_Refund_Error__c);
    }

    // BR-13: yêu cầu không ở REFUND_PROCESSING không được gửi PayHub
    @IsTest
    static void completedRequestIsNotSentAgain() {
        useConfig(SR_PayHubClient.SCENARIO_SUCCESS);
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_COMPLETED, null);
        Test.startTest();
        SR_RefundService.enqueue(new Set<Id>{ r.Id });
        Test.stopTest();

        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, after.Status__c);
        Assert.isNull(after.Refund_Attempts__c);
    }

    // B7/B9: applyFinalResult bị SR_StatusMachine từ chối (COMPLETED → REFUND_FAILED sai Phụ lục C)
    // → StatusChangeException, rollback field đã ghi
    @IsTest
    static void applyFinalResultRollsBackOnInvalidTransition() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Return_Request__c r = createRequest(SR_TestDataFactory.STATUS_COMPLETED, null);
        Return_Request__c locked = SR_RefundSelector.selectForResultById(r.Id)[0];
        try {
            SR_RefundService.applyFinalResult(locked,
                new Return_Request__c(Id = r.Id, Last_Refund_Error__c = 'không được ghi'),
                SR_RefundDomain.STATUS_REFUND_FAILED, 'test');
            Assert.fail('Phải ném StatusChangeException');
        } catch (SR_RefundService.StatusChangeException e) {
            Assert.isNotNull(e.getMessage());
        }
        Return_Request__c after = reload(r.Id);
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, after.Status__c);
        Assert.isNull(after.Last_Refund_Error__c);
    }

    // Đầu-cuối: kiểm định đạt (Dev A) → REFUND_PROCESSING → job PayHub SUCCESS → COMPLETED
    @IsTest
    static void inspectionToCompletedEndToEnd() {
        useConfig(SR_PayHubClient.SCENARIO_SUCCESS);
        Order ord = [SELECT Id, AccountId, Store__c FROM Order LIMIT 1];
        SR_TestDataFactory.RequestSpec spec = SR_TestDataFactory.requestSpecsForOrders(
            new List<Order>{ ord }, SR_TestDataFactory.STATUS_INSPECTING, SR_TestDataFactory.CHANNEL_POS)[0];
        for (SR_TestDataFactory.LineSpec line : spec.lines) {
            line.refundRate = 100;               // DEFECT + SEALED (B.2); giữ nguyên tình trạng thì dùng lại tỷ lệ này
            line.estimatedRefund = 2490000;
        }
        Return_Request__c r = SR_TestDataFactory.createReturnRequest(spec);
        Return_Request__c current = [
            SELECT LastModifiedDate, (SELECT Id FROM Return_Request_Lines__r) FROM Return_Request__c WHERE Id = :r.Id
        ];
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = r.Id;
        input.versionToken = String.valueOf(current.LastModifiedDate.getTime());
        for (Return_Request_Line__c line : current.Return_Request_Lines__r) {
            SR_InspectionLineDTO lineInput = new SR_InspectionLineDTO();
            lineInput.lineId = line.Id;
            lineInput.inspectionResult = 'PASSED';
            lineInput.actualCondition = 'SEALED';
            input.lines.add(lineInput);
        }

        Test.startTest();
        List<SR_ActionResultDTO> results = SR_InspectionService.complete(new List<SR_InspectionRequestDTO>{ input });
        Assert.isTrue(results[0].success, results[0].errorCode + ' ' + results[0].message);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_PROCESSING, results[0].status);
        Test.stopTest();

        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, reload(r.Id).Status__c);
        Assert.areEqual(1, historyCount(r.Id, SR_RefundDomain.STATUS_REFUND_PROCESSING));
        Assert.areEqual(1, historyCount(r.Id, SR_RefundDomain.STATUS_COMPLETED));
    }
}
