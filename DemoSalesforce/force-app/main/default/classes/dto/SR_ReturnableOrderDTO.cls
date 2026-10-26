public class SR_ReturnableOrderDTO {
    @AuraEnabled public Id orderId;
    @AuraEnabled public String orderNumber;
    @AuraEnabled public String customerName;
    @AuraEnabled public String customerPhone;
    @AuraEnabled public Date purchaseDate;
    @AuraEnabled public Date deliveryDate;
    @AuraEnabled public Id storeId;
    @AuraEnabled public String storeCode;
    @AuraEnabled public String storeName;
    @AuraEnabled public List<SR_ReturnableLineDTO> lines;

    public SR_ReturnableOrderDTO() {
        lines = new List<SR_ReturnableLineDTO>();
    }
}
