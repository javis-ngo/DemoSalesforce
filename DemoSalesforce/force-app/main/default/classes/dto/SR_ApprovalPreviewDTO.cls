public class SR_ApprovalPreviewDTO {
    @AuraEnabled public Id accountId;
    @AuraEnabled public Boolean riskFlag;
    @AuraEnabled public List<SR_ApprovalPreviewLineDTO> lines;
    @AuraEnabled public Decimal estimatedRefund;
    @AuraEnabled public String channel;
    @AuraEnabled public Id storeId;
}
