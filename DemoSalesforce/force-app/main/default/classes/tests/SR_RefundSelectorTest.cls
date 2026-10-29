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

    // Queueable chạy dưới quyền người bấm "Hoàn tất kiểm định" (license Salesforce Platform, không có object Order):
    // trước đây lỗi "Didn't understand relationship 'Order__r'" và yêu cầu kẹt ở REFUND_PROCESSING
    @IsTest
    static void selectSendableWorksForPlatformLicenseUser() {
        Store__c store = SR_TestDataFactory.createStore(
            'HCM-RS1', SR_TestDataFactory.REGION_SOUTH, UserInfo.getUserId(), UserInfo.getUserId());
        Account customer = SR_TestDataFactory.createAccount('Khách selector', '0907000222', false);
        Product2 fryer = SR_TestDataFactory.createProduct(
            SR_TestDataFactory.FAMILY_APPLIANCE, 'AF-RS-001', 'Nồi chiên SR Selector', 2490000);
        SR_TestDataFactory.OrderSpec spec = new SR_TestDataFactory.OrderSpec(customer.Id, store.Id);
        spec.deliveryDate = Date.today().addDays(-2);
        spec.items.add(new SR_TestDataFactory.ItemSpec(fryer.Id, 1));
        Order ord = SR_TestDataFactory.createOrder(spec);
        ord = [SELECT Id, OrderNumber, AccountId, Store__c FROM Order WHERE Id = :ord.Id];
        Return_Request__c r = SR_TestDataFactory.createReturnRequest(SR_TestDataFactory.requestSpecsForOrders(
            new List<Order>{ ord }, SR_TestDataFactory.STATUS_REFUND_PROCESSING, SR_TestDataFactory.CHANNEL_POS)[0]);

        List<Return_Request__c> found;
        System.runAs(newPlatformUser()) {
            found = new WithoutSharingCaller().selectSendable(new Set<Id>{ r.Id });
        }
        Assert.areEqual(1, found.size());
        Assert.areEqual(ord.OrderNumber, found[0].Order__r.OrderNumber);
        Assert.areEqual('HCM-RS1', found[0].Store__r.Store_Code__c);
    }

    // Không gán permission set: chỉ có quyền của license Salesforce Platform
    private static User newPlatformUser() {
        String username = 'sr.refund.selector.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12)
            + '@smartreturn.test';
        User u = new User(
            Username = username,
            Email = username,
            LastName = 'SR Platform',
            Alias = 'srplat',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1].Id,
            TimeZoneSidKey = 'Asia/Bangkok',
            LocaleSidKey = 'vi_VN',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    // Giống SR_RefundService (without sharing): user test không được share yêu cầu
    private without sharing class WithoutSharingCaller {
        List<Return_Request__c> selectSendable(Set<Id> ids) {
            return SR_RefundSelector.selectSendable(ids, System.now());
        }
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
