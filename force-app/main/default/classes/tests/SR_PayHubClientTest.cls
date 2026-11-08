@IsTest
private class SR_PayHubClientTest {
    private static SR_PayHubClient.RefundCommand
        validCommand() {

        SR_PayHubClient.RefundCommand command =
            new SR_PayHubClient.RefundCommand();

        command.merchantRef = 'RR-TEST-00001';
        command.orderNumber = '0000012345';
        command.amount = 1992000;

        return command;
    }

    @IsTest
    static void mockSuccess() {
        useMockScenario('SUCCESS');

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        System.assertEquals(
            SR_PayHubClient.OUT_SUCCESS,
            result.outcome
        );

        System.assertEquals(
            200,
            result.httpStatus
        );

        System.assertEquals(
            'PH-MOCK-RR-TEST-00001',
            result.refundId
        );
    }

    @IsTest
    static void mockPending() {
        useMockScenario('PENDING');

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        System.assertEquals(
            SR_PayHubClient.OUT_PENDING,
            result.outcome
        );

        System.assertEquals(
            200,
            result.httpStatus
        );
    }

    @IsTest
    static void mockInvalid() {
        useMockScenario('INVALID');

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        System.assertEquals(
            SR_PayHubClient.OUT_REJECTED,
            result.outcome
        );

        System.assertEquals(
            422,
            result.httpStatus
        );

        System.assertEquals(
            'INVALID_AMOUNT',
            result.errorCode
        );
    }

    @IsTest
    static void mockError() {
        useMockScenario('ERROR');

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        System.assertEquals(
            SR_PayHubClient.OUT_RETRY,
            result.outcome
        );

        System.assertEquals(
            500,
            result.httpStatus
        );

        System.assertEquals(
            'HTTP_500',
            result.errorCode
        );
    }

    @IsTest
    static void mockTimeout() {
        useMockScenario('TIMEOUT');

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        System.assertEquals(
            SR_PayHubClient.OUT_RETRY,
            result.outcome
        );

        System.assertEquals(
            null,
            result.httpStatus
        );

        System.assertEquals(
            'TIMEOUT_OR_NETWORK',
            result.errorCode
        );
    }

    @IsTest
    static void realCalloutUsesNamedCredentialContract() {
        SR_PayHubClient.useMockOverride = false;

        /*
         * Giả lập giá trị
         * SR_Setting__mdt.PayHub_Timeout_Seconds__c = 15.
         */
        SR_PayHubClient.timeoutSecondsOverride = 15;

        Test.setMock(
            HttpCalloutMock.class,
            new PayHubSuccessHttpMock()
        );

        Test.startTest();

        SR_PayHubClient.Result result =
            SR_PayHubClient.sendRefund(
                validCommand()
            );

        Test.stopTest();

        System.assertEquals(
            SR_PayHubClient.OUT_SUCCESS,
            result.outcome
        );

        System.assertEquals(
            'PH-RF-88231',
            result.refundId
        );
    }

    @IsTest
    static void rejectsInvalidCommandBeforeCallout() {
        SR_PayHubClient.RefundCommand command =
            validCommand();

        command.amount = 0;

        try {
            SR_PayHubClient.sendRefund(command);

            System.assert(
                false,
                'Expected PayHubClientException.'
            );
        } catch (
            SR_PayHubClient.PayHubClientException e
        ) {
            System.assert(
                e.getMessage().contains('amount')
            );
        }
    }

    private static void useMockScenario(
        String scenario
    ) {
        SR_PayHubClient.useMockOverride = true;
        SR_PayHubClient.mockScenarioOverride =
            scenario;
    }

    private class PayHubSuccessHttpMock
        implements HttpCalloutMock {

        public HttpResponse respond(
            HttpRequest request
        ) {
            System.assertEquals(
                'callout:PayHub/v1/refunds',
                request.getEndpoint()
            );

            System.assertEquals(
                'POST',
                request.getMethod()
            );

            System.assertEquals(
                'RR-TEST-00001',
                request.getHeader(
                    'Idempotency-Key'
                )
            );

            System.assertEquals(
                'application/json',
                request.getHeader(
                    'Content-Type'
                )
            );

            /*
             * 15 giây trong Custom Metadata
             * phải được chuyển thành 15.000 ms.
             * HttpRequest không có getTimeout() nên kiểm tra giá trị truyền vào setTimeout().
             */
            System.assertEquals(
                15000,
                SR_PayHubClient.timeoutMs()
            );

            Map<String, Object> body =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    request.getBody()
                );

            System.assertEquals(
                'RR-TEST-00001',
                body.get('merchantRef')
            );

            System.assertEquals(
                '0000012345',
                body.get('orderNumber')
            );

            System.assertEquals(
                1992000,
                body.get('amount')
            );

            System.assertEquals(
                'VND',
                body.get('currency')
            );

            System.assertEquals(
                'CUSTOMER_RETURN',
                body.get('reason')
            );

            HttpResponse response =
                new HttpResponse();

            response.setStatusCode(200);

            response.setBody(
                '{"refundId":"PH-RF-88231",' +
                '"status":"SUCCESS"}'
            );

            return response;
        }
    }
}