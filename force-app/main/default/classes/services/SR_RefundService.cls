/**
 * Gửi lệnh hoàn tiền tới PayHub (FR-11, FR-14; BR-12 → BR-15; NFR-04; INT-03).
 * Chạy bất đồng bộ (Queueable) nên người dùng không phải chờ PayHub (NFR-04).
 *  - Đọc → gọi PayHub → mới ghi: Salesforce không cho callout sau DML chưa commit trong cùng transaction.
 *  - Mỗi job tối đa 10 yêu cầu (mỗi callout chờ tối đa 10 giây, tổng 120 giây/transaction); phần còn lại xếp job kế tiếp.
 *  - Không bao giờ hoàn 2 lần (BR-13): chỉ gửi yêu cầu đang REFUND_PROCESSING, Idempotency-Key = mã yêu cầu.
 *  - Xử lý kết quả theo Phụ lục E.3 (SR_RefundDomain). Hết lượt thử hoặc 422 → REFUND_FAILED + báo nhóm Kế toán (FR-14).
 *  - Mọi lần gửi được ghi Integration_Log__c qua SR_PayHubClient (BR-14).
 *  - retryDue(): SR_RefundRetryJob (B6) gọi mỗi 15 phút; applyFinalResult()/notifyAccounting() dùng lại ở
 *    SR_ManualRefundService (B7) và SR_RefundCallbackService (B9).
 *  - Chuyển trạng thái qua SR_StatusMachine.change (chặn chuyển sai MSG-20, ghi lịch sử FR-06); phát sự kiện kết quả
 *    qua SR_EventPublisher (Publish After Commit, BR-15).
 *  - Tham số (công tắc B.4, số lần thử, khoảng cách thử lại) đọc qua SR_Config (Phụ lục B.3, B.4).
 * Tích hợp Dev A:
 *  - SR_InspectionService.complete gọi SR_RefundService.enqueue(ids) sau khi chuyển yêu cầu sang REFUND_PROCESSING.
 *  - Trigger/service của Dev A KHÔNG gọi SR_EventPublisher cho COMPLETED/REFUND_FAILED, vì class này đã tự phát (tránh gửi trùng).
 * without sharing: Queueable chạy dưới quyền người bấm "Hoàn tất kiểm định"; job thử lại chạy dưới quyền người lên lịch.
 * Lưu ý: SR_StatusMachine đọc lại yêu cầu WITH USER_MODE, nên người chạy cần quyền xem yêu cầu (permission set – Dev A).
 * Owner: Dev B
 */
