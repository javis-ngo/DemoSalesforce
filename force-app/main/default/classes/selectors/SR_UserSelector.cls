public with sharing class SR_UserSelector {
    public static User selectCurrentUser() {
        return [SELECT Id, Store_Code__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    }
}
