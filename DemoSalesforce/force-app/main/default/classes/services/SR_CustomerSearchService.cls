/**
 * D.5 – Ô tìm kiếm cho CSKH (FR-17) với cột do Admin chọn bằng Field Set (FR-18).
 *  - Chạy khi nhập từ 3 ký tự; 3 nhóm Khách hàng / Đơn hàng / Yêu cầu đổi trả, tối đa 20 kết quả mỗi nhóm.
 *  - Cột lấy từ Field Set "SR_Search_Columns" trên Account, Order, Return_Request__c; chưa tạo thì dùng cột mặc định.
 *    Chỉ dùng field nằm trực tiếp trên object (bỏ dạng Account.Name).
 *  - Field người dùng không có quyền xem tự bị bỏ khỏi bảng; bản ghi không được chia sẻ không hiện (USER_MODE).
 *  - Picklist trả nhãn tiếng Việt (toLabel), không trả mã.
 * Owner: Dev B
 */
public with sharing class SR_CustomerSearchService {

    public static final Integer MIN_TERM_LENGTH = 3;
    public static final Integer MAX_PER_GROUP = 20;
    public static final String FIELD_SET = 'SR_Search_Columns';

    // Nhóm theo thứ tự hiển thị: object → tiêu đề, cột mặc định khi chưa có Field Set
    private static final List<String> OBJECTS = new List<String>{ 'Account', 'Order', 'Return_Request__c' };
    private static final Map<String, String> TITLES = new Map<String, String>{
        'Account' => 'Khách hàng',
        'Order' => 'Đơn hàng',
        'Return_Request__c' => 'Yêu cầu đổi trả'
    };
    private static final Map<String, List<String>> DEFAULT_COLUMNS = new Map<String, List<String>>{
        'Account' => new List<String>{ 'Name', 'Phone' },
        'Order' => new List<String>{ 'OrderNumber', 'EffectiveDate', 'Status' },
        'Return_Request__c' => new List<String>{ 'Name', 'Status__c', 'Channel__c', 'Estimated_Refund__c' }
    };

    // Kiểu cột lightning-datatable theo kiểu field
    private static final Map<Schema.DisplayType, String> COLUMN_TYPES = new Map<Schema.DisplayType, String>{
        Schema.DisplayType.CURRENCY => 'currency',
        Schema.DisplayType.DOUBLE => 'number',
        Schema.DisplayType.INTEGER => 'number',
        Schema.DisplayType.PERCENT => 'percent',
        Schema.DisplayType.DATE => 'date-local',
        Schema.DisplayType.DATETIME => 'date',
        Schema.DisplayType.PHONE => 'phone',
        Schema.DisplayType.EMAIL => 'email',
        Schema.DisplayType.BOOLEAN => 'boolean'
    };

    // SOSL coi các ký tự này là toán tử (vd. "-" trong RR-2610-00015) → thêm "\" phía trước
    private static final String SOSL_SPECIALS = '?&|!{}[]()^~*:"\'+-\\';

    public class Column {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
    }

    public class ResultGroup {
        @AuraEnabled public String objectName;
        @AuraEnabled public String title;
        @AuraEnabled public List<Column> columns = new List<Column>();
        @AuraEnabled public List<Map<String, Object>> rows = new List<Map<String, Object>>();
    }

    public static List<ResultGroup> searchAll(String term) {
        List<ResultGroup> groups = new List<ResultGroup>();
        String text = (term == null) ? '' : term.trim();
        if (text.length() < MIN_TERM_LENGTH) {
            return groups;
        }
        // Thêm * để gõ "0901" tìm được SĐT 0901234567
        List<List<SObject>> found = SR_CustomerSearchSelector.search(escapeSosl(text) + '*', OBJECTS, MAX_PER_GROUP);
        for (Integer i = 0; i < OBJECTS.size(); i++) {
            groups.add(buildGroup(OBJECTS[i], found[i]));
        }
        return groups;
    }

    @TestVisible
    private static ResultGroup buildGroup(String objectName, List<SObject> hits) {
        ResultGroup g = new ResultGroup();
        g.objectName = objectName;
        g.title = TITLES.get(objectName);

        Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectName).getDescribe();
        List<String> fieldExpressions = new List<String>{ 'Id' };
        Set<String> added = new Set<String>();
        for (String path : columnPaths(describe)) {
            Schema.SObjectField field = describe.fields.getMap().get(path);
            if (field == null) {
                continue;                               // field đã xóa hoặc dạng quan hệ
            }
            Schema.DescribeFieldResult f = field.getDescribe();
            if (!f.isAccessible() || f.getName() == 'Id' || added.contains(f.getName())) {
                continue;                               // không có quyền xem → bỏ cột; trùng → bỏ
            }
            added.add(f.getName());
            Column c = new Column();
            c.fieldName = f.getName();
            c.label = f.getLabel();
            c.type = COLUMN_TYPES.containsKey(f.getType()) ? COLUMN_TYPES.get(f.getType()) : 'text';
            g.columns.add(c);
            Boolean isPicklist = f.getType() == Schema.DisplayType.PICKLIST
                || f.getType() == Schema.DisplayType.MULTIPICKLIST;
            fieldExpressions.add(isPicklist ? 'toLabel(' + c.fieldName + ')' : c.fieldName);
        }
        if (hits == null || hits.isEmpty() || g.columns.isEmpty()) {
            return g;
        }

        // Giữ thứ tự liên quan của SOSL
        Map<Id, SObject> byId = new Map<Id, SObject>(
            SR_CustomerSearchSelector.selectColumns(objectName, fieldExpressions, new Map<Id, SObject>(hits).keySet()));
        for (SObject hit : hits) {
            SObject rec = byId.get(hit.Id);
            if (rec == null) {
                continue;
            }
            Map<String, Object> row = new Map<String, Object>{ 'Id' => rec.Id };
            for (Column c : g.columns) {
                row.put(c.fieldName, rec.get(c.fieldName));
            }
            g.rows.add(row);
        }
        return g;
    }

    // Field Set nếu Admin đã tạo, không thì cột mặc định. Trả tên field viết thường để tra fields.getMap().
    private static List<String> columnPaths(Schema.DescribeSObjectResult describe) {
        List<String> paths = new List<String>();
        Schema.FieldSet fs = describe.fieldSets.getMap().get(FIELD_SET);
        if (fs != null) {
            for (Schema.FieldSetMember m : fs.getFields()) {
                paths.add(m.getFieldPath().toLowerCase());
            }
        } else {
            for (String name : DEFAULT_COLUMNS.get(describe.getName())) {
                paths.add(name.toLowerCase());
            }
        }
        return paths;
    }

    @TestVisible
    private static String escapeSosl(String text) {
        String result = '';
        for (Integer i = 0; i < text.length(); i++) {
            String ch = text.substring(i, i + 1);
            result += SOSL_SPECIALS.contains(ch) ? '\\' + ch : ch;
        }
        return result;
    }
}
