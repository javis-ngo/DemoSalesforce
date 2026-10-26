/**
 * Selector cho Store__c. "inherited sharing": chạy theo sharing của class gọi.
 */
public inherited sharing class SR_StoreSelector {

    // Cửa hàng mà người dùng là CHT hoặc QLV
    public static List<Store__c> selectManagedBy(Id userId) {
        return [
            SELECT Id, Name, Store_Code__c FROM Store__c
            WHERE Store_Manager__c = :userId OR Regional_Manager__c = :userId
            WITH USER_MODE
            ORDER BY Store_Code__c
        ];
    }

    public static Map<Id, Store__c> selectByIds(Set<Id> storeIds) {
        if (storeIds == null || storeIds.isEmpty()) {
            return new Map<Id, Store__c>();
        }

        String soql =
            'SELECT Id, Name, Store_Code__c, Region__c, '
            + 'Store_Manager__c, Regional_Manager__c '
            + 'FROM Store__c WHERE Id IN :storeIds';

        return new Map<Id, Store__c>(
            (List<Store__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'storeIds' => storeIds
                },
                AccessLevel.USER_MODE
            )
        );
    }

    public static Map<String, Store__c> selectByCodes(Set<String> storeCodes) {
        Map<String, Store__c> result = new Map<String, Store__c>();
        if (storeCodes == null || storeCodes.isEmpty()) return result;
        for (Store__c row : [
            SELECT Id, Name, Store_Code__c, Store_Manager__c, Regional_Manager__c
            FROM Store__c WHERE Store_Code__c IN :storeCodes
        ]) result.put(row.Store_Code__c, row);
        return result;
    }
}