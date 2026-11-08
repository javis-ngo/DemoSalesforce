/**
 * INT-04: PayHub báo kết quả cuối cho lệnh đang PENDING (Phụ lục E.4).
 *   POST /services/apexrest/smartreturn/v1/refund-callback
 * PayHub dùng integration user + External Client App riêng (như POS/App). Xử lý ở SR_RefundCallbackService.
 * Owner: Dev B
 */
@RestResource(urlMapping='/smartreturn/v1/refund-callback')
global with sharing class SR_RefundCallbackApi {

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        String body = (req.requestBody == null) ? null : req.requestBody.toString();
        SR_RefundCallbackService.handle(body).writeTo(RestContext.response);
    }
}
