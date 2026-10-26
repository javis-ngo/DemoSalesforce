/**
 * Test cho SR_RefundDomain: bảng xử lý kết quả PayHub (Phụ lục E.3), BR-12, BR-13. Không cần tạo dữ liệu.
 * Chạy: sf apex run test --class-names SR_RefundDomainTest --result-format human
 */
@IsTest
private class SR_RefundDomainTest {

    private static final Integer MAX_ATTEMPTS = 3;
    private static final Integer RETRY_MINUTES = 15;
    private static final Datetime NOW = Datetime.newInstance(2026, 10, 5, 9, 30, 0);

    private static Return_Request__c request(Decimal attempts) {
        return (Return_Request__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Return_Request__c' },
            'Id' => Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001',
            'Name' => 'RR-2610-00015',
            'Status__c' => SR_RefundDomain.STATUS_REFUND_PROCESSING,
            'Actual_Refund__c' => 1992000,
            'Refund_Attempts__c' => attempts,
            'Order__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Order' },
                'OrderNumber' => '00012345'
            }
        }), Return_Request__c.class);
    }

    private static SR_PayHubClient.Result result(String outcome, Integer httpStatus, String refundId, String errorCode) {
        SR_PayHubClient.Result res = new SR_PayHubClient.Result();
        res.outcome = outcome;
        res.httpStatus = httpStatus;
        res.refundId = refundId;
        res.errorCode = errorCode;
        return res;
    }

    private static SR_RefundDomain.Decision decide(Decimal attempts, SR_PayHubClient.Result res) {
        return SR_RefundDomain.decide(request(attempts), res, MAX_ATTEMPTS, RETRY_MINUTES, NOW);
    }

    // BR-13: mã yêu cầu là merchantRef (= Idempotency-Key), lần gửi đầu là lần 1
    @IsTest
    static void commandUsesRequestNumberAsMerchantRef() {
        SR_PayHubClient.RefundCommand cmd = SR_RefundDomain.toCommand(request(null));
        Assert.areEqual('RR-2610-00015', cmd.merchantRef);
        Assert.areEqual('00012345', cmd.orderNumber);
        Assert.areEqual(1992000, cmd.amount);
        Assert.areEqual(1, cmd.attemptNo);
        Assert.areEqual(3, SR_RefundDomain.toCommand(request(2)).attemptNo);
    }

    @IsTest
    static void successCompletesRequest() {
        SR_RefundDomain.Decision d = decide(0, result(SR_PayHubClient.OUT_SUCCESS, 200, 'PH-RF-88231', null));
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, d.toStatus);
        Assert.areEqual('PH-RF-88231', d.changes.PayHub_Refund_Id__c);
        Assert.areEqual(1, d.changes.Refund_Attempts__c);
        Assert.isNull(d.changes.Next_Retry_At__c);
        Assert.isNull(d.changes.Last_Refund_Error__c);
        Assert.isNull(d.error);
    }

    // PENDING: giữ REFUND_PROCESSING, lưu refundId để đối chiếu callback INT-04
    @IsTest
    static void pendingKeepsProcessing() {
        SR_RefundDomain.Decision d = decide(null, result(SR_PayHubClient.OUT_PENDING, 200, 'PH-RF-1', null));
        Assert.isNull(d.toStatus);
        Assert.areEqual('PH-RF-1', d.changes.PayHub_Refund_Id__c);
        Assert.isNull(d.changes.Next_Retry_At__c);
    }

    // 422: Refund Failed ngay ở lần 1, không hẹn thử lại
    @IsTest
    static void rejectedFailsWithoutRetry() {
        SR_RefundDomain.Decision d = decide(0, result(SR_PayHubClient.OUT_REJECTED, 422, null, 'INVALID_AMOUNT'));
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, d.toStatus);
        Assert.isNull(d.changes.Next_Retry_At__c);
        Assert.areEqual('Lần 1/3: REJECTED HTTP 422 INVALID_AMOUNT', d.error);
        Assert.areEqual(d.error, d.changes.Last_Refund_Error__c);
    }

    // BR-12: lần 1, 2 lỗi hệ thống → hẹn gửi lại sau 15 phút
    @IsTest
    static void retryBeforeLastAttemptSchedulesNextTry() {
        SR_RefundDomain.Decision d = decide(1, result(SR_PayHubClient.OUT_RETRY, 500, null, 'HTTP_500'));
        Assert.isNull(d.toStatus);
        Assert.areEqual(2, d.changes.Refund_Attempts__c);
        Assert.areEqual(NOW.addMinutes(RETRY_MINUTES), d.changes.Next_Retry_At__c);
        Assert.areEqual('Lần 2/3: RETRY HTTP 500 HTTP_500', d.changes.Last_Refund_Error__c);
    }

    // BR-12 / UAT-06: lần 3 vẫn lỗi → Refund Failed
    @IsTest
    static void retryOnLastAttemptFails() {
        SR_RefundDomain.Decision d = decide(2, result(SR_PayHubClient.OUT_RETRY, null, null, 'TIMEOUT_OR_NETWORK'));
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, d.toStatus);
        Assert.areEqual(3, d.changes.Refund_Attempts__c);
        Assert.isNull(d.changes.Next_Retry_At__c);
        Assert.areEqual('Lần 3/3: RETRY TIMEOUT_OR_NETWORK', d.error);
    }

    // Không có kết quả (không nên xảy ra) → coi như lỗi tạm thời, thử lại
    @IsTest
    static void missingResultIsRetried() {
        SR_RefundDomain.Decision d = decide(0, null);
        Assert.isNull(d.toStatus);
        Assert.isNotNull(d.changes.Next_Retry_At__c);
        Assert.areEqual('Lần 1/3: NO_RESULT', d.error);
    }

    // Dữ liệu sai không gửi được → xử lý như 422
    @IsTest
    static void invalidCommandIsRejected() {
        SR_PayHubClient.Result res = SR_RefundDomain.invalidCommand('amount must be greater than zero.');
        Assert.areEqual(SR_PayHubClient.OUT_REJECTED, res.outcome);
        Assert.areEqual(SR_RefundDomain.ERROR_INVALID_COMMAND, res.errorCode);
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, decide(0, res).toStatus);
    }

    private static Return_Request__c withStatus(String status) {
        return new Return_Request__c(Status__c = status);
    }

    // ---------- B7: Kế toán hoàn tay ----------

    @IsTest
    static void manualRefundOnlyFromRefundFailed() {
        Assert.isTrue(SR_RefundDomain.canMarkManualRefund(withStatus(SR_RefundDomain.STATUS_REFUND_FAILED)));
        Assert.isFalse(SR_RefundDomain.canMarkManualRefund(withStatus(SR_RefundDomain.STATUS_REFUND_PROCESSING)));
        Assert.isFalse(SR_RefundDomain.canMarkManualRefund(withStatus(SR_RefundDomain.STATUS_COMPLETED)));
        Assert.isFalse(SR_RefundDomain.canMarkManualRefund(null));
    }

    @IsTest
    static void transactionIdIsTrimmedAndBounded() {
        Assert.areEqual('PH-1', SR_RefundDomain.normalizeTransactionId('  PH-1 '));
        Assert.isNull(SR_RefundDomain.normalizeTransactionId('   '));
        Assert.isNull(SR_RefundDomain.normalizeTransactionId(null));
        Assert.isNull(SR_RefundDomain.normalizeTransactionId('x'.repeat(SR_RefundDomain.TRANSACTION_ID_MAX_LENGTH + 1)));
    }

    // ---------- B9: INT-04 ----------

    @IsTest
    static void callbackMovesRefundProcessingToResult() {
        Return_Request__c r = withStatus(SR_RefundDomain.STATUS_REFUND_PROCESSING);
        Assert.areEqual(SR_RefundDomain.STATUS_COMPLETED, SR_RefundDomain.callbackTarget(r, 'SUCCESS'));
        Assert.areEqual(SR_RefundDomain.STATUS_REFUND_FAILED, SR_RefundDomain.callbackTarget(r, 'FAILED'));
        Assert.isNull(SR_RefundDomain.callbackTarget(r, 'PENDING'));
    }

    // E.4: gọi lặp sau khi đã có kết quả thì không đổi gì, kể cả khi báo kết quả khác
    @IsTest
    static void repeatedCallbackIsIgnored() {
        Assert.isNull(SR_RefundDomain.callbackTarget(withStatus(SR_RefundDomain.STATUS_COMPLETED), 'SUCCESS'));
        Assert.isNull(SR_RefundDomain.callbackTarget(withStatus(SR_RefundDomain.STATUS_COMPLETED), 'FAILED'));
        Assert.isNull(SR_RefundDomain.callbackTarget(withStatus(SR_RefundDomain.STATUS_REFUND_FAILED), 'SUCCESS'));
        Assert.isNull(SR_RefundDomain.callbackTarget(null, 'SUCCESS'));
    }

    @IsTest
    static void callbackFailureDescribesReason() {
        Assert.isTrue(SR_RefundDomain.describeCallbackFailure('CARD_CLOSED').endsWith('CARD_CLOSED'));
        Assert.isTrue(SR_RefundDomain.describeCallbackFailure(null).endsWith('không rõ lý do'));
    }
}
