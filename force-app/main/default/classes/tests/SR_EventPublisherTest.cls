/**
 * Test cho SR_EventPublisher: sự kiện kết quả hoàn tiền (FR-09, FR-13, INT-05, BR-15) và thông báo yêu cầu
 * vừa tạo / cập nhật cho màn hình duyệt (FR-08, D.2). Không cần tạo dữ liệu.
 * Chạy: sf apex run test --class-names SR_EventPublisherTest --result-format human
 */
@IsTest
private class SR_EventPublisherTest {

    private static Integer seq = 0;

    private static final String STORE_ID = Store__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

    private static Return_Request__c request(String status) {
        seq++;
        return (Return_Request__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Return_Request__c' },
            'Id' => Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(seq).leftPad(12, '0'),
            'Name' => 'RR-2610-' + String.valueOf(seq).leftPad(5, '0'),
            'Status__c' => status,
            'Actual_Refund__c' => 1992000,
            'Store__c' => STORE_ID,
            'Store__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Store__c' },
                'Store_Code__c' => 'HCM-012'
            }
        }), Return_Request__c.class);
    }

    @IsTest
    static void uiEventsOnlyForResultStatuses() {
        Return_Request__c done = request('COMPLETED');
        List<SR_UI_Notice__e> events = SR_EventPublisher.buildUiEvents(new List<Return_Request__c>{
            done, request('REFUND_FAILED'), request('REFUND_PROCESSING'), null
        });
        Assert.areEqual(2, events.size());
        Assert.areEqual(done.Id, events[0].Request_Id__c);
        Assert.areEqual(done.Name, events[0].Request_Number__c);
        Assert.areEqual('COMPLETED', events[0].Result__c);
        Assert.areEqual(1992000, events[0].Amount__c);
        Assert.areEqual('HCM-012', events[0].Store_Code__c);
        Assert.areEqual('REFUND_FAILED', events[1].Result__c);
    }

    // E.5: mã yêu cầu, kết quả, số tiền, mã cửa hàng, thời điểm
    @IsTest
    static void externalEventsMatchAppendixE5() {
        Datetime at = Datetime.newInstance(2026, 10, 5, 9, 30, 45);
        List<Return_Request_Event__e> events = SR_EventPublisher.buildExternalEvents(
            new List<Return_Request__c>{ request('REFUND_FAILED'), request('INSPECTING') }, at);
        Assert.areEqual(1, events.size());
        Assert.areEqual('REFUND_FAILED', events[0].Result__c);
        Assert.areEqual(1992000, events[0].Amount__c);
        Assert.areEqual('HCM-012', events[0].Store_Code__c);
        Assert.areEqual(at, events[0].Event_Time__c);
        Assert.isTrue(events[0].Request_Number__c.startsWith('RR-'));
    }

    @IsTest
    static void emptyOrNullInputPublishesNothing() {
        Assert.isTrue(SR_EventPublisher.buildUiEvents(null).isEmpty());
        Assert.isTrue(SR_EventPublisher.buildExternalEvents(new List<Return_Request__c>(), System.now()).isEmpty());
        Assert.isTrue(SR_EventPublisher.buildChangeEvents(null, null).isEmpty());
    }

    // Trigger after insert: oldMap = null → CREATED, mọi trạng thái (không lọc như kết quả hoàn tiền)
    @IsTest
    static void changeEventsForCreatedRequests() {
        Return_Request__c created = request('PENDING_APPROVAL');
        List<SR_UI_Notice__e> events = SR_EventPublisher.buildChangeEvents(
            new List<Return_Request__c>{ created, request('NEW') }, null);
        Assert.areEqual(2, events.size());
        Assert.areEqual(SR_EventPublisher.CHANGE_CREATED, events[0].Change_Type__c);
        Assert.areEqual(created.Id, events[0].Request_Id__c);
        Assert.areEqual(created.Name, events[0].Request_Number__c);
        Assert.areEqual(created.Store__c, events[0].Store_Id__c);
        Assert.areEqual('PENDING_APPROVAL', events[0].Status__c);
        Assert.isNull(events[0].Old_Status__c);
        Assert.areEqual('NEW', events[1].Status__c);
    }

    // Trigger after update: mang cả trạng thái cũ để LWC biết yêu cầu vừa vào / ra bộ lọc
    @IsTest
    static void changeEventsForUpdatedRequestsCarryOldStatus() {
        Return_Request__c approved = request('AWAITING_GOODS');
        Return_Request__c before = approved.clone(true);
        before.Status__c = 'PENDING_APPROVAL';
        List<SR_UI_Notice__e> events = SR_EventPublisher.buildChangeEvents(
            new List<Return_Request__c>{ approved }, new Map<Id, Return_Request__c>{ approved.Id => before });
        Assert.areEqual(1, events.size());
        Assert.areEqual(SR_EventPublisher.CHANGE_UPDATED, events[0].Change_Type__c);
        Assert.areEqual('AWAITING_GOODS', events[0].Status__c);
        Assert.areEqual('PENDING_APPROVAL', events[0].Old_Status__c);
    }

    // Thông báo thay đổi tới mọi người đăng ký (BR-16): không mang số tiền, không mang kết quả (tránh toast trùng)
    @IsTest
    static void changeEventsCarryNoAmountOrResult() {
        SR_UI_Notice__e event = SR_EventPublisher.buildChangeEvents(
            new List<Return_Request__c>{ request('COMPLETED') }, null)[0];
        Assert.isNull(event.Result__c);
        Assert.isNull(event.Amount__c);
    }

    // Chạy trong trigger: publish thành công thì không để lại log chờ
    @IsTest
    static void publishChangesLeavesNoPendingLog() {
        Test.startTest();
        SR_EventPublisher.publishChanges(new List<Return_Request__c>{ request('PENDING_APPROVAL') }, null);
        SR_EventPublisher.publishChanges(null, null);
        Test.stopTest();
        Assert.areEqual(0, SR_Logger.getInstance().getPendingCount());
    }

    // Công tắc B.4 bật hoặc tắt: publish không ném lỗi
    @IsTest
    static void publishResultWithSwitchOnAndOff() {
        List<Return_Request__c> reqs = new List<Return_Request__c>{ request('COMPLETED') };
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Test.startTest();
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_POS_App_Notification__c, true);
        SR_EventPublisher.publishResult(reqs);
        SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_POS_App_Notification__c, false);
        SR_EventPublisher.publishResult(reqs);
        SR_EventPublisher.publishResult(null);
        Test.stopTest();
        Assert.areEqual(0, SR_Logger.getInstance().getPendingCount());
    }
}
