/**
 * Test cho các controller màn hình của Dev C (D.1, D.2, D.3, D.4), dữ liệu dựng bằng SR_TestDataFactory của Dev A.
 * Chạy bằng user Admin của test: permission set theo vai trò (SR_Store_Staff…) chưa có trên org nên user
 * Standard User do factory tạo chưa có quyền object SmartReturn.
 * Cấu hình (ngành hàng, tỷ lệ hoàn, ngưỡng duyệt) ghi đè bằng SR_TestDataFactory.seedSmartReturnTestConfig,
 * không phụ thuộc bản ghi Custom Metadata trên org.
 * Chạy: sf apex run test --class-names SR_UiControllerTest --result-format human
 * Owner: Dev C
 */
@IsTest
private class SR_UiControllerTest {

    private static final String CUSTOMER_PHONE = '0901234567';

    @TestSetup
    static void setup() {
        Store__c store = SR_TestDataFactory.createStore(
            'HCM-012', SR_TestDataFactory.REGION_SOUTH, UserInfo.getUserId(), UserInfo.getUserId());
        Account lan = SR_TestDataFactory.createAccount('Chị Lan', CUSTOMER_PHONE, false);
        Map<String, Product2> products = SR_TestDataFactory.createProductCatalog();

        // Nồi chiên giao 2 ngày trước: còn hạn. Điện thoại giao 40 ngày trước: quá hạn.
        SR_TestDataFactory.OrderSpec fryer = new SR_TestDataFactory.OrderSpec(lan.Id, store.Id);
        fryer.effectiveDate = Date.today().addDays(-3);
        fryer.deliveryDate = Date.today().addDays(-2);
        fryer.items.add(new SR_TestDataFactory.ItemSpec(products.get(SR_TestDataFactory.FAMILY_APPLIANCE).Id, 1));
        SR_TestDataFactory.OrderSpec phone = new SR_TestDataFactory.OrderSpec(lan.Id, store.Id);
        phone.effectiveDate = Date.today().addDays(-41);
        phone.deliveryDate = Date.today().addDays(-40);
        phone.items.add(new SR_TestDataFactory.ItemSpec(products.get(SR_TestDataFactory.FAMILY_PHONE).Id, 1));
        SR_TestDataFactory.createOrders(new List<SR_TestDataFactory.OrderSpec>{ fryer, phone });
    }

    // Static bị xóa giữa các test method nên mỗi test gọi lại
    private static void useTestConfig() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    private static OrderItem itemOf(String family) {
        return [SELECT Id, OrderId FROM OrderItem WHERE Product2.Family = :family LIMIT 1];
    }

    // Nồi chiên 2.490.000đ, Không vừa ý + Đã mở hộp: dưới ngưỡng tự duyệt nên tại quầy vào thẳng Inspecting
    private static String fryerDraft() {
        OrderItem oi = itemOf(SR_TestDataFactory.FAMILY_APPLIANCE);
        return JSON.serialize(new Map<String, Object>{
            'orderId' => oi.OrderId,
            'lines' => new List<Object>{ new Map<String, Object>{
                'orderItemId' => oi.Id, 'quantity' => 1, 'reason' => 'NOT_SATISFIED', 'condition' => 'OPENED'
            } }
        });
    }

    private static Id createFryerRequest() {
        SR_CreateResultDTO res = SR_ReturnUiController.createFromCounter(fryerDraft());
        Assert.isTrue(res.success, JSON.serialize(res.errors));
        return res.requestId;
    }

    private static String passedLines(SR_RequestPageService.InspectionData data, String result, String note) {
        List<SR_InspectionLineDTO> lines = new List<SR_InspectionLineDTO>();
        for (SR_RequestPageService.InspectionLine l : data.lines) {
            SR_InspectionLineDTO dto = new SR_InspectionLineDTO();
            dto.lineId = l.lineId;
            dto.inspectionResult = result;
            dto.actualCondition = l.actualCondition;
            dto.inspectionNote = note;
            lines.add(dto);
        }
        return JSON.serialize(lines);
    }

    // D.1: điện thoại quá hạn bị khóa kèm mã khóa, nồi chiên trả được
    @IsTest
    static void returnableOrderLocksExpiredProduct() {
        useTestConfig();
        SR_ReturnableOrderDTO phone = SR_ReturnUiController.getReturnableOrder(itemOf(SR_TestDataFactory.FAMILY_PHONE).OrderId);
        SR_ReturnableOrderDTO fryer = SR_ReturnUiController.getReturnableOrder(itemOf(SR_TestDataFactory.FAMILY_APPLIANCE).OrderId);
        Assert.areEqual(CUSTOMER_PHONE, fryer.customerPhone);
        Assert.isFalse(phone.lines[0].eligible, 'Điện thoại giao 30 ngày trước phải bị khóa');
        Assert.areEqual(SR_ErrorCode.RETURN_WINDOW_EXPIRED, phone.lines[0].lockCode);
        Assert.isTrue(fryer.lines[0].eligible, 'Nồi chiên giao 2 ngày trước phải trả được');
    }

