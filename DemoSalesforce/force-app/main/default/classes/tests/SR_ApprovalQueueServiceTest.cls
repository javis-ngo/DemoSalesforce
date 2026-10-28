/**
 * Test cho SR_ApprovalQueueService: bộ lọc màn hình duyệt (D.2) thành điều kiện truy vấn, không cần tạo dữ liệu.
 * Phân trang bằng cursor được test ở SR_ReturnRequestSelectorTest; duyệt thật qua SR_UiControllerTest.
 * Chạy: sf apex run test --class-names SR_ApprovalQueueServiceTest --result-format human
 */
@IsTest
private class SR_ApprovalQueueServiceTest {

    // Không chọn gì: chờ duyệt, 30 ngày gần nhất, mọi cửa hàng, chờ lâu nhất lên đầu, trang 1
    @IsTest
    static void defaultsWhenNoFilter() {
        SR_ReturnRequestSelector.QueueCriteria c =
            SR_ApprovalQueueService.toCriteria(new SR_ApprovalQueueService.Filters());
        Assert.areEqual('PENDING_APPROVAL', c.status);
        Assert.areEqual(Date.today().addDays(-30), c.fromDate);
        Assert.areEqual(Date.today(), c.toDate);
        Assert.isNull(c.storeId);
        Assert.isNull(c.approverId);
        Assert.areEqual(Return_Request__c.Submitted_At__c, c.orderBy);
        Assert.isFalse(c.descending);
        Assert.areEqual(SR_ApprovalQueueService.PAGE_SIZE, c.pageSize);
        Assert.areEqual(0, c.position);
    }

    @IsTest
    static void appliesChosenFilters() {
        SR_ApprovalQueueService.Filters f = new SR_ApprovalQueueService.Filters();
        f.status = 'APPROVED';
        f.fromDate = Date.newInstance(2026, 10, 1);
        f.toDate = Date.newInstance(2026, 10, 19);
        f.onlyMine = true;
        f.sortBy = 'AMOUNT';
        f.sortDir = 'desc';
        f.pageNumber = 3;
        SR_ReturnRequestSelector.QueueCriteria c = SR_ApprovalQueueService.toCriteria(f);
        Assert.areEqual('APPROVED', c.status);
        Assert.areEqual(f.fromDate, c.fromDate);
        Assert.areEqual(f.toDate, c.toDate);
        Assert.areEqual(UserInfo.getUserId(), c.approverId);
        Assert.areEqual(Return_Request__c.Estimated_Refund__c, c.orderBy);
        Assert.isTrue(c.descending);
        Assert.areEqual(100, c.position);
    }

    // Cursor không bị chặn ở 2000 dòng như OFFSET: trang 1000 bắt đầu từ dòng 49.950
    @IsTest
    static void farPagesAreNotCapped() {
        SR_ApprovalQueueService.Filters f = new SR_ApprovalQueueService.Filters();
        f.pageNumber = 1000;
        Assert.areEqual(49950, SR_ApprovalQueueService.toCriteria(f).position);
    }
}
