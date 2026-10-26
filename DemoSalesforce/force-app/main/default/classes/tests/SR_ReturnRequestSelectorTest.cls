/**
 * Test cho SR_ReturnRequestSelector: phân trang bằng Database.PaginationCursor.
 * Chạy: sf apex run test --class-names SR_ReturnRequestSelectorTest --result-format human
 */
@IsTest
private class SR_ReturnRequestSelectorTest {

    @TestSetup
    static void setup() {
        List<Return_Request__c> requests = new List<Return_Request__c>();
        for (Integer i = 1; i <= 5; i++) {
            requests.add(new Return_Request__c(Name = 'RR-TEST-' + i, Channel__c = 'COUNTER', Status__c = 'NEW'));
        }
        insert requests;
    }

    // 5 yêu cầu, trang 2 dòng: trang đầu đủ 2 dòng, trang cuối còn 1 dòng, quá trang cuối thì rỗng
    @IsTest
    static void sharedWithMePagesThroughAllRows() {
        SR_ReturnRequestSelector.RecordPage first = SR_ReturnRequestSelector.selectSharedWithMe(2, 0);
        SR_ReturnRequestSelector.RecordPage last = SR_ReturnRequestSelector.selectSharedWithMe(2, 4);
        SR_ReturnRequestSelector.RecordPage beyond = SR_ReturnRequestSelector.selectSharedWithMe(2, 6);
        Assert.areEqual(5, first.total);
        Assert.areEqual(2, first.records.size());
        Assert.areEqual(1, last.records.size());
        Assert.areEqual(5, beyond.total);
        Assert.isTrue(beyond.records.isEmpty(), 'Quá trang cuối thì trả rỗng, không lỗi');
    }

    // D.3 + D.4: truy vấn chi tiết đọc được yêu cầu kèm danh sách dòng con (tên relationship đúng trên org)
    @IsTest
    static void detailQueriesIncludeChildLists() {
        Id requestId = [SELECT Id FROM Return_Request__c LIMIT 1].Id;
        Return_Request__c forInspection = SR_ReturnRequestSelector.selectForInspection(requestId);
        Return_Request__c forPortal = SR_ReturnRequestSelector.selectPortalDetail(requestId);
        Assert.areEqual('NEW', forInspection.Status__c);
        Assert.isTrue(forInspection.Return_Request_Lines__r.isEmpty(), 'Yêu cầu test không có dòng');
        Assert.areEqual(requestId, forPortal.Id);
        Assert.areEqual('NEW', SR_ReturnRequestSelector.selectById(requestId).Status__c);
    }

    // Hàng chờ duyệt: tổng số dòng lấy luôn từ cursor, không cần query COUNT riêng
    @IsTest
    static void approvalQueueReturnsTotalAndPage() {
        SR_ReturnRequestSelector.QueueCriteria c = new SR_ReturnRequestSelector.QueueCriteria();
        c.status = 'NEW';
        c.fromDate = Date.today();
        c.toDate = Date.today();
        c.orderBy = Return_Request__c.Submitted_At__c;
        c.pageSize = 2;
        c.position = 2;
        SR_ReturnRequestSelector.RecordPage page = SR_ReturnRequestSelector.selectApprovalQueue(c);
        Assert.areEqual(5, page.total);
        Assert.areEqual(2, page.records.size());
    }
}
