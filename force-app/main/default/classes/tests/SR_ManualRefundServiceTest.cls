/**
 * Test cho SR_ManualRefundService và SR_RefundManualController (B7, FR-14).
 * Chuyển trạng thái + lịch sử qua SR_StatusMachine (Dev A); trạng thái khởi tạo ghi thẳng khi insert.
 * Chạy: sf apex run test --class-names SR_ManualRefundServiceTest --result-format human
 */
@IsTest
private class SR_ManualRefundServiceTest {

    private static Return_Request__c insertRequest(String status) {
        SR_TestDataFactory.seedSmartReturnTestConfig();      // SR_Config cho công tắc B.4 khi phát sự kiện
        Return_Request__c r = new Return_Request__c(Channel__c = 'POS', Status__c = status);
        insert r;
        return r;
    }

    private static String errorOf(Id requestId, String transactionId) {
        try {
            SR_ManualRefundService.markManualRefund(requestId, transactionId);
        } catch (SR_ManualRefundService.ManualRefundException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void withoutPermissionIsRefused() {
        SR_ManualRefundService.hasPermissionOverride = false;
        Assert.areEqual(SR_ManualRefundService.MSG_NO_PERMISSION, errorOf(null, 'PH-1'));
    }

    @IsTest
    static void blankTransactionIdIsRefused() {
        SR_ManualRefundService.hasPermissionOverride = true;
        Assert.areEqual(SR_ManualRefundService.MSG_TRANSACTION_REQUIRED, errorOf(null, '  '));
    }

    @IsTest
    static void unknownRequestIsRefused() {
        SR_ManualRefundService.hasPermissionOverride = true;
        Id fakeId = Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        Assert.areEqual(SR_ManualRefundService.MSG_NOT_FOUND, errorOf(fakeId, 'PH-1'));
    }

    // Phụ lục C: chỉ Refund Failed → Completed; trạng thái khác → MSG-20
    @IsTest
    static void notRefundFailedIsRefused() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_REFUND_PROCESSING);
        SR_ManualRefundService.hasPermissionOverride = true;
        String error = errorOf(r.Id, 'PH-1');
        Assert.isNotNull(error);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_PROCESSING,
            [SELECT Status__c FROM Return_Request__c WHERE Id = :r.Id].Status__c);
    }

    @IsTest
    static void refundFailedBecomesCompletedWithTransactionId() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_REFUND_FAILED);
        SR_ManualRefundService.hasPermissionOverride = true;

        Test.startTest();
        SR_ManualRefundService.markManualRefund(r.Id, ' PH-MANUAL-001 ');
        Test.stopTest();

        Return_Request__c after = [SELECT Status__c, PayHub_Refund_Id__c FROM Return_Request__c WHERE Id = :r.Id];
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, after.Status__c);
        Assert.areEqual('PH-MANUAL-001', after.PayHub_Refund_Id__c);
        // FR-06: SR_StatusMachine ghi lịch sử, correlationId = mã yêu cầu
        Return_Request_History__c h = [
            SELECT From_Status__c, Note__c, Correlation_Id__c FROM Return_Request_History__c
            WHERE Return_Request__c = :r.Id AND To_Status__c = :SR_RefundDomain.STATUS_COMPLETED
        ];
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, h.From_Status__c);
        Assert.isTrue(h.Note__c.contains('PH-MANUAL-001'));
        Assert.isNotNull(h.Correlation_Id__c);
    }

    // Lỗi kỹ thuật (cấu hình thiếu khi phát sự kiện) → rollback, controller trả MSG-90 kèm mã lỗi
    @IsTest
    static void controllerWrapsTechnicalErrorAsMsg90() {
        Return_Request__c r = insertRequest(SR_RefundDomain.STATUS_REFUND_FAILED);
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.PayHub_Timeout_Seconds__c, null);
        SR_ManualRefundService.hasPermissionOverride = true;
        try {
            SR_RefundManualController.markManualRefund(r.Id, 'PH-1');
            Assert.fail('Phải báo lỗi khi cấu hình thiếu');
        } catch (AuraHandledException e) {
            Assert.areNotEqual(SR_ManualRefundService.MSG_NO_PERMISSION, e.getMessage());
        }
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED,
            [SELECT Status__c FROM Return_Request__c WHERE Id = :r.Id].Status__c);
    }

    // Controller trả nguyên câu nghiệp vụ cho LWC
    @IsTest
    static void controllerReturnsBusinessMessage() {
        SR_ManualRefundService.hasPermissionOverride = false;
        try {
            SR_RefundManualController.markManualRefund(null, 'PH-1');
            Assert.fail('Phải báo lỗi khi không có quyền');
        } catch (AuraHandledException e) {
            Assert.areEqual(SR_ManualRefundService.MSG_NO_PERMISSION, e.getMessage());
        }
    }
}
