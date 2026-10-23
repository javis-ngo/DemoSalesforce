/**
 * Quy tắc xử lý kết quả PayHub theo bảng Phụ lục E.3 (FR-11, FR-14; BR-12, BR-13).
 *  | PayHub trả về        | outcome  | Yêu cầu                                                         |
 *  | 200 + SUCCESS        | SUCCESS  | COMPLETED                                                       |
 *  | 200 + PENDING        | PENDING  | giữ REFUND_PROCESSING, chờ PayHub gọi INT-04                    |
 *  | 422                  | REJECTED | REFUND_FAILED ngay, không thử lại                               |
 *  | 5xx, quá 10 giây     | RETRY    | hẹn gửi lại sau N phút; hết lượt → REFUND_FAILED + báo Kế toán   |
 * Không truy vấn, không ghi dữ liệu: nhận bản ghi đã query sẵn và kết quả PayHub, nên test được không cần tạo dữ liệu.
 * Owner: Dev B
 */
public inherited sharing class SR_RefundDomain {

    // [DEV A] Giá trị Status__c do Dev A sở hữu (Phụ lục C); hiện picklist chỉ có NEW. Đổi tên thì sửa ở đây.
    public static final String STATUS_REFUND_PROCESSING = 'REFUND_PROCESSING';
    public static final String STATUS_COMPLETED = 'COMPLETED';
    public static final String STATUS_REFUND_FAILED = 'REFUND_FAILED';

    public static final String ERROR_INVALID_COMMAND = 'INVALID_COMMAND';

    // Kết quả xử lý 1 yêu cầu: các field cần ghi + trạng thái đích (null = giữ REFUND_PROCESSING)
    public class Decision {
        public Return_Request__c changes;
        public String toStatus;
        public String error;
    }

    // Lần gửi này là lần thứ mấy
    public static Integer nextAttempt(Return_Request__c r) {
        return (r.Refund_Attempts__c == null ? 0 : r.Refund_Attempts__c.intValue()) + 1;
    }

    // BR-13: merchantRef = mã yêu cầu = Idempotency-Key → PayHub nhận trùng sẽ trả lại kết quả lần đầu, không hoàn thêm
    public static SR_PayHubClient.RefundCommand toCommand(Return_Request__c r) {
        SR_PayHubClient.RefundCommand cmd = new SR_PayHubClient.RefundCommand();
        cmd.requestId = r.Id;
        cmd.merchantRef = r.Name;
        cmd.orderNumber = r.Order__r?.OrderNumber;
        cmd.amount = (r.Actual_Refund__c == null) ? null : r.Actual_Refund__c.longValue();
        cmd.attemptNo = nextAttempt(r);
        return cmd;
    }

    // Dữ liệu không gửi được (thiếu số đơn, tiền ≤ 0): không gọi PayHub, xử lý như PayHub trả 422
    public static SR_PayHubClient.Result invalidCommand(String message) {
        SR_PayHubClient.Result res = new SR_PayHubClient.Result();
        res.outcome = SR_PayHubClient.OUT_REJECTED;
        res.errorCode = ERROR_INVALID_COMMAND;
        res.responseBody = message;
        return res;
    }

    public static Decision decide(
        Return_Request__c r,
        SR_PayHubClient.Result res,
        Integer maxAttempts,
        Integer retryMinutes,
        Datetime now
    ) {
        Integer attempt = nextAttempt(r);
        Decision d = new Decision();
        d.changes = new Return_Request__c(Id = r.Id, Refund_Attempts__c = attempt, Next_Retry_At__c = null);

        if (res?.outcome == SR_PayHubClient.OUT_SUCCESS) {
            d.toStatus = STATUS_COMPLETED;
            d.changes.PayHub_Refund_Id__c = res.refundId;
            d.changes.Last_Refund_Error__c = null;
        } else if (res?.outcome == SR_PayHubClient.OUT_PENDING) {
            d.changes.PayHub_Refund_Id__c = res.refundId;      // chờ PayHub gọi INT-04
            d.changes.Last_Refund_Error__c = null;
        } else {
            // REJECTED (422) không thử lại; RETRY (5xx/timeout) hoặc kết quả lạ thì thử lại tới hết lượt (BR-12)
            d.error = describeError(attempt, maxAttempts, res);
            d.changes.Last_Refund_Error__c = d.error;
            if (res?.outcome == SR_PayHubClient.OUT_REJECTED || attempt >= maxAttempts) {
                d.toStatus = STATUS_REFUND_FAILED;
            } else {
                d.changes.Next_Retry_At__c = now.addMinutes(retryMinutes);
            }
        }
        return d;
    }

    // vd. "Lần 2/3: RETRY HTTP 500 HTTP_500"
    public static String describeError(Integer attempt, Integer maxAttempts, SR_PayHubClient.Result res) {
        String text = 'Lần ' + attempt + '/' + maxAttempts + ': ' + (res?.outcome == null ? 'NO_RESULT' : res.outcome)
            + (res?.httpStatus == null ? '' : ' HTTP ' + res.httpStatus)
            + (String.isBlank(res?.errorCode) ? '' : ' ' + res.errorCode);
        return text.abbreviate(2000);
    }
}
