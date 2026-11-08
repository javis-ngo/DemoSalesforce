public with sharing class SR_OrderSelector {
    private static final String BASE_QUERY =
        'SELECT Id, OrderNumber, AccountId, Account.Name, Account.Phone, ' +
        'Account.Risk_Flag__c, EffectiveDate, Delivery_Date__c, ' +
        'Store__c, Store__r.Name, Store__r.Store_Code__c, ' +
        'Store__r.Store_Manager__c, Store__r.Regional_Manager__c, ' +
        '(SELECT Id, Product2Id, Product2.Name, Product2.ProductCode, ' +
        'Product2.Family, Quantity, UnitPrice FROM OrderItems) ' +
        'FROM Order';

    /**
     * Returns orders by Id without changing the existing service contract.
     *
     * When forUpdate is false, the query runs in USER_MODE because the result can
     * be used to build user-visible returnable-order data. CRUD, FLS, sharing and
     * restriction rules must therefore be enforced by Salesforce.
     *
     * When forUpdate is true, the method delegates to the business-invariant path.
     * That path deliberately uses SYSTEM_MODE so validation and record locking are
     * not made incomplete by missing field permissions on technical routing,
     * customer-risk or order-line fields. The class remains with sharing, so the
     * caller's record-level sharing scope is still enforced.
     */
    public static Map<Id, Order> selectByIds(Set<Id> orderIds, Boolean forUpdate) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new Map<Id, Order>();
        }
        if (forUpdate == true) {
            return selectForUpdate(orderIds);
        }
        Map<String, Object> binds = new Map<String, Object>{
            'orderIds' => orderIds
        };
        List<Order> rows = (List<Order>) Database.queryWithBinds(
            BASE_QUERY + ' WHERE Id IN :orderIds',
            binds,
            AccessLevel.USER_MODE
        );
        return new Map<Id, Order>(rows);
    }

    /**
     * Returns orders by OrderNumber without changing the existing service contract.
     *
     * A non-locking call runs in USER_MODE because it can contribute to a response
     * shown to the current user. A locking call runs in SYSTEM_MODE for the same
     * business-invariant reason documented on selectForUpdate: the return workflow
     * must validate and lock a complete canonical order graph before calculating
     * eligibility, reserved quantity and refund amounts.
     */
    public static Map<String, Order> selectByNumbers(
        Set<String> orderNumbers,
        Boolean forUpdate
    ) {
        Map<String, Order> result = new Map<String, Order>();
        if (orderNumbers == null || orderNumbers.isEmpty()) {
            return result;
        }
        Map<String, Object> binds = new Map<String, Object>{
            'orderNumbers' => orderNumbers
        };
        String soql = BASE_QUERY + ' WHERE OrderNumber IN :orderNumbers';
        AccessLevel mode = AccessLevel.USER_MODE;
        if (forUpdate == true) {
            soql += ' FOR UPDATE';
            mode = AccessLevel.SYSTEM_MODE;
        }
        for (Order row : (List<Order>) Database.queryWithBinds(soql, binds, mode)) {
            result.put(row.OrderNumber, row);
        }
        return result;
    }

    /**
     * Loads and locks the canonical Order records used by return validation.
     *
     * SYSTEM_MODE is intentional. Eligibility, quantity and refund calculations
     * must use the complete order graph even when the acting user does not have FLS
     * for internal fields such as risk or approval-routing data. Running this query
     * in USER_MODE could produce a permission failure or an incomplete validation
     * result and allow conflicting return transactions. This class is declared
     * with sharing, so SYSTEM_MODE bypasses CRUD/FLS only; record-level access is
     * still governed by the caller's sharing context.
     */
    public static Map<Id, Order> selectForUpdate(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new Map<Id, Order>();
        }
        List<Order> rows = (List<Order>) Database.queryWithBinds(
            BASE_QUERY + ' WHERE Id IN :orderIds FOR UPDATE',
            new Map<String, Object>{ 'orderIds' => orderIds },
            AccessLevel.SYSTEM_MODE
        );
        return new Map<Id, Order>(rows);
    }
}
