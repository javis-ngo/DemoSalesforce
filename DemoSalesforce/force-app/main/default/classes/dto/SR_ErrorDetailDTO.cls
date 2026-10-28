/**
 * Machine-readable error attached to one request or product line.
 * params follows the placeholder order of the mapped Custom Label.
 */
public with sharing class SR_ErrorDetailDTO {
    @AuraEnabled public String sku;
    @AuraEnabled public String reference;
    @AuraEnabled public String code;
    @AuraEnabled public List<String> params;
    @AuraEnabled public String message;

    public SR_ErrorDetailDTO() {
        params = new List<String>();
    }

    public SR_ErrorDetailDTO(
        String sku,
        String code,
        List<String> params
    ) {
        this.sku = sku;
        this.reference = sku;
        this.code = code;
        this.params = params == null ? new List<String>() : params;
    }

    public SR_ErrorDetailDTO(String sku, String code, String message) {
        this.sku = sku;
        this.reference = sku;
        this.code = code;
        this.params = new List<String>();
        this.message = message;
    }
}
