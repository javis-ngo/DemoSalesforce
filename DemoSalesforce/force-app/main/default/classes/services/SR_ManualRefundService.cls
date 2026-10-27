/**
 * B7 – Kế toán xác nhận đã hoàn tiền thủ công: REFUND_FAILED → COMPLETED (FR-14, Phụ lục C).
 *  - Kế toán chỉ có quyền xem yêu cầu (BR-16) nên chạy without sharing và tự kiểm tra
 *    Custom Permission SR_Manual_Refund (gán qua permission set của Kế toán – [DEV A]).
 *  - Khóa bản ghi (FOR UPDATE) rồi mới kiểm tra trạng thái: hai người bấm cùng lúc thì người sau nhận MSG-20.
 *  - Ghi mã giao dịch vào PayHub_Refund_Id__c, chuyển trạng thái + lịch sử qua SR_StatusMachine,
 *    phát sự kiện COMPLETED (Publish After Commit, BR-15) qua SR_RefundService.applyFinalResult.
 * Owner: Dev B
 */
public without sharing class SR_ManualRefundService {

    public static final String PERMISSION = 'SR_Manual_Refund';

    // [DEV C] Có thể chuyển 3 câu dưới thành Custom Label
    @TestVisible
    private static final String MSG_NO_PERMISSION = 'Bạn không có quyền xác nhận hoàn tiền thủ công.';
    @TestVisible
    private static final String MSG_TRANSACTION_REQUIRED = 'Vui lòng nhập mã giao dịch PayHub (tối đa 100 ký tự).';
    @TestVisible
    private static final String MSG_NOT_FOUND = 'Không tìm thấy yêu cầu.';

    // Lỗi nghiệp vụ: controller hiện nguyên câu cho người dùng
    public class ManualRefundException extends Exception {
    }

    @TestVisible
    private static Boolean hasPermissionOverride;

    public static void markManualRefund(Id requestId, String payHubTransactionId) {
        if (!hasPermission()) {
            throw new ManualRefundException(MSG_NO_PERMISSION);
        }
        String transactionId = SR_RefundDomain.normalizeTransactionId(payHubTransactionId);
        if (transactionId == null) {
            throw new ManualRefundException(MSG_TRANSACTION_REQUIRED);
        }
        List<Return_Request__c> found = SR_RefundSelector.selectForResultById(requestId);
        if (found.isEmpty()) {
            throw new ManualRefundException(MSG_NOT_FOUND);
        }
        Return_Request__c r = found[0];
        if (!SR_RefundDomain.canMarkManualRefund(r)) {
            // SR_StatusMachine.labelOf: nhãn tiếng Việt của trạng thái
            throw new ManualRefundException(String.format(System.Label.SR_MSG_20, new List<Object>{
                SR_StatusMachine.labelOf(r.Status__c), SR_StatusMachine.labelOf(SR_RefundDomain.STATUS_COMPLETED)
            }));
        }
        try {
            SR_RefundService.applyFinalResult(
                r,
                new Return_Request__c(Id = r.Id, PayHub_Refund_Id__c = transactionId),
                SR_RefundDomain.STATUS_COMPLETED,
                'Kế toán hoàn tiền thủ công, mã giao dịch ' + transactionId
            );
        } catch (SR_RefundService.StatusChangeException e) {
            // SR_StatusMachine từ chối (MSG-20): câu nghiệp vụ, hiện nguyên cho Kế toán
            throw new ManualRefundException(e.getMessage());
        }
    }

    private static Boolean hasPermission() {
        return (hasPermissionOverride != null) ? hasPermissionOverride : FeatureManagement.checkPermission(PERMISSION);
    }
}
