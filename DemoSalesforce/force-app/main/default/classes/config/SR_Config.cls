public with sharing class SR_Config {
    private static final String DEFAULT_SETTING = 'Default';
    private static final String CONFIGURATION_ERROR = 'CONFIGURATION_ERROR';
    private static final String KEY_SEPARATOR = '|';

    public interface Provider {
        SR_Setting__mdt getSetting(String developerName);
        Map<String, SR_Category_Policy__mdt> getCategoryPolicies();
        Map<String, SR_Refund_Rate__mdt> getRefundRates();
    }

    private class MetadataProvider implements Provider {
        public SR_Setting__mdt getSetting(String developerName) {
            return SR_Setting__mdt.getInstance(developerName);
        }

        public Map<String, SR_Category_Policy__mdt> getCategoryPolicies() {
            return SR_Category_Policy__mdt.getAll();
        }

        public Map<String, SR_Refund_Rate__mdt> getRefundRates() {
            return SR_Refund_Rate__mdt.getAll();
        }
    }

    public class CategoryPolicy {
        public String productFamily { get; private set; }
        public Boolean isReturnable { get; private set; }
        public Integer returnWindowDays { get; private set; }

        private CategoryPolicy(SR_Category_Policy__mdt source) {
            productFamily = source.Product_Family__c;
            isReturnable = source.Is_Returnable__c;
            returnWindowDays = source.Return_Window_Days__c == null
                ? null
                : source.Return_Window_Days__c.intValue();
        }
    }

    @TestVisible
    private static Provider provider = new MetadataProvider();
    @TestVisible
    private static Map<String, Object> overrides = new Map<String, Object>();
    @TestVisible
    private static Map<String, SR_CategoryPolicy> categoryOverrides;
    @TestVisible
    private static Map<String, Decimal> refundRateOverrides;
    private static SR_Setting__mdt settingCache;
    private static Map<String, CategoryPolicy> categoryCache;
    private static Map<String, SR_CategoryPolicy> domainCategoryCache;
    private static Map<String, Decimal> refundRateCache;

    public static Decimal autoApprovalThreshold() {
        return setting().Auto_Approval_Threshold__c;
    }

    public static Decimal storeManagerMaxThreshold() {
        return setting().Store_Manager_Max_Threshold__c;
    }

    public static Integer riskRequestCount() {
        return setting().Risk_Request_Count__c.intValue();
    }

    public static Decimal riskTotalAmount() {
        return setting().Risk_Total_Amount__c;
    }

    public static Integer riskWindowDays() {
        return setting().Risk_Window_Days__c.intValue();
    }

    public static Integer approvalSlaHours() {
        return setting().Approval_SLA_Hours__c.intValue();
    }

    public static Integer goodsDueDays() {
        return setting().Goods_Due_Days__c.intValue();
    }

    public static Integer payHubTimeoutSeconds() {
        return setting().PayHub_Timeout_Seconds__c.intValue();
    }

    public static Integer payHubMaxTotalAttempts() {
        return setting().PayHub_Max_Total_Attempts__c.intValue();
    }

    public static Integer payHubRetryIntervalMinutes() {
        return setting().PayHub_Retry_Interval_Minutes__c.intValue();
    }

    public static Boolean isAutoApprovalEnabled() {
        return setting().Enable_Auto_Approval__c;
    }

    public static Boolean isPayHubEnabled() {
        return setting().Enable_PayHub__c;
    }

    public static Boolean isPosAppNotificationEnabled() {
        return setting().Enable_POS_App_Notification__c;
    }

    public static CategoryPolicy categoryPolicy(String productFamily) {
        if (String.isBlank(productFamily)) {
            throw configurationError('Product family is required.');
        }
        loadCategoryPolicies();
        CategoryPolicy result = categoryCache.get(normalize(productFamily));
        if (result == null) {
            throw configurationError('No active category policy for: ' + productFamily);
        }
        return result;
    }

    public static Decimal refundRate(String reason, String condition) {
        if (String.isBlank(reason) || String.isBlank(condition)) {
            throw configurationError('Reason and condition are required.');
        }
        String key = compositeKey(reason, condition);
        if (refundRateOverrides != null && refundRateOverrides.containsKey(key)) {
            return refundRateOverrides.get(key);
        }
        loadRefundRates();
        if (!refundRateCache.containsKey(key)) {
            throw configurationError(
                'No active refund rate for reason/condition: ' + reason + '/' + condition
            );
        }
        return refundRateCache.get(key);
    }

    public static Decimal getRefundRate(String reason, String condition) {
        try {
            return refundRate(reason, condition);
        } catch (SR_ConfigurationException ex) {
            return null;
        }
    }

    public static SR_CategoryPolicy getCategoryPolicy(String family) {
        if (String.isBlank(family)) {
            return null;
        }
        String key = normalize(family);
        if (categoryOverrides != null) {
            if (categoryOverrides.containsKey(family)) {
                return categoryOverrides.get(family);
            }
            if (categoryOverrides.containsKey(key)) {
                return categoryOverrides.get(key);
            }
        }
        loadDomainCategoryPolicies();
        return domainCategoryCache.get(key);
    }

    @TestVisible
    static void setCategoryPolicyOverrides(Map<String, SR_CategoryPolicy> policies) {
        categoryOverrides = policies;
    }

    @TestVisible
    static void setRefundRateOverrides(Map<String, Decimal> rates) {
        refundRateOverrides = rates;
        refundRateCache = null;
    }

    @TestVisible
    static void setProvider(Provider customProvider) {
        if (customProvider == null) {
            throw configurationError('Config provider cannot be null.');
        }
        provider = customProvider;
        clearCache();
    }

    @TestVisible
    static void resetProvider() {
        provider = new MetadataProvider();
        clearCache();
    }

    @TestVisible
    static void clearCache() {
        settingCache = null;
        categoryCache = null;
        domainCategoryCache = null;
        refundRateCache = null;
    }

    public static SR_Setting__mdt setting() {
        if (settingCache == null) {
            settingCache = applySettingOverrides(provider.getSetting(DEFAULT_SETTING));
            validateSetting(settingCache);
        }
        return settingCache;
    }

    private static SR_Setting__mdt applySettingOverrides(SR_Setting__mdt source) {
        if (overrides == null || overrides.isEmpty()) {
            return source;
        }
        Map<String, Object> raw = source == null
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(source));
        raw.putAll(overrides);
        raw.put('attributes', new Map<String, Object>{ 'type' => 'SR_Setting__mdt' });
        return (SR_Setting__mdt) JSON.deserialize(JSON.serialize(raw), SR_Setting__mdt.class);
    }

    private static void validateSetting(SR_Setting__mdt value) {
        if (value == null) {
            throw configurationError('Missing SR_Setting__mdt.Default.');
        }

        Map<String, Decimal> requiredNumbers = new Map<String, Decimal>{
            'Auto_Approval_Threshold__c' => value.Auto_Approval_Threshold__c,
            'Store_Manager_Max_Threshold__c' => value.Store_Manager_Max_Threshold__c,
            'Risk_Request_Count__c' => value.Risk_Request_Count__c,
            'Risk_Total_Amount__c' => value.Risk_Total_Amount__c,
            'Risk_Window_Days__c' => value.Risk_Window_Days__c,
            'Approval_SLA_Hours__c' => value.Approval_SLA_Hours__c,
            'Goods_Due_Days__c' => value.Goods_Due_Days__c,
            'PayHub_Timeout_Seconds__c' => value.PayHub_Timeout_Seconds__c,
            'PayHub_Max_Total_Attempts__c' => value.PayHub_Max_Total_Attempts__c,
            'PayHub_Retry_Interval_Minutes__c' => value.PayHub_Retry_Interval_Minutes__c
        };

        for (String fieldName : requiredNumbers.keySet()) {
            if (requiredNumbers.get(fieldName) == null) {
                throw configurationError('Missing required setting: ' + fieldName);
            }
        }
    }

    private static void loadCategoryPolicies() {
        if (categoryCache != null) {
            return;
        }
        categoryCache = new Map<String, CategoryPolicy>();
        for (SR_Category_Policy__mdt item : provider.getCategoryPolicies().values()) {
            if (item.Active__c != true || String.isBlank(item.Product_Family__c)) {
                continue;
            }
            if (item.Is_Returnable__c == true && item.Return_Window_Days__c == null) {
                throw configurationError(
                    'Return window is missing for category: ' + item.Product_Family__c
                );
            }
            categoryCache.put(normalize(item.Product_Family__c), new CategoryPolicy(item));
        }
    }

    private static void loadDomainCategoryPolicies() {
        if (domainCategoryCache != null) {
            return;
        }
        domainCategoryCache = new Map<String, SR_CategoryPolicy>();
        for (SR_Category_Policy__mdt item : provider.getCategoryPolicies().values()) {
            if (String.isBlank(item.Product_Family__c)) {
                continue;
            }
            domainCategoryCache.put(
                normalize(item.Product_Family__c),
                new SR_CategoryPolicy(
                    item.Product_Family__c,
                    item.Is_Returnable__c,
                    item.Return_Window_Days__c == null ? null : item.Return_Window_Days__c.intValue(),
                    item.Active__c
                )
            );
        }
    }

    private static void loadRefundRates() {
        if (refundRateCache != null) {
            return;
        }
        refundRateCache = new Map<String, Decimal>();
        for (SR_Refund_Rate__mdt item : provider.getRefundRates().values()) {
            if (item.Active__c != true) {
                continue;
            }
            if (
                String.isBlank(item.Reason__c) ||
                String.isBlank(item.Condition__c) ||
                item.Refund_Rate__c == null
            ) {
                throw configurationError('Active refund-rate metadata is incomplete.');
            }
            refundRateCache.put(
                compositeKey(item.Reason__c, item.Condition__c),
                item.Refund_Rate__c
            );
        }
    }

    private static String compositeKey(String firstValue, String secondValue) {
        return normalize(firstValue) + KEY_SEPARATOR + normalize(secondValue);
    }

    private static String normalize(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    @TestVisible
    private static void setOverride(Schema.SObjectField field, Object value) {
        if (!Test.isRunningTest()) {
            throw new SR_ConfigurationException('SR_Config.setOverride should only be used in tests.');
        }
        if (field == null) {
            throw new SR_ConfigurationException('SR_Config.setOverride: field cannot be null.');
        }
        String fieldName = field.getDescribe().getName();
        Schema.SObjectField known = SR_Setting__mdt.SObjectType.getDescribe().fields.getMap().get(fieldName.toLowerCase());
        if (known == null || known != field) {
            throw new SR_ConfigurationException('SR_Config.setOverride: ' + fieldName + ' is not in SR_Setting__mdt.');
        }
        overrides.put(fieldName, value);
        settingCache = null;
    }

    @TestVisible
    private static void clearOverrides() {
        overrides.clear();
        settingCache = null;
    }

    private static SR_ConfigurationException configurationError(String message) {
        return new SR_ConfigurationException(CONFIGURATION_ERROR, message);
    }
}
