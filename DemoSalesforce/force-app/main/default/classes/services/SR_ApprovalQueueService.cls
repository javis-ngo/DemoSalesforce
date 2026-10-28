/**
 * Nghiệp vụ màn hình duyệt của CHT/QLV (D.2, FR-08): bộ lọc, hàng chờ duyệt, cửa hàng của tôi.
 * Hàng chờ truy vấn ở USER_MODE trong SR_ReturnRequestSelector (BR-16).
 * Hàm duyệt/từ chối thật nằm ở SR_ApprovalService của Dev A.
 * Owner: Dev C
 */
public with sharing class SR_ApprovalQueueService {

    public static final Integer PAGE_SIZE = 50;

    public class Filters {
        public String status;
        public Id storeId;
        public Date fromDate;
        public Date toDate;
        public Boolean onlyMine;
        public String sortBy;      // AMOUNT | WAIT
        public String sortDir;     // asc | desc
        public Integer pageNumber;
    }

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String storeName;
        @AuraEnabled public String channel;
        @AuraEnabled public Decimal estimatedRefund;
        @AuraEnabled public String approvalLevel;
        @AuraEnabled public String approverName;
        @AuraEnabled public Decimal waitingHours;
        @AuraEnabled public Boolean risky;
        @AuraEnabled public Boolean overdue;
        @AuraEnabled public String versionToken; // gửi lại khi duyệt, SR_ApprovalService chống ghi đè (MSG-13)
    }

    public class PageResult {
        @AuraEnabled public List<Row> rows = new List<Row>();
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer pageSize = PAGE_SIZE;
    }

    // 1 dòng đã chọn trên D.2
    public class DecisionItem {
        public Id requestId;
        public String versionToken;
    }

    // Lỗi của 1 dòng; code/params/message theo SR_ErrorDetailDTO để LWC dùng chung msgFromError
    public class DecisionError {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String code;
        @AuraEnabled public List<String> params = new List<String>();
        @AuraEnabled public String message;
    }

    // MSG-11: số thành công / tổng và lý do của từng dòng lỗi
    public class DecisionSummary {
        @AuraEnabled public Integer succeeded = 0;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public List<DecisionError> errors = new List<DecisionError>();
    }

    public class StoreOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String storeCode;
    }

    // Cửa hàng mà người dùng là CHT hoặc QLV (bộ lọc + lọc thông báo realtime)
    public static List<StoreOption> getMyStores() {
        List<StoreOption> result = new List<StoreOption>();
        for (Store__c st : SR_StoreSelector.selectManagedBy(UserInfo.getUserId())) {
            StoreOption o = new StoreOption();
            o.label = st.Store_Code__c + ' – ' + st.Name;
            o.value = st.Id;
            o.storeCode = st.Store_Code__c;
            result.add(o);
        }
        return result;
    }

    public static PageResult getQueue(Filters f) {
        SR_ReturnRequestSelector.RecordPage queue = SR_ReturnRequestSelector.selectApprovalQueue(toCriteria(f));
        PageResult page = new PageResult();
        page.total = queue.total;
        Datetime now = System.now();
        for (Return_Request__c r : queue.records) {
            page.rows.add(toRow(r, now));
        }
        return page;
    }

    // Mặc định: chờ duyệt, 30 ngày gần nhất, chờ lâu nhất lên đầu
    @TestVisible
    private static SR_ReturnRequestSelector.QueueCriteria toCriteria(Filters f) {
        SR_ReturnRequestSelector.QueueCriteria c = new SR_ReturnRequestSelector.QueueCriteria();
        c.status = String.isBlank(f.status) ? SR_ReturnRequestDomain.STATUS_PENDING_APPROVAL : f.status;
        c.fromDate = (f.fromDate == null) ? Date.today().addDays(-30) : f.fromDate;
        c.toDate = (f.toDate == null) ? Date.today() : f.toDate;
        c.storeId = f.storeId;
        c.approverId = (f.onlyMine == true) ? UserInfo.getUserId() : null;
        c.orderBy = (f.sortBy == 'AMOUNT') ? Return_Request__c.Estimated_Refund__c : Return_Request__c.Submitted_At__c;
        c.descending = (f.sortDir == 'desc');
        Integer pageNumber = (f.pageNumber == null || f.pageNumber < 1) ? 1 : f.pageNumber;
        c.pageSize = PAGE_SIZE;
        c.position = (pageNumber - 1) * PAGE_SIZE;
        return c;
    }

    private static Row toRow(Return_Request__c r, Datetime now) {
        Row row = new Row();
        row.id = r.Id;
        row.requestNumber = r.Name;
        row.customerName = r.Account__r?.Name;
        row.storeName = r.Store__r?.Name;
        row.channel = SR_UiUtil.picklistLabel(Return_Request__c.Channel__c, r.Channel__c);
        row.estimatedRefund = r.Estimated_Refund__c;
        row.approvalLevel = r.Approval_Level__c;
        row.approverName = r.Assigned_Approver__r?.Name;
        row.waitingHours = SR_ReturnRequestDomain.waitingHours(r, now);
        row.risky = SR_ReturnRequestDomain.isRiskyCustomer(r);
        row.overdue = SR_ReturnRequestDomain.isApprovalOverdue(r, now);
        row.versionToken = SR_UiUtil.versionTokenOf(r.LastModifiedDate);
        return row;
    }

    // Duyệt / từ chối hàng loạt bằng SR_ApprovalService.decide (Dev A): dòng lỗi không làm hỏng dòng thành công
    public static DecisionSummary decide(List<DecisionItem> items, Boolean approve, String reason) {
        DecisionSummary summary = new DecisionSummary();
        if (items == null || items.isEmpty()) {
            return summary;
        }
        List<SR_ApprovalDecisionDTO> decisions = new List<SR_ApprovalDecisionDTO>();
        for (DecisionItem item : items) {
            SR_ApprovalDecisionDTO d = new SR_ApprovalDecisionDTO();
            d.requestId = item.requestId;
            d.versionToken = item.versionToken;
            d.approve = approve;
            d.reason = reason;
            decisions.add(d);
        }
        List<SR_ActionResultDTO> results = SR_ApprovalService.decide(decisions);
        summary.total = items.size();
        for (Integer i = 0; i < results.size(); i++) {
            SR_ActionResultDTO r = results[i];
            if (r != null && r.success == true) {
                summary.succeeded++;
            } else {
                summary.errors.add(toError(items[i].requestId, r));
            }
        }
        return summary;
    }

    private static DecisionError toError(Id requestId, SR_ActionResultDTO r) {
        DecisionError e = new DecisionError();
        e.requestId = requestId;
        if (r == null) {
            e.code = SR_ErrorCode.INTERNAL_ERROR;
            return e;
        }
        e.requestNumber = r.requestNumber;
        e.code = r.errorCode;
        e.message = r.message;
        if (r.details != null && !r.details.isEmpty() && r.details[0].params != null) {
            e.params = r.details[0].params;
        }
        return e;
    }
}
