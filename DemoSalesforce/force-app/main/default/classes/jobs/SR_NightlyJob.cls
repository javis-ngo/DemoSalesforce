public without sharing class SR_NightlyJob implements Schedulable {

    private static final String JOB_NAME = 'SR SmartReturn nightly automation';
    private static final String CRON_EXPRESSION = '0 0 1 * * ?';
    private static final String VIETNAM_TIME_ZONE = 'Asia/Bangkok';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new SR_ExpireAwaitingGoodsBatch(), 200);
        Database.executeBatch(new SR_RecalculateRiskBatch(), 200);
        Database.executeBatch(new SR_EscalateApprovalBatch(), 10);
        Database.executeBatch(new SR_ResumeRefundBatch(), 50);
    }

    public static Id scheduleDaily() {
        User scheduler = [
            SELECT TimeZoneSidKey
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        if (scheduler.TimeZoneSidKey != VIETNAM_TIME_ZONE) {
            throw new IllegalArgumentException(
                'Lên lịch SmartReturn lúc 01:00 GMT+7 cần user chạy job có múi giờ Asia/Bangkok.'
            );
        }
        unschedule();
        return System.schedule(JOB_NAME, CRON_EXPRESSION, new SR_NightlyJob());
    }

    public static void unschedule() {
        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(job.Id);
        }
    }
}
