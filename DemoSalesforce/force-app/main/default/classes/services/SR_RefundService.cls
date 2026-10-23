/**
 * Gửi lệnh hoàn tiền tới PayHub (FR-11, FR-14; BR-12 → BR-15; NFR-04; INT-03).
 * Chạy bất đồng bộ (Queueable) nên người dùng không phải chờ PayHub (NFR-04).
 *  - Đọc → gọi PayHub → mới ghi: Salesforce không cho callout sau DML chưa commit trong cùng transaction.
 *  - Mỗi job tối đa 10 yêu cầu (mỗi callout chờ tối đa 10 giây, tổng 120 giây/transaction); phần còn lại xếp job kế tiếp.
 *  - Không bao giờ hoàn 2 lần (BR-13): chỉ gửi yêu cầu đang REFUND_PROCESSING, Idempotency-Key = mã yêu cầu.
 *  - Xử lý kết quả theo Phụ lục E.3 (SR_RefundDomain). Hết lượt thử hoặc 422 → REFUND_FAILED + báo nhóm Kế toán (FR-14).
 *  - Mọi lần gửi được ghi Integration_Log__c qua SR_PayHubClient (BR-14).
 *  - Chuyển trạng thái qua SR_StatusMachine (chặn chuyển sai, ghi lịch sử FR-06); phát sự kiện kết quả qua
 *    SR_EventPublisher (Publish After Commit, BR-15).
 * [DEV A] Phụ thuộc phạm vi Dev A (tìm "[DEV A]" để tích hợp):
 *  - SR_StatusMachine.change(...) chưa có trong repo → class này chưa compile được cho tới khi Dev A merge.
 *  - Object/field/Status__c (REFUND_PROCESSING, COMPLETED, REFUND_FAILED, Refund_Attempts__c, ...): Dev A sở hữu.
 *  - Dev A gọi SR_RefundService.enqueue(ids) khi kiểm định xong (SR_InspectionService) sau khi chuyển sang REFUND_PROCESSING.
 *  - Trigger/service của Dev A KHÔNG được gọi SR_EventPublisher cho COMPLETED/REFUND_FAILED, vì class này đã tự phát (tránh gửi trùng).
 * without sharing: Queueable chạy dưới quyền người bấm "Hoàn tất kiểm định"; job thử lại chạy dưới quyền người lên lịch.
 * Owner: Dev B
 */
