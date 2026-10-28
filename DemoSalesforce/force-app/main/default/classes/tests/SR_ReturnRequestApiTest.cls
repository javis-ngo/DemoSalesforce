/**
 * Test cho SR_ReturnRequestApi / SR_ReturnRequestApiService (B8; INT-01, INT-02, import NFR-02; BR-18)
 * và SR_ApiResponse. Dữ liệu dựng bằng SR_TestDataFactory (Dev A), cấu hình bằng seedSmartReturnTestConfig.
 * Chạy: sf apex run test --class-names SR_ReturnRequestApiTest --result-format human
 */
@IsTest
private class SR_ReturnRequestApiTest {

    private static final String BASE = '/services/apexrest/smartreturn/v1/return-requests';
    private static final String STORE_CODE = 'HCM-012';
    private static final String CUSTOMER_PHONE = '0901234567';

    // Đơn của chị Lan giao 2 ngày trước: nồi chiên 2.490.000đ (trả được) + thẻ cào (không trả được, B.1)
    @TestSetup
    static void setup() {
        Store__c store = SR_TestDataFactory.createStore(
            STORE_CODE, SR_TestDataFactory.REGION_SOUTH, UserInfo.getUserId(), UserInfo.getUserId());
        Account lan = SR_TestDataFactory.createAccount('Chị Lan', CUSTOMER_PHONE, false);
        Map<String, Product2> products = SR_TestDataFactory.createProductCatalog();
        SR_TestDataFactory.OrderSpec spec = new SR_TestDataFactory.OrderSpec(lan.Id, store.Id);
        spec.effectiveDate = Date.today().addDays(-3);
        spec.deliveryDate = Date.today().addDays(-2);
        spec.items.add(new SR_TestDataFactory.ItemSpec(products.get(SR_TestDataFactory.FAMILY_APPLIANCE).Id, 1));
        spec.items.add(new SR_TestDataFactory.ItemSpec(products.get(SR_TestDataFactory.FAMILY_PREPAID).Id, 1));
        SR_TestDataFactory.createOrder(spec);
    }

    private static String orderNumber() {
        return [SELECT OrderNumber FROM Order LIMIT 1].OrderNumber;
    }

    // Body INT-01 theo Phụ lục E.1
    private static Map<String, Object> createBody(String externalId, String phone, String sku, String condition) {
        return new Map<String, Object>{
            'externalRequestId' => externalId,
            'channel' => 'POS',
            'orderNumber' => orderNumber(),
            'customerPhone' => phone,
            'storeCode' => STORE_CODE,
            'lines' => new List<Object>{ new Map<String, Object>{
                'sku' => sku, 'quantity' => 1, 'reason' => 'NOT_SATISFIED', 'condition' => condition
            } }
        };
    }

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

    // UAT-05 / BR-06: tạo mới 201 (nồi chiên Đã mở hộp 80% → 1.992.000đ); gửi lại cùng externalRequestId → 200 cùng mã
    @IsTest
    static void createThenDuplicateReturnsSameRequest() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        String body = JSON.serialize(createBody('POS-UAT05-1', CUSTOMER_PHONE, 'AF-PH-5L', 'OPENED'));

        Map<String, Object> first = post(BASE, body);
        Assert.areEqual(201, RestContext.response.statusCode, JSON.serialize(first));
        // Định dạng RR-YYMM-00000 (FR-01) do Dev A sinh; ở đây chỉ cần có mã
        Assert.isNotNull(first.get('requestNumber'));
        Assert.areEqual(1992000, Decimal.valueOf(String.valueOf(first.get('estimatedRefundAmount'))).intValue());
        Assert.areEqual(1, ((List<Object>) first.get('lines')).size());

