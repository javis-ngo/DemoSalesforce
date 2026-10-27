/**
 * B7 – Quick Action "Hoàn tiền thủ công" (LWC srManualRefund) cho Kế toán: REFUND_FAILED → COMPLETED (FR-14).
 * Chỉ nhận/trả dữ liệu; kiểm tra quyền, trạng thái và ghi dữ liệu ở SR_ManualRefundService.
 * Owner: Dev B
 */
public with sharing class SR_RefundManualController {

    @AuraEnabled
    public static void markManualRefund(Id requestId, String payHubTransactionId) {
        try {
            SR_ManualRefundService.markManualRefund(requestId, payHubTransactionId);
        } catch (SR_ManualRefundService.ManualRefundException e) {
            throw SR_UiUtil.auraException(e.getMessage());   // câu nghiệp vụ, hiện nguyên cho Kế toán
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);                     // MSG-90 kèm mã lỗi
        }
    }
}
