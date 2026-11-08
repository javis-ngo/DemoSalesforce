public class SR_InspectionRequestDTO {
    @AuraEnabled public Id requestId;
    @AuraEnabled public String versionToken;
    @AuraEnabled public List<SR_InspectionLineDTO> lines;

    public SR_InspectionRequestDTO() {
        lines = new List<SR_InspectionLineDTO>();
    }
}