        Map<String, Object> second = post(BASE, body);
        Assert.areEqual(200, RestContext.response.statusCode, JSON.serialize(second));
        Assert.areEqual(first.get('requestNumber'), second.get('requestNumber'));
        Assert.areEqual(1, [SELECT COUNT() FROM Return_Request__c WHERE External_Request_Id__c = 'POS-UAT05-1']);
    }

    // Đơn không khớp SĐT → 404 ORDER_NOT_FOUND (E.1)
    @IsTest
    static void wrongPhoneReturns404() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Map<String, Object> body = post(BASE,
            JSON.serialize(createBody('POS-404-1', '0999999999', 'AF-PH-5L', 'OPENED')));
        Assert.areEqual(404, RestContext.response.statusCode, JSON.serialize(body));
        Assert.areEqual(SR_ApiResponse.ORDER_NOT_FOUND, body.get('errorCode'));
    }

    // Thẻ cào không trả được (B.1) → 400 VALIDATION_FAILED, details theo SKU
    @IsTest
    static void nonReturnableCategoryReturns400WithLineDetail() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Map<String, Object> body = post(BASE,
            JSON.serialize(createBody('POS-400-1', CUSTOMER_PHONE, 'TC-VT-100K', 'SEALED')));
        Assert.areEqual(400, RestContext.response.statusCode, JSON.serialize(body));
        Assert.areEqual(SR_ApiResponse.VALIDATION_FAILED, body.get('errorCode'));
        Assert.isNotNull(body.get('details'));
    }

    // Hệ thống ngoài không được tự đặt field nội bộ
    @IsTest
    static void sanitizeClearsInternalFields() {
        SR_CreateLineDTO line = new SR_CreateLineDTO();
        line.orderItemId = UserInfo.getUserId();
        line.unitPrice = 1;
        SR_CreateRequestDTO input = new SR_CreateRequestDTO();
        input.riskFlag = false;
        input.orderId = UserInfo.getUserId();
        input.lines = new List<SR_CreateLineDTO>{ line };

        SR_ReturnRequestApiService.sanitize(input);
        Assert.isNull(input.riskFlag);
        Assert.isNull(input.orderId);
        Assert.isFalse(input.atomicMode);
        Assert.isNull(input.lines[0].orderItemId);
        Assert.isNull(input.lines[0].unitPrice);
    }

    // Mã lỗi cấp yêu cầu suy ra từ errors của Dev A
    @IsTest
    static void errorCodeOfMapsServiceErrors() {
        SR_CreateResultDTO validation = new SR_CreateResultDTO();
        validation.errors.add(new SR_ErrorDetailDTO('AF-PH-5L', SR_ErrorCode.QUANTITY_EXCEEDED, 'x'));
        Assert.areEqual(SR_ApiResponse.VALIDATION_FAILED, SR_ReturnRequestApiService.errorCodeOf(validation));

        SR_CreateResultDTO notFound = new SR_CreateResultDTO();
        notFound.errors.add(new SR_ErrorDetailDTO(null, SR_ErrorCode.ORDER_NOT_FOUND, 'x'));
        Assert.areEqual(SR_ApiResponse.ORDER_NOT_FOUND, SR_ReturnRequestApiService.errorCodeOf(notFound));

        SR_CreateResultDTO internal = new SR_CreateResultDTO();
        internal.errors.add(new SR_ErrorDetailDTO(null, SR_ErrorCode.ORDER_NOT_FOUND, 'x'));
        internal.errors.add(new SR_ErrorDetailDTO(null, SR_ErrorCode.INTERNAL_ERROR, 'boom'));
        Assert.areEqual(SR_ApiResponse.INTERNAL_ERROR, SR_ReturnRequestApiService.errorCodeOf(internal));
    }

    // Dòng lỗi không có câu báo: lấy Custom Label theo mã
    @IsTest
    static void messageOfFallsBackToLabel() {
        SR_ErrorDetailDTO withMessage = new SR_ErrorDetailDTO('SKU', SR_ErrorCode.NOT_RETURNABLE, 'Câu của Dev A');
        Assert.areEqual('Câu của Dev A', SR_ReturnRequestApiService.messageOf(withMessage));
        SR_ErrorDetailDTO withoutMessage = new SR_ErrorDetailDTO('SKU', SR_ErrorCode.NOT_RETURNABLE, new List<String>());
        Assert.isTrue(String.isNotBlank(SR_ReturnRequestApiService.messageOf(withoutMessage)));
        SR_ErrorDetailDTO unknown = new SR_ErrorDetailDTO('SKU', 'SOMETHING_NEW', new List<String>());
        Assert.areEqual('SOMETHING_NEW', SR_ReturnRequestApiService.messageOf(unknown));
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

    // NFR-02 / UAT-01: dòng đúng được tạo, dòng sai (thẻ cào) báo lỗi tại đúng index
    @IsTest
    static void importMixedRowsIsPartialSuccess() {
        SR_TestDataFactory.seedSmartReturnTestConfig();
        Map<String, Object> body = post(BASE + '/import', JSON.serialize(new List<Object>{
            createBody('IMPORT-OK-1', CUSTOMER_PHONE, 'AF-PH-5L', 'OPENED'),
            createBody('IMPORT-BAD-1', CUSTOMER_PHONE, 'TC-VT-100K', 'SEALED')
        }));
        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual(1, body.get('succeeded'), JSON.serialize(body));
        List<Object> results = (List<Object>) body.get('results');
        Assert.areEqual(true, ((Map<String, Object>) results[0]).get('success'));
        Map<String, Object> bad = (Map<String, Object>) results[1];
        Assert.areEqual(false, bad.get('success'));
        Assert.areEqual(SR_ApiResponse.VALIDATION_FAILED, bad.get('errorCode'));
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

    // Lỗi Dev A đã ghi log: trả mã tra cứu của Dev A, không ghi log lần nữa
    @IsTest
    static void loggedErrorReturnsGivenCode() {
        SR_ApiResponse res = SR_ApiResponse.loggedError('ABC123');
        Assert.areEqual(500, res.statusCode);
        Assert.isTrue(((String) ((Map<String, Object>) res.body).get('message')).contains('ABC123'));
        Assert.areEqual(0, SR_Logger.getInstance().getPendingCount());
    }

    @IsTest
    static void errorWithoutDetailsOmitsDetails() {
        SR_ApiResponse res = SR_ApiResponse.error(404, SR_ApiResponse.ORDER_NOT_FOUND, 'x', new List<Object>());
        Assert.isFalse(((Map<String, Object>) res.body).containsKey('details'));
    }
}
