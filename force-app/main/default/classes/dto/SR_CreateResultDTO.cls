public class SR_CreateResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public Boolean isDuplicate;
    @AuraEnabled public Id requestId;
    @AuraEnabled public String requestNumber;
    @AuraEnabled public String status;
    @AuraEnabled public String approvalLevel;
    @AuraEnabled public Decimal estimatedRefund;
    @AuraEnabled public List<SR_LineCreateResultDTO> lines;
    @AuraEnabled public List<SR_ErrorDetailDTO> errors;
    @AuraEnabled public String correlationId;

    public SR_CreateResultDTO() {
        success = false;
        isDuplicate = false;
        lines = new List<SR_LineCreateResultDTO>();
        errors = new List<SR_ErrorDetailDTO>();
        correlationId = SR_Correlation.newId();
    }
}