public without sharing class SR_RefundService implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final Integer BATCH_SIZE = 10;

    private static final String SETTING_DEVELOPER_NAME = 'Default';
    private static final Integer DEFAULT_MAX_ATTEMPTS = 3;
    private static final Integer DEFAULT_RETRY_MINUTES = 15;
    private static final String ACCOUNTING_GROUP = 'SR_Accounting';
    private static final String NOTIFICATION_TYPE = 'SR_Notification';
    private static final String CONTEXT = 'SR_RefundService';

    // [DEV A] Ghi chú lịch sử truyền vào SR_StatusMachine.change; Dev A có thể đổi nếu StatusMachine tự sinh note
    private static final Map<String, String> STATUS_NOTES = new Map<String, String>{
        SR_RefundDomain.STATUS_COMPLETED => 'PayHub hoàn tiền thành công',
        SR_RefundDomain.STATUS_REFUND_FAILED => 'PayHub hoàn tiền lỗi, chuyển Kế toán xử lý'
    };

    @TestVisible
    private static SR_Setting__mdt settingOverride;

    private final List<Id> requestIds;

    public SR_RefundService(List<Id> requestIds) {
        this.requestIds = (requestIds == null) ? new List<Id>() : requestIds;
    }

    /**
     * Xếp job gửi PayHub. Dev A gọi khi kiểm định xong; job thử lại (B6) và job đêm cũng gọi hàm này.
     * Trả về Id job, hoặc null nếu không có gì để gửi hoặc công tắc B.4 "Gửi PayHub" đang tắt
     * (yêu cầu vẫn ở REFUND_PROCESSING, bật lại công tắc thì job đêm gửi tiếp).
     */
    public static Id enqueue(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty() || setting()?.Enable_PayHub__c == false) {
            return null;
        }
        return System.enqueueJob(new SR_RefundService(new List<Id>(requestIds)));
    }

    public void execute(QueueableContext ctx) {
        Set<Id> current = new Set<Id>();
        Set<Id> later = new Set<Id>();
        for (Id requestId : requestIds) {
            if (current.size() < BATCH_SIZE) {
                current.add(requestId);
            } else {
                later.add(requestId);
            }
        }

        process(current);

        // Test không cho Queueable xếp job nối tiếp
        if (!later.isEmpty() && !Test.isRunningTest()) {
            enqueue(later);
        }
    }

    /**
     * Gửi tối đa BATCH_SIZE yêu cầu và ghi kết quả. Không ném lỗi ra ngoài: lỗi được ghi Application_Log__c,
     * phần ghi dữ liệu rollback, yêu cầu giữ REFUND_PROCESSING và PayHub đã nhận thì Idempotency-Key chặn hoàn trùng.
     */
    @TestVisible
    private static void process(Set<Id> ids) {
        SR_Logger logger = SR_Logger.getInstance();
        try {
            // 1) Chỉ ĐỌC rồi gọi PayHub, chưa ghi gì trước khi callout
            List<Return_Request__c> reqs = SR_RefundSelector.selectSendable(ids, System.now());
            Map<Id, SR_PayHubClient.Result> results = send(reqs, logger);

            // 2) Gọi xong hết mới ghi kết quả
            applyResults(reqs, results, logger);
        } catch (Exception e) {
            logger.error(CONTEXT + '.process', CONTEXT, null,
                e.getTypeName() + ': ' + e.getMessage() + ' | Yêu cầu: ' + String.join(new List<Id>(ids), ','),
                null, e.getStackTraceString());
        } finally {
            logger.push();
        }
    }

    private static Map<Id, SR_PayHubClient.Result> send(List<Return_Request__c> reqs, SR_Logger logger) {
        Map<Id, SR_PayHubClient.Result> results = new Map<Id, SR_PayHubClient.Result>();
        for (Return_Request__c r : reqs) {
            try {
                results.put(r.Id, SR_PayHubClient.sendRefund(SR_RefundDomain.toCommand(r)));
            } catch (SR_PayHubClient.PayHubClientException e) {
                // Thiếu số đơn hoặc tiền ≤ 0: PayHub chắc chắn từ chối, không gọi và không thử lại
                logger.warn(CONTEXT + '.send', CONTEXT, r.Name, e.getMessage(), r.Id);
                results.put(r.Id, SR_RefundDomain.invalidCommand(e.getMessage()));
            }
        }
        return results;
    }

    private static void applyResults(
        List<Return_Request__c> reqs,
        Map<Id, SR_PayHubClient.Result> results,
        SR_Logger logger
    ) {
        if (reqs.isEmpty()) {
            return;
        }
        SR_Setting__mdt s = setting();
        Integer maxAttempts = intOrDefault(s?.PayHub_Max_Total_Attempts__c, DEFAULT_MAX_ATTEMPTS);
        Integer retryMinutes = intOrDefault(s?.PayHub_Retry_Interval_Minutes__c, DEFAULT_RETRY_MINUTES);
        Datetime now = System.now();

        List<Return_Request__c> changes = new List<Return_Request__c>();
        Map<String, List<Return_Request__c>> transitions = new Map<String, List<Return_Request__c>>();
        List<Return_Request__c> finished = new List<Return_Request__c>();
        Map<Id, String> failedErrors = new Map<Id, String>();

        for (Return_Request__c r : reqs) {
            SR_RefundDomain.Decision d = SR_RefundDomain.decide(r, results.get(r.Id), maxAttempts, retryMinutes, now);
            changes.add(d.changes);
            if (d.toStatus == null) {
                continue;
            }
            if (!transitions.containsKey(d.toStatus)) {
                transitions.put(d.toStatus, new List<Return_Request__c>());
            }
            // [DEV A] Giả định hợp đồng SR_StatusMachine.change(List<Return_Request__c>, String toStatus, String note):
            // kiểm tra chuyển hợp lệ (MSG-20), set Status__c, ghi Return_Request_History__c và tự update bản ghi.
            // Chỉ Id + trạng thái hiện tại: SR_StatusMachine kiểm tra REFUND_PROCESSING → toStatus,
            // và không ghi đè các field hoàn tiền vừa cập nhật ở trên
            transitions.get(d.toStatus).add(new Return_Request__c(Id = r.Id, Status__c = r.Status__c));
            r.Status__c = d.toStatus;
            finished.add(r);
            if (d.toStatus == SR_RefundDomain.STATUS_REFUND_FAILED) {
                failedErrors.put(r.Id, d.error);
                logger.warn(CONTEXT + '.applyResults', CONTEXT, r.Name, d.error, r.Id);
            }
        }

        Savepoint sp = Database.setSavepoint();
        try {
            update changes;
            // Tối đa 2 lần (COMPLETED, REFUND_FAILED): mỗi trạng thái đích một lần gọi, không theo từng bản ghi
            for (String toStatus : transitions.keySet()) {
                // [DEV A] SR_StatusMachine thuộc Dev A (chưa có trong repo)
                SR_StatusMachine.change(transitions.get(toStatus), toStatus, STATUS_NOTES.get(toStatus));
            }
            SR_EventPublisher.publishResult(finished);
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }

        notifyAccounting(finished, failedErrors, logger);
    }

    /**
     * FR-14: báo nhóm Kế toán (Public Group SR_Accounting) qua Custom Notification SR_Notification, kèm lỗi.
     * Kế toán vẫn thấy yêu cầu REFUND_FAILED trong danh sách nên gửi thông báo lỗi chỉ ghi log, không rollback.
     */
    private static void notifyAccounting(List<Return_Request__c> finished, Map<Id, String> failedErrors, SR_Logger logger) {
        if (failedErrors.isEmpty()) {
            return;
        }
        try {
            Id groupId = SR_RefundSelector.selectGroupId(ACCOUNTING_GROUP);
            Id typeId = SR_RefundSelector.selectNotificationTypeId(NOTIFICATION_TYPE);
            if (groupId == null || typeId == null) {
                logger.warn(CONTEXT + '.notifyAccounting', CONTEXT, null,
                    'Thiếu Public Group ' + ACCOUNTING_GROUP + ' hoặc Custom Notification ' + NOTIFICATION_TYPE
                    + ', không báo được Kế toán cho ' + failedErrors.size() + ' yêu cầu', null);
                return;
            }
            for (Return_Request__c r : finished) {
                if (!failedErrors.containsKey(r.Id)) {
                    continue;
                }
                Messaging.CustomNotification n = new Messaging.CustomNotification();
                n.setNotificationTypeId(typeId);
                n.setTargetId(r.Id);
                n.setTitle('Hoàn tiền lỗi – cần xử lý');
                n.setBody(String.format(System.Label.SR_MSG_31, new List<Object>{ r.Name }) + '\n' + failedErrors.get(r.Id));
                n.send(new Set<String>{ groupId });
            }
        } catch (Exception e) {
            logger.error(CONTEXT + '.notifyAccounting', CONTEXT, null,
                e.getTypeName() + ': ' + e.getMessage(), null, e.getStackTraceString());
        }
    }

    private static SR_Setting__mdt setting() {
        return (settingOverride != null) ? settingOverride : SR_Setting__mdt.getInstance(SETTING_DEVELOPER_NAME);
    }

    private static Integer intOrDefault(Decimal value, Integer fallback) {
        return (value == null || value <= 0) ? fallback : value.intValue();
    }
}
