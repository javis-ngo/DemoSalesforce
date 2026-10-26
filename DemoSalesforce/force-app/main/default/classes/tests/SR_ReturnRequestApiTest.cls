/**
 * Test cho SR_ReturnRequestApi / SR_ReturnRequestApiService (B8; INT-01, INT-02, import NFR-02; BR-18)
 * và SR_ApiResponse. Các test dưới đây không cần dữ liệu.
 * [DEV A] TODO tích hợp khi có SR_TestDataFactory + SR_ReturnRequestService.createRequests:
 *  - POS tạo yêu cầu → 201, estimatedRefundAmount 1992000; gửi lại cùng externalRequestId → 200 cùng requestNumber (UAT-05)
 *  - thẻ cào → 400 NOT_RETURNABLE; import 200 dòng có 4 dòng sai số lượng → succeeded 196 (UAT-01)
 * Chạy: sf apex run test --class-names SR_ReturnRequestApiTest --result-format human
 */
@IsTest
private class SR_ReturnRequestApiTest {

    private static final String BASE = '/services/apexrest/smartreturn/v1/return-requests';

    private static Map<String, Object> post(String uri, String body) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        SR_ReturnRequestApi.doPost();
        return parse();
    }

    private static Map<String, Object> get(String uri) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
        SR_ReturnRequestApi.doGet();
        return parse();
    }

    private static Map<String, Object> parse() {
        Blob body = RestContext.response.responseBody;
        return body == null ? null : (Map<String, Object>) JSON.deserializeUntyped(body.toString());
    }

    private static String firstDetailCode(Map<String, Object> body) {
        return (String) ((Map<String, Object>) ((List<Object>) body.get('details'))[0]).get('code');
    }

    // ---------- INT-01 ----------

    @IsTest
    static void emptyBodyReturns400MissingField() {
        Map<String, Object> body = post(BASE, '');
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.VALIDATION_FAILED, body.get('errorCode'));
        Assert.areEqual(SR_ApiResponse.MISSING_FIELD, firstDetailCode(body));
    }

    @IsTest
    static void invalidJsonReturns400InvalidValue() {
        Map<String, Object> body = post(BASE, '{"channel": ');
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.INVALID_VALUE, firstDetailCode(body));
    }

    // Kênh Tại quầy không được tạo qua API
    @IsTest
    static void counterChannelIsRejected() {
        Map<String, Object> body = post(BASE, '{"channel":"COUNTER","orderNumber":"00000100","lines":[]}');
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.INVALID_VALUE, firstDetailCode(body));
    }

    @IsTest
    static void missingChannelIsRejected() {
        Map<String, Object> body = post(BASE, '{"orderNumber":"00000100"}');
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.MISSING_FIELD, firstDetailCode(body));
    }

    // ---------- Import ----------

    @IsTest
    static void importMoreThan200IsRejected() {
        List<Object> items = new List<Object>();
        for (Integer i = 0; i <= SR_ReturnRequestApiService.MAX_IMPORT; i++) {
            items.add(new Map<String, Object>{ 'channel' => 'POS' });
        }
        Map<String, Object> body = post(BASE + '/import', JSON.serialize(items));
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.INVALID_VALUE, firstDetailCode(body));
    }

    @IsTest
    static void importEmptyListIsRejected() {
        post(BASE + '/import', '[]');
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    // NFR-02: dòng lỗi được báo từng dòng, giữ đúng index
    @IsTest
    static void importReportsInvalidRowsPerIndex() {
        Map<String, Object> body = post(BASE + '/import', JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'channel' => 'COUNTER', 'externalRequestId' => 'IMPORT-1' },
            new Map<String, Object>{ 'externalRequestId' => 'IMPORT-2' }
        }));
        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual(2, body.get('total'));
        Assert.areEqual(0, body.get('succeeded'));
        List<Object> results = (List<Object>) body.get('results');
        Map<String, Object> second = (Map<String, Object>) results[1];
        Assert.areEqual(1, second.get('index'));
        Assert.areEqual('IMPORT-2', second.get('externalRequestId'));
        Assert.areEqual(false, second.get('success'));
    }

    // ---------- INT-02 ----------

    @IsTest
    static void unknownRequestReturns404() {
        Map<String, Object> body = get(BASE + '/RR-0000-99999');
        Assert.areEqual(404, RestContext.response.statusCode);
        Assert.areEqual(SR_ApiResponse.REQUEST_NOT_FOUND, body.get('errorCode'));
    }

    @IsTest
    static void lookupWithoutNumberReturns400() {
        get(BASE);
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    // E.2 + BR-18: đúng field, dòng đã kiểm định trả tiền thực hoàn, không có Ghi chú nội bộ
    @IsTest
    static void detailBodyFollowsE2() {
        Return_Request__c r = (Return_Request__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Return_Request__c' },
            'Name' => 'RR-2610-00015',
            'Status__c' => 'COMPLETED',
            'Estimated_Refund__c' => 2000000,
            'Actual_Refund__c' => 1992000,
            'Internal_Note__c' => 'KHÔNG ĐƯỢC LỘ',
            'Order__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Order' }, 'OrderNumber' => '00012345'
            },
            'Return_Request_Lines__r' => new Map<String, Object>{ 'totalSize' => 1, 'done' => true, 'records' =>
                new List<Object>{ new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'Return_Request_Line__c' },
                    'Quantity__c' => 1, 'Inspection_Result__c' => 'PASSED',
                    'Estimated_Refund__c' => 2000000, 'Actual_Refund__c' => 1992000
                } }
            },
            'Return_Request_Histories__r' => new Map<String, Object>{ 'totalSize' => 1, 'done' => true, 'records' =>
                new List<Object>{ new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'Return_Request_History__c' },
                    'To_Status__c' => 'NEW', 'Changed_At__c' => '2026-10-05T02:12:03.000+0000'
                } }
            }
        }), Return_Request__c.class);

        Map<String, Object> body = SR_ReturnRequestApiService.toDetailBody(r);
        Assert.areEqual('RR-2610-00015', body.get('requestNumber'));
        Assert.areEqual('00012345', body.get('orderNumber'));
        Assert.areEqual(1992000, ((Decimal) body.get('refundAmount')).intValue());
        Assert.isFalse(JSON.serialize(body).contains('KHÔNG ĐƯỢC LỘ'), 'BR-18');
        Map<String, Object> line = (Map<String, Object>) ((List<Object>) body.get('lines'))[0];
        Assert.areEqual(1992000, ((Decimal) line.get('refundAmount')).intValue());
        Map<String, Object> history = (Map<String, Object>) ((List<Object>) body.get('history'))[0];
        Assert.areEqual('2026-10-05T09:12:03+07:00', history.get('changedAt'));
    }

    // ---------- SR_ApiResponse ----------

    @IsTest
    static void internalErrorLogsAndReturnsLookupCode() {
        Test.startTest();
        SR_ApiResponse res = SR_ApiResponse.internalError('Cls.method', 'ctx', new DmlException('boom'), null);
        Test.stopTest();
        Assert.areEqual(500, res.statusCode);
        Map<String, Object> body = (Map<String, Object>) res.body;
        Assert.areEqual(SR_ApiResponse.INTERNAL_ERROR, body.get('errorCode'));
        Assert.isTrue(Pattern.matches('.*E\\d{15}.*', (String) body.get('message')), (String) body.get('message'));
    }

    @IsTest
    static void errorWithoutDetailsOmitsDetails() {
        SR_ApiResponse res = SR_ApiResponse.error(404, SR_ApiResponse.ORDER_NOT_FOUND, 'x', new List<Object>());
        Assert.isFalse(((Map<String, Object>) res.body).containsKey('details'));
    }
}
