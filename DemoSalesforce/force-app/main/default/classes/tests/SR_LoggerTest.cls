@IsTest
private class SR_LoggerTest {

    @IsTest
    static void getInstance_returnsSingleton() {
        Assert.areEqual(SR_Logger.getInstance(), SR_Logger.getInstance(), 'Phải trả về cùng một instance');
    }

    @IsTest
    static void logMethods_addToPendingList() {
        SR_Logger logger = SR_Logger.getInstance();

        logger.info('ctx', 'info message');
        logger.warn('ctx', 'warn message');
        logger.debug('ctx', 'debug message');
        logger.error('ctx', 'error message');
        logger.error('ctx', 'error message', new DmlException('boom'));
        logger.info('Cls.method', 'ctx', 'corr-1', 'msg', '001000000000000AAA');
        logger.warn('Cls.method', 'ctx', 'corr-1', 'msg', '001000000000000AAA');
        logger.debug('Cls.method', 'ctx', 'corr-1', 'msg', '001000000000000AAA');
        logger.error('Cls.method', 'ctx', 'corr-1', 'msg', '001000000000000AAA', 'stack');

        Assert.areEqual(9, logger.getPendingCount(), 'Chưa push thì log phải nằm trong danh sách chờ');
    }

    // NFR-09: mã lỗi trả cho người dùng phải khớp Correlation_Id__c của log
    @IsTest
    static void errorWithCode_returnsCodeAndQueuesLog() {
        SR_Logger logger = SR_Logger.getInstance();
        String code = logger.errorWithCode('Cls.method', 'ctx', new DmlException('boom'), null);

        Assert.isTrue(Pattern.matches('E\\d{15}', code), 'Mã lỗi sai định dạng: ' + code);
        Assert.areEqual(1, logger.getPendingCount());
    }

    @IsTest
    static void errorWithCode_nullException_stillReturnsCode() {
        Assert.isNotNull(SR_Logger.getInstance().errorWithCode('Cls.method', 'ctx', null, null));
    }

    @IsTest
    static void push_publishesAndClearsPendingList() {
        SR_Logger logger = SR_Logger.getInstance();
        logger.info('ctx', 'info message');
        logger.error('ctx', 'error message', new DmlException('boom'));

        Test.startTest();
        logger.push();
        Test.stopTest();

        Assert.areEqual(0, logger.getPendingCount(), 'Sau push danh sách chờ phải rỗng');
    }

    @IsTest
    static void push_emptyList_doesNothing() {
        SR_Logger logger = SR_Logger.getInstance();

        logger.push();

        Assert.areEqual(0, logger.getPendingCount());
    }

    @IsTest
    static void toLogEvent_mapsAllFields() {
        Application_Log__c log = new Application_Log__c(
            Class_Method__c   = 'Cls.method',
            Context__c        = 'ctx',
            Correlation_Id__c = 'corr-1',
            Level__c          = SR_Logger.LEVEL_ERROR,
            Message__c        = 'msg',
            Record_Id__c      = '001000000000000AAA',
            Stack_Trace__c    = 'stack',
            User__c           = UserInfo.getUserId()
        );

        Log_Event__e evt = SR_LoggerHelper.toLogEvent(log);

        Assert.areEqual('Cls.method', evt.Class_Method__c);
        Assert.areEqual('ctx', evt.Context__c);
        Assert.areEqual('corr-1', evt.Correlation_Id__c);
        Assert.areEqual(SR_Logger.LEVEL_ERROR, evt.Level__c);
        Assert.areEqual('msg', evt.Message__c);
        Assert.areEqual('001000000000000AAA', evt.Record_Id__c);
        Assert.areEqual('stack', evt.Stack_Trace__c);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), evt.User__c);
    }

    @IsTest
    static void toLogEvent_truncatesLongValues() {
        Application_Log__c log = new Application_Log__c(
            Message__c = 'a'.repeat(300)
        );

        Log_Event__e evt = SR_LoggerHelper.toLogEvent(log);

        Assert.areEqual(SR_LoggerHelper.MAX_MESSAGE, evt.Message__c.length());
        Assert.isNull(evt.User__c, 'User__c null thì giữ null');
    }

    @IsTest
    static void toLogEvent_nullInput_returnsNull() {
        Assert.isNull(SR_LoggerHelper.toLogEvent(null));
        Assert.isTrue(SR_LoggerHelper.toLogEvents(null).isEmpty());
    }

    @IsTest
    static void getRunningUserId_returnsCurrentUser() {
        Assert.areEqual(UserInfo.getUserId(), SR_Logger.getRunningUserId());
    }
}