/**
 * Nghiệp vụ trang chi tiết yêu cầu (D.3 kiểm định, nút Nhận hàng / Hủy – FR-10, Phụ lục C).
 * Chỉ gom dữ liệu cho màn hình và gọi service của Dũng: tính tiền dòng (calcLineRefund),
 * đổi trạng thái (SR_StatusMachine.change). Hoàn tất kiểm định gọi thẳng SR_InspectionService từ controller.
 * Owner: Dev C
 */
public with sharing class SR_RequestPageService {

    public class InspectionLine {
        @AuraEnabled public Id lineId;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String reason;
        @AuraEnabled public String declaredCondition;
        @AuraEnabled public String actualCondition;
        @AuraEnabled public String result;          // PASSED | FAILED, null = chưa kiểm định
        @AuraEnabled public String note;
        @AuraEnabled public Decimal estimatedRefund;
        @AuraEnabled public Decimal actualRefund;   // tiền theo tình trạng thực tế, chưa xét Đạt / Không đạt
    }

    public class InspectionData {
        @AuraEnabled public String status;
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
            throw auraException(System.Label.SR_ERR_UNAUTHORIZED);
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
        data.canInspect = SR_ReturnRequestDomain.canInspect(r, r.Return_Request_Lines__r);
        for (Return_Request_Line__c l : r.Return_Request_Lines__r) {
            data.lines.add(toLine(l));
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

    // Đổi tình trạng thực tế → tiền dòng theo B.2, do hàm tính tiền của Dũng tính (không tính trong JS).
    // Chữ ký theo DUNG-04 ("ví dụ calcLineRefund"); Dũng chốt tên khác thì chỉ sửa dòng này.
    public static Decimal calcLineRefund(Id lineId, String actualCondition) {
        requireInternalUser();
        Return_Request_Line__c l = SR_ReturnRequestLineSelector.selectById(lineId);
        return SR_ReturnRequestService.calcLineRefund(l.Unit_Price__c, l.Quantity__c, l.Reason__c, actualCondition);
    }

    // Nhận hàng: Awaiting Goods → Inspecting
    public static void receiveGoods(Id requestId) {
        requireInternalUser();
        Return_Request__c r = SR_ReturnRequestSelector.selectById(requestId);
        if (!SR_ReturnRequestDomain.canReceiveGoods(r)) {
            throw invalidTransition(r, SR_ReturnRequestDomain.STATUS_INSPECTING);
        }
        SR_StatusMachine.change(new List<Return_Request__c>{ r }, SR_ReturnRequestDomain.STATUS_INSPECTING, null);
    }

    // Hủy từ New / Pending Approval / Awaiting Goods; lý do ghi vào lịch sử trạng thái
    public static void cancel(Id requestId, String reason) {
        requireInternalUser();
        Return_Request__c r = SR_ReturnRequestSelector.selectById(requestId);
        if (!SR_ReturnRequestDomain.canCancel(r)) {
            throw invalidTransition(r, SR_ReturnRequestDomain.STATUS_CANCELLED);
        }
        SR_StatusMachine.change(new List<Return_Request__c>{ r }, SR_ReturnRequestDomain.STATUS_CANCELLED, reason);
    }

    // ---------- Hàm phụ ----------

    private static InspectionLine toLine(Return_Request_Line__c l) {
        Boolean inspected = SR_ReturnRequestDomain.isInspected(l);
        InspectionLine line = new InspectionLine();
        line.lineId = l.Id;
        line.productName = l.Order_Product__r?.Product2?.Name;
        line.sku = l.Order_Product__r?.Product2?.ProductCode;
        line.quantity = l.Quantity__c;
        line.reason = l.Reason__c;
        line.declaredCondition = l.Declared_Condition__c;
        // Chưa ghi tình trạng thực tế thì bắt đầu bằng tình trạng khách khai báo
        line.actualCondition = (l.Actual_Condition__c != null) ? l.Actual_Condition__c : l.Declared_Condition__c;
        line.result = inspected ? l.Inspection_Result__c : null;
        line.note = l.Inspection_Note__c;
        line.estimatedRefund = l.Estimated_Refund__c;
        line.actualRefund = inspected ? l.Actual_Refund__c : l.Estimated_Refund__c;
        return line;
    }

    // MSG-20: trang đã cũ (người khác vừa đổi trạng thái) thì báo luôn, không gọi state machine
    private static AuraHandledException invalidTransition(Return_Request__c r, String toStatus) {
        return auraException(String.format(System.Label.SR_MSG_20, new List<Object>{
            SR_StatusMachine.labelOf(r.Status__c), SR_StatusMachine.labelOf(toStatus)
        }));
    }

    // setMessage để getMessage() trả đúng câu báo thay vì "Script-thrown exception"
    private static AuraHandledException auraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
