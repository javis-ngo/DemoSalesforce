/**
 * Per-request outcome for bulk approval decisions.
 */
public with sharing class SR_DecisionResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public Id requestId;
    @AuraEnabled public String requestNumber;
    @AuraEnabled public String status;
    @AuraEnabled public String versionToken;
    @AuraEnabled public List<SR_ErrorDetailDTO> errors;
    @AuraEnabled public String correlationId;

    public SR_DecisionResultDTO() {
        success = false;
        errors = new List<SR_ErrorDetailDTO>();
    }
}
