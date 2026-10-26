public class SR_CreateLineDTO {
    @AuraEnabled public Id orderItemId;
    @AuraEnabled public String sku;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public String reason;
    @AuraEnabled public String condition;
    @AuraEnabled public Decimal unitPrice;
}
