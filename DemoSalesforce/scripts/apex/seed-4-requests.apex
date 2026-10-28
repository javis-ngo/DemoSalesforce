// =====================================================================
// SmartReturn – Seed 4/4: yêu cầu đổi trả mẫu, tạo qua service của Dev A (Đức)
// Cần SR_ReturnRequestService.createRequests và SR_CreateRequestDTO / SR_CreateResultDTO.
// Đi qua service nên tiền hoàn, cấp duyệt, lịch sử trạng thái và chia sẻ đều như thật:
//  - Anh Khoa: 3 yêu cầu trong 30 ngày (để test UAT-03)
//  - Anh Tuấn: laptop 25tr chờ QLV duyệt, lùi giờ gửi về 30 giờ trước (demo cảnh báo quá hạn)
//  - Chị Mai: 1 yêu cầu của cửa hàng HN-007 (UAT-08: NV HCM-012 mở link phải bị chặn)
// Chạy sau seed 2. Chạy lại riêng script này không tạo trùng (BR-06: trùng mã giao dịch).
// Owner: Dev C (Đức)
// =====================================================================

// [đơn (10 ký tự đầu của tên đơn), SKU, SL, lý do, tình trạng, mã giao dịch]
List<List<Object>> plan = new List<List<Object>>{
    new List<Object>{ 'SR-SEED 04', 'AC-TN-01', 1, 'NOT_SATISFIED', 'SEALED', 'SEED-UAT03-1' },
    new List<Object>{ 'SR-SEED 04', 'AC-TN-01', 1, 'NOT_SATISFIED', 'SEALED', 'SEED-UAT03-2' },
    new List<Object>{ 'SR-SEED 04', 'AC-TN-01', 1, 'DEFECT', 'OPENED', 'SEED-UAT03-3' },
    new List<Object>{ 'SR-SEED 08', 'LT-15-PRO', 1, 'DEFECT', 'OPENED', 'SEED-OVERDUE-1' },
    new List<Object>{ 'SR-SEED 11', 'AC-TN-01', 1, 'WRONG_ITEM', 'SEALED', 'SEED-UAT08-1' }
};

Map<String, OrderItem> lineOf = new Map<String, OrderItem>();
for (OrderItem oi : [
    SELECT Id, OrderId, Order.Name, Order.OrderNumber, Order.Account.Phone, Order.Store__r.Store_Code__c, Product2.ProductCode
    FROM OrderItem WHERE Order.Name LIKE 'SR-SEED%'
]) {
    lineOf.put(oi.Order.Name.left(10) + '|' + oi.Product2.ProductCode, oi);
}

// Kênh POS: tự duyệt thì vào Inspecting (không bị job đêm hủy như Awaiting Goods của App)
List<SR_CreateRequestDTO> requests = new List<SR_CreateRequestDTO>();
for (List<Object> p : plan) {
    OrderItem oi = lineOf.get((String) p[0] + '|' + (String) p[1]);
    if (oi == null) {
        throw new IllegalArgumentException('Không thấy đơn ' + (String) p[0] + ' – chạy seed 2 trước');
    }
    Map<String, Object> body = new Map<String, Object>{
        'externalRequestId' => p[5],
        'channel' => 'POS',
        'orderId' => oi.OrderId,
        'orderNumber' => oi.Order.OrderNumber,
        'customerPhone' => oi.Order.Account.Phone,
        'storeCode' => oi.Order.Store__r.Store_Code__c,
        'lines' => new List<Object>{
            new Map<String, Object>{
                'orderItemId' => oi.Id, 'sku' => p[1], 'quantity' => p[2], 'reason' => p[3], 'condition' => p[4]
            }
        }
    };
    requests.add((SR_CreateRequestDTO) JSON.deserialize(JSON.serialize(body), SR_CreateRequestDTO.class));
}
List<SR_CreateResultDTO> results = SR_ReturnRequestService.createRequests(requests);
for (Integer i = 0; i < results.size(); i++) {
    if (results[i].success != true) {
        System.debug('SEED | LỖI tạo ' + (String) plan[i][5] + ': ' + JSON.serialize(results[i].errors).left(500));
    }
}

// Yêu cầu laptop: lùi thời điểm gửi duyệt về 30 giờ trước → quá hạn 24 giờ (BR-11)
List<Return_Request__c> overdue = [
    SELECT Id, Status__c FROM Return_Request__c WHERE External_Request_Id__c = 'SEED-OVERDUE-1' LIMIT 1
];
if (!overdue.isEmpty()) {
    if (overdue[0].Status__c != 'PENDING_APPROVAL') {
        System.debug('SEED | CHÚ Ý: yêu cầu laptop đang ' + overdue[0].Status__c
            + ', không phải PENDING_APPROVAL (xem lại ngưỡng duyệt và công tắc Tự duyệt)');
    }
    update new Return_Request__c(
        Id = overdue[0].Id,
        Submitted_At__c = System.now().addHours(-30),
        Approval_Due_At__c = System.now().addHours(-6)
    );
}

for (Return_Request__c r : [
    SELECT Name, External_Request_Id__c, Status__c, Approval_Level__c, Estimated_Refund__c,
           Assigned_Approver__r.Name, Store__r.Store_Code__c, Account__r.Name
    FROM Return_Request__c WHERE External_Request_Id__c LIKE 'SEED-%' ORDER BY External_Request_Id__c
]) {
    System.debug('SEED | ' + r.Name + ' | ' + r.External_Request_Id__c + ' | ' + r.Account__r?.Name
        + ' | ' + r.Store__r?.Store_Code__c + ' | ' + r.Status__c + ' | cấp ' + r.Approval_Level__c
        + ' | người duyệt ' + r.Assigned_Approver__r?.Name + ' | dự kiến ' + r.Estimated_Refund__c);
}
System.debug('SEED | Seed 4 XONG');