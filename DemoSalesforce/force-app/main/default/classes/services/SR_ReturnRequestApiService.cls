/**
 * Nghiệp vụ API cho POS/App (Phụ lục E.1, E.2; FR-03, FR-04; NFR-02).
 *  - create(): INT-01. 201 tạo mới; 200 khi gửi trùng externalRequestId, trả nội dung lần đầu (BR-06, UAT-05).
 *  - importRequests(): tối đa 200 yêu cầu, kết quả từng dòng; dòng lỗi không làm hỏng dòng đúng (NFR-02, UAT-01).
 *  - lookup(): INT-02. 404 REQUEST_NOT_FOUND nếu không có hoặc integration user không được xem.
 * Kiểm tra hạn, ngành hàng, số lượng, tính tiền, chống trùng nằm ở SR_ReturnRequestService.createRequests (Dev A);
 * class này chỉ kiểm tra những gì riêng của API (channel POS/APP) và dựng JSON theo Phụ lục E.
 * Không trả Ghi chú nội bộ (BR-18).
 * Hợp đồng Dev A:
 *  - Body JSON E.1 deserialize thẳng vào SR_CreateRequestDTO / SR_CreateLineDTO (cùng tên field).
 *  - createRequests trả List<SR_CreateResultDTO> cùng thứ tự đầu vào: success, isDuplicate, requestNumber, status,
 *    approvalLevel, estimatedRefund, lines (SR_LineCreateResultDTO), errors (SR_ErrorDetailDTO: sku, code,
 *    params, message), correlationId (= mã tra log khi INTERNAL_ERROR, Dev A đã ghi log).
 * Owner: Dev B
 */
