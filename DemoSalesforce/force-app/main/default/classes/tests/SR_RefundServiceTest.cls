/**
 * Test cho SR_RefundService: xếp job, công tắc B.4, chia lô 10 yêu cầu (NFR-04, BR-12, BR-13).
 * Bảng xử lý kết quả PayHub được test ở SR_RefundDomainTest.
 * [DEV A] TODO tích hợp: thêm test luồng đầy đủ (SUCCESS / ERROR x3 → REFUND_FAILED, UAT-06) khi Dev A merge
 *       SR_TestDataFactory, SR_StatusMachine và các giá trị Status__c.
 * Chạy: sf apex run test --class-names SR_RefundServiceTest --result-format human
 */
@IsTest
private class SR_RefundServiceTest {

    private static Id fakeId(Integer i) {
        return Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(i).leftPad(12, '0');
    }

    private static Set<Id> fakeIds(Integer count) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 1; i <= count; i++) {
            ids.add(fakeId(i));
        }
        return ids;
    }

    @IsTest
    static void enqueueSkipsEmptyInput() {
        Assert.isNull(SR_RefundService.enqueue(null));
        Assert.isNull(SR_RefundService.enqueue(new Set<Id>()));
    }

    // Công tắc B.4 "Gửi PayHub" tắt: không xếp job
    @IsTest
    static void enqueueSkipsWhenPayHubDisabled() {
        SR_RefundService.settingOverride = new SR_Setting__mdt(Enable_PayHub__c = false);
        Test.startTest();
        Assert.isNull(SR_RefundService.enqueue(fakeIds(1)));
        Assert.areEqual(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    // Yêu cầu không tồn tại / không ở REFUND_PROCESSING: không gọi PayHub, không lỗi
    @IsTest
    static void jobWithNothingSendableDoesNothing() {
        SR_RefundService.settingOverride = new SR_Setting__mdt(Enable_PayHub__c = true);
        SR_PayHubClient.useMockOverride = true;
        Test.startTest();
        Id jobId = SR_RefundService.enqueue(fakeIds(SR_RefundService.BATCH_SIZE + 5));
        Test.stopTest();
        Assert.isNotNull(jobId);
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status);
        Assert.areEqual(0, job.NumberOfErrors);
    }
}
