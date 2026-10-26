public class SR_ApprovalPreviewResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String approvalLevel;
    @AuraEnabled public Id assignedApproverId;
    @AuraEnabled public String targetStatus;
    @AuraEnabled public String errorCode;
    @AuraEnabled public String message;
    @AuraEnabled public Decimal estimatedRefund;
    @AuraEnabled public Boolean riskFlag;
    @AuraEnabled public List<SR_LineCreateResultDTO> lines;
    @AuraEnabled public List<SR_ErrorDetailDTO> errors;

    public SR_ApprovalPreviewResultDTO() {
        success = false;
        lines = new List<SR_LineCreateResultDTO>();
        errors = new List<SR_ErrorDetailDTO>();
    }
}
