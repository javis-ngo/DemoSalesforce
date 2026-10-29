/**
 * Phát sự kiện khi yêu cầu có kết quả hoàn tiền: COMPLETED hoặc REFUND_FAILED (FR-09, FR-13, INT-05).
 *  - SR_UI_Notice__e: màn hình duyệt CHT/QLV (srApprovalWorkspace), luôn phát.
 *  - Return_Request_Event__e: POS/App (INT-05, Phụ lục E.5), chỉ phát khi công tắc B.4
 *    "Thông báo POS/App" (Enable_POS_App_Notification__c) bật.
 * Cả 2 event là Publish After Commit → chỉ gửi khi dữ liệu đã lưu thành công, giao dịch rollback thì không gửi (BR-15).
 * Event chỉ chứa mã yêu cầu, kết quả, số tiền, mã cửa hàng, thời điểm: không có Ghi chú nội bộ (BR-18).
 * Gọi từ SR_RefundService (B5); SR_RefundManualController (B7) và SR_RefundCallbackApi (B9) dùng lại.
 * Tích hợp Dev A: SR_RefundService đã gọi publishResult sau khi chuyển trạng thái, nên trigger/service của Dev A
 * không cần gọi lại cho COMPLETED/REFUND_FAILED (tránh sự kiện trùng). Chuyển trạng thái ở nơi khác sang
 * COMPLETED/REFUND_FAILED thì gọi hàm này sau khi đã update.
 * Ngoài ra publishChanges (gọi từ ReturnRequestTrigger) phát SR_UI_Notice__e có Change_Type__c = CREATED / UPDATED
 * mỗi khi yêu cầu được tạo / cập nhật, để srApprovalWorkspace tự làm mới bảng (FR-08, D.2).
 * Owner: Dev B
 */
public without sharing class SR_EventPublisher {

    public static final Set<String> RESULT_STATUSES = new Set<String>{
        SR_RefundDomain.STATUS_COMPLETED,
        SR_RefundDomain.STATUS_REFUND_FAILED
    };

    public static final String CHANGE_CREATED = 'CREATED';
    public static final String CHANGE_UPDATED = 'UPDATED';

    private static final String CONTEXT = 'SR_EventPublisher';

    /**
     * reqs cần có: Id, Name, Status__c (trạng thái MỚI), Actual_Refund__c, Store__r.Store_Code__c.
     * Yêu cầu không ở trạng thái kết quả thì bỏ qua.
     */
    public static void publishResult(List<Return_Request__c> reqs) {
        publish(buildUiEvents(reqs));
        if (notifyPosApp()) {
            publish(buildExternalEvents(reqs, System.now()));
        }
    }

    @TestVisible
    private static List<SR_UI_Notice__e> buildUiEvents(List<Return_Request__c> reqs) {
        List<SR_UI_Notice__e> events = new List<SR_UI_Notice__e>();
        for (Return_Request__c r : results(reqs)) {
            events.add(new SR_UI_Notice__e(
                Request_Id__c = r.Id,
                Request_Number__c = r.Name,
                Result__c = r.Status__c,
                Amount__c = r.Actual_Refund__c,
                Store_Code__c = r.Store__r?.Store_Code__c
            ));
        }
        return events;
    }

    @TestVisible
    private static List<Return_Request_Event__e> buildExternalEvents(List<Return_Request__c> reqs, Datetime eventTime) {
        List<Return_Request_Event__e> events = new List<Return_Request_Event__e>();
        for (Return_Request__c r : results(reqs)) {
            events.add(new Return_Request_Event__e(
                Request_Number__c = r.Name,
                Result__c = r.Status__c,
                Amount__c = r.Actual_Refund__c,
                Store_Code__c = r.Store__r?.Store_Code__c,
                Event_Time__c = eventTime
            ));
        }
        return events;
    }

    /**
     * Yêu cầu vừa tạo (oldMap = null) hoặc vừa cập nhật: báo srApprovalWorkspace tải lại bảng (FR-08, D.2).
     * Gọi từ ReturnRequestTrigger nên bắt được mọi nguồn: quầy, POS/App, import, duyệt, job đêm, hoàn tiền.
     * Platform event tới mọi người đăng ký, không theo sharing (BR-16), nên event chỉ là tín hiệu: Id, mã yêu cầu,
     * cửa hàng, trạng thái cũ/mới; không có khách hàng, số tiền. LWC tự lấy dữ liệu qua getQueue (USER_MODE).
     * Không điền Result__c → không ra toast MSG-30/MSG-31 trùng với publishResult.
     */
    public static void publishChanges(List<Return_Request__c> newRecords, Map<Id, Return_Request__c> oldMap) {
        publish(buildChangeEvents(newRecords, oldMap));
    }

    @TestVisible
    private static List<SR_UI_Notice__e> buildChangeEvents(
        List<Return_Request__c> newRecords,
        Map<Id, Return_Request__c> oldMap
    ) {
        List<SR_UI_Notice__e> events = new List<SR_UI_Notice__e>();
        if (newRecords == null) {
            return events;
        }
        for (Return_Request__c r : newRecords) {
            Return_Request__c old = (oldMap == null) ? null : oldMap.get(r.Id);
            events.add(new SR_UI_Notice__e(
                Change_Type__c = (old == null) ? CHANGE_CREATED : CHANGE_UPDATED,
                Request_Id__c = r.Id,
                Request_Number__c = r.Name,
                Store_Id__c = r.Store__c,
                Status__c = r.Status__c,
                Old_Status__c = old?.Status__c
            ));
        }
        return events;
    }

    private static List<Return_Request__c> results(List<Return_Request__c> reqs) {
        List<Return_Request__c> filtered = new List<Return_Request__c>();
        if (reqs == null) {
            return filtered;
        }
        for (Return_Request__c r : reqs) {
            if (r != null && RESULT_STATUSES.contains(r.Status__c)) {
                filtered.add(r);
            }
        }
        return filtered;
    }

    // Publish lỗi không làm hỏng giao dịch (hoàn tiền, tạo / cập nhật yêu cầu): ghi log để tra cứu (NFR-09).
    // Chỉ push khi có lỗi: hàm chạy trong trigger, không đẩy sớm log đang chờ của nơi gọi.
    private static void publish(List<SObject> events) {
        if (events.isEmpty()) {
            return;
        }
        SR_Logger logger = SR_Logger.getInstance();
        Boolean failed = false;
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failed = true;
                logger.error(CONTEXT + '.publish', CONTEXT, null,
                    'Publish ' + events[i].getSObjectType() + ' thất bại: ' + results[i].getErrors()[0].getMessage(),
                    (String) events[i].get('Request_Number__c'), null);
            }
        }
        if (failed) {
            logger.push();
        }
    }

    // Công tắc B.4 qua SR_Config, mặc định bật (chưa cấu hình = bật)
    private static Boolean notifyPosApp() {
        return SR_Config.isPosAppNotificationEnabled() != false;
    }
}
