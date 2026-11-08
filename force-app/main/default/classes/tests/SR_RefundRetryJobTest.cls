/**
 * Test cho SR_RefundRetryJob và SR_RefundService.retryDue (B6, BR-12).
 * Công tắc B.4 ghi đè bằng SR_TestDataFactory.overrideConfig (Dev A).
 * Chạy: sf apex run test --class-names SR_RefundRetryJobTest --result-format human
 */
@IsTest
private class SR_RefundRetryJobTest {

    private static Return_Request__c insertRequest(Datetime nextRetryAt, String payHubRefundId) {
        Return_Request__c r = new Return_Request__c(
            Channel__c = 'POS',
            Status__c = SR_RefundDomain.STATUS_REFUND_PROCESSING,
            Refund_Attempts__c = 1,
            Next_Retry_At__c = nextRetryAt,
            PayHub_Refund_Id__c = payHubRefundId
        );
        insert r;
        return r;
    }

    private static void enablePayHub(Boolean enabled) {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_PayHub__c, enabled);
    }

    @IsTest
    static void schedulesFourJobsAndRescheduleDoesNotDuplicate() {
        Test.startTest();
        SR_RefundRetryJob.scheduleEvery15Minutes();
        List<Id> second = SR_RefundRetryJob.scheduleEvery15Minutes();
        Test.stopTest();

        Assert.areEqual(4, second.size());
        List<CronTrigger> jobs = [
            SELECT CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :SR_RefundRetryJob.JOB_NAME_PREFIX + '%'
            ORDER BY CronExpression
        ];
        Assert.areEqual(4, jobs.size(), 'Lên lịch lại không được tạo job trùng');
        Assert.areEqual('0 0 * * * ?', jobs[0].CronExpression);
    }

    @IsTest
    static void unscheduleRemovesJobs() {
        SR_RefundRetryJob.scheduleEvery15Minutes();
        SR_RefundRetryJob.unscheduleAll();
        Assert.areEqual(0, [
            SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :SR_RefundRetryJob.JOB_NAME_PREFIX + '%'
        ]);
    }

    @IsTest
    static void nothingDueEnqueuesNothing() {
        enablePayHub(true);
        Test.startTest();
        new SR_RefundRetryJob().execute(null);
        Assert.areEqual(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    // Công tắc B.4 tắt: không nhận việc, giữ giờ hẹn
    @IsTest
    static void payHubDisabledKeepsSchedule() {
        Return_Request__c r = insertRequest(System.now().addMinutes(-1), null);
        enablePayHub(false);
        Test.startTest();
        Assert.areEqual(0, SR_RefundService.retryDue());
        Test.stopTest();
        Assert.isNotNull([SELECT Next_Retry_At__c FROM Return_Request__c WHERE Id = :r.Id].Next_Retry_At__c);
    }

    // Đến giờ: nhận việc (xóa giờ hẹn) và xếp 1 job gửi. Chưa đến giờ / đang chờ INT-04: không đụng tới.
    @IsTest
    static void claimsOnlyDueRequests() {
        Return_Request__c due = insertRequest(System.now().addMinutes(-1), null);
        Return_Request__c notYet = insertRequest(System.now().addMinutes(10), null);
        Return_Request__c pending = insertRequest(System.now().addMinutes(-1), 'PH-RF-PENDING');
        enablePayHub(true);
        SR_PayHubClient.useMockOverride = true;

        Test.startTest();
        Assert.areEqual(1, SR_RefundService.retryDue());
        Assert.areEqual(1, Limits.getQueueableJobs());
        Assert.isNull([SELECT Next_Retry_At__c FROM Return_Request__c WHERE Id = :due.Id].Next_Retry_At__c);
        Assert.isNotNull([SELECT Next_Retry_At__c FROM Return_Request__c WHERE Id = :notYet.Id].Next_Retry_At__c);
        Assert.isNotNull([SELECT Next_Retry_At__c FROM Return_Request__c WHERE Id = :pending.Id].Next_Retry_At__c);
        // Lần quét thứ 2 ngay sau đó không nhận trùng
        Assert.areEqual(0, SR_RefundService.retryDue());
        Test.stopTest();
    }
}
