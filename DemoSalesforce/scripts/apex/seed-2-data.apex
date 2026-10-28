// =====================================================================
// SmartReturn – Seed 2/4: cửa hàng, sản phẩm + giá, khách hàng, đơn hàng (DUC-02)
// Chạy riêng: sf apex run -f scripts/apex/seed-2-data.apex -o sr-shared
// Mỗi lần chạy: xóa đơn hàng + yêu cầu đổi trả cũ của 6 khách mẫu rồi tạo lại.
// Cửa hàng, sản phẩm, khách dùng lại theo mã / SKU / SĐT nên không bị trùng.
// Ngày giao tính theo hôm nay: chạy lại vào ngày test/demo để đơn đúng tình huống.
// Owner: Dev C (Đức)
// =====================================================================

Date today = Date.today();
Id me = UserInfo.getUserId();
String userPattern = '%@sr-' + String.valueOf(UserInfo.getOrganizationId()).toLowerCase() + '.test';

// 1) User test tạo ở seed 1; vai nào thiếu thì người chạy script đóng vai
Map<String, Id> userIdOf = new Map<String, Id>();
for (User u : [SELECT Id, Username FROM User WHERE Username LIKE :userPattern AND IsActive = true]) {
    userIdOf.put(u.Username.substringBefore('@'), u.Id);
}
Id chtHcm012 = userIdOf.containsKey('cht.hcm012') ? userIdOf.get('cht.hcm012') : me;
Id qlvNam = userIdOf.containsKey('qlv.nam') ? userIdOf.get('qlv.nam') : me;

// 2) Giá trị picklist Vùng: nhận cả API name tiếng Anh lẫn nhãn tiếng Việt
Map<String, String> region = new Map<String, String>{ 'NORTH' => 'NORTH', 'CENTRAL' => 'CENTRAL', 'SOUTH' => 'SOUTH' };
for (Schema.PicklistEntry e : Store__c.Region__c.getDescribe().getPicklistValues()) {
    String v = e.getValue().toUpperCase();
    if (v == 'NORTH' || e.getLabel() == 'Bắc') {
        region.put('NORTH', e.getValue());
    }
    if (v == 'CENTRAL' || e.getLabel() == 'Trung') {
        region.put('CENTRAL', e.getValue());
    }
    if (v == 'SOUTH' || e.getLabel() == 'Nam') {
        region.put('SOUTH', e.getValue());
    }
}

// 3) Cửa hàng: 3 vùng, 5 cửa hàng; mỗi cửa hàng có CHT, mỗi vùng có QLV
List<Store__c> stores = new List<Store__c>{
    new Store__c(Name = 'Phương Nam Hoàn Kiếm', Store_Code__c = 'HN-001', Region__c = region.get('NORTH'), Store_Manager__c = me, Regional_Manager__c = me),
    new Store__c(Name = 'Phương Nam Cầu Giấy', Store_Code__c = 'HN-007', Region__c = region.get('NORTH'), Store_Manager__c = me, Regional_Manager__c = me),
    new Store__c(Name = 'Phương Nam Hải Châu', Store_Code__c = 'DN-003', Region__c = region.get('CENTRAL'), Store_Manager__c = me, Regional_Manager__c = me),
    new Store__c(Name = 'Phương Nam Thủ Đức', Store_Code__c = 'HCM-005', Region__c = region.get('SOUTH'), Store_Manager__c = me, Regional_Manager__c = qlvNam),
    new Store__c(Name = 'Phương Nam Quận 1', Store_Code__c = 'HCM-012', Region__c = region.get('SOUTH'), Store_Manager__c = chtHcm012, Regional_Manager__c = qlvNam)
};
upsert stores Store_Code__c;
Map<String, Id> storeIdOf = new Map<String, Id>();
for (Store__c s : stores) {
    storeIdOf.put(s.Store_Code__c, s.Id);
}