    // D.1: tính trước rồi tạo, cùng một JSON; tiền và cấp duyệt do service của Dev A tính
    @IsTest
    static void previewThenCreateFromCounter() {
        useTestConfig();
        SR_ApprovalPreviewResultDTO preview = SR_ReturnUiController.previewCreate(fryerDraft());
        Assert.isTrue(preview.success, JSON.serialize(preview.errors));
        Assert.isTrue(preview.estimatedRefund > 0);
        Assert.isNotNull(preview.approvalLevel);
        Assert.areEqual(preview.estimatedRefund, preview.lines[0].refundAmount);

        SR_CreateResultDTO created = SR_ReturnUiController.createFromCounter(fryerDraft());
        Assert.isTrue(created.success, JSON.serialize(created.errors));
        Assert.isNotNull(created.requestId);
        Assert.areEqual(preview.estimatedRefund, created.estimatedRefund);
        Assert.areEqual(SR_ReturnRequestService.CHANNEL_COUNTER,
            [SELECT Channel__c FROM Return_Request__c WHERE Id = :created.requestId].Channel__c);
    }

    // D.3: kiểm định Đạt → chuyển sang hoàn tiền (hoặc đã hoàn tất nếu PayHub giả lập trả SUCCESS)
    @IsTest
    static void inspectionMovesRequestToRefund() {
        useTestConfig();
        Id requestId = createFryerRequest();
        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        Assert.isTrue(data.canInspect, data.status);
        Assert.isNotNull(data.versionToken);

        SR_ReturnUiController.completeInspection(requestId, data.versionToken, passedLines(data, 'PASSED', null));

        Assert.areEqual(SR_StatusMachine.REFUND_PROCESSING,
            [SELECT Status__c FROM Return_Request__c WHERE Id = :requestId].Status__c);
        // SR_RefundService xếp job gửi PayHub; không gọi Test.stopTest nên job không chạy, không cần mock callout
        Assert.areEqual(1, Limits.getQueueableJobs(), 'Phải đưa yêu cầu vào hàng đợi hoàn tiền');
    }

    // D.3: giữ nguyên tình trạng thì tiền dòng bằng tiền dự kiến; tiền do Apex tính, không tính trong JS
    @IsTest
    static void lineRefundComesFromService() {
        useTestConfig();
        Id requestId = createFryerRequest();
        SR_RequestPageService.InspectionLine line = SR_ReturnUiController.getInspectionData(requestId).lines[0];
        Assert.areEqual(line.estimatedRefund, SR_ReturnUiController.calcLineRefund(line.lineId, line.declaredCondition));
    }

