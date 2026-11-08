public class SR_CreateRequestDTO {
    @AuraEnabled public String externalRequestId;
    @AuraEnabled public String channel;
    @AuraEnabled public Id orderId;
    @AuraEnabled public String orderNumber;
    @AuraEnabled public String customerPhone;
    @AuraEnabled public String storeCode;
    @AuraEnabled public Boolean riskFlag;
    @AuraEnabled public List<SR_CreateLineDTO> lines;
    @AuraEnabled public Boolean atomicMode;
}
