/**
 * B9 – INT-04: PayHub báo kết quả cuối cho lệnh đang PENDING (FR-12, Phụ lục E.4).
 *  - Khóa yêu cầu (FOR UPDATE) theo merchantRef = mã yêu cầu; không có → 404 REQUEST_NOT_FOUND.
 *  - Chỉ đổi khi đang REFUND_PROCESSING: SUCCESS → COMPLETED, FAILED → REFUND_FAILED + báo Kế toán (FR-14).
 *    PayHub gọi lặp (yêu cầu đã có kết quả) → vẫn 200 nhưng không đổi dữ liệu, không thêm lịch sử.
 *  - Chuyển trạng thái + lịch sử + sự kiện (Publish After Commit, BR-15) qua SR_RefundService.applyFinalResult.
 *  - Mọi lần PayHub gọi đều ghi Integration_Log__c chiều INBOUND (BR-14), kể cả khi lỗi.
 * without sharing: integration user của PayHub không được chia sẻ yêu cầu theo cửa hàng.
 * Owner: Dev B
 */
public without sharing class SR_RefundCallbackService {

    public static final String ENDPOINT = '/services/apexrest/smartreturn/v1/refund-callback';
    private static final String LOG_SYSTEM_NAME = 'PayHub';
    private static final String CONTEXT = 'SR_RefundCallbackService';

    public static SR_ApiResponse handle(String body) {
        Long started = System.currentTimeMillis();
        SR_Logger logger = SR_Logger.getInstance();
        String merchantRef;
        String status;
        Id requestId;
        SR_ApiResponse result;
        try {
            Map<String, Object> payload = parse(body);
            merchantRef = (payload == null) ? null : trimmed(payload.get('merchantRef'));
            status = (payload == null) ? null : trimmed(payload.get('status'));

            if (payload == null) {
                result = SR_ApiResponse.badRequest(SR_ApiResponse.INVALID_VALUE, 'JSON không hợp lệ');
            } else if (merchantRef == null) {
                result = SR_ApiResponse.badRequest(SR_ApiResponse.MISSING_FIELD, 'Thiếu merchantRef');
            } else if (!SR_RefundDomain.isValidCallbackStatus(status)) {
                result = SR_ApiResponse.badRequest(SR_ApiResponse.INVALID_VALUE, 'status phải là SUCCESS hoặc FAILED');
            } else {
                List<Return_Request__c> found = SR_RefundSelector.selectForResultByNumber(merchantRef);
                if (found.isEmpty()) {
                    result = SR_ApiResponse.error(404, SR_ApiResponse.REQUEST_NOT_FOUND, 'Không tìm thấy yêu cầu', null);
                } else {
                    requestId = found[0].Id;
                    apply(found[0], status, trimmed(payload.get('refundId')), trimmed(payload.get('failureReason')), logger);
                    result = new SR_ApiResponse(200, new Map<String, Object>{ 'received' => true });
                }
            }
        } catch (Exception e) {
            result = SR_ApiResponse.internalError(CONTEXT + '.handle', CONTEXT, e, requestId);
        }

        logInbound(body, result, merchantRef, status, requestId, System.currentTimeMillis() - started);
        logger.push();
        return result;
    }

    private static void apply(Return_Request__c r, String status, String refundId, String failureReason, SR_Logger logger) {
        String toStatus = SR_RefundDomain.callbackTarget(r, status);
        if (toStatus == null) {
            // Gọi lặp hoặc yêu cầu không còn chờ PayHub: không đổi dữ liệu (E.4)
            logger.info(CONTEXT + '.apply', CONTEXT, r.Name,
                'Bỏ qua callback ' + status + ': yêu cầu đang ' + r.Status__c, r.Id);
            return;
        }
        if (r.PayHub_Refund_Id__c != null && refundId != null && r.PayHub_Refund_Id__c != refundId) {
            logger.warn(CONTEXT + '.apply', CONTEXT, r.Name,
                'refundId callback ' + refundId + ' khác refundId đã lưu ' + r.PayHub_Refund_Id__c, r.Id);
        }

        Return_Request__c changes = new Return_Request__c(Id = r.Id);
        if (refundId != null) {
            changes.PayHub_Refund_Id__c = refundId.abbreviate(SR_RefundDomain.TRANSACTION_ID_MAX_LENGTH);
        }
        String note;
        if (toStatus == SR_RefundDomain.STATUS_COMPLETED) {
            changes.Last_Refund_Error__c = null;
            note = 'PayHub báo hoàn tiền thành công qua INT-04' + (refundId == null ? '' : ', mã ' + refundId);
        } else {
            changes.Last_Refund_Error__c = SR_RefundDomain.describeCallbackFailure(failureReason);
            note = changes.Last_Refund_Error__c;
        }
        SR_RefundService.applyFinalResult(r, changes, toStatus, note);

        if (toStatus == SR_RefundDomain.STATUS_REFUND_FAILED) {
            SR_RefundService.notifyAccounting(
                new List<Return_Request__c>{ r }, new Map<Id, String>{ r.Id => changes.Last_Refund_Error__c });
        }
    }

    // null nếu không phải JSON object
    private static Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            return (parsed instanceof Map<String, Object>) ? (Map<String, Object>) parsed : null;
        } catch (JSONException e) {
            return null;
        }
    }

    private static String trimmed(Object value) {
        return (value == null || String.isBlank(String.valueOf(value))) ? null : String.valueOf(value).trim();
    }

    private static void logInbound(String body, SR_ApiResponse result, String merchantRef, String status,
        Id requestId, Long durationMs) {
        try {
            Boolean ok = result.statusCode == 200 && status == SR_RefundDomain.CALLBACK_SUCCESS;
            SR_IntegrationLogger logger = SR_IntegrationLogger.getInstance();
            logger.add(merchantRef, SR_IntegrationLogger.DIRECTION_INBOUND, ENDPOINT, body, result.toJson(),
                result.statusCode, durationMs,
                ok ? SR_IntegrationLogger.RESULT_SUCCESS : SR_IntegrationLogger.RESULT_FAILED,
                1, LOG_SYSTEM_NAME, requestId);
            logger.push();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SR_RefundCallbackService: log failed - ' + e.getMessage());
        }
    }
}
