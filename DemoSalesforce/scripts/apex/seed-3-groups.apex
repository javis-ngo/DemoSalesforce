// =====================================================================
// Tên group lấy từ class của Đức – Dev A (SR_SharingService), nên cần class đó đã deploy (hiện chưa có).
// Quy tắc DUNG-13: SR_Store_<mã> = user có User.Store_Code__c = mã (NV + CHT);
//                  SR_Region_<vùng> = QLV của các cửa hàng trong vùng (Store__c.Regional_Manager__c).
// Thêm SR_Accounting = user có permission set SR_Accountant (theo Guide-DevC).
// Chạy sau seed 2. Chạy lại được: thêm thành viên còn thiếu, bỏ user không còn đúng vai.
// Owner: Dev C (Đức)
// =====================================================================

List<Store__c> stores = [
    SELECT Store_Code__c, Region__c, Regional_Manager__c FROM Store__c
    WHERE Store_Code__c IN ('HN-001', 'HN-007', 'DN-003', 'HCM-005', 'HCM-012')
];
Map<String, String> groupLabel = new Map<String, String>{ 'SR_Accounting' => 'SR Kế toán' };
Map<String, Set<Id>> wanted = new Map<String, Set<Id>>{ 'SR_Accounting' => new Set<Id>() };
Map<String, String> storeGroupOf = new Map<String, String>();
for (Store__c s : stores) {
    String storeGroup = SR_SharingService.storeGroupName(s.Store_Code__c);
    String regionGroup = SR_SharingService.regionGroupName(s.Region__c);
    storeGroupOf.put(s.Store_Code__c, storeGroup);
    groupLabel.put(storeGroup, 'SR Cửa hàng ' + s.Store_Code__c);
    groupLabel.put(regionGroup, 'SR Vùng ' + s.Region__c);
    if (!wanted.containsKey(storeGroup)) {
        wanted.put(storeGroup, new Set<Id>());
    }
    if (!wanted.containsKey(regionGroup)) {
        wanted.put(regionGroup, new Set<Id>());
    }
    if (s.Regional_Manager__c != null) {
        wanted.get(regionGroup).add(s.Regional_Manager__c);
    }
}
for (User u : [SELECT Id, Store_Code__c FROM User WHERE IsActive = true AND Store_Code__c IN :storeGroupOf.keySet()]) {
    wanted.get(storeGroupOf.get(u.Store_Code__c)).add(u.Id);
}
for (PermissionSetAssignment a : [
    SELECT AssigneeId FROM PermissionSetAssignment
    WHERE PermissionSet.Name = 'SR_Accountant' AND Assignee.IsActive = true
]) {
    wanted.get('SR_Accounting').add(a.AssigneeId);
}

// Tạo group còn thiếu
Map<String, Id> groupIdOf = new Map<String, Id>();
for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Regular' AND DeveloperName IN :groupLabel.keySet()]) {
    groupIdOf.put(g.DeveloperName, g.Id);
}
List<Group> newGroups = new List<Group>();
for (String devName : groupLabel.keySet()) {
    if (!groupIdOf.containsKey(devName)) {
        newGroups.add(new Group(Name = groupLabel.get(devName), DeveloperName = devName, Type = 'Regular'));
    }
}
insert newGroups;
for (Group g : newGroups) {
    groupIdOf.put(g.DeveloperName, g.Id);
}
Map<Id, String> devNameOf = new Map<Id, String>();
for (String devName : groupIdOf.keySet()) {
    devNameOf.put(groupIdOf.get(devName), devName);
}

// Đồng bộ thành viên là user (giữ nguyên thành viên là group lồng nhau)
Set<String> existing = new Set<String>();
List<GroupMember> toRemove = new List<GroupMember>();
for (GroupMember gm : [SELECT Id, GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :groupIdOf.values()]) {
    existing.add(gm.GroupId + '|' + gm.UserOrGroupId);
    Boolean isUser = String.valueOf(gm.UserOrGroupId).startsWith('005');
    if (isUser && !wanted.get(devNameOf.get(gm.GroupId)).contains(gm.UserOrGroupId)) {
        toRemove.add(gm);
    }
}
List<GroupMember> toAdd = new List<GroupMember>();
for (String devName : wanted.keySet()) {
    for (Id uid : wanted.get(devName)) {
        if (!existing.contains(groupIdOf.get(devName) + '|' + uid)) {
            toAdd.add(new GroupMember(GroupId = groupIdOf.get(devName), UserOrGroupId = uid));
        }
    }
}
insert toAdd;
delete toRemove;
for (String devName : wanted.keySet()) {
    System.debug('SEED | Group ' + devName + ': ' + wanted.get(devName).size() + ' user');
}
System.debug('SEED | Seed 3 XONG: tạo mới ' + newGroups.size() + ' group, thêm ' + toAdd.size() + ', bỏ ' + toRemove.size() + ' thành viên');