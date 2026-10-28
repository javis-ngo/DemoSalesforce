/**
 * Test cho SR_RefundSelector.
 * Chạy: sf apex run test --class-names SR_RefundSelectorTest --result-format human
 */
@IsTest
private class SR_RefundSelectorTest {

    // Id không tồn tại → không có gì để gửi
    @IsTest
    static void selectSendableIgnoresUnknownIds() {
        Id unknown = Return_Request__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        Assert.isTrue(SR_RefundSelector.selectSendable(new Set<Id>{ unknown }, System.now()).isEmpty());
    }

    @IsTest
    static void selectGroupIdFindsRegularGroup() {
        Group g = new Group(Name = 'SR Test Group', DeveloperName = 'SR_Test_Refund_Group', Type = 'Regular');
        insert g;
        Assert.areEqual(g.Id, SR_RefundSelector.selectGroupId('SR_Test_Refund_Group'));
        Assert.isNull(SR_RefundSelector.selectGroupId('SR_Not_Existing_Group'));
    }

    @IsTest
    static void selectNotificationTypeIdReturnsNullWhenMissing() {
        Assert.isNull(SR_RefundSelector.selectNotificationTypeId('SR_Not_Existing_Type'));
    }
}
