public inherited sharing class SR_ReturnRequestSelector {
    public class RecordPage {
        public Integer total = 0;
        public List<Return_Request__c> records = new List<Return_Request__c>();
    }

    public class QueueCriteria {
        public String status;
        public Date fromDate;
        public Date toDate;
        public Id storeId;
        public Id approverId;
        public Schema.SObjectField orderBy;
        public Boolean descending = false;
        public Integer pageSize;
        public Integer position = 0;
    }

    public class RiskAggregate {
        public Integer requestCount;
        public Decimal totalAmount;
    }

    private static final String ACTION_FIELDS =
        'SELECT Id, Name, Status__c, Channel__c, Account__c, Order__c, ' +
        'Store__c, Assigned_Approver__c, Approval_Level__c, CreatedById, ' +
        'Estimated_Refund__c, Actual_Refund__c, Rejection_Reason__c, ' +
        'Inspection_Completed_At__c, LastModifiedDate ' +
        'FROM Return_Request__c';

    /**
     * Returns the quantity already reserved by every non-terminal return request.
     *
     * SYSTEM_MODE is intentional because this aggregate protects a cross-user
     * quantity invariant. The calculation must include reservations created by
     * other users, channels and integration-owned records; applying the current
     * user's CRUD/FLS could fail the query or understate the reserved quantity and
     * allow the total returned quantity to exceed the purchased quantity. Record
     * scope is still controlled by the inherited sharing context of the caller.
     */
    public static Map<Id, Decimal> sumReservedQuantity(Set<Id> orderItemIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (orderItemIds == null || orderItemIds.isEmpty()) {
            return result;
        }
        String soql =
            'SELECT Order_Product__c orderItemId, SUM(Quantity__c) qty ' +
            'FROM Return_Request_Line__c ' +
            'WHERE Order_Product__c IN :orderItemIds ' +
            'AND Return_Request__r.Status__c NOT IN (\'REJECTED\', \'CANCELLED\') ' +
            'GROUP BY Order_Product__c';
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'orderItemIds' => orderItemIds },
            AccessLevel.SYSTEM_MODE
        );
        for (AggregateResult row : rows) {
            result.put(
                (Id) row.get('orderItemId'),
                (Decimal) row.get('qty')
            );
        }
        return result;
    }

    /**
     * Aggregates the canonical risk history for the supplied customer accounts.
     *
     * SYSTEM_MODE is intentional because risk routing must not vary according to
     * which employee or channel creates the next request. USER_MODE could omit
     * requests outside the acting user's object/field permissions and incorrectly
     * bypass regional approval. The inherited sharing context continues to govern
     * record-level scope.
     */
    public static Map<Id, RiskAggregate> aggregateRisk(
        Set<Id> accountIds,
        Datetime sinceValue
    ) {
        Map<Id, RiskAggregate> result = new Map<Id, RiskAggregate>();
        if (accountIds == null || accountIds.isEmpty() || sinceValue == null) {
            return result;
        }
        String soql =
            'SELECT Account__c accountId, COUNT(Id) requestCount, ' +
            'SUM(Estimated_Refund__c) totalAmount ' +
            'FROM Return_Request__c ' +
            'WHERE Account__c IN :accountIds ' +
            'AND Status__c != \'CANCELLED\' ' +
            'AND CreatedDate >= :sinceValue ' +
            'GROUP BY Account__c';
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'accountIds' => accountIds,
                'sinceValue' => sinceValue
            },
            AccessLevel.SYSTEM_MODE
        );
        for (AggregateResult row : rows) {
            RiskAggregate value = new RiskAggregate();
            value.requestCount = (Integer) row.get('requestCount');
            value.totalAmount = (Decimal) row.get('totalAmount');
            result.put((Id) row.get('accountId'), value);
        }
        return result;
    }

    /**
     * Finds existing requests used to enforce external-request idempotency.
     *
     * SYSTEM_MODE is intentional because a duplicate must be detected even when
     * the original request was created by another channel, integration user or
     * store employee. Using USER_MODE could hide the original record and allow a
     * second request with the same external identifier. Only the fields required
     * to return the original idempotent result are selected.
     */
    public static Map<String, Return_Request__c> selectByExternalIdsForIdempotency(
        Set<String> externalIds
    ) {
        Map<String, Return_Request__c> result =
            new Map<String, Return_Request__c>();
        if (externalIds == null || externalIds.isEmpty()) {
            return result;
        }
        String soql =
            'SELECT Id, Name, Status__c, Approval_Level__c, ' +
            'Estimated_Refund__c, External_Request_Id__c, ' +
            '(SELECT Id, Order_Product__c, Product__r.ProductCode, Quantity__c, ' +
            'Unit_Price__c, Refund_Rate__c, Estimated_Refund__c ' +
            'FROM Return_Request_Lines__r) ' +
            'FROM Return_Request__c ' +
            'WHERE External_Request_Id__c IN :externalIds';
        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'externalIds' => externalIds },
                AccessLevel.SYSTEM_MODE
            );
        for (Return_Request__c row : rows) {
            result.put(row.External_Request_Id__c, row);
        }
        return result;
    }

    // Compatibility wrapper retained for the current SR_ReturnRequestService.
    public static Map<String, Return_Request__c> selectByExternalIds(
        Set<String> externalIds
    ) {
        return selectByExternalIdsForIdempotency(externalIds);
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
        return selectActionRecords(requestIds, forUpdate);
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
        return selectActionRecords(requestIds, forUpdate);
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
        String soql =
            'SELECT Id, Return_Request__c, Order_Product__c, Product__c, ' +
            'Quantity__c, Unit_Price__c, Reason__c, Declared_Condition__c, ' +
            'Actual_Condition__c, Refund_Rate__c, Actual_Refund__c, ' +
            'Inspection_Result__c, Inspection_Note__c ' +
            'FROM Return_Request_Line__c ' +
            'WHERE Return_Request__c IN :requestIds ' +
            'ORDER BY Return_Request__c, Name';
        List<Return_Request_Line__c> rows =
            (List<Return_Request_Line__c>) Database.queryWithBinds(
                soql,
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

    /**
     * Reloads the canonical completion state after an authorized inspection write.
     *
     * SYSTEM_MODE is intentional because the refresh follows domain DML that
     * persists workflow-controlled inspection fields using elevated access.
     * Status__c and LastModifiedDate must reflect the final database state
     * regardless of the inspector's direct CRUD or FLS.
     *
     * This method does not authorize access and must only be called for requests
     * that the service has already authorized and successfully processed.
     */
    public static Map<Id, Return_Request__c>
        selectInspectionCompletionState(Set<Id> requestIds) {

        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }

        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                'SELECT Id, Name, Status__c, LastModifiedDate '
                + 'FROM Return_Request__c '
                + 'WHERE Id IN:requestIds',
                new Map<String, Object>{
                    'requestIds' => requestIds
                },
                AccessLevel.SYSTEM_MODE
            );

        return new Map<Id, Return_Request__c>(rows);
    }

    /**
     * Loads and locks canonical Return Request records for a domain operation.
     *
     * SYSTEM_MODE is intentional because cross-user state transitions must inspect
     * and lock all technical fields required by the state machine. The caller must
     * perform operation-specific authorization before DML, and inherited sharing
     * continues to control record-level visibility.
     */
    public static Map<Id, Return_Request__c> selectForUpdate(Set<Id> requestIds) {
        return selectActionRecords(requestIds, true);
    }

    /**
     * Returns the approval work queue in USER_MODE because the records and fields
     * are displayed directly to the current user. Salesforce must enforce sharing,
     * restriction rules, object permissions and FLS for every selected field.
     */
    public static RecordPage selectApprovalQueue(QueueCriteria criteria) {
        if (criteria == null || String.isBlank(criteria.status)) {
            return new RecordPage();
        }
        Integer pageSize = normalizePageSize(criteria.pageSize);
        Integer position = criteria.position == null
            ? 0
            : Math.max(0, criteria.position);
        Date fromDate = criteria.fromDate == null
            ? Date.today().addDays(-30)
            : criteria.fromDate;
        Date toDate = criteria.toDate == null ? Date.today() : criteria.toDate;
        Datetime fromDt = Datetime.newInstance(
            fromDate,
            Time.newInstance(0, 0, 0, 0)
        );
        Datetime toDt = Datetime.newInstance(
            toDate.addDays(1),
            Time.newInstance(0, 0, 0, 0)
        );
        Map<String, Object> binds = new Map<String, Object>{
            'status' => criteria.status,
            'fromDt' => fromDt,
            'toDt' => toDt
        };
        String soql =
            'SELECT Id, Name, Status__c, Account__r.Name, ' +
            'Account__r.Risk_Flag__c, Store__r.Name, Channel__c, ' +
            'Estimated_Refund__c, Approval_Level__c, ' +
            'Assigned_Approver__r.Name, Submitted_At__c, ' +
            'Approval_Due_At__c, LastModifiedDate ' +
            'FROM Return_Request__c ' +
            'WHERE Status__c = :status ' +
            'AND CreatedDate >= :fromDt AND CreatedDate < :toDt';
        if (criteria.storeId != null) {
            soql += ' AND Store__c = :storeId';
            binds.put('storeId', criteria.storeId);
        }
        if (criteria.approverId != null) {
            soql += ' AND Assigned_Approver__c = :approverId';
            binds.put('approverId', criteria.approverId);
        }
        String orderField = criteria.orderBy == null
            ? 'CreatedDate'
            : criteria.orderBy.getDescribe().getName();
        soql += ' ORDER BY ' + orderField;
        soql += criteria.descending == true ? ' DESC' : ' ASC';
        soql += ' NULLS LAST LIMIT ' + Limits.getLimitApexPaginationCursorRows();
        Database.PaginationCursor cursor =
            Database.getPaginationCursorWithBinds(
                soql,
                binds,
                AccessLevel.USER_MODE
            );
        return fetchPage(cursor, position, pageSize);
    }

    /**
     * Returns the current customer's shared requests in USER_MODE because this data
     * is rendered directly in the authenticated portal. Sharing Sets, CRUD, FLS and
     * restriction rules must all be honored.
     */
    public static RecordPage selectSharedWithMe(Integer pageSize, Integer position) {
        String soql =
            'SELECT Id, Name, CreatedDate, Status__c, ' +
            'Estimated_Refund__c, Actual_Refund__c ' +
            'FROM Return_Request__c ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT ' + Limits.getLimitApexPaginationCursorRows();
        Database.PaginationCursor cursor =
            Database.getPaginationCursorWithBinds(
                soql,
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            );
        return fetchPage(
            cursor,
            position == null ? 0 : Math.max(0, position),
            normalizePageSize(pageSize)
        );
    }

    /**
     * Returns an allowlisted portal detail in USER_MODE because the result is
     * displayed directly to the current customer. The query intentionally excludes
     * customer identity, internal notes and refund-operational fields.
     */
    public static Return_Request__c selectPortalDetail(Id requestId) {
        if (requestId == null) {
            return null;
        }
        String soql =
            'SELECT Id, Name, Status__c, ' +
            '(SELECT Id, Product__r.Name, Quantity__c ' +
            'FROM Return_Request_Lines__r ORDER BY Name), ' +
            '(SELECT Id, To_Status__c, Changed_At__c ' +
            'FROM Return_Request_Histories__r ' +
            'ORDER BY Changed_At__c, Name) ' +
            'FROM Return_Request__c WHERE Id = :requestId LIMIT 1';
        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'requestId' => requestId },
                AccessLevel.USER_MODE
            );
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Searches customer-service-visible request data in USER_MODE because the
     * results are rendered directly to a CSKH user. CRUD, FLS, record sharing and
     * restriction rules must determine both searchable fields and returned rows.
     */
    public static List<Return_Request__c> searchForCustomerService(
        String searchTerm,
        Integer maximumRows
    ) {
        if (String.isBlank(searchTerm)) {
            return new List<Return_Request__c>();
        }
        Integer rowLimit = maximumRows == null
            ? 50
            : Math.max(1, Math.min(maximumRows, 200));
        String likeTerm = '%' + searchTerm.trim() + '%';
        String soql =
            'SELECT Id, Name, CreatedDate, Status__c, Channel__c, ' +
            'Account__r.Name, Account__r.Phone, Order__r.OrderNumber, ' +
            'Store__r.Name, Estimated_Refund__c, Actual_Refund__c, ' +
            'Approval_Level__c, Assigned_Approver__r.Name, LastModifiedDate ' +
            'FROM Return_Request__c ' +
            'WHERE Name LIKE :likeTerm ' +
            'OR Account__r.Name LIKE :likeTerm ' +
            'OR Account__r.Phone LIKE :likeTerm ' +
            'OR Order__r.OrderNumber LIKE :likeTerm ' +
            'ORDER BY CreatedDate DESC LIMIT :rowLimit';
        return (List<Return_Request__c>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'likeTerm' => likeTerm,
                'rowLimit' => rowLimit
            },
            AccessLevel.USER_MODE
        );
    }

    public static Boolean isSharedWithMe(Id requestId) {
        if (requestId == null) {
            return false;
        }
        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                'SELECT Id FROM Return_Request__c ' +
                'WHERE Id = :requestId LIMIT 1',
                new Map<String, Object>{ 'requestId' => requestId },
                AccessLevel.USER_MODE
            );
        return !rows.isEmpty();
    }

    public static Map<Id, Return_Request__c> selectByIds(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }
        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                ACTION_FIELDS + ' WHERE Id IN :requestIds',
                new Map<String, Object>{ 'requestIds' => requestIds },
                AccessLevel.USER_MODE
            );
        return new Map<Id, Return_Request__c>(rows);
    }

    private static Map<Id, Return_Request__c> selectActionRecords(
        Set<Id> requestIds,
        Boolean forUpdate
    ) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Return_Request__c>();
        }
        String soql = ACTION_FIELDS + ' WHERE Id IN :requestIds';
        AccessLevel mode = AccessLevel.USER_MODE;
        if (forUpdate == true) {
            soql += ' FOR UPDATE';
            mode = AccessLevel.SYSTEM_MODE;
        }
        List<Return_Request__c> rows =
            (List<Return_Request__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'requestIds' => requestIds },
                mode
            );
        return new Map<Id, Return_Request__c>(rows);
    }

    private static RecordPage fetchPage(
        Database.PaginationCursor cursor,
        Integer position,
        Integer pageSize
    ) {
        RecordPage page = new RecordPage();
        page.total = cursor.getNumRecords();
        if (position >= 0 && position < page.total) {
            Integer remaining = page.total - position;
            Integer fetchSize = Math.min(pageSize, remaining);
            for (SObject row : cursor.fetchPage(position, fetchSize).getRecords()) {
                page.records.add((Return_Request__c) row);
            }
        }
        return page;
    }

    private static Integer normalizePageSize(Integer pageSize) {
        if (pageSize == null) {
            return 25;
        }
        return Math.max(1, Math.min(pageSize, 200));
    }
}
