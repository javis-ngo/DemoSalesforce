/**
 * Nghiệp vụ trang chi tiết yêu cầu (D.3 kiểm định, nút Nhận hàng / Hủy – FR-10, Phụ lục C).
 * Chỉ gom dữ liệu cho màn hình và gọi service của Dev A: tỷ lệ + tiền dòng (SR_RefundCalculator.rateFor,
 * SR_ReturnRequestService.calcLineRefund), đổi trạng thái (SR_StatusMachine.change),
 * hoàn tất kiểm định (SR_InspectionService.complete).
 * Owner: Dev C
 */
public with sharing class SR_RequestPageService {

    // Tên field theo SR_InspectionLineDTO của Dev A để LWC gửi lại nguyên dòng khi hoàn tất
    public class InspectionLine {
        @AuraEnabled public Id lineId;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String reason;
        @AuraEnabled public String declaredCondition;
        @AuraEnabled public String actualCondition;
        @AuraEnabled public String inspectionResult; // PASSED | FAILED, null = chưa kiểm định
        @AuraEnabled public String inspectionNote;
        @AuraEnabled public Decimal estimatedRefund;
        @AuraEnabled public Decimal actualRefund;    // tiền theo tình trạng thực tế, chưa xét Đạt / Không đạt
    }

    public class InspectionData {
        @AuraEnabled public String status;
        @AuraEnabled public String versionToken;          // gửi lại khi hoàn tất, chống ghi đè (STALE_RECORD)
        @AuraEnabled public Boolean canInspect = false;
        @AuraEnabled public Boolean unauthorized = false; // khách portal lỡ vào trang nội bộ
        @AuraEnabled public String portalUrl;             // nút "Về trang Portal" khi unauthorized
        @AuraEnabled public List<InspectionLine> lines = new List<InspectionLine>();
    }

    // Nút nào trên trang yêu cầu được hiện (LWC srRequestActions)
    public class ActionState {
        @AuraEnabled public Boolean canReceiveGoods = false;
        @AuraEnabled public Boolean canCancel = false;
    }

    // Trang yêu cầu chỉ dành cho nhân viên nội bộ; test đổi giá trị này để giả lập khách portal
    @TestVisible private static String userType = UserInfo.getUserType();

    public static Boolean isInternalUser() {
        return userType == 'Standard';
    }

    // Chặn cả khi khách gọi thẳng Apex mà không qua trang
    public static void requireInternalUser() {
        if (!isInternalUser()) {
            throw SR_UiUtil.auraException(System.Label.SR_ERR_UNAUTHORIZED);
        }
    }

    public static InspectionData getInspectionData(Id requestId) {
        InspectionData data = new InspectionData();
        // Khách lỡ vào trang: không đọc bản ghi, chỉ báo để LWC hiện Unauthorized và nút về Portal
        if (!isInternalUser()) {
            data.unauthorized = true;
            data.portalUrl = System.Label.SR_Portal_Url;
            return data;
        }
        Return_Request__c r = SR_ReturnRequestSelector.selectForInspection(requestId);
        data.status = r.Status__c;
        data.versionToken = SR_UiUtil.versionTokenOf(r.LastModifiedDate);
        data.canInspect = SR_ReturnRequestDomain.canInspect(r, r.Return_Request_Lines__r);
        Map<Id, Return_Request_Line__c> products = SR_ReturnRequestSelector.selectProductInfo(
            new Map<Id, Return_Request_Line__c>(r.Return_Request_Lines__r).keySet());
        for (Return_Request_Line__c l : r.Return_Request_Lines__r) {
            data.lines.add(toLine(l, products.get(l.Id)));
        }
        return data;
    }

    public static ActionState getActionState(Id requestId) {
        ActionState state = new ActionState();
        if (!isInternalUser()) {
            return state; // khách portal: không hiện nút nào
        }
        Return_Request__c r = SR_ReturnRequestSelector.selectById(requestId);
        state.canReceiveGoods = SR_ReturnRequestDomain.canReceiveGoods(r);
        state.canCancel = SR_ReturnRequestDomain.canCancel(r);
        return state;
    }

    // Đổi tình trạng thực tế → tiền dòng theo B.2: tỷ lệ theo lý do + tình trạng thực tế, tiền do Dev A tính
    // (không tính trong JS). Chưa cấu hình tỷ lệ thì 0đ.
    public static Decimal calcLineRefund(Id lineId, String actualCondition) {
        requireInternalUser();
        Return_Request_Line__c l = SR_ReturnRequestLineSelector.selectById(lineId);
        Decimal rate = SR_RefundCalculator.rateFor(l.Reason__c, actualCondition);
        return (rate == null) ? 0 : SR_ReturnRequestService.calcLineRefund(l.Unit_Price__c, l.Quantity__c, rate);
    }

    // Hoàn tất kiểm định: SR_InspectionService kiểm tra MSG-21 / MSG-22, tính lại tiền và đổi trạng thái
    public static void completeInspection(Id requestId, String versionToken, List<SR_InspectionLineDTO> lines) {
        requireInternalUser();
        SR_InspectionRequestDTO input = new SR_InspectionRequestDTO();
        input.requestId = requestId;
        input.versionToken = versionToken;
        input.lines = (lines == null) ? new List<SR_InspectionLineDTO>() : lines;
        throwIfFailed(SR_InspectionService.complete(new List<SR_InspectionRequestDTO>{ input })[0]);
    }

    // Nhận hàng: Awaiting Goods → Inspecting
    public static void receiveGoods(Id requestId) {
        requireInternalUser();
        Return_Request__c r = SR_ReturnRequestSelector.selectById(requestId);
        if (!SR_ReturnRequestDomain.canReceiveGoods(r)) {
            throw invalidTransition(r, SR_StatusMachine.INSPECTING);
        }
        changeStatus(r, SR_StatusMachine.INSPECTING, 'Nhận hàng tại cửa hàng');
    }

    // Hủy từ New / Pending Approval / Awaiting Goods; lý do ghi vào lịch sử trạng thái
    public static void cancel(Id requestId, String reason) {
        requireInternalUser();
        Return_Request__c r = SR_ReturnRequestSelector.selectById(requestId);
        if (!SR_ReturnRequestDomain.canCancel(r)) {
            throw invalidTransition(r, SR_StatusMachine.CANCELLED);
        }
        changeStatus(r, SR_StatusMachine.CANCELLED, reason);
    }

    // ---------- Hàm phụ ----------

    private static void changeStatus(Return_Request__c r, String toStatus, String note) {
        SR_StatusChangeDTO change = new SR_StatusChangeDTO();
        change.requestId = r.Id;
        change.toStatus = toStatus;
        change.note = note;
        change.correlationId = SR_Correlation.newId();
        throwIfFailed(SR_StatusMachine.change(new List<SR_StatusChangeDTO>{ change })[0]);
    }

    // Service của Dev A trả lỗi trong kết quả thay vì throw: đổi thành câu báo cho LWC
    private static void throwIfFailed(SR_ActionResultDTO result) {
        if (result != null && result.success == true) {
            return;
        }
        String message = (result == null) ? null : result.message;
        if (String.isBlank(message) && result != null && !result.details.isEmpty()) {
            message = result.details[0].message;
        }
        throw SR_UiUtil.auraException(String.isBlank(message) ? System.Label.SR_MSG_90 : message);
    }

    // product: dòng chỉ có Order_Product__r.Product2 (SR_ReturnRequestSelector.selectProductInfo), có thể null
    private static InspectionLine toLine(Return_Request_Line__c l, Return_Request_Line__c product) {
        Boolean inspected = SR_ReturnRequestDomain.isInspected(l);
        InspectionLine line = new InspectionLine();
        line.lineId = l.Id;
        line.productName = product?.Order_Product__r?.Product2?.Name;
        line.sku = product?.Order_Product__r?.Product2?.ProductCode;
        line.quantity = l.Quantity__c;
        line.reason = l.Reason__c;
        line.declaredCondition = l.Declared_Condition__c;
        // Chưa ghi tình trạng thực tế thì bắt đầu bằng tình trạng khách khai báo
        line.actualCondition = (l.Actual_Condition__c != null) ? l.Actual_Condition__c : l.Declared_Condition__c;
        line.inspectionResult = inspected ? l.Inspection_Result__c : null;
        line.inspectionNote = l.Inspection_Note__c;
        line.estimatedRefund = l.Estimated_Refund__c;
        line.actualRefund = inspected ? l.Actual_Refund__c : l.Estimated_Refund__c;
        return line;
    }

    // MSG-20: trang đã cũ (người khác vừa đổi trạng thái) thì báo luôn, không gọi state machine
    private static AuraHandledException invalidTransition(Return_Request__c r, String toStatus) {
        return SR_UiUtil.auraException(SR_Util.format(System.Label.SR_MSG_20, new List<Object>{
            SR_StatusMachine.labelOf(r.Status__c), SR_StatusMachine.labelOf(toStatus)
        }));
    }
}