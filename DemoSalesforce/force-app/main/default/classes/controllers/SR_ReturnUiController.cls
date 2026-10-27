/**
 * Controller cho màn hình tạo yêu cầu trả hàng tại quầy (D.1) và trang yêu cầu (D.3 kiểm định, nút Nhận hàng / Hủy).
 * Chỉ nhận/trả dữ liệu. Kiểm tra điều kiện, tính tiền, định tuyến duyệt, kiểm định nằm ở service của Dev A
 * (SR_ReturnRequestService, SR_InspectionService, SR_StatusMachine); dữ liệu cho trang yêu cầu gom ở SR_RequestPageService.
 * Owner: Dev C
 */
public with sharing class SR_ReturnUiController {

    // ---------- D.1: tạo yêu cầu tại quầy ----------

    // D.1 bước 1–3: thông tin đơn và từng dòng sản phẩm, dòng nào bị khóa kèm mã khóa (lockCode)
    @AuraEnabled(cacheable=true)
    public static SR_ReturnableOrderDTO getReturnableOrder(Id orderId) {
        try {
            return SR_ReturnRequestService.getReturnableOrder(orderId);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // D.1 bước 4: tính trước tiền từng dòng, tổng tiền và cấp duyệt – không ghi dữ liệu
    // draftJson: SR_CreateRequestDTO { "orderId": "...", "lines": [ { "orderItemId", "quantity", "reason", "condition" } ] }
    @AuraEnabled
    public static SR_ApprovalPreviewResultDTO previewCreate(String draftJson) {
        try {
            return SR_ReturnRequestService.previewCreate(toCounterRequest(draftJson));
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // D.1 bước 5: tạo yêu cầu tại quầy, cùng JSON với previewCreate
    @AuraEnabled
    public static SR_CreateResultDTO createFromCounter(String draftJson) {
        try {
            return SR_ReturnRequestService.createRequests(
                new List<SR_CreateRequestDTO>{ toCounterRequest(draftJson) })[0];
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // ---------- D.3: trang yêu cầu ----------

    // Các dòng cần kiểm định, versionToken chống ghi đè và component có được hiện không
    @AuraEnabled
    public static SR_RequestPageService.InspectionData getInspectionData(Id requestId) {
        try {
            return SR_RequestPageService.getInspectionData(requestId);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // Đổi tình trạng thực tế → tiền dòng tính lại theo B.2 bằng hàm của Dev A
    @AuraEnabled
    public static Decimal calcLineRefund(Id lineId, String actualCondition) {
        try {
            return SR_RequestPageService.calcLineRefund(lineId, actualCondition);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // linesJson: List<SR_InspectionLineDTO> [ { "lineId", "inspectionResult": "PASSED" | "FAILED", "actualCondition", "inspectionNote" } ]
    // Kiểm tra MSG-21, MSG-22, tính lại tiền và đổi trạng thái do SR_InspectionService làm
    @AuraEnabled
    public static void completeInspection(Id requestId, String versionToken, String linesJson) {
        try {
            SR_RequestPageService.completeInspection(
                requestId,
                versionToken,
                (List<SR_InspectionLineDTO>) JSON.deserialize(linesJson, List<SR_InspectionLineDTO>.class)
            );
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // Nút Nhận hàng / Hủy nào được hiện theo trạng thái hiện tại
    @AuraEnabled
    public static SR_RequestPageService.ActionState getActionState(Id requestId) {
        try {
            return SR_RequestPageService.getActionState(requestId);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // Awaiting Goods → Inspecting
    @AuraEnabled
    public static void receiveGoods(Id requestId) {
        try {
            SR_RequestPageService.receiveGoods(requestId);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e); // MSG-20 đã soạn sẵn thì giữ nguyên
        }
    }

    // Chỉ hủy từ New / Pending Approval / Awaiting Goods (OI-07)
    @AuraEnabled
    public static void cancelRequest(Id requestId, String reason) {
        try {
            SR_RequestPageService.cancel(requestId, reason);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e); // MSG-20 đã soạn sẵn thì giữ nguyên
        }
    }

    // Màn hình D.1 luôn là kênh Tại quầy; cửa hàng xử lý do service lấy theo người tạo
    private static SR_CreateRequestDTO toCounterRequest(String draftJson) {
        SR_CreateRequestDTO req = (SR_CreateRequestDTO) JSON.deserialize(draftJson, SR_CreateRequestDTO.class);
        req.channel = SR_ReturnRequestService.CHANNEL_COUNTER;
        return req;
    }
}
