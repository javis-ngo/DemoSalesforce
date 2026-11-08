/**
 * API cho POS/App (Phụ lục E), OAuth 2.0 Client Credentials qua External Client App, mỗi hệ thống 1 integration user:
 *   POST /services/apexrest/smartreturn/v1/return-requests          INT-01 tạo yêu cầu
 *   GET  /services/apexrest/smartreturn/v1/return-requests/{mã}     INT-02 tra cứu
 *   POST /services/apexrest/smartreturn/v1/return-requests/import   nhập tối đa 200 yêu cầu (NFR-02)
 *        – đường này BRD chưa có, cần thống nhất với IT; body là mảng JSON cùng cấu trúc INT-01.
 * Chỉ đọc request, gọi SR_ReturnRequestApiService và ghi response. JSON sai → 400; lỗi khác → 500 kèm mã tra log.
 * with sharing: integration user chỉ thấy yêu cầu của cửa hàng được chia sẻ (BR-16).
 * Owner: Dev B
 */
@RestResource(urlMapping='/smartreturn/v1/return-requests/*')
global with sharing class SR_ReturnRequestApi {

    private static final String IMPORT_SUFFIX = '/import';
    private static final String CONTEXT = 'SR_ReturnRequestApi';

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        String body = (req.requestBody == null) ? '' : req.requestBody.toString();
        SR_ApiResponse result;
        try {
            if (String.isBlank(body)) {
                result = SR_ApiResponse.badRequest(SR_ApiResponse.MISSING_FIELD, 'Body rỗng');
            } else if (req.requestURI != null && req.requestURI.removeEnd('/').endsWith(IMPORT_SUFFIX)) {
                result = SR_ReturnRequestApiService.importRequests(
                    (List<SR_CreateRequestDTO>) JSON.deserialize(body, List<SR_CreateRequestDTO>.class));
            } else {
                result = SR_ReturnRequestApiService.create(
                    (SR_CreateRequestDTO) JSON.deserialize(body, SR_CreateRequestDTO.class));
            }
        } catch (JSONException e) {
            result = SR_ApiResponse.badRequest(SR_ApiResponse.INVALID_VALUE, 'JSON không hợp lệ: ' + e.getMessage());
        } catch (Exception e) {
            result = SR_ApiResponse.internalError(CONTEXT + '.doPost', CONTEXT, e, null);
        }
        result.writeTo(RestContext.response);
    }

    @HttpGet
    global static void doGet() {
        SR_ApiResponse result;
        try {
            String path = (RestContext.request.requestURI == null) ? '' : RestContext.request.requestURI.removeEnd('/');
            String requestNumber = EncodingUtil.urlDecode(path.substringAfterLast('/'), 'UTF-8');
            if (requestNumber == 'return-requests') {
                requestNumber = null;                       // gọi thiếu mã: .../return-requests
            }
            result = SR_ReturnRequestApiService.lookup(requestNumber);
        } catch (Exception e) {
            result = SR_ApiResponse.internalError(CONTEXT + '.doGet', CONTEXT, e, null);
        }
        result.writeTo(RestContext.response);
    }
}
