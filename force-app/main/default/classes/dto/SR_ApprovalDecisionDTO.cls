public class SR_ApprovalDecisionDTO {
    @AuraEnabled public Id requestId;
    @AuraEnabled public Boolean approve;
    @AuraEnabled public String reason;
    @AuraEnabled public String versionToken;
}
