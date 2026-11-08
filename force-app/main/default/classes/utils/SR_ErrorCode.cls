/**
 * Canonical SmartReturn error codes plus adapter mappings.
 *
 * Domain services return code/params. REST adapters use getHttpStatus().
 * LWC adapters use getMessageKey(); null means use the service-provided message,
 * with SR_MSG_90 as the final fallback.
 */
public with sharing class SR_ErrorCode {
    public static final String MISSING_FIELD = 'MISSING_FIELD';
    public static final String INVALID_VALUE = 'INVALID_VALUE';
    public static final String NOT_RETURNABLE = 'NOT_RETURNABLE';
    public static final String RETURN_WINDOW_EXPIRED = 'RETURN_WINDOW_EXPIRED';
    public static final String QUANTITY_EXCEEDED = 'QUANTITY_EXCEEDED';
    public static final String SKU_NOT_IN_ORDER = 'SKU_NOT_IN_ORDER';
    public static final String ORDER_NOT_FOUND = 'ORDER_NOT_FOUND';
    public static final String REQUEST_NOT_FOUND = 'REQUEST_NOT_FOUND';
    public static final String INTERNAL_ERROR = 'INTERNAL_ERROR';
    public static final String CONFIGURATION_ERROR = 'CONFIGURATION_ERROR';
    public static final String VALIDATION_FAILED = 'VALIDATION_FAILED';
    public static final String INVALID_STATUS_TRANSITION = 'INVALID_STATUS_TRANSITION';
    public static final String FORBIDDEN = 'FORBIDDEN';
    public static final String STALE_RECORD = 'STALE_RECORD';

    public static final Integer HTTP_BAD_REQUEST = 400;
    public static final Integer HTTP_NOT_FOUND = 404;
    public static final Integer HTTP_INTERNAL_SERVER_ERROR = 500;

    private static final Set<String> SUPPORTED_CODES = new Set<String>{
        MISSING_FIELD,
        INVALID_VALUE,
        NOT_RETURNABLE,
        RETURN_WINDOW_EXPIRED,
        QUANTITY_EXCEEDED,
        SKU_NOT_IN_ORDER,
        ORDER_NOT_FOUND,
        REQUEST_NOT_FOUND,
        INTERNAL_ERROR,
        CONFIGURATION_ERROR,
        VALIDATION_FAILED
    };

    //TO-DO: missing the map section for another 
    private static final Map<String, String> MESSAGE_KEYS = new Map<String, String>{
        NOT_RETURNABLE => 'SR_MSG_03',
        RETURN_WINDOW_EXPIRED => 'SR_MSG_02',
        QUANTITY_EXCEEDED => 'SR_MSG_04',
        ORDER_NOT_FOUND => 'SR_ERR_ORDER_NOT_FOUND',
        INTERNAL_ERROR => 'SR_MSG_90'
    };

    private static final Map<String, Integer> HTTP_STATUSES =
        new Map<String, Integer>{
            MISSING_FIELD => HTTP_BAD_REQUEST,
            INVALID_VALUE => HTTP_BAD_REQUEST,
            NOT_RETURNABLE => HTTP_BAD_REQUEST,
            RETURN_WINDOW_EXPIRED => HTTP_BAD_REQUEST,
            QUANTITY_EXCEEDED => HTTP_BAD_REQUEST,
            SKU_NOT_IN_ORDER => HTTP_BAD_REQUEST,
            ORDER_NOT_FOUND => HTTP_NOT_FOUND,
            REQUEST_NOT_FOUND => HTTP_NOT_FOUND,
            INTERNAL_ERROR => HTTP_INTERNAL_SERVER_ERROR,
            CONFIGURATION_ERROR => HTTP_INTERNAL_SERVER_ERROR,
            VALIDATION_FAILED => HTTP_BAD_REQUEST
        };

    private SR_ErrorCode() {
    }

    public static Boolean isSupported(String code) {
        return String.isNotBlank(code) && SUPPORTED_CODES.contains(code);
    }

    public static String getMessageKey(String code) {
        validateCode(code);
        return MESSAGE_KEYS.get(code);
    }

    public static String message(String code) {
        String key = getMessageKey(code);
        if (key == 'SR_MSG_02') {
            return System.Label.SR_MSG_02;
        }
        if (key == 'SR_MSG_03') {
            return System.Label.SR_MSG_03;
        }
        if (key == 'SR_MSG_04') {
            return System.Label.SR_MSG_04;
        }
        if (key == 'SR_ERR_ORDER_NOT_FOUND') {
            return System.Label.SR_ERR_ORDER_NOT_FOUND;
        }
        if (key == 'SR_MSG_90') {
            return System.Label.SR_MSG_90;
        }
        return code;
    }

    public static Integer getHttpStatus(String code) {
        validateCode(code);
        return HTTP_STATUSES.get(code);
    }

    public static ErrorDescriptor describe(String code) {
        validateCode(code);
        return new ErrorDescriptor(
            code,
            MESSAGE_KEYS.get(code),
            HTTP_STATUSES.get(code)
        );
    }

    public static Set<String> getSupportedCodes() {
        return SUPPORTED_CODES.clone();
    }

    private static void validateCode(String code) {
        if (!isSupported(code)) {
            throw new SR_ErrorCodeException('Unsupported SmartReturn error code: ' + code);
        }
    }

    public class ErrorDescriptor {
        @AuraEnabled public String code { get; private set; }
        @AuraEnabled public String messageKey { get; private set; }
        @AuraEnabled public Integer httpStatus { get; private set; }

        private ErrorDescriptor(
            String code,
            String messageKey,
            Integer httpStatus
        ) {
            this.code = code;
            this.messageKey = messageKey;
            this.httpStatus = httpStatus;
        }
    }

    public class SR_ErrorCodeException extends Exception {
    }
}
