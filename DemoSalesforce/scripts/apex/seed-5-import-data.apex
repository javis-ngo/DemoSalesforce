// =====================================================================
// SmartReturn – Seed 5: dữ liệu cho test import 200 yêu cầu (NFR-02, UAT-01, B11)
// Chạy: npm run seed (chạy seed 1 → 5 rồi tự sinh postman/import-200-return-requests.json)
//   hoặc riêng: sf apex run -f scripts/apex/seed-5-import-data.apex rồi npm run seed:import-json
// Cần chạy seed 2 trước (6 khách mẫu + sản phẩm 6 ngành hàng trong Standard Price Book).
// Tạo:
//   - 2 cửa hàng vùng Nam: HCM-021 (CHT sm.nam1), HCM-022 (CHT sm.nam2), QLV rm.nam cho cả hai
//   - 16 đơn hàng "SR-IMPORT xx" của 6 khách có sẵn, số lượng lớn để đủ cho ~200 yêu cầu
// Mỗi lần chạy: xóa yêu cầu đổi trả + đơn "SR-IMPORT" cũ rồi tạo lại (ngày giao tính theo hôm nay).
// OrderNumber tự sinh nên đổi mỗi lần chạy: file JSON import do scripts/seed.js sinh lại theo đơn mới.
// Lưu ý: chạy lại seed 2 sẽ xóa đơn của 6 khách mẫu, kể cả đơn SR-IMPORT.
// Owner: Dev B
// =====================================================================

Date today = Date.today();

// 1) Người dùng CHT / QLV vùng Nam
Map<String, Id> userIdOf = new Map<String, Id>();
for (User u : [
    SELECT Id, Username FROM User
    WHERE Username IN ('sm.nam1@smartreturn.demo.vn', 'sm.nam2@smartreturn.demo.vn', 'rm.nam@smartreturn.demo.vn')
    AND IsActive = true
]) {
    userIdOf.put(u.Username.substringBefore('@'), u.Id);
}
for (String key : new List<String>{ 'sm.nam1', 'sm.nam2', 'rm.nam' }) {
    if (!userIdOf.containsKey(key)) {
        throw new IllegalArgumentException('Thiếu user ' + key + '@smartreturn.demo.vn');
    }
}

// 2) Cửa hàng (upsert theo mã nên chạy lại không bị trùng)
List<Store__c> stores = new List<Store__c>{
    new Store__c(Name = 'Phương Nam Bình Thạnh', Store_Code__c = 'HCM-021', Region__c = 'South',
        Store_Manager__c = userIdOf.get('sm.nam1'), Regional_Manager__c = userIdOf.get('rm.nam')),
    new Store__c(Name = 'Phương Nam Gò Vấp', Store_Code__c = 'HCM-022', Region__c = 'South',
        Store_Manager__c = userIdOf.get('sm.nam2'), Regional_Manager__c = userIdOf.get('rm.nam'))
};
upsert stores Store_Code__c;
Map<String, Id> storeIdOf = new Map<String, Id>();
for (Store__c s : stores) {
    storeIdOf.put(s.Store_Code__c, s.Id);
}

// 3) Sản phẩm + giá có sẵn (seed 2)
Pricebook2 std = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Map<String, PricebookEntry> entryOf = new Map<String, PricebookEntry>();
for (PricebookEntry e : [
    SELECT Id, UnitPrice, Product2.ProductCode FROM PricebookEntry
    WHERE Pricebook2Id = :std.Id AND IsActive = true
    AND Product2.ProductCode IN ('AF-PH-5L', 'MX-ST-15', 'LT-15-PRO', 'PH-A55', 'AC-TN-01', 'TC-VT-100K', 'SW-AV-1Y')
]) {
    entryOf.put(e.Product2.ProductCode, e);
}
if (entryOf.size() < 7) {
    throw new IllegalArgumentException('Thiếu sản phẩm/giá, chạy seed 2 trước. Có: ' + entryOf.keySet());
}

// 4) Khách có sẵn, theo SĐT
Map<String, Id> accountIdOf = new Map<String, Id>();
for (Account a : [SELECT Id, Phone FROM Account WHERE Phone != null]) {
    accountIdOf.put(a.Phone, a.Id);
}

// 5) Xóa dữ liệu SR-IMPORT cũ: yêu cầu đổi trả trước, rồi đơn hàng
List<Order> oldOrders = [SELECT Id, Status FROM Order WHERE Name LIKE 'SR-IMPORT%'];
Set<Id> oldOrderIds = new Map<Id, Order>(oldOrders).keySet();
List<Return_Request__c> oldRequests = [SELECT Id FROM Return_Request__c WHERE Order__c IN :oldOrderIds];
delete oldRequests;
List<Order> backToDraft = new List<Order>();
for (Order o : oldOrders) {
    if (o.Status != 'Draft') {
        backToDraft.add(new Order(Id = o.Id, Status = 'Draft'));
    }
}
update backToDraft;
delete oldOrders;
System.debug('SEED | Đã xóa ' + oldRequests.size() + ' yêu cầu và ' + oldOrders.size() + ' đơn SR-IMPORT cũ');

