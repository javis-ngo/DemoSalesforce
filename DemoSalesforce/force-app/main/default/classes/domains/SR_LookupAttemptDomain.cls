/**
 * Quy tắc khóa tra cứu trên Portal (D.4): sai Portal_Max_Failed__c lần trong
 * Portal_Lock_Minutes__c phút gần nhất thì khóa mã yêu cầu đó.
 * Setting để trống thì dùng mặc định của đề bài: sai 5 lần trong 15 phút.
 * Không truy vấn, không ghi dữ liệu.
 */
public inherited sharing class SR_LookupAttemptDomain {

    public static final Integer DEFAULT_MAX_FAILED = 5;
    public static final Integer DEFAULT_LOCK_MINUTES = 15;

    // Mốc bắt đầu đếm số lần sai
    public static Datetime lockWindowStart(SR_Setting__mdt s, Datetime now) {
        return now.addMinutes(-lockMinutes(s));
    }

    public static Boolean isLocked(Integer failedInWindow, SR_Setting__mdt s) {
        return failedInWindow >= maxFailed(s);
    }

    private static Integer lockMinutes(SR_Setting__mdt s) {
        return (s == null || s.Portal_Lock_Minutes__c == null) ? DEFAULT_LOCK_MINUTES : s.Portal_Lock_Minutes__c.intValue();
    }

    private static Integer maxFailed(SR_Setting__mdt s) {
        return (s == null || s.Portal_Max_Failed__c == null) ? DEFAULT_MAX_FAILED : s.Portal_Max_Failed__c.intValue();
    }

    // Key__c dài tối đa 80 ký tự
    public static SR_Lookup_Attempt__c newFailedAttempt(String key) {
        return new SR_Lookup_Attempt__c(Key__c = key.abbreviate(80));
    }
}
