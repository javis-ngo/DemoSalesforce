/**
 * Helper cho SR_Logger và SR_IntegrationLogger: chứa các xử lý chuyển đổi dữ liệu log.
 */
public with sharing class SR_LoggerHelper {

    // ---- Giới hạn độ dài field trên Log_Event__e ----
    @TestVisible private static final Integer MAX_CLASS_METHOD   = 255;
    @TestVisible private static final Integer MAX_CONTEXT        = 32768;
    @TestVisible private static final Integer MAX_CORRELATION_ID = 100;
    @TestVisible private static final Integer MAX_LEVEL          = 50;
    @TestVisible private static final Integer MAX_MESSAGE        = 255;
    @TestVisible private static final Integer MAX_RECORD_ID      = 18;
    @TestVisible private static final Integer MAX_STACK_TRACE    = 65536;

    // ---- Giới hạn độ dài field trên Integration_Log_Event__e ----
    @TestVisible private static final Integer MAX_DIRECTION      = 20;
    @TestVisible private static final Integer MAX_ENDPOINT       = 255;
    @TestVisible private static final Integer MAX_BODY           = 32768;
    @TestVisible private static final Integer MAX_RESULT         = 20;
    @TestVisible private static final Integer MAX_RETURN_REQUEST = 18;
    @TestVisible private static final Integer MAX_SYSTEM         = 100;

    // ================== Application_Log__c -> Log_Event__e ==================

    /**
     * Convert Application_Log__c (chưa insert) thành Log_Event__e.
     * Giá trị vượt quá độ dài field sẽ được cắt bớt để tránh lỗi khi publish.
     */
    public static Log_Event__e toLogEvent(Application_Log__c log) {
        if (log == null) {
            return null;
        }

        return new Log_Event__e(
            Class_Method__c   = truncate(log.Class_Method__c, MAX_CLASS_METHOD),
            Context__c        = truncate(log.Context__c, MAX_CONTEXT),
            Correlation_Id__c = truncate(log.Correlation_Id__c, MAX_CORRELATION_ID),
            Level__c          = truncate(log.Level__c, MAX_LEVEL),
            Message__c        = truncate(log.Message__c, MAX_MESSAGE),
            Record_Id__c      = truncate(log.Record_Id__c, MAX_RECORD_ID),
            Stack_Trace__c    = truncate(log.Stack_Trace__c, MAX_STACK_TRACE),
            User__c           = log.User__c == null ? null : String.valueOf(log.User__c)
        );
    }

    /**
     * Convert danh sách Application_Log__c thành danh sách Log_Event__e.
     */
    public static List<Log_Event__e> toLogEvents(List<Application_Log__c> logs) {
        List<Log_Event__e> events = new List<Log_Event__e>();
        if (logs == null) {
            return events;
        }
        for (Application_Log__c log : logs) {
            Log_Event__e evt = toLogEvent(log);
            if (evt != null) {
                events.add(evt);
            }
        }
        return events;
    }

    // ============ Integration_Log__c -> Integration_Log_Event__e ============

    /**
     * Convert Integration_Log__c (chưa insert) thành Integration_Log_Event__e.
     * Giá trị vượt quá độ dài field sẽ được cắt bớt để tránh lỗi khi publish.
     */
    public static Integration_Log_Event__e toIntegrationLogEvent(Integration_Log__c log) {
        if (log == null) {
            return null;
        }

        return new Integration_Log_Event__e(
            Attempt_No__c     = log.Attempt_No__c,
            Correlation_Id__c = truncate(log.Correlation_Id__c, MAX_CORRELATION_ID),
            Direction__c      = truncate(log.Direction__c, MAX_DIRECTION),
            Duration_Ms__c    = log.Duration_Ms__c,
            Endpoint__c       = truncate(log.Endpoint__c, MAX_ENDPOINT),
            Http_Status__c    = log.Http_Status__c,
            Request_Body__c   = truncate(log.Request_Body__c, MAX_BODY),
            Response_Body__c  = truncate(log.Response_Body__c, MAX_BODY),
            Result__c         = truncate(log.Result__c, MAX_RESULT),
            Return_Request__c = log.Return_Request__c == null ? null : String.valueOf(log.Return_Request__c),
            System__c         = truncate(log.System__c, MAX_SYSTEM)
        );
    }

    /**
     * Convert danh sách Integration_Log__c thành danh sách Integration_Log_Event__e.
     */
    public static List<Integration_Log_Event__e> toIntegrationLogEvents(List<Integration_Log__c> logs) {
        List<Integration_Log_Event__e> events = new List<Integration_Log_Event__e>();
        if (logs == null) {
            return events;
        }
        for (Integration_Log__c log : logs) {
            Integration_Log_Event__e evt = toIntegrationLogEvent(log);
            if (evt != null) {
                events.add(evt);
            }
        }
        return events;
    }

    // ---- Private ----

    @TestVisible
    private static String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.left(maxLength) : value;
    }
}