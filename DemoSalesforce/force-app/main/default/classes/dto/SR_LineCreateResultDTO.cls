public class SR_LineCreateResultDTO {
    @AuraEnabled public Id lineId;
    @AuraEnabled public Id orderItemId;
    @AuraEnabled public String sku;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal unitPrice;
    @AuraEnabled public Decimal refundRate;
    @AuraEnabled public Decimal refundAmount;
}
