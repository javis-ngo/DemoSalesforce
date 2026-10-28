// =====================================================================
// SmartReturn – Seed 1/4: user cho từng vai trò + permission set 
// Chạy cả bộ: npm run seed | chạy riêng: sf apex run -f scripts/apex/seed-1-users.apex -o sr-shared
// Chỉ đụng User và PermissionSetAssignment (setup object), nên tách khỏi seed 2
// để tránh lỗi MIXED_DML_OPERATION. Chạy lại không tạo trùng: user đã có thì dùng lại.
// Owner: Dev C (Đức)
// =====================================================================

String domain = '@sr-' + String.valueOf(UserInfo.getOrganizationId()).toLowerCase() + '.test';

// Vai trò theo thứ tự ưu tiên khi thiếu license:
// [username (phần trước @), tên, permission set, mã cửa hàng, license dùng được – ưu tiên trước]
List<List<String>> roles = new List<List<String>>{
    new List<String>{ 'nv.hcm012', 'NV HCM-012', 'SR_Store_Staff', 'HCM-012', 'Salesforce' },
    new List<String>{ 'cht.hcm012', 'CHT HCM-012', 'SR_Store_Manager', 'HCM-012', 'Salesforce,Salesforce Platform' },
    new List<String>{ 'qlv.nam', 'QLV Nam', 'SR_Regional_Manager', '', 'Salesforce Platform,Salesforce' },
    new List<String>{ 'ketoan', 'Kế toán', 'SR_Accountant', '', 'Salesforce Platform,Salesforce' },
    new List<String>{ 'cskh', 'CSKH', 'SR_CSKH', '', 'Salesforce,Salesforce Platform' },
    new List<String>{ 'nv.hn001', 'NV HN-001', 'SR_Store_Staff', 'HN-001', 'Salesforce' }
};

// 1) Kiểm tra license trước
Map<String, Integer> free = new Map<String, Integer>();
for (UserLicense l : [
    SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense
    WHERE Name IN ('Salesforce', 'Salesforce Platform')
]) {
    free.put(l.Name, l.TotalLicenses - l.UsedLicenses);
    System.debug('SEED | License ' + l.Name + ': còn trống ' + (l.TotalLicenses - l.UsedLicenses) + '/' + l.TotalLicenses);
}

// Profile theo license: ưu tiên Standard User / Standard Platform User
Map<String, Id> profileOf = new Map<String, Id>();
for (Profile p : [
    SELECT Id, Name, UserLicense.Name FROM Profile
    WHERE UserLicense.Name IN ('Salesforce', 'Salesforce Platform')
    AND UserType = 'Standard' AND PermissionsModifyAllData = false
    ORDER BY Name
]) {
    if (!profileOf.containsKey(p.UserLicense.Name) || p.Name == 'Standard User' || p.Name == 'Standard Platform User') {
        profileOf.put(p.UserLicense.Name, p.Id);
    }
}

// 2) Tạo user còn thiếu; vai nào hết license thì bỏ qua (xem báo cáo cuối log)
Set<String> usernames = new Set<String>();
for (List<String> r : roles) {
    usernames.add(r[0] + domain);
}
Map<String, User> byUsername = new Map<String, User>();
for (User u : [SELECT Id, Username, IsActive, Store_Code__c FROM User WHERE Username IN :usernames]) {
    byUsername.put(u.Username, u);
}
List<User> toInsert = new List<User>();
List<User> toUpdate = new List<User>();
for (List<String> r : roles) {
    String username = r[0] + domain;
    String storeCode = String.isBlank(r[3]) ? null : r[3];
    User existing = byUsername.get(username);
    if (existing != null) {
        if (!existing.IsActive || existing.Store_Code__c != storeCode) {
            toUpdate.add(new User(Id = existing.Id, IsActive = true, Store_Code__c = storeCode));
        }
        continue;
    }
    String license = null;
    for (String l : r[4].split(',')) {
        if (license == null && free.get(l) != null && free.get(l) > 0 && profileOf.containsKey(l)) {
            license = l;
        }
    }
    if (license == null) {
        continue;
    }
    free.put(license, free.get(license) - 1);
    toInsert.add(new User(
        Username = username,
        FirstName = 'SR',
        LastName = r[1],
        Alias = r[0].remove('.').left(8),
        CommunityNickname = r[0] + '.sr',
        Email = UserInfo.getUserEmail(),
        ProfileId = profileOf.get(license),
        TimeZoneSidKey = UserInfo.getTimeZone().getID(),
        LocaleSidKey = UserInfo.getLocale(),
        LanguageLocaleKey = UserInfo.getLanguage(),
        EmailEncodingKey = 'UTF-8',
        Store_Code__c = storeCode
    ));
}
List<Database.SaveResult> inserted = Database.insert(toInsert, false);
for (Integer i = 0; i < inserted.size(); i++) {
    if (inserted[i].isSuccess()) {
        byUsername.put(toInsert[i].Username, toInsert[i]);
    } else {
        System.debug('SEED | LỖI tạo ' + toInsert[i].Username + ': ' + inserted[i].getErrors()[0].getMessage());
    }
}
List<Database.SaveResult> updated = Database.update(toUpdate, false);
for (Integer i = 0; i < updated.size(); i++) {
    if (!updated[i].isSuccess()) {
        System.debug('SEED | LỖI cập nhật user ' + toUpdate[i].Id + ': ' + updated[i].getErrors()[0].getMessage());
    }
}

