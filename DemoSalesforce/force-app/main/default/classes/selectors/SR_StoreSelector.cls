public with sharing class SR_StoreSelector {
    private static final String BASE_QUERY =
        'SELECT Id, Name, Store_Code__c, Region__c, ' +
        'Store_Manager__c, Regional_Manager__c ' +
        'FROM Store__c';

    /**
     * Loads stores used by approval preview and routing.
     *
     * SYSTEM_MODE is intentional because Store_Manager__c and
     * Regional_Manager__c are internal routing fields. The return workflow must
     * resolve the same approver regardless of whether the initiating employee has
     * direct FLS to those fields. The class remains with sharing, so record-level
     * visibility is still enforced. Callers must validate that a supplied store Id
     * belongs to the current order, user store or managed region before acting on
     * the returned record.
     */
    public static Map<Id, Store__c> selectByIds(Set<Id> storeIds) {
        if (storeIds == null || storeIds.isEmpty()) {
            return new Map<Id, Store__c>();
        }
        List<Store__c> rows = (List<Store__c>) Database.queryWithBinds(
            BASE_QUERY + ' WHERE Id IN :storeIds',
            new Map<String, Object>{ 'storeIds' => storeIds },
            AccessLevel.SYSTEM_MODE
        );
        return new Map<Id, Store__c>(rows);
    }

    /**
     * Loads stores by their external business code for deterministic store
     * resolution during request creation.
     *
     * SYSTEM_MODE is intentional because store resolution and approver routing are
     * business invariants. Missing FLS on routing fields must not change which
     * store or approver the domain service selects. Record-level sharing continues
     * to be enforced by this class's with sharing declaration, and the service must
     * still reject a client-supplied store code that is outside the caller's
     * authorized order, store, region or integration scope.
     */
    public static Map<String, Store__c> selectByCodes(Set<String> storeCodes) {
        Map<String, Store__c> result = new Map<String, Store__c>();
        if (storeCodes == null || storeCodes.isEmpty()) {
            return result;
        }
        List<Store__c> rows = (List<Store__c>) Database.queryWithBinds(
            BASE_QUERY + ' WHERE Store_Code__c IN :storeCodes',
            new Map<String, Object>{ 'storeCodes' => storeCodes },
            AccessLevel.SYSTEM_MODE
        );
        for (Store__c row : rows) {
            result.put(row.Store_Code__c, row);
        }
        return result;
    }

    /**
     * Locks Store records for a domain operation that must prevent concurrent
     * routing or store-configuration changes.
     *
     * SYSTEM_MODE is intentional because the lock protects a cross-user business
     * invariant. Technical routing fields must remain available while the lock is
     * held even when the acting user does not have direct CRUD/FLS permission for
     * those fields. The with sharing declaration still controls record scope.
     */
    public static Map<Id, Store__c> selectForUpdate(Set<Id> storeIds) {
        if (storeIds == null || storeIds.isEmpty()) {
            return new Map<Id, Store__c>();
        }
        List<Store__c> rows = (List<Store__c>) Database.queryWithBinds(
            BASE_QUERY + ' WHERE Id IN :storeIds FOR UPDATE',
            new Map<String, Object>{ 'storeIds' => storeIds },
            AccessLevel.SYSTEM_MODE
        );
        return new Map<Id, Store__c>(rows);
    }
}