public with sharing class SR_ReturnRequestApiService {

    public static final Integer MAX_IMPORT = 200;
    public static final Set<String> API_CHANNELS = new Set<String>{ 'POS', 'APP' };

    // Việt Nam không đổi giờ theo mùa nên offset cố định
    private static final String TIME_ZONE = 'Asia/Ho_Chi_Minh';
    private static final String TIME_OFFSET = '+07:00';
    private static final String MSG_INVALID_REQUEST = 'Yêu cầu không hợp lệ';

    // ---------- INT-01 ----------

    public static SR_ApiResponse create(SR_CreateRequestDTO input) {
        Map<String, Object> invalid = validateInput(input);
        if (invalid != null) {
            return SR_ApiResponse.error(400, SR_ApiResponse.VALIDATION_FAILED, MSG_INVALID_REQUEST,
                new List<Object>{ invalid });
        }
        SR_CreateResultDTO r = SR_ReturnRequestService.createRequests(
            new List<SR_CreateRequestDTO>{ sanitize(input) })[0];
        if (r.success == true) {
            return new SR_ApiResponse(r.isDuplicate == true ? 200 : 201, toCreatedBody(r));
        }
        String errorCode = errorCodeOf(r);
        if (errorCode == SR_ApiResponse.INTERNAL_ERROR) {
            // Dev A đã ghi log với mã correlationId: chỉ trả mã tra cứu, không ghi log lần nữa (MSG-90)
            return SR_ApiResponse.loggedError(r.correlationId);
        }
        if (errorCode == SR_ApiResponse.ORDER_NOT_FOUND) {
            return SR_ApiResponse.error(404, SR_ApiResponse.ORDER_NOT_FOUND, errorMessageOf(r), null);
        }
        return SR_ApiResponse.error(400, SR_ApiResponse.VALIDATION_FAILED, MSG_INVALID_REQUEST, toDetails(r));
    }

    // ---------- Import (NFR-02) ----------

    public static SR_ApiResponse importRequests(List<SR_CreateRequestDTO> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return SR_ApiResponse.badRequest(SR_ApiResponse.MISSING_FIELD, 'Danh sách yêu cầu trống');
        }
        if (inputs.size() > MAX_IMPORT) {
            return SR_ApiResponse.badRequest(SR_ApiResponse.INVALID_VALUE,
                'Tối đa ' + MAX_IMPORT + ' yêu cầu mỗi lần, đã gửi ' + inputs.size());
        }

        // Dòng sai channel / rỗng báo lỗi tại chỗ, chỉ gửi dòng hợp lệ vào service (giữ vị trí index)
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        List<SR_CreateRequestDTO> valid = new List<SR_CreateRequestDTO>();
        List<Integer> validIndexes = new List<Integer>();
        for (Integer i = 0; i < inputs.size(); i++) {
            Map<String, Object> invalid = validateInput(inputs[i]);
            if (invalid == null) {
                valid.add(sanitize(inputs[i]));
                validIndexes.add(i);
                items.add(null);
            } else {
                items.add(importItem(i, inputs[i], false, null, null, SR_ApiResponse.VALIDATION_FAILED,
                    MSG_INVALID_REQUEST, new List<Object>{ invalid }));
            }
        }

        if (!valid.isEmpty()) {
            List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(valid);
            for (Integer k = 0; k < results.size(); k++) {
                SR_CreateResultDTO r = results[k];
                Integer i = validIndexes[k];
                Boolean ok = r.success == true;
                items[i] = importItem(i, inputs[i], ok, r.requestNumber, r.status,
                    ok ? null : errorCodeOf(r), ok ? null : importMessageOf(r), ok ? null : toDetails(r));
            }
        }

        Integer succeeded = 0;
        for (Map<String, Object> item : items) {
            if (item.get('success') == true) {
                succeeded++;
            }
        }
        return new SR_ApiResponse(200, new Map<String, Object>{
            'total' => items.size(),
            'succeeded' => succeeded,
            'failed' => items.size() - succeeded,
            'results' => items
        });
    }

    // ---------- INT-02 ----------

    public static SR_ApiResponse lookup(String requestNumber) {
        if (String.isBlank(requestNumber)) {
            return SR_ApiResponse.badRequest(SR_ApiResponse.MISSING_FIELD, 'Thiếu mã yêu cầu');
        }
        List<Return_Request__c> found = SR_ReturnRequestApiSelector.selectDetailByNumber(requestNumber.trim());
        if (found.isEmpty()) {
            return SR_ApiResponse.error(404, SR_ApiResponse.REQUEST_NOT_FOUND, 'Không tìm thấy yêu cầu', null);
        }
        return new SR_ApiResponse(200, toDetailBody(found[0]));
    }

    // ---------- Hàm phụ ----------

    // null = hợp lệ; ngược lại là 1 dòng details theo E.1. Kiểm tra còn lại (thiếu đơn, dòng...) do Dev A làm.
    @TestVisible
    private static Map<String, Object> validateInput(SR_CreateRequestDTO input) {
        if (input == null) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.MISSING_FIELD, 'Yêu cầu rỗng');
        }
        String channel = SR_Util.normalize(input.channel);
        if (channel == null) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.MISSING_FIELD, 'Thiếu channel');
        }
        // COUNTER chỉ dùng cho màn hình tại quầy (D.1), không nhận qua API
        if (!API_CHANNELS.contains(channel)) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.INVALID_VALUE, 'channel phải là POS hoặc APP');
        }
        return null;
    }

    // Field nội bộ không cho hệ thống ngoài tự đặt: rủi ro do Salesforce tính, đơn tra theo orderNumber + SĐT
    @TestVisible
    private static SR_CreateRequestDTO sanitize(SR_CreateRequestDTO input) {
        input.riskFlag = null;
        input.orderId = null;
        input.atomicMode = false;
        if (input.lines != null) {
            for (SR_CreateLineDTO line : input.lines) {
                if (line != null) {
                    line.orderItemId = null;
                    line.unitPrice = null;
                }
            }
        }
        return input;
    }

    // errorCode cấp yêu cầu (E.1): ORDER_NOT_FOUND, INTERNAL_ERROR, còn lại VALIDATION_FAILED
    @TestVisible
    private static String errorCodeOf(SR_CreateResultDTO r) {
        String result = SR_ApiResponse.VALIDATION_FAILED;
        for (SR_ErrorDetailDTO e : r.errors) {
            if (e?.code == SR_ApiResponse.INTERNAL_ERROR) {
                return SR_ApiResponse.INTERNAL_ERROR;
            }
            if (e?.code == SR_ApiResponse.ORDER_NOT_FOUND) {
                result = SR_ApiResponse.ORDER_NOT_FOUND;
            }
        }
        return result;
    }

    private static String errorMessageOf(SR_CreateResultDTO r) {
        return r.errors.isEmpty() ? MSG_INVALID_REQUEST : messageOf(r.errors[0]);
    }

    private static String importMessageOf(SR_CreateResultDTO r) {
        String errorCode = errorCodeOf(r);
        if (errorCode == SR_ApiResponse.INTERNAL_ERROR) {
            return SR_Util.format(System.Label.SR_MSG_90, new List<Object>{ r.correlationId });
        }
        return errorCode == SR_ApiResponse.ORDER_NOT_FOUND ? errorMessageOf(r) : MSG_INVALID_REQUEST;
    }

    // Câu báo của dòng lỗi: dùng câu Dev A soạn; trống thì lấy Custom Label theo mã (MSG-xx) điền params
    @TestVisible
    private static String messageOf(SR_ErrorDetailDTO e) {
        if (String.isNotBlank(e.message)) {
            return e.message;
        }
        if (!SR_ErrorCode.isSupported(e.code)) {
            return e.code;
        }
        return SR_Util.format(SR_ErrorCode.message(e.code), e.params);
    }

    private static List<Object> toDetails(SR_CreateResultDTO r) {
        List<Object> details = new List<Object>();
        for (SR_ErrorDetailDTO e : r.errors) {
            if (e != null && e.code != SR_ApiResponse.INTERNAL_ERROR) {
                details.add(SR_ApiResponse.detail(e.sku, e.code, messageOf(e)));
            }
        }
        return details;
    }

    private static Map<String, Object> importItem(Integer index, SR_CreateRequestDTO input, Boolean success,
        String requestNumber, String status, String errorCode, String message, List<Object> details) {
        return new Map<String, Object>{
            'index' => index,
            'externalRequestId' => input?.externalRequestId,
            'success' => success,
            'requestNumber' => requestNumber,
            'status' => status,
            'errorCode' => success ? null : errorCode,
            'message' => success ? null : message,
            'details' => (details == null || details.isEmpty()) ? null : details
        };
    }

    // Body thành công theo mẫu E.1
    private static Map<String, Object> toCreatedBody(SR_CreateResultDTO r) {
        List<Object> lines = new List<Object>();
        if (r.lines != null) {
            for (SR_LineCreateResultDTO l : r.lines) {
                lines.add(new Map<String, Object>{
                    'sku' => l.sku,
                    'quantity' => l.quantity,
                    'unitPrice' => l.unitPrice,
                    'refundRate' => l.refundRate,
                    'refundAmount' => l.refundAmount
                });
            }
        }
        return new Map<String, Object>{
            'requestNumber' => r.requestNumber,
            'status' => r.status,
            'approvalLevel' => r.approvalLevel,
            'estimatedRefundAmount' => r.estimatedRefund,
            'lines' => lines
        };
    }

    // Body tra cứu theo mẫu E.2. Dòng đã kiểm định thì trả tiền thực hoàn, chưa thì tiền dự kiến.
    @TestVisible
    private static Map<String, Object> toDetailBody(Return_Request__c r) {
        Boolean anyInspected = false;
        List<Object> lines = new List<Object>();
        for (Return_Request_Line__c l : r.Return_Request_Lines__r) {
            Boolean inspected = String.isNotBlank(l.Inspection_Result__c);
            anyInspected = anyInspected || inspected;
            lines.add(new Map<String, Object>{
                'sku' => l.Order_Product__r?.Product2?.ProductCode,
                'quantity' => l.Quantity__c,
                'inspectionResult' => l.Inspection_Result__c,
                'refundAmount' => inspected ? l.Actual_Refund__c : l.Estimated_Refund__c
            });
        }
        List<Object> history = new List<Object>();
        for (Return_Request_History__c h : r.Return_Request_Histories__r) {
            history.add(new Map<String, Object>{
                'status' => h.To_Status__c,
                'changedAt' => toIso(h.Changed_At__c != null ? h.Changed_At__c : h.CreatedDate)
            });
        }
        return new Map<String, Object>{
            'requestNumber' => r.Name,
            'status' => r.Status__c,
            'orderNumber' => r.Order__r?.OrderNumber,
            'refundAmount' => (anyInspected && r.Actual_Refund__c != null) ? r.Actual_Refund__c : r.Estimated_Refund__c,
            'lines' => lines,
            'history' => history
        };
    }

    // vd. 2026-10-05T09:12:03+07:00
    @TestVisible
    private static String toIso(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ss', TIME_ZONE) + TIME_OFFSET;
    }
}
