@IsTest(SeeAllData=false)
private class SR_ErrorCodeTest {
    @IsTest
    static void mapsValidationCodesToHttp400() {
        List<String> validationCodes = new List<String>{
            SR_ErrorCode.MISSING_FIELD,
            SR_ErrorCode.INVALID_VALUE,
            SR_ErrorCode.NOT_RETURNABLE,
            SR_ErrorCode.RETURN_WINDOW_EXPIRED,
            SR_ErrorCode.QUANTITY_EXCEEDED,
            SR_ErrorCode.SKU_NOT_IN_ORDER
        };

        for (String code : validationCodes) {
            Assert.areEqual(
                400,
                SR_ErrorCode.getHttpStatus(code),
                'Wrong HTTP status for ' + code
            );
        }
    }

    @IsTest
    static void mapsNotFoundAndInternalCodes() {
        Assert.areEqual(
            404,
            SR_ErrorCode.getHttpStatus(SR_ErrorCode.ORDER_NOT_FOUND)
        );
        Assert.areEqual(
            404,
            SR_ErrorCode.getHttpStatus(SR_ErrorCode.REQUEST_NOT_FOUND)
        );
        Assert.areEqual(
            500,
            SR_ErrorCode.getHttpStatus(SR_ErrorCode.INTERNAL_ERROR)
        );
    }

    @IsTest
    static void mapsMessageKeysFromAppendixF() {
        Assert.areEqual(
            'SR_MSG_03',
            SR_ErrorCode.getMessageKey(SR_ErrorCode.NOT_RETURNABLE)
        );
        Assert.areEqual(
            'SR_MSG_02',
            SR_ErrorCode.getMessageKey(SR_ErrorCode.RETURN_WINDOW_EXPIRED)
        );
        Assert.areEqual(
            'SR_MSG_04',
            SR_ErrorCode.getMessageKey(SR_ErrorCode.QUANTITY_EXCEEDED)
        );
        Assert.areEqual(
            'SR_ERR_ORDER_NOT_FOUND',
            SR_ErrorCode.getMessageKey(SR_ErrorCode.ORDER_NOT_FOUND)
        );
        Assert.areEqual(
            'SR_MSG_90',
            SR_ErrorCode.getMessageKey(SR_ErrorCode.INTERNAL_ERROR)
        );

        Assert.isNull(SR_ErrorCode.getMessageKey(SR_ErrorCode.MISSING_FIELD));
        Assert.isNull(SR_ErrorCode.getMessageKey(SR_ErrorCode.INVALID_VALUE));
        Assert.isNull(SR_ErrorCode.getMessageKey(SR_ErrorCode.SKU_NOT_IN_ORDER));
        Assert.isNull(SR_ErrorCode.getMessageKey(SR_ErrorCode.REQUEST_NOT_FOUND));
    }

    @IsTest
    static void descriptorContainsCompleteAdapterMapping() {
        SR_ErrorCode.ErrorDescriptor descriptor =
            SR_ErrorCode.describe(SR_ErrorCode.RETURN_WINDOW_EXPIRED);

        Assert.areEqual(SR_ErrorCode.RETURN_WINDOW_EXPIRED, descriptor.code);
        Assert.areEqual('SR_MSG_02', descriptor.messageKey);
        Assert.areEqual(400, descriptor.httpStatus);
    }

    @IsTest
    static void rejectsUnknownCode() {
        Boolean thrown = false;

        try {
            SR_ErrorCode.getHttpStatus('UNKNOWN_CODE');
        } catch (SR_ErrorCode.SR_ErrorCodeException expected) {
            thrown = true;
            Assert.isTrue(expected.getMessage().contains('UNKNOWN_CODE'));
        }

        Assert.isTrue(thrown, 'Unknown error code must fail fast');
    }

    @IsTest
    static void supportedCodeSetIsDefensiveCopy() {
        Set<String> firstRead = SR_ErrorCode.getSupportedCodes();
        firstRead.clear();
        Set<String> secondRead = SR_ErrorCode.getSupportedCodes();

        // 9 mã của Phụ lục E.1/E.2 + VALIDATION_FAILED (errorCode cấp yêu cầu, E.1)
        // + CONFIGURATION_ERROR (lỗi cấu hình nội bộ, trả 500)
        Set<String> expected = new Set<String>{
            SR_ErrorCode.MISSING_FIELD,
            SR_ErrorCode.INVALID_VALUE,
            SR_ErrorCode.NOT_RETURNABLE,
            SR_ErrorCode.RETURN_WINDOW_EXPIRED,
            SR_ErrorCode.QUANTITY_EXCEEDED,
            SR_ErrorCode.SKU_NOT_IN_ORDER,
            SR_ErrorCode.ORDER_NOT_FOUND,
            SR_ErrorCode.REQUEST_NOT_FOUND,
            SR_ErrorCode.INTERNAL_ERROR,
            SR_ErrorCode.VALIDATION_FAILED,
            SR_ErrorCode.CONFIGURATION_ERROR
        };
        Assert.areEqual(expected, secondRead, 'Clear on first read must not affect later reads');
    }

    @IsTest
    static void mapsRequestLevelAndConfigurationCodes() {
        Assert.areEqual(
            400,
            SR_ErrorCode.getHttpStatus(SR_ErrorCode.VALIDATION_FAILED)
        );
        Assert.areEqual(
            500,
            SR_ErrorCode.getHttpStatus(SR_ErrorCode.CONFIGURATION_ERROR)
        );
    }
}
