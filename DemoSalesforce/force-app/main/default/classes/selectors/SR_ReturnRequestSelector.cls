/**
 * Selector cho Return_Request__c: gom truy vấn yêu cầu trả hàng của màn hình duyệt (D.2), trang yêu cầu (D.3)
 * và Customer Portal (D.4).
 *  - "inherited sharing": chạy theo sharing của class gọi.
 *  - Truy vấn "của tôi" cho khách đăng nhập LUÔN áp sharing (USER_MODE trong class con with sharing SharedWithMe),
 *    vì không có điều kiện lọc theo khách: chỉ Sharing Set giới hạn kết quả.
 *  - Phân trang bằng Database.PaginationCursor thay cho OFFSET (OFFSET chỉ tới 2000 dòng). Mỗi lần gọi tạo cursor
 *    mới nên luôn thấy dữ liệu mới nhất. Dùng PaginationCursor (cursor cho UI, 200.000 cursor/ngày) thay vì
 *    Database.Cursor (10.000 cursor/ngày, dùng chung với xử lý nền).
 * Owner: Dev C
 */
public inherited sharing class SR_ReturnRequestSelector {

    // Một trang kết quả: tổng số dòng khớp điều kiện và các dòng của trang
    public class RecordPage {
        public Integer total = 0;
        public List<Return_Request__c> records = new List<Return_Request__c>();
    }

    // Điều kiện lọc hàng chờ duyệt (D.2). Service điền sẵn giá trị mặc định trước khi gọi.
    public class QueueCriteria {
        public String status;
        public Date fromDate;                  // từ 00:00 ngày này
        public Date toDate;                    // đến hết ngày này
        public Id storeId;                     // null = mọi cửa hàng
        public Id approverId;                  // null = mọi người duyệt
        public Schema.SObjectField orderBy;
        public Boolean descending = false;
        public Integer pageSize;
        public Integer position = 0;           // vị trí dòng đầu trang, tính từ 0
    }

    // ---------- Portal: khách vãng lai (SYSTEM_MODE, sharing theo class gọi) ----------
    // Guest không có quyền object nào; API 68 không ghi mode thì chạy USER_MODE nên phải ghi rõ SYSTEM_MODE.
    // SYSTEM_MODE vẫn theo từ khóa sharing của class gọi (SR_PortalService: without sharing).

    // Kèm SĐT của khách để đối chiếu 4 số cuối
    public static List<Return_Request__c> selectByNameWithPhone(String requestNumber) {
        return [
            SELECT Id, Account__r.Phone FROM Return_Request__c WHERE Name = :requestNumber
            WITH SYSTEM_MODE LIMIT 1
        ];
    }

    // Chỉ các field Portal được hiện (BR-17): trạng thái, lịch sử, tên + số lượng sản phẩm.
    // Thời điểm đổi trạng thái lấy theo Changed_At__c; dòng lịch sử cũ chưa có thì dùng CreatedDate.
    // Khách đăng nhập chỉ tới đây sau khi isSharedWithMe đã kiểm tra quyền.
    public static Return_Request__c selectPortalDetail(Id requestId) {
        return [
            SELECT Id, Name, Status__c,
                   (SELECT Id, Order_Product__r.Product2.Name, Quantity__c FROM Return_Request_Lines__r ORDER BY Name),
                   (SELECT Id, To_Status__c, Changed_At__c, CreatedDate FROM Return_Request_Histories__r
                    ORDER BY Changed_At__c NULLS LAST, CreatedDate, Name)
            FROM Return_Request__c WHERE Id = :requestId
            WITH SYSTEM_MODE
        ];
    }

    // ---------- Trang yêu cầu (D.3): USER_MODE ----------

    // Trạng thái hiện tại, để kiểm tra trước khi bấm Nhận hàng / Hủy
    public static Return_Request__c selectById(Id requestId) {
        return [
            SELECT Id, Name, Status__c FROM Return_Request__c WHERE Id = :requestId WITH USER_MODE
        ];
    }

    public static Map<Id, Return_Request__c> selectByIds(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }
        return new Map<Id, Return_Request__c>([
            SELECT Id, Name, Status__c, Approval_Level__c, Assigned_Approver__c,
                Submitted_At__c, Approval_Due_At__c, Rejection_Reason__c,
                Estimated_Refund__c, Actual_Refund__c, Version_Token__c, LastModifiedDate,
                Store__r.Store_Manager__c, Store__r.Regional_Manager__c
            FROM Return_Request__c WHERE Id IN :requestIds
            WITH USER_MODE
        ]);
    }

    // Yêu cầu kèm các dòng để kiểm định; LastModifiedDate để tính versionToken cho SR_InspectionService
    public static Return_Request__c selectForInspection(Id requestId) {
        return [
            SELECT Id, Name, Status__c, LastModifiedDate,
                   (SELECT Id, Order_Product__r.Product2.Name, Order_Product__r.Product2.ProductCode, Quantity__c,
                           Reason__c, Declared_Condition__c, Actual_Condition__c, Estimated_Refund__c, Actual_Refund__c,
                           Inspection_Result__c, Inspection_Note__c
                    FROM Return_Request_Lines__r ORDER BY Name)
            FROM Return_Request__c WHERE Id = :requestId
            WITH USER_MODE
        ];
    }

    // ---------- Portal: khách đăng nhập (luôn with sharing) ----------

    public static RecordPage selectSharedWithMe(Integer pageSize, Integer position) {
        return new SharedWithMe().page(pageSize, position);
    }

    public static Boolean isSharedWithMe(Id requestId) {
        return new SharedWithMe().contains(requestId);
    }

    // ---------- Màn hình duyệt: USER_MODE, chỉ thấy yêu cầu và field được phép xem (BR-16) ----------

    public static RecordPage selectApprovalQueue(QueueCriteria c) {
        Map<String, Object> binds = new Map<String, Object>();
        String soql = 'SELECT Id, Name, Status__c, Account__r.Name, Account__r.Risk_Flag__c, Store__r.Name, Channel__c, ' +
            'Estimated_Refund__c, Approval_Level__c, Assigned_Approver__r.Name, Submitted_At__c, ' +
            'Approval_Due_At__c, LastModifiedDate FROM Return_Request__c' + queueWhere(c, binds) +
            ' ORDER BY ' + c.orderBy.getDescribe().getName() + (c.descending ? ' DESC' : ' ASC') + ' NULLS LAST' +
            maxRows();
        return fetchPage(Database.getPaginationCursorWithBinds(soql, binds, AccessLevel.USER_MODE), c.position, c.pageSize);
    }

    private static String queueWhere(QueueCriteria c, Map<String, Object> binds) {
        binds.put('status', c.status);
        binds.put('fromDt', Datetime.newInstance(c.fromDate, Time.newInstance(0, 0, 0, 0)));
        binds.put('toDt', Datetime.newInstance(c.toDate.addDays(1), Time.newInstance(0, 0, 0, 0)));
        String whereClause = ' WHERE Status__c = :status AND CreatedDate >= :fromDt AND CreatedDate < :toDt';
        if (c.storeId != null) {
            whereClause += ' AND Store__c = :storeId';
            binds.put('storeId', c.storeId);
        }
        if (c.approverId != null) {
            whereClause += ' AND Assigned_Approver__c = :approverId';
            binds.put('approverId', c.approverId);
        }
        return whereClause;
    }

    // ---------- Phân trang ----------

    // Một PaginationCursor chứa tối đa 100.000 dòng: giới hạn sẵn để danh sách quá dài không làm lỗi trang
    private static String maxRows() {
        return ' LIMIT ' + Limits.getLimitApexPaginationCursorRows();
    }

    // Lấy 1 trang từ cursor; trang nằm ngoài số dòng hiện có thì trả rỗng.
    // fetchPage báo lỗi nếu đọc quá dòng cuối, nên trang cuối chỉ lấy phần còn lại.
    private static RecordPage fetchPage(Database.PaginationCursor cursor, Integer position, Integer pageSize) {
        RecordPage p = new RecordPage();
        p.total = cursor.getNumRecords();
        if (position >= 0 && position < p.total) {
            for (SObject row : cursor.fetchPage(position, Math.min(pageSize, p.total - position)).getRecords()) {
                p.records.add((Return_Request__c) row);
            }
        }
        return p;
    }

    // Sharing Set: Account của User = Account__c của yêu cầu
    private with sharing class SharedWithMe {

        public RecordPage page(Integer pageSize, Integer position) {
            Database.PaginationCursor cursor = Database.getPaginationCursor(
                'SELECT Id, Name, CreatedDate, Status__c, Estimated_Refund__c, Actual_Refund__c' +
                ' FROM Return_Request__c ORDER BY CreatedDate DESC' + maxRows(), AccessLevel.USER_MODE);
            return fetchPage(cursor, position, pageSize);
        }

        public Boolean contains(Id requestId) {
            return ![SELECT Id FROM Return_Request__c WHERE Id = :requestId WITH USER_MODE].isEmpty();
        }
    }

    public static Map<Id, Decimal> sumReservedQuantity(Set<Id> orderItemIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (orderItemIds == null || orderItemIds.isEmpty()) return result;
        for (AggregateResult ar : [
            SELECT Order_Product__c orderItemId, SUM(Quantity__c) qty
            FROM Return_Request_Line__c
            WHERE Order_Product__c IN :orderItemIds
              AND Return_Request__r.Status__c NOT IN :SR_ReturnRequestConstants.getReservationExcludedStatuses()
            GROUP BY Order_Product__c
        ]) result.put((Id) ar.get('orderItemId'), (Decimal) ar.get('qty'));
        return result;
    }

    public class RiskAggregate {
        public Integer requestCount;
        public Decimal totalAmount;
    }

    public static Map<String, Return_Request__c> selectByExternalIds(Set<String> externalIds) {
        Map<String, Return_Request__c> result = new Map<String, Return_Request__c>();
        if (externalIds == null || externalIds.isEmpty()) {
            return result;
        }
        for (Return_Request__c row : [
            SELECT Id, Name, Status__c, Approval_Level__c, Estimated_Refund__c, External_Request_Id__c,
                (SELECT Id, Order_Product__c, Product__r.ProductCode, Quantity__c,
                        Unit_Price__c, Refund_Rate__c, Estimated_Refund__c
                 FROM Return_Request_Lines__r)
            FROM Return_Request__c
            WHERE External_Request_Id__c IN :externalIds
        ]) {
            result.put(row.External_Request_Id__c, row);
        }
        return result;
    }

    public static Map<Id, RiskAggregate> aggregateRisk(Set<Id> accountIds, Datetime since) {
        Map<Id, RiskAggregate> result = new Map<Id, RiskAggregate>();
        if (accountIds == null || accountIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Account__c accountId, COUNT(Id) requestCount, SUM(Estimated_Refund__c) totalAmount
            FROM Return_Request__c
            WHERE Account__c IN :accountIds
              AND Status__c != :SR_ReturnRequestConstants.STATUS_CANCELLED
              AND CreatedDate >= :since
            GROUP BY Account__c
        ]) {
            RiskAggregate aggregate = new RiskAggregate();
            aggregate.requestCount = (Integer) ar.get('requestCount');
            aggregate.totalAmount = (Decimal) ar.get('totalAmount');
            result.put((Id) ar.get('accountId'), aggregate);
        }
        return result;
    }

    /**
     * Loads approval records and optionally locks them before a decision.
     *
     * The true branch deliberately uses SYSTEM_MODE because approval validation
     * must evaluate the canonical status, assigned approver, creator and version
     * token while holding a row lock. Missing FLS must not turn a valid record into
     * a false "not found" result or permit a concurrent overwrite. The false branch
     * uses USER_MODE because an unlocked result can be used in a user-visible flow.
     */
    public static Map<Id, Return_Request__c> selectForApprovalDecision(
        Set<Id> requestIds,
        Boolean forUpdate
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }

        String soql =
            'SELECT Id, Name, Status__c, Channel__c, Approval_Level__c, '
            + 'Assigned_Approver__c, CreatedById, Submitted_At__c, '
            + 'Approval_Due_At__c, Rejection_Reason__c, Version_Token__c, '
            + 'LastModifiedDate, Store__c '
            + 'FROM Return_Request__c WHERE Id IN :requestIds'
            + (forUpdate == true ? ' FOR UPDATE' : '');

        return new Map<Id, Return_Request__c>(
            (List<Return_Request__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'requestIds' => requestIds
                },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    public static List<Return_Request__c> selectOverdueChtApprovals(
        Datetime dueBefore,
        Integer requestedLimit,
        Boolean forUpdate
    ) {
        if (dueBefore == null) {
            return new List<Return_Request__c>();
        }

        Integer rowLimit = requestedLimit == null
            ? 200
            : Math.max(1, Math.min(requestedLimit, 2000));

        String pendingStatus = SR_StatusMachine.PENDING_APPROVAL;
        String chtLevel = 'CHT';
        String soql = approvalDecisionBaseQuery()
            + ' WHERE Status__c = :pendingStatus'
            + ' AND Approval_Level__c = :chtLevel'
            + ' AND Approval_Due_At__c != null'
            + ' AND Approval_Due_At__c <= :dueBefore'
            + ' ORDER BY Approval_Due_At__c ASC'
            + ' LIMIT ' + rowLimit
            + (forUpdate == true ? ' FOR UPDATE' : '');

        return (List<Return_Request__c>) Database.query(soql);
    }

    private static String approvalDecisionBaseQuery() {
        return 'SELECT Id, Name, Status__c, Channel__c, Approval_Level__c, '
            + 'Assigned_Approver__c, CreatedById, Estimated_Refund__c, '
            + 'Submitted_At__c, Approval_Due_At__c, Rejection_Reason__c, '
            + 'Version_Token__c, LastModifiedDate, Store__c, '
            + 'Store__r.Store_Manager__c, Store__r.Regional_Manager__c '
            + 'FROM Return_Request__c';
    }

    /**
     * Loads inspection records and optionally locks them before inspection results
     * are persisted.
     *
     * The true branch deliberately uses SYSTEM_MODE because status, completion and
     * optimistic-lock checks must use the canonical record while it is locked.
     * USER_MODE could make the result depend on the inspector's technical FLS and
     * undermine concurrency protection. The false branch uses USER_MODE.
     */
    public static Map<Id, Return_Request__c> selectForInspection(
        Set<Id> requestIds,
        Boolean forUpdate
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }

        String soql =
            'SELECT Id, Name, Status__c, Inspection_Completed_At__c, '
            + 'LastModifiedDate, Version_Token__c '
            + 'FROM Return_Request__c WHERE Id IN :requestIds'
            + (forUpdate == true ? ' FOR UPDATE' : '');

        return new Map<Id, Return_Request__c>(
            (List<Return_Request__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'requestIds' => requestIds },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    /**
     * Loads the persisted line population required to validate a complete
     * inspection submission.
     *
     * SYSTEM_MODE is intentional because every stored line must participate in the
     * completeness and refund calculation checks. Omitting a line because of FLS
     * could allow a partial inspection to be accepted. The calling service remains
     * responsible for authorizing the request and exposing only allowlisted DTOs.
     */
    public static Map<Id, List<Return_Request_Line__c>> selectInspectionLines(
        Set<Id> requestIds
    ) {
        Map<Id, List<Return_Request_Line__c>> result =
            new Map<Id, List<Return_Request_Line__c>>();
        if (requestIds == null || requestIds.isEmpty()) {
            return result;
        }

        List<Return_Request_Line__c> rows =
            (List<Return_Request_Line__c>) Database.queryWithBinds(
                'SELECT Id, Return_Request__c, Quantity__c, Unit_Price__c, '
                + 'Reason__c, Declared_Condition__c, Actual_Condition__c, '
                + 'Refund_Rate__c, Estimated_Refund__c, Actual_Refund__c, '
                + 'Inspection_Result__c, Inspection_Note__c '
                + 'FROM Return_Request_Line__c '
                + 'WHERE Return_Request__c IN :requestIds ORDER BY Id',
                new Map<String, Object>{ 'requestIds' => requestIds },
                AccessLevel.SYSTEM_MODE
            );

        for (Return_Request_Line__c row : rows) {
            if (!result.containsKey(row.Return_Request__c)) {
                result.put(
                    row.Return_Request__c,
                    new List<Return_Request_Line__c>()
                );
            }
            result.get(row.Return_Request__c).add(row);
        }
        return result;
    }

}
