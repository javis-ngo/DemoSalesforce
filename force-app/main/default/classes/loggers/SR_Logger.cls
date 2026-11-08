/**
 * Logger hệ thống (Singleton).
 * - add()/info()/warn()/debug()/error(): build Application_Log__c (không insert) và đưa vào danh sách chờ.
 * - push(): convert toàn bộ danh sách chờ sang Log_Event__e và bulk publish bằng 1 lần EventBus.publish.
 *
 * Cách dùng:
 *   SR_Logger logger = SR_Logger.getInstance();
 *   try {
 *       logger.info('Bắt đầu đồng bộ', 'Sync order');
 *       // ...
 *   } catch (Exception e) {
 *       logger.error('Sync lỗi', e.getMessage(), e);
 *   } finally {
 *       logger.push();
 *   }
 */
public with sharing class SR_Logger {

    // Giá trị phải khớp với Global Value Set Log_Level
    public static final String LEVEL_INFO  = 'INFO';
    public static final String LEVEL_WARN  = 'WARN';
    public static final String LEVEL_DEBUG = 'DEBUG';
    public static final String LEVEL_ERROR = 'ERROR';

    private static final String GUEST_USER_TYPE = 'Guest';

    // ---- Singleton ----
    private static SR_Logger instance;

    // Danh sách log đang chờ publish
    private List<Application_Log__c> logs = new List<Application_Log__c>();

    private SR_Logger() {}

    public static SR_Logger getInstance() {
        if (instance == null) {
            instance = new SR_Logger();
        }
        return instance;
    }

    // ---- Method chung ----

    /**
     * Build Application_Log__c và thêm vào danh sách chờ.
     * Chưa publish: cần gọi push() để publish các log đã add.
     */
    public void add(
        String classMethod,
        String context,
        String correlationId,
        String level,
        String message,
        String recordId,
        String stackTrace
    ) {
        logs.add(new Application_Log__c(
            Class_Method__c   = classMethod,
            Context__c        = context,
            Correlation_Id__c = correlationId,
            Level__c          = level,
            Message__c        = message,
            Record_Id__c      = recordId,
            Stack_Trace__c    = stackTrace,
            User__c           = getRunningUserId()
        ));
    }

    /**
     * Convert các log đang chờ sang Log_Event__e và bulk publish.
     * Danh sách chờ được xóa sau khi publish. Không throw exception ra ngoài
     * để việc ghi log không làm hỏng luồng nghiệp vụ.
     */
    public void push() {
        if (logs.isEmpty()) {
            return;
        }

        List<Log_Event__e> logEvents = SR_LoggerHelper.toLogEvents(logs);
        logs.clear();

        try {
            List<Database.SaveResult> results = EventBus.publish(logEvents);

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'SR_Logger: publish Log_Event__e [' + i + '] thất bại - '
                            + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'SR_Logger: lỗi khi publish log - ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    /** Số log đang chờ push. */
    public Integer getPendingCount() {
        return logs.size();
    }

    // ---- INFO ----

    public void info(String context, String message) {
        add(null, context, null, LEVEL_INFO, message, null, null);
    }

    public void info(String classMethod, String context, String correlationId, String message, String recordId) {
        add(classMethod, context, correlationId, LEVEL_INFO, message, recordId, null);
    }

    // ---- WARN ----

    public void warn(String context, String message) {
        add(null, context, null, LEVEL_WARN, message, null, null);
    }

    public void warn(String classMethod, String context, String correlationId, String message, String recordId) {
        add(classMethod, context, correlationId, LEVEL_WARN, message, recordId, null);
    }

    // ---- DEBUG ----

    public void debug(String context, String message) {
        add(null, context, null, LEVEL_DEBUG, message, null, null);
    }

    public void debug(String classMethod, String context, String correlationId, String message, String recordId) {
        add(classMethod, context, correlationId, LEVEL_DEBUG, message, recordId, null);
    }

    // ---- ERROR ----

    public void error(String context, String message) {
        add(null, context, null, LEVEL_ERROR, message, null, null);
    }

    /** Tự động lấy stack trace từ Exception. */
    public void error(String context, String message, Exception ex) {
        add(null, context, null, LEVEL_ERROR, message, null, ex == null ? null : ex.getStackTraceString());
    }

    public void error(
        String classMethod,
        String context,
        String correlationId,
        String message,
        String recordId,
        String stackTrace
    ) {
        add(classMethod, context, correlationId, LEVEL_ERROR, message, recordId, stackTrace);
    }

    /**
     * Ghi ERROR kèm mã tra cứu (lưu ở Correlation_Id__c) và trả mã đó để hiện cho người dùng
     * trong MSG-90 hoặc trả trong API 500 (NFR-09). Người dùng báo mã, tìm trong tab Nhật ký lỗi.
     * Vẫn cần gọi push() sau đó.
     */
    public String errorWithCode(String classMethod, String context, Exception ex, String recordId) {
        String code = newErrorCode();
        add(classMethod, context, code, LEVEL_ERROR,
            ex == null ? null : ex.getTypeName() + ': ' + ex.getMessage(),
            recordId, ex == null ? null : ex.getStackTraceString());
        return code;
    }

    /** Mã lỗi dạng E + yyMMddHHmmss (giờ VN) + 3 số ngẫu nhiên, vd. E261019093015123. */
    @TestVisible
    private static String newErrorCode() {
        return 'E' + Datetime.now().format('yyMMddHHmmss', 'Asia/Ho_Chi_Minh')
            + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 1000)).leftPad(3, '0');
    }

    // ---- Private ----

    /** Trả về Id user đang chạy; Guest user thì trả về null. */
    @TestVisible
    private static Id getRunningUserId() {
        if (UserInfo.getUserType() == GUEST_USER_TYPE) {
            return null;
        }
        return UserInfo.getUserId();
    }
}