// 6) Đơn hàng: [tên, SĐT khách, cửa hàng, giao cách đây mấy ngày, thanh toán, 'SKU:SL,...']
//    Ngành hàng đổi được: Gia dụng 30 ngày, Laptop 15 ngày, Điện thoại / Phụ kiện 7 ngày (Phụ lục B.1).
//    Giao 1–3 ngày trước nên file import dùng được trong ~4 ngày sau khi chạy seed.
String full = 'AF-PH-5L:4,MX-ST-15:4,LT-15-PRO:3,PH-A55:4,AC-TN-01:6';
List<List<Object>> plan = new List<List<Object>>{
    new List<Object>{ 'SR-IMPORT 01', '0901234567', 'HCM-021', 1, 'Card', full },
    new List<Object>{ 'SR-IMPORT 02', '0912345678', 'HCM-021', 2, 'E-Wallet', full },
    new List<Object>{ 'SR-IMPORT 03', '0938111222', 'HCM-021', 3, 'Cash', full },
    new List<Object>{ 'SR-IMPORT 04', '0987654321', 'HCM-021', 1, 'Card', full },
    new List<Object>{ 'SR-IMPORT 05', '0909333444', 'HCM-021', 2, 'Mixed', full },
    new List<Object>{ 'SR-IMPORT 06', '0977555666', 'HCM-021', 3, 'Card', full },
    new List<Object>{ 'SR-IMPORT 07', '0901234567', 'HCM-021', 2, 'E-Wallet', full },
    new List<Object>{ 'SR-IMPORT 08', '0912345678', 'HCM-021', 1, 'Card', full },
    new List<Object>{ 'SR-IMPORT 09', '0938111222', 'HCM-022', 1, 'Card', full },
    new List<Object>{ 'SR-IMPORT 10', '0987654321', 'HCM-022', 2, 'Cash', full },
    new List<Object>{ 'SR-IMPORT 11', '0909333444', 'HCM-022', 3, 'Card', full },
    new List<Object>{ 'SR-IMPORT 12', '0977555666', 'HCM-022', 1, 'E-Wallet', full },
    new List<Object>{ 'SR-IMPORT 13', '0901234567', 'HCM-022', 2, 'Card', full },
    new List<Object>{ 'SR-IMPORT 14', '0909333444', 'HCM-022', 1, 'Mixed', full },
    // Có thẻ cào + phần mềm (không đổi trả được, MSG-05)
    new List<Object>{ 'SR-IMPORT 15', '0977555666', 'HCM-022', 2, 'Cash',
        'TC-VT-100K:5,SW-AV-1Y:2,AF-PH-5L:4,AC-TN-01:6' },
    // Giao 20 ngày trước: điện thoại / phụ kiện đã hết hạn (MSG-03), gia dụng còn hạn
    new List<Object>{ 'SR-IMPORT 16', '0912345678', 'HCM-022', 20, 'Card', 'PH-A55:3,AC-TN-01:3,MX-ST-15:4' }
};
List<Order> orders = new List<Order>();
for (List<Object> p : plan) {
    Id accountId = accountIdOf.get((String) p[1]);
    if (accountId == null) {
        throw new IllegalArgumentException('Không có khách SĐT ' + p[1] + ', chạy seed 2 trước');
    }
    Date delivery = today.addDays(-(Integer) p[3]);
    orders.add(new Order(
        Name = (String) p[0],
        AccountId = accountId,
        Store__c = storeIdOf.get((String) p[2]),
        EffectiveDate = delivery.addDays(-1),
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
        PricebookEntry e = entryOf.get(part.substringBefore(':'));
        items.add(new OrderItem(
            OrderId = orders[i].Id,
            PricebookEntryId = e.Id,
            Quantity = Integer.valueOf(part.substringAfter(':')),
            UnitPrice = e.UnitPrice
        ));
    }
}
insert items;
List<Order> toActivate = new List<Order>();
for (Order o : orders) {
    toActivate.add(new Order(Id = o.Id, Status = 'Activated'));
}
update toActivate;

// 7) Danh sách đơn
for (Order o : [
    SELECT Name, OrderNumber, Account.Name, Account.Phone, Store__r.Store_Code__c, Delivery_Date__c
    FROM Order WHERE Id IN :orders ORDER BY Name
]) {
    System.debug('SEED | Đơn ' + o.OrderNumber + ' | ' + o.Name + ' | ' + o.Account.Name + ' ' + o.Account.Phone
        + ' | ' + o.Store__r.Store_Code__c + ' | giao ' + o.Delivery_Date__c.format());
}
System.debug('SEED | XONG: ' + stores.size() + ' cửa hàng, ' + orders.size() + ' đơn, ' + items.size() + ' dòng đơn');