    // Yêu cầu tại quầy tự duyệt đã ở Inspecting: không còn nút Nhận hàng / Hủy, gọi thẳng thì báo MSG-20
    @IsTest
    static void receiveAndCancelBlockedWhenInspecting() {
        useTestConfig();
        Id requestId = createFryerRequest();
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

    // D.3: Không đạt mà thiếu ghi chú → SR_InspectionService từ chối (MSG-21), yêu cầu vẫn ở Inspecting
    @IsTest
    static void failedLineNeedsNote() {
        useTestConfig();
        Id requestId = createFryerRequest();
        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        try {
            SR_ReturnUiController.completeInspection(requestId, data.versionToken, passedLines(data, 'FAILED', null));
            Assert.fail('Phải báo thiếu ghi chú');
        } catch (AuraHandledException e) {
            Assert.isTrue(String.isNotBlank(e.getMessage()));
        }
        Assert.areEqual(SR_StatusMachine.INSPECTING, [SELECT Status__c FROM Return_Request__c WHERE Id = :requestId].Status__c);
    }

    // Khách portal lỡ vào trang yêu cầu: không trả dữ liệu, báo Unauthorized kèm link Portal; gọi thẳng Apex cũng bị chặn
    @IsTest
    static void portalUserIsUnauthorized() {
        useTestConfig();
        Id requestId = createFryerRequest();
        SR_RequestPageService.userType = 'PowerCustomerSuccess';

        SR_RequestPageService.InspectionData data = SR_ReturnUiController.getInspectionData(requestId);
        Assert.isTrue(data.unauthorized);
        Assert.isFalse(data.canInspect);
        Assert.isTrue(data.lines.isEmpty());
        Assert.areEqual(System.Label.SR_Portal_Url, data.portalUrl);

        SR_RequestPageService.ActionState state = SR_ReturnUiController.getActionState(requestId);
        Assert.isFalse(state.canReceiveGoods || state.canCancel);

        try {
            SR_ReturnUiController.completeInspection(requestId, null, '[]');
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

    // D.2: yêu cầu chờ duyệt giao cho user chạy test (do nhân viên khác tạo) → thấy trong hàng chờ và duyệt được
    @IsTest
    static void approvalQueueListsAndApproves() {
        useTestConfig();
        OrderItem oi = itemOf(SR_TestDataFactory.FAMILY_APPLIANCE);
        Order o = [SELECT AccountId, Store__c FROM Order WHERE Id = :oi.OrderId];
        SR_TestDataFactory.RequestSpec spec = new SR_TestDataFactory.RequestSpec();
        spec.accountId = o.AccountId;
        spec.orderId = oi.OrderId;
        spec.storeId = o.Store__c;
        spec.status = SR_StatusMachine.PENDING_APPROVAL;
        spec.assignedApproverId = UserInfo.getUserId();
        spec.submittedAt = System.now().addHours(-30);
        spec.approvalDueAt = System.now().addHours(-6);
        SR_TestDataFactory.LineSpec line = new SR_TestDataFactory.LineSpec();
        line.orderItemId = oi.Id;
        spec.lines.add(line);
        User staff = SR_TestDataFactory.createUser(SR_TestDataFactory.ROLE_STORE_STAFF, 'HCM-012');
        System.runAs(staff) {
            SR_TestDataFactory.createReturnRequest(spec); // người tạo khác người duyệt (MSG-10)
        }

        // User chạy test là CHT + QLV của HCM-012 trong setup
        Assert.areEqual('HCM-012', SR_ApprovalUiController.getMyStores()[0].storeCode);
        Assert.areEqual(1, SR_ApprovalUiController.getQueue(null).total, 'Bộ lọc mặc định: chờ duyệt, 30 ngày');

        SR_ApprovalQueueService.PageResult page = SR_ApprovalUiController.getQueue(
            JSON.serialize(new Map<String, Object>{ 'onlyMine' => true }));
        Assert.areEqual(1, page.total);
        Assert.isTrue(page.rows[0].overdue, 'Chờ quá 24 giờ phải tô đỏ');
        Assert.isNotNull(page.rows[0].versionToken);

        String items = JSON.serialize(new List<Object>{ new Map<String, Object>{
            'requestId' => page.rows[0].id, 'versionToken' => page.rows[0].versionToken
        } });
        SR_ApprovalQueueService.DecisionSummary d = SR_ApprovalUiController.decide(items, true, null);
        Assert.areEqual(1, d.total);
        Assert.areEqual(1, d.succeeded, JSON.serialize(d.errors));

        // Duyệt lại bằng token cũ: dòng báo lỗi, không throw
        SR_ApprovalQueueService.DecisionSummary again = SR_ApprovalUiController.decide(items, true, null);
        Assert.areEqual(0, again.succeeded);
        Assert.areEqual(1, again.errors.size());
        Assert.isNotNull(again.errors[0].code);
    }

    // D.4: sai 4 số cuối → MSG-40; đúng → thấy trạng thái + lịch sử, không có số tiền
    @IsTest
    static void portalLookupChecksPhone() {
        useTestConfig();
        Id requestId = createFryerRequest();
        String code = [SELECT Name FROM Return_Request__c WHERE Id = :requestId].Name;

        SR_PortalService.LookupResult wrong = SR_PortalController.lookup(code, '0000');
        Assert.isFalse(wrong.found);
        Assert.areEqual(System.Label.SR_MSG_40, wrong.message);

        SR_PortalService.LookupResult ok = SR_PortalController.lookup(code, CUSTOMER_PHONE.right(4));
        Assert.isTrue(ok.found);
        Assert.isNotNull(ok.statusLabel);
        Assert.isFalse(ok.products.isEmpty());

        // Khách đăng nhập: danh sách + chi tiết đi qua sharing (user test thấy được yêu cầu vừa tạo)
        List<SR_PortalService.MyRequest> mine = SR_PortalController.getMyRequests(10, 1);
        Assert.areEqual(code, mine[0].requestNumber);
        Assert.isTrue(SR_PortalController.getMyRequestDetail(requestId).found);
    }

    // Lỗi không lường trước: không lộ lỗi hệ thống, báo MSG-90 kèm mã lỗi
    @IsTest
    static void controllersHideUnexpectedErrors() {
        String msg90Start = System.Label.SR_MSG_90.substringBefore('{0}');
        try {
            SR_ApprovalUiController.decide('không phải JSON', true, null);
            Assert.fail('Phải báo MSG-90');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg90Start), e.getMessage());
        }
        try {
            SR_ApprovalUiController.getQueue('{');
            Assert.fail('Phải báo MSG-90');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg90Start), e.getMessage());
        }
    }
}
