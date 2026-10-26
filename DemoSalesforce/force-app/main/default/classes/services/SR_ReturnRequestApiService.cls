/**
 * Nghiệp vụ API cho POS/App (Phụ lục E.1, E.2; FR-03, FR-04; NFR-02).
 *  - create(): INT-01. 201 tạo mới; 200 khi gửi trùng externalRequestId, trả nội dung lần đầu (BR-06, UAT-05).
 *  - importRequests(): tối đa 200 yêu cầu, kết quả từng dòng; dòng lỗi không làm hỏng dòng đúng (NFR-02, UAT-01).
 *  - lookup(): INT-02. 404 REQUEST_NOT_FOUND nếu không có hoặc integration user không được xem.
 * Kiểm tra hạn, ngành hàng, số lượng, tính tiền, chống trùng nằm ở SR_ReturnRequestService.createRequests (Dev A);
 * class này chỉ kiểm tra những gì riêng của API (channel POS/APP, số lượng import) và dựng JSON theo Phụ lục E.
 * Không trả Ghi chú nội bộ (BR-18).
 * [DEV A] Giả định hợp đồng SR_DTO (chưa có trong repo):
 *  - CreateRequest: externalRequestId, channel, orderNumber, customerPhone, storeCode,
 *    lines[] { sku, quantity, reason, condition } – đúng tên field JSON ở E.1 nên deserialize thẳng.
 *  - CreateResult: success, duplicate, requestNumber, status, approvalLevel, estimatedRefundAmount,
 *    lines[] (ResultLine: sku, quantity, unitPrice, refundRate, refundAmount),
 *    errorCode (ORDER_NOT_FOUND | VALIDATION_FAILED | ...), message, details[] (LineError: sku, code, message).
 *  - createRequests trả kết quả cùng thứ tự với đầu vào.
 * Owner: Dev B
 */
public with sharing class SR_ReturnRequestApiService {

    public static final Integer MAX_IMPORT = 200;
    public static final Set<String> API_CHANNELS = new Set<String>{ 'POS', 'APP' };

    // Việt Nam không đổi giờ theo mùa nên offset cố định
    private static final String TIME_ZONE = 'Asia/Ho_Chi_Minh';
    private static final String TIME_OFFSET = '+07:00';

    // ---------- INT-01 ----------

    public static SR_ApiResponse create(SR_DTO.CreateRequest input) {
        Map<String, Object> invalid = validateInput(input);
        if (invalid != null) {
            return SR_ApiResponse.error(400, SR_ApiResponse.VALIDATION_FAILED, 'Yêu cầu không hợp lệ',
                new List<Object>{ invalid });
        }
        SR_DTO.CreateResult r = SR_ReturnRequestService.createRequests(new List<SR_DTO.CreateRequest>{ input })[0];
        if (r.success == true) {
            return new SR_ApiResponse(r.duplicate == true ? 200 : 201, toCreatedBody(r));
        }
        if (r.errorCode == SR_ApiResponse.ORDER_NOT_FOUND) {
            return SR_ApiResponse.error(404, SR_ApiResponse.ORDER_NOT_FOUND, r.message, null);
        }
        if (r.errorCode == SR_ApiResponse.VALIDATION_FAILED) {
            return SR_ApiResponse.error(400, SR_ApiResponse.VALIDATION_FAILED, r.message, toDetails(r));
        }
        // Service trả lỗi lạ: ghi log, trả 500 kèm mã tra cứu
        return SR_ApiResponse.internalError('SR_ReturnRequestApiService.create', 'INT-01',
            new ApiException(r.errorCode + ': ' + r.message), null);
    }

    // ---------- Import (NFR-02) ----------

    public static SR_ApiResponse importRequests(List<SR_DTO.CreateRequest> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return SR_ApiResponse.badRequest(SR_ApiResponse.MISSING_FIELD, 'Danh sách yêu cầu trống');
        }
        if (inputs.size() > MAX_IMPORT) {
            return SR_ApiResponse.badRequest(SR_ApiResponse.INVALID_VALUE,
                'Tối đa ' + MAX_IMPORT + ' yêu cầu mỗi lần, đã gửi ' + inputs.size());
        }

        // Dòng sai channel / rỗng báo lỗi tại chỗ, chỉ gửi dòng hợp lệ vào service (giữ vị trí index)
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        List<SR_DTO.CreateRequest> valid = new List<SR_DTO.CreateRequest>();
        List<Integer> validIndexes = new List<Integer>();
        for (Integer i = 0; i < inputs.size(); i++) {
            Map<String, Object> invalid = validateInput(inputs[i]);
            if (invalid == null) {
                valid.add(inputs[i]);
                validIndexes.add(i);
                items.add(null);
            } else {
                items.add(importItem(i, inputs[i], false, null, null, SR_ApiResponse.VALIDATION_FAILED,
                    'Yêu cầu không hợp lệ', new List<Object>{ invalid }));
            }
        }

        if (!valid.isEmpty()) {
            List<SR_DTO.CreateResult> results = SR_ReturnRequestService.createRequests(valid);
            for (Integer k = 0; k < results.size(); k++) {
                SR_DTO.CreateResult r = results[k];
                Integer i = validIndexes[k];
                items[i] = importItem(i, inputs[i], r.success == true, r.requestNumber, r.status,
                    r.errorCode, r.message, toDetails(r));
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

    // null = hợp lệ; ngược lại là 1 dòng details theo E.1
    @TestVisible
    private static Map<String, Object> validateInput(SR_DTO.CreateRequest input) {
        if (input == null) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.MISSING_FIELD, 'Yêu cầu rỗng');
        }
        if (String.isBlank(input.channel)) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.MISSING_FIELD, 'Thiếu channel');
        }
        if (!API_CHANNELS.contains(input.channel)) {
            return SR_ApiResponse.detail(null, SR_ApiResponse.INVALID_VALUE, 'channel phải là POS hoặc APP');
        }
        return null;
    }

    private static Map<String, Object> importItem(Integer index, SR_DTO.CreateRequest input, Boolean success,
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

    // [DEV A] LineError: sku, code, message
    private static List<Object> toDetails(SR_DTO.CreateResult r) {
        List<Object> details = new List<Object>();
        if (r.details == null) {
            return details;
        }
        for (SR_DTO.LineError e : r.details) {
            details.add(SR_ApiResponse.detail(e.sku, e.code, e.message));
        }
        return details;
    }

    // Body thành công theo mẫu E.1
    private static Map<String, Object> toCreatedBody(SR_DTO.CreateResult r) {
        List<Object> lines = new List<Object>();
        if (r.lines != null) {
            for (SR_DTO.ResultLine l : r.lines) {
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
            'estimatedRefundAmount' => r.estimatedRefundAmount,
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

    public class ApiException extends Exception {
    }
}