public without sharing class SR_RefundService implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final Integer BATCH_SIZE = 10;

    // Mỗi lần quét thử lại nhận tối đa 100 yêu cầu (10 job nối tiếp × 10 yêu cầu)
    @TestVisible
    private static final Integer RETRY_SCAN_LIMIT = 100;

    // = độ dài field Return_Request_History__c.Note__c
    private static final Integer HISTORY_NOTE_MAX_LENGTH = 1000;
    private static final String ACCOUNTING_GROUP = 'SR_Accounting';
    private static final String NOTIFICATION_TYPE = 'SR_Notification';
    private static final String CONTEXT = 'SR_RefundService';

    // Ghi chú lịch sử khi chuyển trạng thái từ kết quả PayHub
    private static final Map<String, String> STATUS_NOTES = new Map<String, String>{
        SR_RefundDomain.STATUS_COMPLETED => 'PayHub hoàn tiền thành công',
        SR_RefundDomain.STATUS_REFUND_FAILED => 'PayHub hoàn tiền lỗi, chuyển Kế toán xử lý'
    };

    // Test lỗi xếp job ở SR_InspectionService (cùng kiểu SR_StatusMachine.forceHistoryFailureForTest)
    @TestVisible
    private static Boolean forceEnqueueFailureForTest = false;

    // SR_StatusMachine từ chối chuyển trạng thái (vd. MSG-20 khi người khác vừa đổi trạng thái)
    public class StatusChangeException extends Exception {
    }

    private class EnqueueException extends Exception {
    }

    private final List<Id> requestIds;

    public SR_RefundService(List<Id> requestIds) {
        this.requestIds = (requestIds == null) ? new List<Id>() : requestIds;
    }

    /**
     * Xếp job gửi PayHub. SR_InspectionService gọi khi kiểm định xong; job thử lại (B6) và job đêm cũng gọi hàm này.
     * Trả về Id job, hoặc null nếu không có gì để gửi hoặc công tắc B.4 "Gửi PayHub" đang tắt
     * (yêu cầu vẫn ở REFUND_PROCESSING, bật lại công tắc thì job đêm gửi tiếp).
     */
    public static Id enqueue(Set<Id> requestIds) {
        if (Test.isRunningTest() && forceEnqueueFailureForTest) {
            throw new EnqueueException('Forced enqueue failure.');
        }
        if (requestIds == null || requestIds.isEmpty() || SR_Config.isPayHubEnabled() == false) {
            return null;
        }
        return System.enqueueJob(new SR_RefundService(new List<Id>(requestIds)));
    }

    /**
     * B6 – BR-12: SR_RefundRetryJob gọi mỗi 15 phút. Nhận các yêu cầu đã đến giờ hẹn gửi lại (tối đa
     * RETRY_SCAN_LIMIT, phần dư lần quét sau lấy tiếp), xóa Next_Retry_At__c để lần quét sau không nhận trùng,
     * rồi xếp job gửi. DML ở đây không ảnh hưởng callout vì callout chạy ở transaction của Queueable.
     * Trả về số yêu cầu đã xếp gửi lại.
     */
    public static Integer retryDue() {
        // Công tắc B.4 tắt: giữ nguyên giờ hẹn, bật lại thì lần quét kế tiếp gửi
        if (SR_Config.isPayHubEnabled() == false) {
            return 0;
        }
        List<Return_Request__c> due = SR_RefundSelector.selectDueForRetry(System.now(), RETRY_SCAN_LIMIT);
        if (due.isEmpty()) {
            return 0;
        }
        Set<Id> ids = new Set<Id>();
        for (Return_Request__c r : due) {
            r.Next_Retry_At__c = null;
            ids.add(r.Id);
        }
        update due;
        enqueue(ids);
        return ids.size();
    }

    /**
     * B7 (Kế toán hoàn tay), B9 (PayHub callback): ghi kết quả cuối cho 1 yêu cầu đã khóa FOR UPDATE.
     * r cần Id, Name, Status__c (trạng thái hiện tại), Actual_Refund__c, Store__r.Store_Code__c.
     * changes: các field hoàn tiền cần ghi (PayHub_Refund_Id__c, Last_Refund_Error__c...), có Id.
     * Lỗi thì rollback toàn bộ và ném ra để nơi gọi trả lỗi; SR_StatusMachine từ chối → StatusChangeException
     * kèm câu báo của SR_StatusMachine (MSG-20).
     */
    public static void applyFinalResult(Return_Request__c r, Return_Request__c changes, String toStatus, String note) {
        Savepoint sp = Database.setSavepoint();
        try {
            changes.Next_Retry_At__c = null;
            update changes;
            SR_ActionResultDTO result = SR_StatusMachine.change(
                new List<SR_StatusChangeDTO>{ statusChange(r, toStatus, note) })[0];
            if (result.success != true) {
                throw new StatusChangeException(result.message);
            }
            r.Status__c = toStatus;
            SR_EventPublisher.publishResult(new List<Return_Request__c>{ r });
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
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
        Integer maxAttempts = SR_Config.payHubMaxTotalAttempts();
        Integer retryMinutes = SR_Config.payHubRetryIntervalMinutes();
        Datetime now = System.now();

        List<Return_Request__c> changes = new List<Return_Request__c>();
        List<Return_Request__c> transitioned = new List<Return_Request__c>();
        List<SR_StatusChangeDTO> statusChanges = new List<SR_StatusChangeDTO>();
        Map<Id, String> failedErrors = new Map<Id, String>();

        for (Return_Request__c r : reqs) {
            SR_RefundDomain.Decision d = SR_RefundDomain.decide(r, results.get(r.Id), maxAttempts, retryMinutes, now);
            changes.add(d.changes);
            if (d.toStatus == null) {
                continue;
            }
            // Một lần gọi SR_StatusMachine cho cả lô; mỗi yêu cầu mang trạng thái đích riêng
            transitioned.add(r);
            statusChanges.add(statusChange(r, d.toStatus, STATUS_NOTES.get(d.toStatus)));
            if (d.toStatus == SR_RefundDomain.STATUS_REFUND_FAILED) {
                failedErrors.put(r.Id, d.error);
            }
        }

        List<Return_Request__c> finished = new List<Return_Request__c>();
        Savepoint sp = Database.setSavepoint();
        try {
            // Field hoàn tiền (số lần thử, refundId, lỗi) ghi nhận lần gọi PayHub vừa xảy ra, nên ghi kể cả khi
            // chuyển trạng thái bị từ chối
            update changes;
            List<SR_ActionResultDTO> statusResults = SR_StatusMachine.change(statusChanges);
            for (Integer i = 0; i < statusResults.size(); i++) {
                Return_Request__c r = transitioned[i];
                SR_ActionResultDTO res = statusResults[i];
                if (res.success == true) {
                    r.Status__c = statusChanges[i].toStatus;
                    finished.add(r);
                } else {
                    // vd. người khác vừa đổi trạng thái: không phát sự kiện, không báo Kế toán cho yêu cầu này
                    failedErrors.remove(r.Id);
                    logger.error(CONTEXT + '.applyResults', CONTEXT, r.Name,
                        'Không chuyển được sang ' + statusChanges[i].toStatus + ': ' + res.errorCode + ' ' + res.message,
                        r.Id, null);
                }
            }
            SR_EventPublisher.publishResult(finished);
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }

        for (Return_Request__c r : finished) {
            if (failedErrors.containsKey(r.Id)) {
                logger.warn(CONTEXT + '.applyResults', CONTEXT, r.Name, failedErrors.get(r.Id), r.Id);
            }
        }
        notifyAccounting(finished, failedErrors);
    }

    /**
     * FR-14: báo nhóm Kế toán (Public Group SR_Accounting) qua Custom Notification SR_Notification, kèm lỗi.
     * Kế toán vẫn thấy yêu cầu REFUND_FAILED trong danh sách nên gửi thông báo lỗi chỉ ghi log, không rollback.
     * Dùng lại ở SR_RefundCallbackService (PayHub báo FAILED qua INT-04). Gọi SAU khi đã ghi dữ liệu;
     * log được đưa vào SR_Logger, nơi gọi tự push().
     */
    public static void notifyAccounting(List<Return_Request__c> finished, Map<Id, String> failedErrors) {
        if (failedErrors == null || failedErrors.isEmpty()) {
            return;
        }
        SR_Logger logger = SR_Logger.getInstance();
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

    // correlationId = mã yêu cầu = Idempotency-Key, để nối dòng lịch sử với Integration_Log__c
    private static SR_StatusChangeDTO statusChange(Return_Request__c r, String toStatus, String note) {
        SR_StatusChangeDTO change = new SR_StatusChangeDTO();
        change.requestId = r.Id;
        change.toStatus = toStatus;
        change.note = (note == null) ? null : note.abbreviate(HISTORY_NOTE_MAX_LENGTH);
        change.correlationId = r.Name;
        return change;
    }
}