// 4) Sản phẩm đủ 6 ngành hàng + giá trong Standard Price Book.
//    Family phải giống hệt giá trị trong Custom Metadata SR_Category_Policy.
Map<String, List<String>> productInfo = new Map<String, List<String>>{
    'AF-PH-5L' => new List<String>{ 'Nồi chiên không dầu 5L', 'Gia dụng' },
    'MX-ST-15' => new List<String>{ 'Máy xay sinh tố 1.5L', 'Gia dụng' },
    'LT-15-PRO' => new List<String>{ 'Laptop 15 inch Pro', 'Laptop' },
    'PH-A55' => new List<String>{ 'Điện thoại A55', 'Điện thoại' },
    'AC-TN-01' => new List<String>{ 'Tai nghe Bluetooth', 'Phụ kiện' },
    'TC-VT-100K' => new List<String>{ 'Thẻ cào Viettel 100K', 'Thẻ cào' },
    'SW-AV-1Y' => new List<String>{ 'Phần mềm diệt virus 1 năm', 'Phần mềm' }
};
Map<String, Decimal> price = new Map<String, Decimal>{
    'AF-PH-5L' => 2490000, 'MX-ST-15' => 1500000, 'LT-15-PRO' => 25000000, 'PH-A55' => 9990000,
    'AC-TN-01' => 1290000, 'TC-VT-100K' => 100000, 'SW-AV-1Y' => 490000
};
Map<String, Product2> productOf = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :price.keySet()]) {
    productOf.put(p.ProductCode, p);
}
for (String sku : price.keySet()) {
    Product2 p = productOf.containsKey(sku) ? productOf.get(sku) : new Product2(ProductCode = sku);
    p.Name = productInfo.get(sku)[0];
    p.Family = productInfo.get(sku)[1];
    p.IsActive = true;
    productOf.put(sku, p);
}
upsert productOf.values();

Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!std.IsActive) {
    std.IsActive = true;
    update std;
}
Set<Id> productIds = new Map<Id, Product2>(productOf.values()).keySet();
Map<Id, PricebookEntry> entryOfProduct = new Map<Id, PricebookEntry>();
for (PricebookEntry e : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :std.Id AND Product2Id IN :productIds]) {
    entryOfProduct.put(e.Product2Id, e);
}
Map<String, PricebookEntry> entryOf = new Map<String, PricebookEntry>();
for (String sku : price.keySet()) {
    Id pid = productOf.get(sku).Id;
    PricebookEntry e = entryOfProduct.containsKey(pid)
        ? entryOfProduct.get(pid)
        : new PricebookEntry(Pricebook2Id = std.Id, Product2Id = pid);
    e.UnitPrice = price.get(sku);
    e.IsActive = true;
    entryOf.put(sku, e);
}
upsert entryOf.values();

// 5) Khách hàng mẫu, nhận diện theo SĐT. Đừng dùng 6 SĐT này cho dữ liệu test riêng:
//    mỗi lần chạy, đơn hàng và yêu cầu của các khách này bị xóa rồi tạo lại.
Map<String, String> customers = new Map<String, String>{
    '0901234567' => 'Chị Lan',
    '0912345678' => 'Anh Minh',
    '0938111222' => 'Chị Hoa',
    '0987654321' => 'Anh Khoa (khách rủi ro)',
    '0909333444' => 'Anh Tuấn',
    '0977555666' => 'Chị Mai'
};
Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
Map<String, Account> accountOf = new Map<String, Account>();
for (Account a : [SELECT Id, Phone FROM Account WHERE Phone IN :customers.keySet()]) {
    accountOf.put(a.Phone, a);
}
for (String phone : customers.keySet()) {
    Account a = accountOf.containsKey(phone) ? accountOf.get(phone) : new Account(Phone = phone);
    a.Name = customers.get(phone);
    // Bỏ cờ Rủi ro còn sót từ lần test trước (cờ được tính lại khi tạo yêu cầu)
    if (accountFields.containsKey('risk_flag__c')) {
        a.put('Risk_Flag__c', false);
    }
    if (accountFields.containsKey('risk_flag_updated_at__c')) {
        a.put('Risk_Flag_Updated_At__c', null);
    }
    accountOf.put(phone, a);
}
upsert accountOf.values();
Set<Id> accountIds = new Map<Id, Account>(accountOf.values()).keySet();

// 6) Xóa dữ liệu cũ của khách mẫu: yêu cầu đổi trả trước (nếu object đã có), rồi đơn hàng
List<Order> oldOrders = [SELECT Id, Status FROM Order WHERE AccountId IN :accountIds];
Set<Id> oldOrderIds = new Map<Id, Order>(oldOrders).keySet();
if (Schema.getGlobalDescribe().containsKey('return_request__c')) {
    List<SObject> oldRequests = Database.query(
        'SELECT Id FROM Return_Request__c WHERE Account__c IN :accountIds OR Order__c IN :oldOrderIds');
    delete oldRequests;
    System.debug('SEED | Đã xóa ' + oldRequests.size() + ' yêu cầu đổi trả cũ');
}
List<Order> backToDraft = new List<Order>();
for (Order o : oldOrders) {
    if (o.Status != 'Draft') {
        backToDraft.add(new Order(Id = o.Id, Status = 'Draft'));
    }
}
update backToDraft;
delete oldOrders;
System.debug('SEED | Đã xóa ' + oldOrders.size() + ' đơn hàng cũ');

