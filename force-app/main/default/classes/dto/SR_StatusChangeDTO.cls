public class SR_StatusChangeDTO {
    @AuraEnabled public Id requestId;
    @AuraEnabled public String toStatus;
    @AuraEnabled public String note;
    @AuraEnabled public String rejectionReason;
    @AuraEnabled public String correlationId;
    @AuraEnabled public String versionToken;
}
