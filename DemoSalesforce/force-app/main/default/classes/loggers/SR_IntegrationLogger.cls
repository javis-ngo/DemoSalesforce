/**
 * Logger cho callout/integration (Singleton).
 * - add(): build Integration_Log__c (không insert) và đưa vào danh sách chờ.
 * - push(): convert toàn bộ danh sách chờ sang Integration_Log_Event__e và
 *           bulk publish bằng 1 lần EventBus.publish.
 *
 * Cách dùng:
 *   SR_IntegrationLogger logger = SR_IntegrationLogger.getInstance();
 *   Long start = System.currentTimeMillis();
 *   HttpResponse res = new Http().send(req);
 *   logger.add(
 *       corrId, SR_IntegrationLogger.DIRECTION_OUTBOUND, req.getEndpoint(),
 *       req.getBody(), res.getBody(), res.getStatusCode(),
 *       System.currentTimeMillis() - start,
 *       res.getStatusCode() < 300 ? SR_IntegrationLogger.RESULT_SUCCESS : SR_IntegrationLogger.RESULT_FAILED,
 *       1, 'ERP', returnRequestId
 *   );
 *   logger.push();
 */
public with sharing class SR_IntegrationLogger {

    // Giá trị phải khớp với picklist trên Integration_Log__c
    public static final String DIRECTION_INBOUND  = 'INBOUND';
    public static final String DIRECTION_OUTBOUND = 'OUTBOUND';

    public static final String RESULT_SUCCESS = 'SUCCESS';
    public static final String RESULT_PENDING = 'PENDING';
    public static final String RESULT_FAILED  = 'FAILED';

    // ---- Singleton ----
    private static SR_IntegrationLogger instance;

    // Danh sách log đang chờ publish
    private List<Integration_Log__c> logs = new List<Integration_Log__c>();

    private SR_IntegrationLogger() {}

    public static SR_IntegrationLogger getInstance() {
        if (instance == null) {
            instance = new SR_IntegrationLogger();
        }
        return instance;
    }

    // ---- Method chung ----

    /**
     * Build Integration_Log__c và thêm vào danh sách chờ.
     * Chưa publish: cần gọi push() để publish các log đã add.
     */
    public void add(
        String correlationId,
        String direction,
        String endpoint,
        String requestBody,
        String responseBody,
        Integer httpStatus,
        Long durationMs,
        String result,
        Integer attemptNo,
        String systemName,
        Id returnRequestId
    ) {
        logs.add(new Integration_Log__c(
            Attempt_No__c     = attemptNo,
            Correlation_Id__c = correlationId,
            Direction__c      = direction,
            Duration_Ms__c    = durationMs,
            Endpoint__c       = endpoint,
            Http_Status__c    = httpStatus,
            Request_Body__c   = requestBody,
            Response_Body__c  = responseBody,
            Result__c         = result,
            Return_Request__c = returnRequestId,
            System__c         = systemName
        ));
    }

    /**
     * Convert các log đang chờ sang Integration_Log_Event__e và bulk publish.
     * Danh sách chờ được xóa sau khi publish. Không throw exception ra ngoài
     * để việc ghi log không làm hỏng luồng nghiệp vụ.
     */
    public void push() {
        if (logs.isEmpty()) {
            return;
        }

        List<Integration_Log_Event__e> logEvents = SR_LoggerHelper.toIntegrationLogEvents(logs);
        logs.clear();

        try {
            List<Database.SaveResult> results = EventBus.publish(logEvents);

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'SR_IntegrationLogger: publish Integration_Log_Event__e [' + i + '] thất bại - '
                            + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'SR_IntegrationLogger: lỗi khi publish log - ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    /** Số log đang chờ push. */
    public Integer getPendingCount() {
        return logs.size();
    }
}