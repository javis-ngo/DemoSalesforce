/**
 * Test cho SR_ReturnRequestDomain: chạy trên bản ghi trong bộ nhớ, không cần tạo dữ liệu.
 * Chạy: sf apex run test --class-names SR_ReturnRequestDomainTest --result-format human
 */
@IsTest
private class SR_ReturnRequestDomainTest {

    // Estimated_Refund__c / Actual_Refund__c là roll-up (chỉ đọc) nên phải dựng bản ghi qua JSON
    private static Return_Request__c withRefund(Decimal estimated, Decimal actual) {
        return (Return_Request__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Return_Request__c' },
            'Estimated_Refund__c' => estimated,
            'Actual_Refund__c' => actual
        }), Return_Request__c.class);
    }

    // D.4: chỉ so 4 số cuối, bỏ qua mã vùng, dấu cách, dấu gạch
    @IsTest
    static void phoneLast4IgnoresFormatting() {
        Return_Request__c r = new Return_Request__c(Account__r = new Account(Phone = '+84 (90) 123-4567'));
        Assert.isTrue(SR_ReturnRequestDomain.matchesPhoneLast4(r, '4567'));
        Assert.isFalse(SR_ReturnRequestDomain.matchesPhoneLast4(r, '0000'), 'Sai 4 số cuối');
        Assert.isFalse(SR_ReturnRequestDomain.matchesPhoneLast4(r, '567'), 'Phải nhập đủ 4 số');
        Assert.isFalse(SR_ReturnRequestDomain.matchesPhoneLast4(r, null), 'Không nhập');
        Assert.isFalse(SR_ReturnRequestDomain.matchesPhoneLast4(new Return_Request__c(), '4567'), 'Yêu cầu không có khách');
    }

    // Portal: đã hoàn thì hiện tiền thực hoàn, chưa hoàn thì hiện tiền dự kiến
    @IsTest
    static void refundAmountPrefersActual() {
        Assert.areEqual(900000, SR_ReturnRequestDomain.refundAmount(withRefund(1000000, 900000)));
        Assert.areEqual(1000000, SR_ReturnRequestDomain.refundAmount(withRefund(1000000, 0)));
        Assert.areEqual(1000000, SR_ReturnRequestDomain.refundAmount(withRefund(1000000, null)));
    }

    @IsTest
    static void waitingHoursCountFromSubmit() {
        Datetime now = Datetime.newInstanceGmt(2026, 10, 20, 10, 0, 0);
        Return_Request__c submitted = new Return_Request__c(Submitted_At__c = now.addMinutes(-90));
        Assert.areEqual(1.5, SR_ReturnRequestDomain.waitingHours(submitted, now));
        Assert.areEqual(0, SR_ReturnRequestDomain.waitingHours(new Return_Request__c(), now), 'Chưa gửi duyệt');
    }

    // D.2: chỉ tô đỏ yêu cầu đang chờ duyệt mà đã quá hạn
    @IsTest
    static void overdueOnlyWhenPendingAndPastDue() {
        Datetime now = System.now();
        Assert.isTrue(SR_ReturnRequestDomain.isApprovalOverdue(
            new Return_Request__c(Status__c = 'PENDING_APPROVAL', Approval_Due_At__c = now.addHours(-1)), now));
        Assert.isFalse(SR_ReturnRequestDomain.isApprovalOverdue(
            new Return_Request__c(Status__c = 'PENDING_APPROVAL', Approval_Due_At__c = now.addHours(1)), now), 'Chưa tới hạn');
        Assert.isFalse(SR_ReturnRequestDomain.isApprovalOverdue(
            new Return_Request__c(Status__c = 'PENDING_APPROVAL'), now), 'Không có hạn duyệt');
        Assert.isFalse(SR_ReturnRequestDomain.isApprovalOverdue(
            new Return_Request__c(Status__c = 'AWAITING_GOODS', Approval_Due_At__c = now.addHours(-1)), now), 'Đã duyệt xong');
    }

    // D.3: Nhận hàng chỉ khi chờ mang hàng; Hủy chỉ từ New / Pending Approval / Awaiting Goods (OI-07)
    @IsTest
    static void requestPageButtonsFollowStatus() {
        Assert.isTrue(SR_ReturnRequestDomain.canReceiveGoods(new Return_Request__c(Status__c = 'AWAITING_GOODS')));
        Assert.isFalse(SR_ReturnRequestDomain.canReceiveGoods(new Return_Request__c(Status__c = 'INSPECTING')));
        for (String status : new List<String>{ 'NEW', 'PENDING_APPROVAL', 'AWAITING_GOODS' }) {
            Assert.isTrue(SR_ReturnRequestDomain.canCancel(new Return_Request__c(Status__c = status)), status);
        }
        for (String status : new List<String>{ 'INSPECTING', 'REFUND_PROCESSING', 'COMPLETED', 'CANCELLED' }) {
            Assert.isFalse(SR_ReturnRequestDomain.canCancel(new Return_Request__c(Status__c = status)), status);
        }
    }

    // D.3: chỉ kiểm định khi đang Inspecting và còn dòng chưa có kết quả
    @IsTest
    static void inspectOnlyWhileLinesPending() {
        Return_Request__c inspecting = new Return_Request__c(Status__c = 'INSPECTING');
        Return_Request_Line__c pending = new Return_Request_Line__c(Inspection_Result__c = 'NOT_INSPECTED');
        Return_Request_Line__c passed = new Return_Request_Line__c(Inspection_Result__c = 'PASSED');
        Assert.isTrue(SR_ReturnRequestDomain.canInspect(inspecting, new List<Return_Request_Line__c>{ passed, pending }));
        Assert.isFalse(SR_ReturnRequestDomain.canInspect(inspecting, new List<Return_Request_Line__c>{ passed }),
            'Đã hoàn tất kiểm định');
        Assert.isFalse(SR_ReturnRequestDomain.canInspect(
            new Return_Request__c(Status__c = 'AWAITING_GOODS'), new List<Return_Request_Line__c>{ pending }), 'Chưa nhận hàng');
        Assert.isFalse(SR_ReturnRequestDomain.isInspected(new Return_Request_Line__c()), 'Chưa có kết quả');
    }

    @IsTest
    static void riskyFollowsAccountFlag() {
        Assert.isTrue(SR_ReturnRequestDomain.isRiskyCustomer(
            new Return_Request__c(Account__r = new Account(Risk_Flag__c = true))));
        Assert.isFalse(SR_ReturnRequestDomain.isRiskyCustomer(
            new Return_Request__c(Account__r = new Account(Risk_Flag__c = false))));
        Assert.isFalse(SR_ReturnRequestDomain.isRiskyCustomer(new Return_Request__c()), 'Yêu cầu không có khách');
    }
}
