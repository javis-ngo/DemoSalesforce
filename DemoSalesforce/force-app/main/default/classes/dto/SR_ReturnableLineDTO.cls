public class SR_ReturnableLineDTO {
    @AuraEnabled public Id orderId;
    @AuraEnabled public String orderNumber;
    @AuraEnabled public String customerName;
    @AuraEnabled public String customerPhone;
    @AuraEnabled public Date purchaseDate;
    @AuraEnabled public Date deliveryDate;
    @AuraEnabled public Id storeId;
    @AuraEnabled public String storeCode;
    @AuraEnabled public String storeName;

    @AuraEnabled public Id orderItemId;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String sku;
    @AuraEnabled public String category;
    @AuraEnabled public Decimal unitPrice;
    @AuraEnabled public Decimal purchasedQuantity;
    @AuraEnabled public Decimal previouslyReturnedQuantity;
    @AuraEnabled public Decimal returnableQuantity;
    @AuraEnabled public Date returnDeadline;
    @AuraEnabled public Boolean eligible;
    @AuraEnabled public String lockCode;
    @AuraEnabled public String lockMessage;
}
