/**
 * Controller cho Customer Portal (D.4, FR-05, BR-17, NFR-07).
 * Chỉ nhận/trả dữ liệu, nghiệp vụ nằm ở SR_PortalService. Class này không tự truy vấn nên để with sharing;
 * phần without sharing cho khách vãng lai chỉ nằm trong SR_PortalService.
 * Owner: Dev C
 */
public with sharing class SR_PortalController {

    // ---------- Khách vãng lai ----------
    @AuraEnabled
    public static SR_PortalService.LookupResult lookup(String requestNumber, String phoneLast4) {
        try {
            return SR_PortalService.lookup(requestNumber, phoneLast4);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    // ---------- Khách đăng nhập ----------
    @AuraEnabled
    public static List<SR_PortalService.MyRequest> getMyRequests(Integer pageSize, Integer pageNumber) {
        try {
            return SR_PortalService.getMyRequests(pageSize, pageNumber);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }

    @AuraEnabled
    public static SR_PortalService.LookupResult getMyRequestDetail(Id requestId) {
        try {
            return SR_PortalService.getMyRequestDetail(requestId);
        } catch (Exception e) {
            throw SR_UiUtil.auraError(e);
        }
    }
}
