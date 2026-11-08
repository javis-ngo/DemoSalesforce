/**
 * Nghiệp vụ Customer Portal (D.4, FR-05, BR-17, NFR-07).
 *  - Khách vãng lai: tra bằng mã yêu cầu + 4 số cuối SĐT. Guest không có quyền trên object,
 *    nên class này chạy without sharing và CHỈ trả trạng thái, lịch sử, tên + số lượng sản phẩm.
 *  - Khách đăng nhập: thấy yêu cầu của mình qua Sharing Set. Phần kiểm tra quyền dùng
 *    SR_ReturnRequestSelector.selectSharedWithMe / isSharedWithMe, luôn chạy with sharing.
 * Owner: Dev C
 */
public without sharing class SR_PortalService {

    public class HistoryItem {
        @AuraEnabled public String key;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String changedAt;
    }

    public class ProductItem {
        @AuraEnabled public String key;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal quantity;
    }

    public class LookupResult {
        @AuraEnabled public Boolean found = false;
        @AuraEnabled public String message;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public List<HistoryItem> history = new List<HistoryItem>();
        @AuraEnabled public List<ProductItem> products = new List<ProductItem>();
    }

    public class MyRequest {
        @AuraEnabled public Id id;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public Decimal amount;
    }

    // ---------- Khách vãng lai ----------
    // Không throw lỗi khi nhập sai: throw sẽ rollback cả bản ghi đếm số lần sai.
    public static LookupResult lookup(String requestNumber, String phoneLast4) {
        String code = (requestNumber == null) ? '' : requestNumber.trim().toUpperCase();
        String last4 = (phoneLast4 == null) ? '' : phoneLast4.trim();
        if (isLocked(code)) {
            return notFound(System.Label.SR_MSG_41);              // sai 5 lần trong 15 phút
        }
        List<Return_Request__c> found = SR_ReturnRequestSelector.selectByNameWithPhone(code);
        if (found.isEmpty() || !SR_ReturnRequestDomain.matchesPhoneLast4(found[0], last4)) {
            Database.insert(SR_LookupAttemptDomain.newFailedAttempt(code), AccessLevel.SYSTEM_MODE);
            return notFound(System.Label.SR_MSG_40);              // cùng một câu cho mọi trường hợp sai
        }
        return detail(found[0].Id);
    }

    // ---------- Khách đăng nhập ----------
    public static List<MyRequest> getMyRequests(Integer pageSize, Integer pageNumber) {
        Integer size = (pageSize == null || pageSize < 1) ? 10 : Math.min(pageSize, 50);
        Integer position = ((pageNumber == null || pageNumber < 1) ? 0 : pageNumber - 1) * size;
        List<MyRequest> result = new List<MyRequest>();
        for (Return_Request__c r : SR_ReturnRequestSelector.selectSharedWithMe(size, position).records) {
            MyRequest m = new MyRequest();
            m.id = r.Id;
            m.requestNumber = r.Name;
            m.createdDate = r.CreatedDate.format('dd/MM/yyyy', 'Asia/Ho_Chi_Minh');
            m.statusLabel = SR_StatusMachine.labelOf(r.Status__c);
            m.amount = SR_ReturnRequestDomain.refundAmount(r);
            result.add(m);
        }
        return result;
    }

    public static LookupResult getMyRequestDetail(Id requestId) {
        if (!SR_ReturnRequestSelector.isSharedWithMe(requestId)) {
            return notFound(System.Label.SR_MSG_40);
        }
        return detail(requestId);
    }

    // ---------- Hàm phụ ----------
    // Chỉ lấy trạng thái, lịch sử, tên + số lượng sản phẩm. KHÔNG lấy số tiền, tên, SĐT (BR-17).
    private static LookupResult detail(Id requestId) {
        Return_Request__c r = SR_ReturnRequestSelector.selectPortalDetail(requestId);
        LookupResult res = new LookupResult();
        res.found = true;
        res.requestNumber = r.Name;
        res.statusLabel = SR_StatusMachine.labelOf(r.Status__c);
        for (Return_Request_History__c h : r.Return_Request_Histories__r) {
            HistoryItem hi = new HistoryItem();
            hi.key = h.Id;
            hi.statusLabel = SR_StatusMachine.labelOf(h.To_Status__c);
            Datetime changedAt = (h.Changed_At__c != null) ? h.Changed_At__c : h.CreatedDate;
            hi.changedAt = changedAt.format('dd/MM/yyyy HH:mm', 'Asia/Ho_Chi_Minh');
            res.history.add(hi);
        }
        for (Return_Request_Line__c l : r.Return_Request_Lines__r) {
            ProductItem pi = new ProductItem();
            pi.key = l.Id;
            pi.name = l.Order_Product__r?.Product2?.Name;
            pi.quantity = l.Quantity__c;
            res.products.add(pi);
        }
        return res;
    }

    private static LookupResult notFound(String message) {
        LookupResult res = new LookupResult();
        res.message = message;
        return res;
    }

    private static Boolean isLocked(String code) {
        SR_Setting__mdt s = SR_Config.setting();
        Datetime since = SR_LookupAttemptDomain.lockWindowStart(s, System.now());
        return SR_LookupAttemptDomain.isLocked(SR_LookupAttemptSelector.countByKeySince(code, since), s);
    }
}
