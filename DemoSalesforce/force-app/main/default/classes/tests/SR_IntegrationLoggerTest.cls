@IsTest
private class SR_IntegrationLoggerTest {

    private static void addSampleLog(SR_IntegrationLogger logger) {
        logger.add(
            'corr-1',
            SR_IntegrationLogger.DIRECTION_OUTBOUND,
            'https://example.com/api',
            '{"a":1}',
            '{"ok":true}',
            200,
            123L,
            SR_IntegrationLogger.RESULT_SUCCESS,
            1,
            'ERP',
            null
        );
    }

    @IsTest
    static void getInstance_returnsSingleton() {
        SR_IntegrationLogger first = SR_IntegrationLogger.getInstance();
        SR_IntegrationLogger second = SR_IntegrationLogger.getInstance();
        Assert.areEqual(first, second, 'Phải trả về cùng một instance');
        Assert.isTrue(first === second, 'Phải là cùng một tham chiếu singleton');
    }

    @IsTest
    static void add_addsToPendingList() {
        SR_IntegrationLogger logger = SR_IntegrationLogger.getInstance();

        addSampleLog(logger);
        addSampleLog(logger);

        Assert.areEqual(2, logger.getPendingCount(), 'Chưa push thì log phải nằm trong danh sách chờ');
    }

    @IsTest
    static void push_publishesAndClearsPendingList() {
        SR_IntegrationLogger logger = SR_IntegrationLogger.getInstance();
        addSampleLog(logger);
        addSampleLog(logger);

        Test.startTest();
        logger.push();
        Test.stopTest();

        Assert.areEqual(0, logger.getPendingCount(), 'Sau push danh sách chờ phải rỗng');
    }

    @IsTest
    static void push_emptyList_doesNothing() {
        SR_IntegrationLogger logger = SR_IntegrationLogger.getInstance();

        logger.push();

        Assert.areEqual(0, logger.getPendingCount());
    }

    @IsTest
    static void toIntegrationLogEvent_mapsAllFields() {
        Integration_Log__c log = new Integration_Log__c(
            Attempt_No__c     = 2,
            Correlation_Id__c = 'corr-1',
            Direction__c      = SR_IntegrationLogger.DIRECTION_INBOUND,
            Duration_Ms__c    = 250,
            Endpoint__c       = 'https://example.com/api',
            Http_Status__c    = 500,
            Request_Body__c   = 'req',
            Response_Body__c  = 'res',
            Result__c         = SR_IntegrationLogger.RESULT_FAILED,
            System__c         = 'ERP'
        );

        Integration_Log_Event__e evt = SR_LoggerHelper.toIntegrationLogEvent(log);

        Assert.areEqual(2, evt.Attempt_No__c);
        Assert.areEqual('corr-1', evt.Correlation_Id__c);
        Assert.areEqual(SR_IntegrationLogger.DIRECTION_INBOUND, evt.Direction__c);
        Assert.areEqual(250, evt.Duration_Ms__c);
        Assert.areEqual('https://example.com/api', evt.Endpoint__c);
        Assert.areEqual(500, evt.Http_Status__c);
        Assert.areEqual('req', evt.Request_Body__c);
        Assert.areEqual('res', evt.Response_Body__c);
        Assert.areEqual(SR_IntegrationLogger.RESULT_FAILED, evt.Result__c);
        Assert.areEqual('ERP', evt.System__c);
        Assert.isNull(evt.Return_Request__c, 'Return_Request__c null thì giữ null');
    }

    @IsTest
    static void toIntegrationLogEvent_truncatesLongValues() {
        Integration_Log__c log = new Integration_Log__c(
            Endpoint__c      = 'e'.repeat(300),
            Request_Body__c  = 'a'.repeat(40000),
            Response_Body__c = 'b'.repeat(40000)
        );

        Integration_Log_Event__e evt = SR_LoggerHelper.toIntegrationLogEvent(log);

        Assert.areEqual(SR_LoggerHelper.MAX_ENDPOINT, evt.Endpoint__c.length());
        Assert.areEqual(SR_LoggerHelper.MAX_BODY, evt.Request_Body__c.length());
        Assert.areEqual(SR_LoggerHelper.MAX_BODY, evt.Response_Body__c.length());
    }

    @IsTest
    static void toIntegrationLogEvents_handlesNullAndList() {
        Assert.isNull(SR_LoggerHelper.toIntegrationLogEvent(null));
        Assert.isTrue(SR_LoggerHelper.toIntegrationLogEvents(null).isEmpty());

        List<Integration_Log_Event__e> events = SR_LoggerHelper.toIntegrationLogEvents(
            new List<Integration_Log__c>{ new Integration_Log__c(System__c = 'A'), null, new Integration_Log__c(System__c = 'B') }
        );
        Assert.areEqual(2, events.size(), 'Phần tử null phải bị bỏ qua');
    }
}