/**
 * Selector cho SR_Lookup_Attempt__c (các lần tra cứu sai trên Portal, D.4).
 * "inherited sharing": Portal gọi từ class without sharing vì Guest không có quyền trên object.
 * SYSTEM_MODE ghi rõ: API 68 không ghi mode thì chạy USER_MODE, Guest sẽ bị chặn.
 * Owner: Dev C
 */
public inherited sharing class SR_LookupAttemptSelector {

    public static Integer countByKeySince(String key, Datetime since) {
        return [
            SELECT COUNT() FROM SR_Lookup_Attempt__c WHERE Key__c = :key AND CreatedDate >= :since
            WITH SYSTEM_MODE
        ];
    }
}
