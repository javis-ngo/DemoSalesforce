/**
 * Phản hồi JSON dùng chung cho các REST API của SmartReturn (Phụ lục E).
 *  - Lỗi dùng chung một cấu trúc (E.1): { "errorCode", "message", "details": [ { "sku", "code", "message" } ] }.
 *  - 500 INTERNAL_ERROR: ghi Application_Log__c kèm mã tra cứu và trả mã đó trong message (MSG-90, NFR-09).
 * Service dựng SR_ApiResponse, class @RestResource chỉ gọi writeTo(RestContext.response).
 * Owner: Dev B
 */
public inherited sharing class SR_ApiResponse {

    // errorCode (cấp yêu cầu) – Phụ lục E.1, E.2, E.4
    public static final String VALIDATION_FAILED = 'VALIDATION_FAILED';
    public static final String ORDER_NOT_FOUND = 'ORDER_NOT_FOUND';
    public static final String REQUEST_NOT_FOUND = 'REQUEST_NOT_FOUND';
    public static final String INTERNAL_ERROR = 'INTERNAL_ERROR';

    // code trong details (cấp field / SKU) – Phụ lục E.1
    public static final String MISSING_FIELD = 'MISSING_FIELD';
    public static final String INVALID_VALUE = 'INVALID_VALUE';

    public Integer statusCode;
    public Object body;

    public SR_ApiResponse(Integer statusCode, Object body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public static SR_ApiResponse error(Integer statusCode, String errorCode, String message, List<Object> details) {
        Map<String, Object> body = new Map<String, Object>{ 'errorCode' => errorCode, 'message' => message };
        if (details != null && !details.isEmpty()) {
            body.put('details', details);
        }
        return new SR_ApiResponse(statusCode, body);
    }

    // 400 cho một lỗi field, vd. thiếu merchantRef hoặc JSON sai
    public static SR_ApiResponse badRequest(String code, String message) {
        return error(400, VALIDATION_FAILED, 'Yêu cầu không hợp lệ',
            new List<Object>{ detail(null, code, message) });
    }

    public static Map<String, Object> detail(String sku, String code, String message) {
        return new Map<String, Object>{ 'sku' => sku, 'code' => code, 'message' => message };
    }

    // 500: ghi log ngay (push) rồi trả mã tra cứu cho hệ thống gọi
    public static SR_ApiResponse internalError(String classMethod, String context, Exception e, Id recordId) {
        SR_Logger logger = SR_Logger.getInstance();
        String code = logger.errorWithCode(classMethod, context, e, recordId);
        logger.push();
        return error(500, INTERNAL_ERROR, String.format(System.Label.SR_MSG_90, new List<Object>{ code }), null);
    }

    public String toJson() {
        return body == null ? null : JSON.serialize(body);
    }

    public void writeTo(RestResponse res) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        String json = toJson();
        res.responseBody = json == null ? null : Blob.valueOf(json);
    }
}
