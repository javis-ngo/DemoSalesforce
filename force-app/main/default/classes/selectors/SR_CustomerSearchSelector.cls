/**
 * Selector cho ô tìm kiếm CSKH (D.5; FR-17, FR-18).
 *  - USER_MODE cho cả SOSL và SOQL: chỉ thấy bản ghi được chia sẻ (BR-16) và field được cấp quyền.
 * Owner: Dev B
 */
public inherited sharing class SR_CustomerSearchSelector {

    // Thứ tự kết quả = thứ tự objectNames. soslTerm đã escape ký tự đặc biệt.
    public static List<List<SObject>> search(String soslTerm, List<String> objectNames, Integer maxPerGroup) {
        List<String> returning = new List<String>();
        for (String objectName : objectNames) {
            returning.add(objectName + '(Id LIMIT ' + maxPerGroup + ')');
        }
        String sosl = 'FIND \'' + soslTerm + '\' IN ALL FIELDS RETURNING ' + String.join(returning, ', ');
        return Search.query(sosl, AccessLevel.USER_MODE);
    }

    // fieldExpressions: tên field hoặc toLabel(field), đã kiểm tra tồn tại + quyền xem ở service
    public static List<SObject> selectColumns(String objectName, List<String> fieldExpressions, Set<Id> ids) {
        String soql = 'SELECT ' + String.join(fieldExpressions, ', ') + ' FROM ' + objectName + ' WHERE Id IN :ids';
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'ids' => ids }, AccessLevel.USER_MODE);
    }
}
