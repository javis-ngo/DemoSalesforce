/**
 * Quy tắc trên bản ghi Return_Request__c cho màn hình duyệt (D.2), trang yêu cầu (D.3) và Customer Portal (D.4).
 * Không truy vấn, không ghi dữ liệu: nhận bản ghi đã query sẵn, nên test được mà không cần tạo dữ liệu.
 */
public inherited sharing class SR_ReturnRequestDomain {

    public static final String STATUS_NEW = 'NEW';
    public static final String STATUS_PENDING_APPROVAL = 'PENDING_APPROVAL';
    public static final String STATUS_AWAITING_GOODS = 'AWAITING_GOODS';
    public static final String STATUS_INSPECTING = 'INSPECTING';
    public static final String STATUS_CANCELLED = 'CANCELLED';
    public static final String RESULT_NOT_INSPECTED = 'NOT_INSPECTED';

    // Phụ lục C: chỉ hủy được từ New / Pending Approval / Awaiting Goods (OI-07: không hủy khi đang hoàn tiền)
    private static final Set<String> CANCELLABLE = new Set<String>{
        STATUS_NEW, STATUS_PENDING_APPROVAL, STATUS_AWAITING_GOODS
    };

    // D.3: nút Nhận hàng chỉ có khi đang chờ mang hàng (Awaiting Goods → Inspecting).
    // Hiện/ẩn nút theo đây; SR_StatusMachine vẫn chặn chuyển sai (MSG-20).
    public static Boolean canReceiveGoods(Return_Request__c r) {
        return r.Status__c == STATUS_AWAITING_GOODS;
    }

    public static Boolean canCancel(Return_Request__c r) {
        return CANCELLABLE.contains(r.Status__c);
    }

    // D.3: dòng đã có kết quả Đạt / Không đạt
    public static Boolean isInspected(Return_Request_Line__c l) {
        return String.isNotBlank(l.Inspection_Result__c) && l.Inspection_Result__c != RESULT_NOT_INSPECTED;
    }

    // D.3: chỉ kiểm định khi đang Inspecting và còn dòng chưa có kết quả (chưa hoàn tất kiểm định)
    public static Boolean canInspect(Return_Request__c r, List<Return_Request_Line__c> lines) {
        if (r.Status__c != STATUS_INSPECTING) {
            return false;
        }
        for (Return_Request_Line__c l : lines) {
            if (!isInspected(l)) {
                return true;
            }
        }
        return false;
    }

    // D.4: 4 số cuối SĐT của khách, bỏ ký tự không phải số. Cần query Account__r.Phone.
    public static Boolean matchesPhoneLast4(Return_Request__c r, String last4) {
        return last4 != null && last4.length() == 4
            && digitsOnly(r.Account__r?.Phone).endsWith(last4);
    }

    // Portal: tiền thực hoàn nếu đã có, chưa có thì tiền dự kiến
    public static Decimal refundAmount(Return_Request__c r) {
        return (r.Actual_Refund__c != null && r.Actual_Refund__c > 0) ? r.Actual_Refund__c : r.Estimated_Refund__c;
    }

    // D.2: số giờ đã chờ duyệt, lấy 1 chữ số thập phân
    public static Decimal waitingHours(Return_Request__c r, Datetime now) {
        return (r.Submitted_At__c == null) ? 0 :
            Decimal.valueOf(now.getTime() - r.Submitted_At__c.getTime()).divide(3600000, 1);
    }

    // D.2: đang chờ duyệt mà đã quá hạn duyệt thì tô đỏ
    public static Boolean isApprovalOverdue(Return_Request__c r, Datetime now) {
        return r.Status__c == STATUS_PENDING_APPROVAL && r.Approval_Due_At__c != null && r.Approval_Due_At__c < now;
    }

    // BR-09: khách đang bị gắn cờ rủi ro
    public static Boolean isRiskyCustomer(Return_Request__c r) {
        return r.Account__r?.Risk_Flag__c == true;
    }

    private static String digitsOnly(String s) {
        return (s == null) ? '' : s.replaceAll('[^0-9]', '');
    }
}
