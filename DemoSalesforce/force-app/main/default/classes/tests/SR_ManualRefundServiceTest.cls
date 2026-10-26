/**
 * Test cho SR_ManualRefundService và SR_RefundManualController (B7, FR-14).
 * [DEV A] Các test có tạo Return_Request__c cần picklist Status__c có REFUND_FAILED / REFUND_PROCESSING / COMPLETED
 *         và SR_StatusMachine (change, labelOf).
 * Chạy: sf apex run test --class-names SR_ManualRefundServiceTest --result-format human
 */
@IsTest
private class SR_ManualRefundServiceTest {

    private static Return_Request__c insertRequest(String status) {
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
