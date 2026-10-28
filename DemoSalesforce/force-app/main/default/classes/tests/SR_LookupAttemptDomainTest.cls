/**
 * Test cho SR_LookupAttemptDomain: quy tắc khóa tra cứu trên Portal, không cần tạo dữ liệu.
 * Chạy: sf apex run test --class-names SR_LookupAttemptDomainTest --result-format human
 */
@IsTest
private class SR_LookupAttemptDomainTest {

    @IsTest
    static void locksAfterMaxFailuresInWindow() {
        SR_Setting__mdt s = new SR_Setting__mdt(Portal_Max_Failed__c = 5, Portal_Lock_Minutes__c = 15);
        Datetime now = Datetime.newInstanceGmt(2026, 10, 20, 10, 0, 0);
        Assert.areEqual(now.addMinutes(-15), SR_LookupAttemptDomain.lockWindowStart(s, now));
        Assert.isFalse(SR_LookupAttemptDomain.isLocked(4, s), 'Sai 4 lần chưa khóa');
        Assert.isTrue(SR_LookupAttemptDomain.isLocked(5, s), 'Sai 5 lần thì khóa');
    }

    // Bản ghi Default chưa điền 2 field Portal thì vẫn khóa sau 5 lần sai trong 15 phút
    @IsTest
    static void usesDefaultsWhenSettingIsBlank() {
        SR_Setting__mdt s = new SR_Setting__mdt();
        Datetime now = Datetime.newInstanceGmt(2026, 10, 20, 10, 0, 0);
        Assert.areEqual(now.addMinutes(-15), SR_LookupAttemptDomain.lockWindowStart(s, now));
        Assert.isFalse(SR_LookupAttemptDomain.isLocked(4, s), 'Sai 4 lần chưa khóa');
        Assert.isTrue(SR_LookupAttemptDomain.isLocked(5, s), 'Sai 5 lần thì khóa');
    }

    // Key__c chỉ chứa được 80 ký tự
    @IsTest
    static void failedAttemptKeyFitsField() {
        Assert.areEqual('RR-2610-00001', SR_LookupAttemptDomain.newFailedAttempt('RR-2610-00001').Key__c);
        Assert.areEqual(80, SR_LookupAttemptDomain.newFailedAttempt('X'.repeat(200)).Key__c.length());
    }
}
