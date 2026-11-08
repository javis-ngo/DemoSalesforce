public class SR_ApprovalPreviewLineDTO {
    @AuraEnabled public Id orderItemId;
    @AuraEnabled public String sku;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal unitPrice;
    @AuraEnabled public String reason;
    @AuraEnabled public String condition;
}
