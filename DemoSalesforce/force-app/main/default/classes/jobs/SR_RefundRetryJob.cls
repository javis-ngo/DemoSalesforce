/**
 * B6 – BR-12: gửi lại lệnh hoàn tiền lỗi (5xx/timeout), cách lần trước ít nhất 15 phút.
 * Scheduled Apex không đặt được lịch "mỗi 15 phút" trong 1 job, nên tạo 4 job ở phút 00/15/30/45.
 * Việc quét, nhận việc và xếp Queueable nằm ở SR_RefundService.retryDue(); class này chỉ là điểm vào lịch.
 * Lên lịch 1 lần (Anonymous Apex):  SR_RefundRetryJob.scheduleEvery15Minutes();
 * Hủy lịch:                         SR_RefundRetryJob.unscheduleAll();
 * Job chạy dưới quyền người lên lịch → người đó cần permission set SR_PayHub_Callout (B3).
 * Owner: Dev B
 */
public without sharing class SR_RefundRetryJob implements Schedulable {

    @TestVisible
    private static final String JOB_NAME_PREFIX = 'SR PayHub retry :';
    private static final List<Integer> MINUTES = new List<Integer>{ 0, 15, 30, 45 };
    private static final String CONTEXT = 'SR_RefundRetryJob';

    public void execute(SchedulableContext ctx) {
        SR_Logger logger = SR_Logger.getInstance();
        try {
            Integer count = SR_RefundService.retryDue();
            if (count > 0) {
                logger.info(CONTEXT + '.execute', CONTEXT, null, 'Xếp gửi lại ' + count + ' yêu cầu', null);
            }
        } catch (Exception e) {
            logger.error(CONTEXT + '.execute', CONTEXT, null,
                e.getTypeName() + ': ' + e.getMessage(), null, e.getStackTraceString());
        } finally {
            logger.push();
        }
    }

    // Chạy lại nhiều lần vẫn chỉ có đúng 4 job (hủy job cũ cùng tên trước)
    public static List<Id> scheduleEvery15Minutes() {
        unscheduleAll();
        List<Id> jobIds = new List<Id>();
        for (Integer minute : MINUTES) {
            jobIds.add(System.schedule(jobName(minute), '0 ' + minute + ' * * * ?', new SR_RefundRetryJob()));
        }
        return jobIds;
    }

    public static void unscheduleAll() {
        List<String> names = new List<String>();
        for (Integer minute : MINUTES) {
            names.add(jobName(minute));
        }
        for (Id jobId : SR_RefundSelector.selectScheduledJobIds(names)) {
            System.abortJob(jobId);
        }
    }

    private static String jobName(Integer minute) {
        return JOB_NAME_PREFIX + String.valueOf(minute).leftPad(2, '0');
    }
}
