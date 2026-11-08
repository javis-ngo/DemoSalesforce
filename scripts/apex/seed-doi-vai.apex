// =====================================================================
// SmartReturn – Đổi vai cho 1 user test (DUC-02): thiếu license thì 1 user đóng nhiều vai
// Chạy: npm run seed:doi-vai -- <VAI> [--user <tên>] [--store <mã cửa hàng>] [-o <org>]
//   vd: npm run seed:doi-vai -- KETOAN
//       npm run seed:doi-vai -- NV --user cht.hcm012 --store HN-001 -o sr-shared
// Chạy tay: sửa 3 biến cấu hình bên dưới rồi sf apex run -f scripts/apex/seed-doi-vai.apex -o sr-shared
// Việc làm: bỏ permission set vai SmartReturn cũ, gán permission set vai mới, đặt User.Store_Code__c.
// Chỉ đụng User và PermissionSetAssignment (setup object) để tránh lỗi MIXED_DML_OPERATION;
// group cửa hàng/vùng cập nhật bằng seed 3 (npm run seed:doi-vai tự chạy tiếp seed 3).
// Trả các user test về vai gốc: chạy lại seed 1.
// Owner: Dev C
// =====================================================================

String role = 'KETOAN';        // NV | CHT | QLV | KETOAN | CSKH
String userKey = '';            // phần trước @ của user test, vd 'cht.hcm012'; để trống = user test đầu tiên
String storeCode = 'HCM-012';   // cửa hàng cho vai NV / CHT

Map<String, String> psOfRole = new Map<String, String>{
    'NV' => 'SR_Store_Staff',
    'CHT' => 'SR_Store_Manager',
    'QLV' => 'SR_Regional_Manager',
    'KETOAN' => 'SR_Accountant',
    'CSKH' => 'SR_CSKH'
};
Set<String> storeRoles = new Set<String>{ 'NV', 'CHT' };
Set<String> rolePs = new Set<String>(psOfRole.values());
rolePs.add('SR_Admin');

// 1) Kiểm tra hết trước khi sửa, để không đổi dở dang
role = role.trim().toUpperCase();
if (!psOfRole.containsKey(role)) {
    throw new IllegalArgumentException('Vai không hợp lệ: ' + role + ' – chọn một trong ' + psOfRole.keySet());
}
String domain = '@sr-' + String.valueOf(UserInfo.getOrganizationId()).toLowerCase() + '.test';
String userPattern = '%' + domain;
String wantedUsername = userKey.contains('@') ? userKey : userKey + domain;
List<User> found = String.isBlank(userKey)
    ? [SELECT Id, Username, Name, Store_Code__c, Profile.UserLicense.Name FROM User
       WHERE Username LIKE :userPattern AND IsActive = true ORDER BY Username LIMIT 1]
    : [SELECT Id, Username, Name, Store_Code__c, Profile.UserLicense.Name FROM User
       WHERE Username = :wantedUsername AND IsActive = true];
if (found.isEmpty()) {
    throw new IllegalArgumentException('Không thấy user test ' + userKey + ' – chạy seed 1 trước');
}
User u = found[0];
if (u.Id == UserInfo.getUserId()) {
    throw new IllegalArgumentException('Không đổi vai cho chính người chạy script');
}

String wantPs = psOfRole.get(role);
List<PermissionSet> wanted = [SELECT Id FROM PermissionSet WHERE Name = :wantPs];
if (wanted.isEmpty()) {
    throw new IllegalArgumentException('CHƯA CÓ permission set ' + wantPs + ' (chờ Đức – Dev A deploy)');
}

String newStoreCode = storeRoles.contains(role) ? storeCode.trim().toUpperCase() : null;
if (newStoreCode != null && [SELECT COUNT() FROM Store__c WHERE Store_Code__c = :newStoreCode] == 0) {
    throw new IllegalArgumentException('Không có cửa hàng ' + newStoreCode + ' – chạy seed 2 trước');
}

// 2) Bỏ permission set vai cũ, gán vai mới (không đụng permission set khác của user)
List<PermissionSetAssignment> oldRoles = new List<PermissionSetAssignment>();
Boolean hasWanted = false;
for (PermissionSetAssignment a : [
    SELECT Id, PermissionSet.Name FROM PermissionSetAssignment
    WHERE AssigneeId = :u.Id AND PermissionSet.Name IN :rolePs
]) {
    if (a.PermissionSet.Name == wantPs) {
        hasWanted = true;
    } else {
        oldRoles.add(a);
    }
}
delete oldRoles;
if (!hasWanted) {
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = wanted[0].Id);
}

// 3) NV / CHT thuộc 1 cửa hàng; vai khác không gắn cửa hàng
if (u.Store_Code__c != newStoreCode) {
    update new User(Id = u.Id, Store_Code__c = newStoreCode);
}

// 4) Nhắc những gì script này không tự sửa được
String license = u.Profile.UserLicense.Name;
if (role == 'NV' && license != 'Salesforce') {
    System.debug('SEED | CHÚ Ý: ' + u.Username + ' dùng license ' + license
        + ' nên không mở được Đơn hàng, không thử được Quick Action D.1. Vai NV cần license Salesforce.');
}
if (role == 'CHT'
    && [SELECT COUNT() FROM Store__c WHERE Store_Code__c = :newStoreCode AND Store_Manager__c = :u.Id] == 0) {
    System.debug('SEED | CHÚ Ý: ' + u.Username + ' chưa là Store_Manager__c của ' + newStoreCode
        + ': yêu cầu cần CHT duyệt sẽ không giao cho user này. Sửa trên bản ghi cửa hàng nếu cần.');
}
if (role == 'QLV' && [SELECT COUNT() FROM Store__c WHERE Regional_Manager__c = :u.Id] == 0) {
    System.debug('SEED | CHÚ Ý: ' + u.Username + ' chưa là Regional_Manager__c của cửa hàng nào: '
        + 'hàng chờ D.2 sẽ trống. Sửa trên các bản ghi cửa hàng trong vùng nếu cần.');
}

System.debug('SEED | ' + u.Username + ' → vai ' + role + ' (' + wantPs + ')'
    + (newStoreCode == null ? '' : ', cửa hàng ' + newStoreCode)
    + ', bỏ ' + oldRoles.size() + ' permission set vai cũ');
System.debug('SEED | Đăng nhập thử bằng Setup › Users › ' + u.Name + ' › Login (cần bật "Administrators Can Log in as Any User")');
System.debug('SEED | Đổi vai XONG');
