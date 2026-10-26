/**
 * Selector cho luồng hoàn tiền PayHub (FR-11, FR-12, FR-14; BR-12, BR-13): gửi (B5), thử lại (B6),
 * Kế toán hoàn tay (B7), PayHub callback (B9).
 *  - "inherited sharing": SR_RefundService chạy without sharing vì Queueable chạy dưới quyền người bấm
 *    "Hoàn tất kiểm định" (nhân viên cửa hàng), người này không chắc xem được các field hoàn tiền.
 * Owner: Dev B
 */
public inherited sharing class SR_RefundSelector {

    // Yêu cầu được phép gửi PayHub:
    //  - BR-13: chỉ yêu cầu đang REFUND_PROCESSING và chưa có refundId (PENDING thì chờ INT-04, không gửi lại)
    //  - BR-12: lần thử lại phải đã đến giờ hẹn Next_Retry_At__c (cách lần trước ≥ 15 phút)
    // [DEV A] Field Return_Request__c (Status__c, Actual_Refund__c, Refund_Attempts__c, Next_Retry_At__c,
    // PayHub_Refund_Id__c, Order__c, Store__c) và giá trị REFUND_PROCESSING do Dev A sở hữu.
    public static List<Return_Request__c> selectSendable(Set<Id> requestIds, Datetime now) {
        return [
            SELECT Id, Name, Status__c, Actual_Refund__c, Refund_Attempts__c,
                   Order__r.OrderNumber, Store__r.Store_Code__c
            FROM Return_Request__c
            WHERE Id IN :requestIds
              AND Status__c = :SR_RefundDomain.STATUS_REFUND_PROCESSING
              AND PayHub_Refund_Id__c = null
              AND (Next_Retry_At__c = null OR Next_Retry_At__c <= :now)
        ];
    }

    // B6 – BR-12: yêu cầu đã đến giờ gửi lại; quá maxRows thì lần quét sau lấy tiếp.
    // FOR UPDATE: hai lần quét chồng nhau (job chạy chậm) không cùng nhận một yêu cầu
    // (SOQL có FOR UPDATE không được dùng ORDER BY).
    public static List<Return_Request__c> selectDueForRetry(Datetime now, Integer maxRows) {
        return [
            SELECT Id, Next_Retry_At__c
            FROM Return_Request__c
            WHERE Status__c = :SR_RefundDomain.STATUS_REFUND_PROCESSING
              AND PayHub_Refund_Id__c = null
              AND Next_Retry_At__c != null
              AND Next_Retry_At__c <= :now
            LIMIT :maxRows
            FOR UPDATE
        ];
    }

    // B7, B9: khóa yêu cầu trước khi đổi kết quả hoàn tiền, kèm field SR_EventPublisher cần
    public static List<Return_Request__c> selectForResultById(Id requestId) {
        return [
            SELECT Id, Name, Status__c, Actual_Refund__c, PayHub_Refund_Id__c, Store__r.Store_Code__c
            FROM Return_Request__c
            WHERE Id = :requestId
            LIMIT 1
            FOR UPDATE
        ];
    }

    // B9 – INT-04: merchantRef = mã yêu cầu (Name)
    public static List<Return_Request__c> selectForResultByNumber(String requestNumber) {
        return [
            SELECT Id, Name, Status__c, Actual_Refund__c, PayHub_Refund_Id__c, Store__r.Store_Code__c
            FROM Return_Request__c
            WHERE Name = :requestNumber
            LIMIT 1
            FOR UPDATE
        ];
    }

    // B6: job lịch thử lại đang có (để hủy trước khi lên lịch lại)
    public static List<Id> selectScheduledJobIds(List<String> jobNames) {
        List<Id> ids = new List<Id>();
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN :jobNames]) {
            ids.add(ct.Id);
        }
        return ids;
    }

    // FR-14: Public Group của Kế toán; null nếu chưa tạo (scripts/apex/seed-3-groups.apex)
    public static Id selectGroupId(String developerName) {
        List<Group> groups = [
            SELECT Id FROM Group WHERE DeveloperName = :developerName AND Type = 'Regular' LIMIT 1
        ];
        return groups.isEmpty() ? null : groups[0].Id;
    }

    // Custom Notification Type; null nếu chưa deploy
    public static Id selectNotificationTypeId(String developerName) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :developerName LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
}
