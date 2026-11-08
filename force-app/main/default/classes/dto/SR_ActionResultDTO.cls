public inherited sharing class SR_ActionResultDTO {
    @AuraEnabled
    public Boolean success { get; set; }
    

    @AuraEnabled
    public Id recordId { get; set; }

    @AuraEnabled
    public String requestNumber { get; set; }

    @AuraEnabled
    public String status { get; set; }

    @AuraEnabled
    public String errorCode { get; set; }

    @AuraEnabled
    public String message { get; set; }

    @AuraEnabled
    public List<SR_ErrorDetailDTO> details { get; set; }

    @AuraEnabled
    public String correlationId { get; set; }

    @AuraEnabled
    public String versionToken { get; set; }

    public SR_ActionResultDTO() {
        this.success = false;
        this.details = new List<SR_ErrorDetailDTO>();
    }

    public static SR_ActionResultDTO successResult(
        Id recordId,
        String requestNumber,
        String status,
        String versionToken
    ) {
        SR_ActionResultDTO result = new SR_ActionResultDTO();
        result.success = true;
        result.recordId = recordId;
        result.requestNumber = requestNumber;
        result.status = status;
        result.versionToken = versionToken;
        return result;
    }

    public static SR_ActionResultDTO errorResult(
        Id recordId,
        String requestNumber,
        String errorCode,
        String message,
        String correlationId,
        List<SR_ErrorDetailDTO> details
    ) {
        SR_ActionResultDTO result = new SR_ActionResultDTO();
        result.success = false;
        result.recordId = recordId;
        result.requestNumber = requestNumber;
        result.errorCode = errorCode;
        result.message = message;
        result.correlationId = correlationId;
        result.details = details == null
            ? new List<SR_ErrorDetailDTO>()
            : details;
        return result;
    }
}