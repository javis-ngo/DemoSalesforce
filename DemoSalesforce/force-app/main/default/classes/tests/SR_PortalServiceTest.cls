/**
 * Test cho SR_PortalService chạy bằng user Guest thật của site (không có quyền object nào).
 * Ở API 68, truy vấn/ghi không ghi mode sẽ chạy USER_MODE và Guest bị chặn; test này giữ cho
 * đường khách vãng lai luôn ở SYSTEM_MODE.
 * Chạy: sf apex run test --class-names SR_PortalServiceTest --result-format human
 * Owner: Dev C
 */
@IsTest
private class SR_PortalServiceTest {

    private static final String UNKNOWN_CODE = 'RR-0000-99999';

    // Mã không tồn tại: vẫn báo MSG-40 và đếm lần sai; sai đủ 5 lần trong 15 phút thì báo MSG-41
    @IsTest
    static void guestWrongCodeIsCountedThenLocked() {
        User guest = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
        List<SR_PortalService.LookupResult> results = new List<SR_PortalService.LookupResult>();
        System.runAs(guest) {
            for (Integer i = 0; i < SR_LookupAttemptDomain.DEFAULT_MAX_FAILED; i++) {
                results.add(SR_PortalService.lookup(UNKNOWN_CODE, '1234'));
            }
            // Mã nhập chữ thường, có khoảng trắng vẫn tính là cùng một mã
            results.add(SR_PortalService.lookup(' rr-0000-99999 ', '1234'));
        }

        for (Integer i = 0; i < SR_LookupAttemptDomain.DEFAULT_MAX_FAILED; i++) {
            Assert.isFalse(results[i].found, 'Mã không tồn tại thì không tìm thấy');
            Assert.areEqual(System.Label.SR_MSG_40, results[i].message, 'Mọi trường hợp sai đều báo MSG-40');
        }
        Assert.areEqual(System.Label.SR_MSG_41, results[results.size() - 1].message, 'Sai đủ 5 lần thì khóa');
        Assert.areEqual(SR_LookupAttemptDomain.DEFAULT_MAX_FAILED,
            [SELECT COUNT() FROM SR_Lookup_Attempt__c WHERE Key__c = :UNKNOWN_CODE WITH SYSTEM_MODE],
            'Mỗi lần sai ghi 1 bản ghi, lần bị khóa thì không ghi thêm');
    }
}
