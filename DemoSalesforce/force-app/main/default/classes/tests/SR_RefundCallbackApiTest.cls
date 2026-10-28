/**
 * Test cho SR_RefundCallbackApi / SR_RefundCallbackService (B9; INT-04, Phụ lục E.4; FR-12, FR-14).
 * Chuyển trạng thái + lịch sử qua SR_StatusMachine.change (Dev A); trạng thái khởi tạo ghi thẳng khi insert.
 * Chạy: sf apex run test --class-names SR_RefundCallbackApiTest --result-format human
 */
@IsTest
private class SR_RefundCallbackApiTest {

    private static Map<String, Object> callback(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = SR_RefundCallbackService.ENDPOINT;
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        SR_RefundCallbackApi.doPost();
        Blob res = RestContext.response.responseBody;
        return res == null ? null : (Map<String, Object>) JSON.deserializeUntyped(res.toString());
    }

    private static String payload(String merchantRef, String status) {
        return JSON.serialize(new Map<String, Object>{
            'refundId' => 'PH-RF-88231',
            'merchantRef' => merchantRef,
            'status' => status,
            'failureReason' => 'CARD_CLOSED',
            'processedAt' => '2026-10-05T10:02:10+07:00'
        });
    }

    private static Return_Request__c insertRequest(String status) {
        SR_TestDataFactory.seedSmartReturnTestConfig();      // SR_Config cho công tắc B.4 khi phát sự kiện
        Return_Request__c r = new Return_Request__c(Channel__c = 'POS', Status__c = status);
        insert r;
        return [SELECT Id, Name FROM Return_Request__c WHERE Id = :r.Id];
    }

    // ---------- Không cần dữ liệu ----------

    @IsTest
    static void invalidJsonReturns400() {
        callback('not json');
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void missingMerchantRefReturns400() {
        callback('{"status":"SUCCESS"}');
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void unknownStatusReturns400() {
        callback(payload('RR-2610-00015', 'PENDING'));
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void unknownMerchantRefReturns404() {
        Map<String, Object> body = callback(payload('RR-0000-99999', 'SUCCESS'));
        Assert.areEqual(404, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.REQUEST_NOT_FOUND, body.get('errorCode'));
    }

    // ---------- Có dữ liệu ----------

    // E.4: PayHub gọi 2 lần – lần 2 vẫn 200, không thêm lịch sử
    @IsTest
    static void successCallbackIsIdempotent() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_REFUND_PROCESSING);
        Test.startTest();
        for (Integer i = 0; i < 2; i++) {
            Map<String, Object> body = callback(payload(r.Name, 'SUCCESS'));
            Assert.areEqual(200, RestContext.response.statusCode);
            Assert.areEqual(true, body.get('received'));
        }
        Test.stopTest();

        Return_Request__c after = [SELECT Status__c, PayHub_Refund_Id__c FROM Return_Request__c WHERE Id = :r.Id];
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, after.Status__c);
        Assert.areEqual('PH-RF-88231', after.PayHub_Refund_Id__c);
        Assert.areEqual(1, [
            SELECT COUNT() FROM Return_Request_History__c
            WHERE Return_Request__c = :r.Id AND To_Status__c = :SR_RefundDomain.STATUS_COMPLETED
        ]);
    }

    @IsTest
    static void failedCallbackMovesToRefundFailed() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_REFUND_PROCESSING);
        Test.startTest();
        callback(payload(r.Name, 'FAILED'));
        Integer statusCode = RestContext.response.statusCode;       // RestContext bị xóa sau Test.stopTest
        Test.stopTest();

        Assert.areEqual(200, statusCode);
        Return_Request__c after = [SELECT Status__c, Last_Refund_Error__c FROM Return_Request__c WHERE Id = :r.Id];
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, after.Status__c);
        Assert.isTrue(after.Last_Refund_Error__c.contains('CARD_CLOSED'));
    }

    // Đã hoàn tất rồi mà PayHub lại báo FAILED: không đổi dữ liệu
    @IsTest
    static void lateCallbackDoesNotChangeFinishedRequest() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_COMPLETED);
        callback(payload(r.Name, 'FAILED'));
        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, [SELECT Status__c FROM Return_Request__c WHERE Id = :r.Id].Status__c);
    }
}
