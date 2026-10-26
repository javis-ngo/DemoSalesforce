/**
 * Controller cho màn hình tạo yêu cầu trả hàng tại quầy (D.1) và trang yêu cầu (D.3 kiểm định, nút Nhận hàng / Hủy).
 * Chỉ nhận/trả dữ liệu. Kiểm tra điều kiện, tính tiền, định tuyến duyệt, kiểm định nằm ở service của Dũng;
 * dữ liệu cho trang yêu cầu gom ở SR_RequestPageService.
 */
public with sharing class SR_ReturnUiController {

    // ---------- D.1: tạo yêu cầu tại quầy ----------

    // D.1 bước 1–3: thông tin đơn và từng dòng sản phẩm, dòng nào bị khóa kèm lý do
    @AuraEnabled(cacheable=true)
    public static SR_DTO.ReturnableInfo getReturnableLines(Id orderId) {
        try {
            return SR_ReturnRequestService.getReturnableLines(orderId);
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // D.1 bước 4: tính trước tiền từng dòng, tổng tiền và cấp duyệt – không ghi dữ liệu
    // draftJson: { "orderId": "...", "lines": [ { "orderItemId", "quantity", "reason", "condition" } ] }
    @AuraEnabled
    public static SR_DTO.PreviewResult previewLevel(String draftJson) {
        try {
            return SR_ApprovalService.previewLevel(toCounterRequest(draftJson));
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // D.1 bước 5: tạo yêu cầu tại quầy, cùng JSON với previewLevel
    @AuraEnabled
    public static SR_DTO.CreateResult createFromCounter(String draftJson) {
        try {
            return SR_ReturnRequestService.createRequests(
                new List<SR_DTO.CreateRequest>{ toCounterRequest(draftJson) })[0];
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // ---------- D.3: trang yêu cầu ----------

    // Các dòng cần kiểm định và nút nào được hiện theo trạng thái
    @AuraEnabled
    public static SR_RequestPageService.InspectionData getInspectionData(Id requestId) {
        try {
            return SR_RequestPageService.getInspectionData(requestId);
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // Đổi tình trạng thực tế → tiền dòng tính lại theo B.2 bằng hàm của Dũng
    @AuraEnabled
    public static Decimal calcLineRefund(Id lineId, String actualCondition) {
        try {
            return SR_RequestPageService.calcLineRefund(lineId, actualCondition);
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // resultsJson: [ { "lineId", "result": "PASSED" | "FAILED", "actualCondition", "note" } ] (LineResultDTO)
    // Kiểm tra MSG-21, MSG-22, tính lại tiền và đổi trạng thái do SR_InspectionService làm
    @AuraEnabled
    public static void completeInspection(Id requestId, String resultsJson) {
        try {
            SR_RequestPageService.requireInternalUser();
            SR_InspectionService.complete(
                requestId, (List<SR_DTO.LineResult>) JSON.deserialize(resultsJson, List<SR_DTO.LineResult>.class));
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // Nút Nhận hàng / Hủy nào được hiện theo trạng thái hiện tại
    @AuraEnabled
    public static SR_RequestPageService.ActionState getActionState(Id requestId) {
        try {
            return SR_RequestPageService.getActionState(requestId);
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // Awaiting Goods → Inspecting
    @AuraEnabled
    public static void receiveGoods(Id requestId) {
        try {
            SR_RequestPageService.receiveGoods(requestId);
        } catch (AuraHandledException e) {
            throw e; // MSG-20 đã soạn sẵn
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // Chỉ hủy từ New / Pending Approval / Awaiting Goods (OI-07)
    @AuraEnabled
    public static void cancelRequest(Id requestId, String reason) {
        try {
            SR_RequestPageService.cancel(requestId, reason);
        } catch (AuraHandledException e) {
            throw e; // MSG-20 đã soạn sẵn
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }

    // Màn hình D.1 luôn là kênh Tại quầy; cửa hàng xử lý do service lấy theo người tạo
    private static SR_DTO.CreateRequest toCounterRequest(String draftJson) {
        SR_DTO.CreateRequest req = (SR_DTO.CreateRequest) JSON.deserialize(draftJson, SR_DTO.CreateRequest.class);
        req.channel = SR_ReturnRequestService.CH_COUNTER;
        return req;
    }
}