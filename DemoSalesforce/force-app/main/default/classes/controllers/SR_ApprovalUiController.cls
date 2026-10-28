/**
 * Controller cho màn hình duyệt của CHT/QLV (D.2, FR-08, FR-09).
 * Chỉ nhận/trả dữ liệu: hàng chờ và duyệt hàng loạt ở SR_ApprovalQueueService (truy vấn USER_MODE, BR-16).
 * Owner: Dev C (hàm duyệt thật là SR_ApprovalService.decide của Dev A)
 */
public with sharing class SR_ApprovalUiController {

    // Cửa hàng mà người dùng là CHT hoặc QLV (bộ lọc + lọc thông báo realtime)
    @AuraEnabled(cacheable=true)
    public static List<SR_ApprovalQueueService.StoreOption> getMyStores() {
        try {
            return SR_ApprovalQueueService.getMyStores();
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // filtersJson: các field của SR_ApprovalQueueService.Filters; để trống thì dùng bộ lọc mặc định
    @AuraEnabled
    public static SR_ApprovalQueueService.PageResult getQueue(String filtersJson) {
        try {
            SR_ApprovalQueueService.Filters f = String.isBlank(filtersJson)
                ? new SR_ApprovalQueueService.Filters()
                : (SR_ApprovalQueueService.Filters) JSON.deserialize(filtersJson, SR_ApprovalQueueService.Filters.class);
            return SR_ApprovalQueueService.getQueue(f);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // itemsJson: [ { "requestId": "...", "versionToken": "1761100984000" } ] (versionToken lấy từ getQueue)
    @AuraEnabled
    public static SR_ApprovalQueueService.DecisionSummary decide(String itemsJson, Boolean approve, String reason) {
        try {
            List<SR_ApprovalQueueService.DecisionItem> items = (List<SR_ApprovalQueueService.DecisionItem>)
                JSON.deserialize(itemsJson, List<SR_ApprovalQueueService.DecisionItem>.class);
            return SR_ApprovalQueueService.decide(items, approve, reason);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }
}
