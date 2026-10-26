/**
 * Test cho các controller màn hình của Dev C (D.1, D.2, D.3, D.4).
 * Chạy: sf apex run test --class-names SR_UiControllerTest --result-format human
 */
@IsTest
private class SR_UiControllerTest {

    @TestSetup
    static void setup() {
        SR_TestDataFactory.createStandardData();
    }

    // Giả lập PayHub trả SUCCESS nếu cấu hình đang dùng PayHub thật
    private class PayHubOk implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"refundId":"PH-RF-TEST","status":"SUCCESS"}');
            return res;
        }
    }

    private static Id createSmallCounterRequest() {
        Order o = SR_TestDataFactory.orderWithSku('AF-PH-5L');
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :o.Id LIMIT 1];
        String body = JSON.serialize(new Map<String, Object>{
            'orderId' => o.Id,
            'lines' => new List<Object>{ new Map<String, Object>{
                'orderItemId' => oi.Id, 'quantity' => 1, 'reason' => 'NOT_SATISFIED', 'condition' => 'OPENED'
            } }
        });
        SR_DTO.CreateResult res;
        System.runAs(SR_TestDataFactory.userByAlias('srstaff')) {
            res = SR_ReturnUiController.createFromCounter(body);
        }
        Assert.isTrue(res.success, res.message);
        return res.requestId;
    }

    // D.1: điện thoại quá hạn bị khóa, nồi chiên trả được
    @IsTest
    static void returnableLinesShowBlockedProducts() {
        Order phoneOrder = SR_TestDataFactory.orderWithSku('PH-X');
        Order fryerOrder = SR_TestDataFactory.orderWithSku('AF-PH-5L');
        System.runAs(SR_TestDataFactory.userByAlias('srstaff')) {
            SR_DTO.ReturnableInfo phone = SR_ReturnUiController.getReturnableLines(phoneOrder.Id);
            SR_DTO.ReturnableInfo fryer = SR_ReturnUiController.getReturnableLines(fryerOrder.Id);
            Assert.isFalse(phone.lines[0].returnable);
            Assert.isNotNull(phone.lines[0].blockReason);
            Assert.isTrue(fryer.lines[0].returnable);
            Assert.areEqual(80, fryer.rates.get('NOT_SATISFIED|OPENED').intValue());
        }
    }

    // D.3: kiểm định Đạt → chuyển sang hoàn tiền (hoặc đã hoàn tất nếu PayHub giả lập trả SUCCESS)
    @IsTest
    static void inspectionMovesRequestToRefund() {
        Id requestId = createSmallCounterRequest();
        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        Assert.isTrue(data.canInspect);

        String results = JSON.serialize(new List<Object>{ new Map<String, Object>{
            'lineId' => data.lines[0].lineId, 'result' => 'PASSED', 'actualCondition' => 'OPENED', 'note' => ''
        } });
        Test.setMock(HttpCalloutMock.class, new PayHubOk());
        Test.startTest();
        SR_ReturnUiController.completeInspection(requestId, results);
        Test.stopTest();

        String status = [SELECT Status__c FROM Return_Request__c WHERE Id = :requestId].Status__c;
        Assert.isTrue(status == 'REFUND_PROCESSING' || status == 'COMPLETED', status);
    }

    // D.3: giữ nguyên tình trạng thì tiền dòng bằng tiền dự kiến; tiền do Apex tính, không tính trong JS
    @IsTest
    static void lineRefundComesFromService() {
        Id requestId = createSmallCounterRequest();
        SR_RequestPageService.InspectionLine line = SR_ReturnUiController.getInspectionData(requestId).lines[0];
        Assert.areEqual(line.estimatedRefund, SR_ReturnUiController.calcLineRefund(line.lineId, line.declaredCondition));
    }

    // Yêu cầu tại quầy tự duyệt đã ở Inspecting: không còn nút Nhận hàng / Hủy, gọi thẳng thì báo MSG-20
    @IsTest
    static void receiveAndCancelBlockedWhenInspecting() {
        Id requestId = createSmallCounterRequest();
        SR_RequestPageService.ActionState state = SR_ReturnUiController.getActionState(requestId);
        Assert.isFalse(state.canReceiveGoods);
        Assert.isFalse(state.canCancel);
        String msg20Start = System.Label.SR_MSG_20.substringBefore('{0}');
        try {
            SR_ReturnUiController.receiveGoods(requestId);
            Assert.fail('Phải báo MSG-20 khi nhận hàng');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg20Start), e.getMessage());
        }
        try {
            SR_ReturnUiController.cancelRequest(requestId, 'Khách đổi ý');
            Assert.fail('Phải báo MSG-20 khi hủy');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg20Start), e.getMessage());
        }
    }

    // D.3: Không đạt mà thiếu ghi chú → MSG-21
    @IsTest
    static void failedLineNeedsNote() {
        Id requestId = createSmallCounterRequest();
        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        String results = JSON.serialize(new List<Object>{ new Map<String, Object>{
            'lineId' => data.lines[0].lineId, 'result' => 'FAILED', 'actualCondition' => 'USED', 'note' => ''
        } });
        try {
            SR_ReturnUiController.completeInspection(requestId, results);
            Assert.fail('Phải báo MSG-21');
        } catch (AuraHandledException e) {
            Assert.areEqual(System.Label.SR_MSG_21, e.getMessage());
        }
    }

    // Khách portal lỡ vào trang yêu cầu: không trả dữ liệu, báo Unauthorized kèm link Portal; gọi thẳng Apex cũng bị chặn
    @IsTest
    static void portalUserIsUnauthorized() {
        Id requestId = createSmallCounterRequest();
        SR_RequestPageService.userType = 'PowerCustomerSuccess';

        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        Assert.isTrue(data.unauthorized);
        Assert.isFalse(data.canInspect);
        Assert.isTrue(data.lines.isEmpty());
        Assert.areEqual(System.Label.SR_Portal_Url, data.portalUrl);

        SR_RequestPageService.ActionState state = SR_ReturnUiController.getActionState(requestId);
        Assert.isFalse(state.canReceiveGoods || state.canCancel);

        try {
            SR_ReturnUiController.completeInspection(requestId, '[]');
            Assert.fail('Khách portal không được hoàn tất kiểm định');
        } catch (AuraHandledException e) {
            Assert.areEqual(System.Label.SR_ERR_UNAUTHORIZED, e.getMessage());
        }
        try {
            SR_ReturnUiController.receiveGoods(requestId);
            Assert.fail('Khách portal không được nhận hàng');
        } catch (AuraHandledException e) {
            Assert.areEqual(System.Label.SR_ERR_UNAUTHORIZED, e.getMessage());
        }
    }

    // D.2: QLV (user chạy test) thấy yêu cầu 25tr trong hàng chờ và duyệt được
    @IsTest
    static void approvalQueueListsAndApproves() {
        Order o = SR_TestDataFactory.orderWithSku('LT-Y');
        System.runAs(SR_TestDataFactory.userByAlias('srstaff')) {
            SR_ReturnRequestService.createRequests(new List<SR_DTO.CreateRequest>{
                SR_TestDataFactory.counterRequest(o, 'DEFECT', 'SEALED', 1) });
        }
        SR_ApprovalQueueService.PageResult page = SR_ApprovalUiController.getQueue(
            JSON.serialize(new Map<String, Object>{ 'onlyMine' => true }));
        Assert.areEqual(1, page.total);

        String items = JSON.serialize(new List<Object>{ new Map<String, Object>{
            'requestId' => page.rows[0].id, 'lastModified' => page.rows[0].lastModified
        } });
        SR_DTO.DecisionResult d = SR_ApprovalUiController.decide(items, true, null);
        Assert.areEqual(1, d.succeeded, d.summary);
    }

    // D.4: sai 4 số cuối → MSG-40; đúng → thấy trạng thái + lịch sử, không có số tiền
    @IsTest
    static void portalLookupChecksPhone() {
        Id requestId = createSmallCounterRequest();
        String code = [SELECT Name FROM Return_Request__c WHERE Id = :requestId].Name;

        SR_PortalService.LookupResult wrong = SR_PortalController.lookup(code, '0000');
        Assert.isFalse(wrong.found);
        Assert.areEqual(System.Label.SR_MSG_40, wrong.message);

        SR_PortalService.LookupResult ok = SR_PortalController.lookup(code, '4567');
        Assert.isTrue(ok.found);
        Assert.isFalse(ok.history.isEmpty());
    }
}
