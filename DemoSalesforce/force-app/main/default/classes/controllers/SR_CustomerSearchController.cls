/**
 * D.5 – Ô tìm kiếm cho CSKH (FR-17, FR-18), LWC srCustomerSearch. Xử lý ở SR_CustomerSearchService.
 * Owner: Dev B
 */
public with sharing class SR_CustomerSearchController {

    @AuraEnabled(cacheable=true)
    public static List<SR_CustomerSearchService.ResultGroup> searchAll(String term) {
        try {
            return SR_CustomerSearchService.searchAll(term);
        } catch (Exception e) {
            throw SR_Util.auraError(e);
        }
    }
}