// 7) Đơn hàng mẫu. Tên đơn bắt đầu bằng "SR-SEED xx" để seed 4 và người test tìm lại.
//    [tên đơn, SĐT khách, cửa hàng, giao cách đây mấy ngày (null = mua mang về tại quầy), thanh toán, 'SKU:SL,...']
List<List<Object>> plan = new List<List<Object>>{
    new List<Object>{ 'SR-SEED 01 Chuyện 1 – nồi chiên chị Lan', '0901234567', 'HCM-012', 4, 'E-Wallet', 'AF-PH-5L:1' },
    new List<Object>{ 'SR-SEED 02 Chuyện 2 – laptop anh Minh', '0912345678', 'HCM-012', 3, 'Card', 'LT-15-PRO:1' },
    new List<Object>{ 'SR-SEED 03 UAT-02 – khách thường, món 1,5tr', '0938111222', 'HCM-005', 2, 'Card', 'MX-ST-15:1' },
    new List<Object>{ 'SR-SEED 04 UAT-03 – đã có 3 yêu cầu', '0987654321', 'HCM-012', 2, 'Cash', 'AC-TN-01:3' },
    new List<Object>{ 'SR-SEED 05 UAT-03 – món 1,5tr để test', '0987654321', 'HCM-012', 1, 'Card', 'MX-ST-15:1' },
    new List<Object>{ 'SR-SEED 06 UAT-04 – điện thoại giao 10 ngày', '0909333444', 'HCM-012', 10, 'Card', 'PH-A55:1' },
    new List<Object>{ 'SR-SEED 07 Hôm nay là ngày cuối đổi trả', '0909333444', 'HCM-005', 7, 'Card', 'PH-A55:1' },
    new List<Object>{ 'SR-SEED 08 Chờ QLV duyệt quá 24 giờ', '0909333444', 'HCM-012', 2, 'Card', 'LT-15-PRO:1' },
    new List<Object>{ 'SR-SEED 09 OI-03 – mua tại quầy, không ngày giao', '0977555666', 'HN-001', null, 'Cash', 'AF-PH-5L:1' },
    new List<Object>{ 'SR-SEED 10 Thẻ cào + phần mềm không đổi trả', '0977555666', 'DN-003', 1, 'Mixed', 'TC-VT-100K:2,SW-AV-1Y:1,AC-TN-01:1' },
    new List<Object>{ 'SR-SEED 11 UAT-08 – yêu cầu của HN-007', '0977555666', 'HN-007', 1, 'Card', 'AC-TN-01:1' }
};
List<Order> orders = new List<Order>();
for (List<Object> p : plan) {
    Integer deliveredDaysAgo = (Integer) p[3];
    Date delivery = (deliveredDaysAgo == null) ? null : today.addDays(-deliveredDaysAgo);
    orders.add(new Order(
        Name = (String) p[0],
        AccountId = accountOf.get((String) p[1]).Id,
        Store__c = storeIdOf.get((String) p[2]),
        EffectiveDate = (delivery == null) ? today.addDays(-3) : delivery.addDays(-1),
        Delivery_Date__c = delivery,
        Payment_Method__c = (String) p[4],
        Pricebook2Id = std.Id,
        Status = 'Draft'
    ));
}
insert orders;
List<OrderItem> items = new List<OrderItem>();
for (Integer i = 0; i < plan.size(); i++) {
    for (String part : ((String) plan[i][5]).split(',')) {
        String sku = part.substringBefore(':');
        items.add(new OrderItem(
            OrderId = orders[i].Id,
            PricebookEntryId = entryOf.get(sku).Id,
            Quantity = Integer.valueOf(part.substringAfter(':')),
            UnitPrice = price.get(sku)
        ));
    }
}
insert items;
// Thêm OrderItem xong mới Activate
List<Order> toActivate = new List<Order>();
for (Order o : orders) {
    toActivate.add(new Order(Id = o.Id, Status = 'Activated'));
}
update toActivate;

// 8) Danh sách đơn để test (số đơn tự sinh nên mỗi lần chạy một khác)
for (Order o : [
    SELECT Name, OrderNumber, Account.Name, Account.Phone, Store__r.Store_Code__c, Delivery_Date__c, EffectiveDate
    FROM Order WHERE Id IN :orders ORDER BY Name
]) {
    String dateText = (o.Delivery_Date__c == null)
        ? 'mua tại quầy ' + o.EffectiveDate.format()
        : 'giao ' + o.Delivery_Date__c.format();
    System.debug('SEED | Đơn ' + o.OrderNumber + ' | ' + o.Name + ' | ' + o.Account.Name + ' ' + o.Account.Phone
        + ' | ' + o.Store__r?.Store_Code__c + ' | ' + dateText);
}
System.debug('SEED | Seed 2 XONG: ' + stores.size() + ' cửa hàng, ' + productOf.size() + ' sản phẩm, '
    + accountOf.size() + ' khách, ' + orders.size() + ' đơn hàng');