// 3) Permission set: mỗi user test giữ đúng permission set của vai mình;
//    người chạy script là Admin và được thêm SR_Admin (không bỏ permission set khác của bạn)
Id me = UserInfo.getUserId();
Set<String> rolePs = new Set<String>{
    'SR_Store_Staff', 'SR_Store_Manager', 'SR_Regional_Manager', 'SR_Accountant', 'SR_CSKH', 'SR_Admin'
};
Map<String, Id> psId = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :rolePs]) {
    psId.put(ps.Name, ps.Id);
}
Map<Id, String> wantPs = new Map<Id, String>();
for (List<String> r : roles) {
    User u = byUsername.get(r[0] + domain);
    if (u != null) {
        wantPs.put(u.Id, r[2]);
    }
}
wantPs.put(me, 'SR_Admin');
Set<String> alreadyHas = new Set<String>();
List<PermissionSetAssignment> psaDelete = new List<PermissionSetAssignment>();
for (PermissionSetAssignment a : [
    SELECT Id, AssigneeId, PermissionSet.Name FROM PermissionSetAssignment
    WHERE AssigneeId IN :wantPs.keySet() AND PermissionSet.Name IN :rolePs
]) {
    if (a.PermissionSet.Name == wantPs.get(a.AssigneeId)) {
        alreadyHas.add(a.AssigneeId + '|' + a.PermissionSet.Name);
    } else if (a.AssigneeId != me) {
        psaDelete.add(a);
    }
}
delete psaDelete;
List<PermissionSetAssignment> psaInsert = new List<PermissionSetAssignment>();
for (Id uid : wantPs.keySet()) {
    String ps = wantPs.get(uid);
    if (psId.containsKey(ps) && !alreadyHas.contains(uid + '|' + ps)) {
        psaInsert.add(new PermissionSetAssignment(AssigneeId = uid, PermissionSetId = psId.get(ps)));
    }
}
Map<Id, String> psaError = new Map<Id, String>();
List<Database.SaveResult> psaResults = Database.insert(psaInsert, false);
for (Integer i = 0; i < psaResults.size(); i++) {
    if (!psaResults[i].isSuccess()) {
        psaError.put(psaInsert[i].AssigneeId, psaResults[i].getErrors()[0].getMessage());
    }
}

// 4) Báo cáo vai trò → user
System.debug('SEED | ===== Vai trò → user =====');
for (List<String> r : roles) {
    User u = byUsername.get(r[0] + domain);
    if (u == null) {
        String fallback = (r[0].startsWith('cht') || r[0].startsWith('qlv'))
            ? 'admin (người chạy script) đóng vai này, seed 2 gán admin làm CHT/QLV'
            : 'đổi vai 1 user test sang vai này: npm run seed:doi-vai -- <VAI> (xem seed-doi-vai.apex)';
        System.debug('SEED | ' + r[1] + ' → THIẾU LICENSE: ' + fallback);
        continue;
    }
    String status = r[2];
    if (!psId.containsKey(r[2])) {
        status = 'CHƯA CÓ permission set ' + r[2] + ' (chờ Đức – Dev A deploy)';
    } else if (psaError.containsKey(u.Id)) {
        status = 'LỖI gán ' + r[2] + ': ' + psaError.get(u.Id);
    }
    System.debug('SEED | ' + r[1] + ' → ' + r[0] + domain + ' | ' + status);
}
String adminStatus = psId.containsKey('SR_Admin') ? 'SR_Admin' : 'CHƯA CÓ permission set SR_Admin (chờ Đức – Dev A deploy)';
if (psaError.containsKey(me)) {
    adminStatus = 'LỖI gán SR_Admin: ' + psaError.get(me);
}
System.debug('SEED | Admin → ' + UserInfo.getUserName() + ' (người chạy script) | ' + adminStatus);
System.debug('SEED | Seed 1 XONG');