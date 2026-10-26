/**
 * Test cho SR_CustomerSearchService / SR_CustomerSearchController (B10; D.5, FR-17, FR-18).
 * Chạy: sf apex run test --class-names SR_CustomerSearchServiceTest --result-format human
 */
@IsTest
private class SR_CustomerSearchServiceTest {

    @IsTest
    static void shortTermReturnsNothing() {
        Assert.isTrue(SR_CustomerSearchController.searchAll('09').isEmpty());
        Assert.isTrue(SR_CustomerSearchController.searchAll('  ab  ').isEmpty());
        Assert.isTrue(SR_CustomerSearchController.searchAll(null).isEmpty());
    }

    // Dấu "-" trong mã yêu cầu, dấu nháy... phải escape để SOSL không coi là toán tử
    @IsTest
    static void escapesSoslSpecialCharacters() {
        Assert.areEqual('RR\\-2610\\-00015', SR_CustomerSearchService.escapeSosl('RR-2610-00015'));
        Assert.areEqual('O\\\'Neil', SR_CustomerSearchService.escapeSosl('O\'Neil'));
        Assert.areEqual('0901', SR_CustomerSearchService.escapeSosl('0901'));
    }

    // 3 nhóm theo thứ tự, mỗi dòng có Id + các cột
    @IsTest
    static void returnsThreeGroupsWithRows() {
        Account a = new Account(Name = 'Nguyễn Thị Lan', Phone = '0901234567');
        insert a;
        Test.setFixedSearchResults(new List<Id>{ a.Id });

        List<SR_CustomerSearchService.ResultGroup> groups = SR_CustomerSearchController.searchAll('0901');

        Assert.areEqual(3, groups.size());
        Assert.areEqual('Account', groups[0].objectName);
        Assert.areEqual('Order', groups[1].objectName);
        Assert.areEqual('Return_Request__c', groups[2].objectName);
        Assert.areEqual(1, groups[0].rows.size());
        Assert.areEqual(a.Id, groups[0].rows[0].get('Id'));
        Assert.areEqual('Nguyễn Thị Lan', groups[0].rows[0].get('Name'));
        Assert.areEqual(0, groups[1].rows.size());
    }

    // Chưa có Field Set: dùng cột mặc định, có kiểu cột cho datatable
    @IsTest
    static void defaultColumnsWhenNoFieldSet() {
        SR_CustomerSearchService.ResultGroup g = SR_CustomerSearchService.buildGroup('Account', new List<SObject>());
        List<String> names = new List<String>();
        for (SR_CustomerSearchService.Column c : g.columns) {
            names.add(c.fieldName);
        }
        if (Schema.SObjectType.Account.fieldSets.getMap().get(SR_CustomerSearchService.FIELD_SET) == null) {
            Assert.areEqual(new List<String>{ 'Name', 'Phone' }, names);
            Assert.areEqual('phone', g.columns[1].type);
        } else {
            Assert.isFalse(names.isEmpty(), 'Field Set có cột thì phải trả cột');
        }
        Assert.areEqual('Khách hàng', g.title);
    }
}
