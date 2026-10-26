/**
 * Test cho SR_EventPublisher: sự kiện kết quả hoàn tiền (FR-09, FR-13, INT-05, BR-15). Không cần tạo dữ liệu.
 * Chạy: sf apex run test --class-names SR_EventPublisherTest --result-format human
 */
@IsTest
private class SR_EventPublisherTest {

    private static Integer seq = 0;

    private static Return_Request__c request(String status) {
        seq++;
        return (Return_Request__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Return_Request__c' },
            'Id' => Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(seq).leftPad(12, '0'),
            'Name' => 'RR-2610-' + String.valueOf(seq).leftPad(5, '0'),
            'Status__c' => status,
            'Actual_Refund__c' => 1992000,
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
    }

    // Công tắc B.4 bật hoặc tắt: publish không ném lỗi
    @IsTest
    static void publishResultWithSwitchOnAndOff() {
        List<Return_Request__c> reqs = new List<Return_Request__c>{ request('COMPLETED') };
        Test.startTest();
        SR_EventPublisher.notifyPosAppOverride = true;
        SR_EventPublisher.publishResult(reqs);
        SR_EventPublisher.notifyPosAppOverride = false;
        SR_EventPublisher.publishResult(reqs);
        SR_EventPublisher.publishResult(null);
        Test.stopTest();
        Assert.areEqual(0, SR_Logger.getInstance().getPendingCount());
    }
}
