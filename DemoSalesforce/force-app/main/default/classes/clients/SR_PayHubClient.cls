/**
 * Client gửi lệnh hoàn tiền tới PayHub.
 *
 * - Callout thật: Named Credential "PayHub".
 * - Mock runtime: điều khiển bởi SR_Setting__mdt.Default (đọc qua SR_Config):
 * PayHub_Use_Mock__c và PayHub_Mock_Scenario__c.
 */
public with sharing class SR_PayHubClient {
    public static final String OUT_SUCCESS = 'SUCCESS';
    public static final String OUT_PENDING = 'PENDING';
    public static final String OUT_REJECTED = 'REJECTED';
    public static final String OUT_RETRY = 'RETRY';

    public static final String SCENARIO_SUCCESS = 'SUCCESS';
    public static final String SCENARIO_PENDING = 'PENDING';
    public static final String SCENARIO_INVALID = 'INVALID';
    public static final String SCENARIO_ERROR = 'ERROR';
    public static final String SCENARIO_TIMEOUT = 'TIMEOUT';

    private static final String ENDPOINT =
        'callout:PayHub/v1/refunds';

    private static final String LOG_SYSTEM_NAME = 'PayHub';

    private static final Integer DEFAULT_TIMEOUT_SECONDS = 10;
    private static final Integer MAX_TIMEOUT_MS = 120000;

    public interface Client {
        Result sendRefund(RefundCommand command);
    }

    public class RefundCommand {
        public Id requestId;
        public String merchantRef;
        public String orderNumber;
        public Long amount;
        public Integer attemptNo;    // lần gửi thứ mấy, ghi vào Integration_Log__c (BR-14); null = 1
    }

    public class Result {
        public String outcome;
        public String refundId;
        public Integer httpStatus;
        public String errorCode;
        public String requestBody;
        public String responseBody;
        public Long durationMs;
    }

    public class PayHubClientException extends Exception {
    }

    /*
     * Các override phục vụ unit test.
     */
    @TestVisible
    private static Client clientOverride;

    @TestVisible
    private static Boolean useMockOverride;

    @TestVisible
    private static String mockScenarioOverride;

    @TestVisible
    private static Decimal timeoutSecondsOverride;

    /**
     * Entry point gửi yêu cầu hoàn tiền.
     */
    public static Result sendRefund(
        RefundCommand command
    ) {
        validate(command);

        Result result = client().sendRefund(command);

        logResult(command, result);

        return result;
    }

    /**
     * Ghi log kết quả callout PayHub qua SR_IntegrationLogger.
     * Việc ghi log không được làm hỏng luồng nghiệp vụ.
     */
    private static void logResult(
        RefundCommand command,
        Result result
    ) {
        if (result == null) {
            return;
        }

        try {
            String logResult = SR_IntegrationLogger.RESULT_FAILED;

            if (result.outcome == OUT_SUCCESS) {
                logResult = SR_IntegrationLogger.RESULT_SUCCESS;
            } else if (result.outcome == OUT_PENDING) {
                logResult = SR_IntegrationLogger.RESULT_PENDING;
            }

            SR_IntegrationLogger logger =
                SR_IntegrationLogger.getInstance();

            logger.add(
                command.merchantRef,
                SR_IntegrationLogger.DIRECTION_OUTBOUND,
                ENDPOINT,
                result.requestBody,
                result.responseBody,
                result.httpStatus,
                result.durationMs,
                logResult,
                command.attemptNo == null ? 1 : command.attemptNo,
                LOG_SYSTEM_NAME,
                command.requestId
            );

            logger.push();
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'SR_PayHubClient: log failed - ' +
                e.getMessage()
            );
        }
    }

    /**
     * Chọn client thật hoặc mock theo Custom Metadata.
     */
    public static Client client() {
        if (clientOverride!= null) {
            return clientOverride;
        }

        return useMock()
            ? (Client) new MockClient()
            : (Client) new HttpClient();
    }

    /**
     * Tạo request body theo hợp đồng PayHub.
     */
    public static String buildBody(
        RefundCommand command
    ) {
        validate(command);

        return JSON.serialize(
            new Map<String, Object>{
                'merchantRef' => command.merchantRef,
                'orderNumber' => command.orderNumber,
                'amount' => command.amount,
                'currency' => 'VND',
                'reason' => 'CUSTOMER_RETURN'
            }
        );
    }

    /**
     * Chuẩn hóa HTTP response của PayHub thành outcome nội bộ.
     */
    public static void interpret(Result result) {
        if (result == null) {
            throw new PayHubClientException(
                'PayHub result must not be null.'
            );
        }

        try {
            if (result.httpStatus == 200) {
                Map<String, Object> body =
                    (Map<String, Object>)
                    JSON.deserializeUntyped(
                        result.responseBody
                    );

                result.refundId =
                    (String) body.get('refundId');

                String status =
                    (String) body.get('status');

                if (status == 'SUCCESS') {
                    result.outcome = OUT_SUCCESS;
                } else if (status == 'PENDING') {
                    result.outcome = OUT_PENDING;
                } else {
                    result.outcome = OUT_RETRY;
                    result.errorCode = 'UNKNOWN_STATUS';
                }
            } else if (result.httpStatus == 422) {
                Map<String, Object> body =
                    (Map<String, Object>)
                    JSON.deserializeUntyped(
                        result.responseBody
                    );

                result.outcome = OUT_REJECTED;
                result.errorCode =
                    (String) body.get('errorCode');

                if (String.isBlank(result.errorCode)) {
                    result.errorCode =
                        'INVALID_REQUEST';
                }
            } else {
                result.outcome = OUT_RETRY;
                result.errorCode =
                    'HTTP_' +
                    String.valueOf(result.httpStatus);
            }
        } catch (Exception e) {
            result.outcome = OUT_RETRY;
            result.errorCode = 'BAD_RESPONSE';
        }
    }

    private static void validate(
        RefundCommand command
    ) {
        if (command == null) {
            throw new PayHubClientException(
                'Refund command must not be null.'
            );
        }

        if (String.isBlank(command.merchantRef)) {
            throw new PayHubClientException(
                'merchantRef is required.'
            );
        }

        if (String.isBlank(command.orderNumber)) {
            throw new PayHubClientException(
                'orderNumber is required.'
            );
        }

        if (
            command.amount == null ||
            command.amount <= 0
        ) {
            throw new PayHubClientException(
                'amount must be greater than zero.'
            );
        }
    }

    private static Boolean useMock() {
        if (useMockOverride!= null) {
            return useMockOverride;
        }

        SR_Setting__mdt setting = getSetting();

        return setting!= null &&
            setting.PayHub_Use_Mock__c == true;
    }

    private static String mockScenario() {
        if (mockScenarioOverride!= null) {
            return mockScenarioOverride;
        }

        SR_Setting__mdt setting = getSetting();

        return setting == null
            ? null
            : setting.PayHub_Mock_Scenario__c;
    }

    // Qua SR_Config để test ghi đè được bằng SR_TestDataFactory.overrideConfig.
    // Cấu hình thiếu thì trả null → dùng giá trị mặc định (không mock, timeout 10 giây).
    private static SR_Setting__mdt getSetting() {
        try {
            return SR_Config.setting();
        } catch (SR_ConfigurationException e) {
            return null;
        }
    }

    /**
     * Lấy timeout từ Custom Metadata.
     *
     * Giá trị cấu hình là giây, trong khi HttpRequest.setTimeout()
     * nhận mili giây.
     *
     * Nếu metadata không có hoặc giá trị không hợp lệ:
     * - Dùng mặc định 10 giây.
     *
     * Salesforce cho phép timeout tối đa 120 giây.
     */
    @TestVisible
    private static Integer timeoutMs() {
        Decimal timeoutSeconds =
            timeoutSecondsOverride;

        if (timeoutSeconds == null) {
            SR_Setting__mdt setting = getSetting();

            timeoutSeconds = setting == null
                ? null
                : setting.PayHub_Timeout_Seconds__c;
        }

        if (
            timeoutSeconds == null ||
            timeoutSeconds <= 0
        ) {
            timeoutSeconds =
                DEFAULT_TIMEOUT_SECONDS;
        }

        Integer configuredTimeoutMs =
            (timeoutSeconds * 1000).intValue();

        if (configuredTimeoutMs > MAX_TIMEOUT_MS) {
            return MAX_TIMEOUT_MS;
        }

        return configuredTimeoutMs;
    }

    /**
     * Client gọi PayHub thật qua Named Credential "PayHub".
     */
    public class HttpClient implements Client {
        public Result sendRefund(
            RefundCommand command
        ) {
            Result result = new Result();

            result.requestBody =
                buildBody(command);

            HttpRequest request =
                new HttpRequest();

            request.setEndpoint(ENDPOINT);
            request.setMethod('POST');

            request.setHeader(
                'Content-Type',
                'application/json'
            );

            request.setHeader(
                'Idempotency-Key',
                command.merchantRef
            );

            request.setTimeout(timeoutMs());
            request.setBody(result.requestBody);

            Long startedAt =
                System.currentTimeMillis();

            try {
                HttpResponse response =
                    new Http().send(request);

                result.httpStatus =
                    response.getStatusCode();

                result.responseBody =
                    response.getBody();

                interpret(result);
            } catch (CalloutException e) {
                result.outcome = OUT_RETRY;
                result.errorCode =
                    'TIMEOUT_OR_NETWORK';
                result.responseBody =
                    e.getMessage();
            }

            result.durationMs =
                System.currentTimeMillis() -
                startedAt;

            return result;
        }
    }

    /**
     * Client giả lập PayHub cho dev, test và UAT.
     */
    public class MockClient implements Client {
        public Result sendRefund(
            RefundCommand command
        ) {
            Result result = new Result();

            result.requestBody =
                buildBody(command);

            result.durationMs = 5;

            String scenario = mockScenario();

            if (String.isBlank(scenario)) {
                scenario = SCENARIO_SUCCESS;
            }

            scenario =
                scenario.trim().toUpperCase();

            if (scenario == SCENARIO_TIMEOUT) {
                result.outcome = OUT_RETRY;
                result.errorCode =
                    'TIMEOUT_OR_NETWORK';
                result.responseBody =
                    'Read timed out (mock)';

                return result;
            }

            if (scenario == SCENARIO_PENDING) {
                result.httpStatus = 200;

                result.responseBody =
                    JSON.serialize(
                        new Map<String, Object>{
                            'refundId' =>
                                mockRefundId(command),
                            'status' => 'PENDING'
                        }
                    );
            } else if (
                scenario == SCENARIO_INVALID
            ) {
                result.httpStatus = 422;
                result.responseBody =
                    '{"errorCode":"INVALID_AMOUNT"}';
            } else if (
                scenario == SCENARIO_ERROR
            ) {
                result.httpStatus = 500;
                result.responseBody =
                    '{"errorCode":"INTERNAL_ERROR"}';
            } else if (
                scenario == SCENARIO_SUCCESS
            ) {
                result.httpStatus = 200;

                result.responseBody =
                    JSON.serialize(
                        new Map<String, Object>{
                            'refundId' =>
                                mockRefundId(command),
                            'status' => 'SUCCESS'
                        }
                    );
            } else {
                result.outcome = OUT_RETRY;
                result.errorCode =
                    'UNSUPPORTED_MOCK_SCENARIO';

                result.responseBody =
                    'Unsupported mock scenario: ' +
                    scenario;

                return result;
            }

            interpret(result);

            return result;
        }

        private String mockRefundId(
            RefundCommand command
        ) {
            return 'PH-MOCK-' +
                command.merchantRef;
        }
    }
}