# SmartReturn – Kế hoạch làm trong 1 tuần (3 dev)

Nguồn: BRD – SmartReturn v1.0 (19/10/2026). Giả định: 3 người đều code được Apex/LWC, làm 5 ngày (N1 → N5; nếu bắt đầu hôm nay thì từ T2 19/10 đến T6 23/10).

| Vai trò | Người | Phụ trách |
|---|---|---|
| Dev A – Nền tảng & nghiệp vụ (kiêm lead) | ______ | Data model, cấu hình, quy tắc nghiệp vụ, phân quyền, job đêm, merge & deploy |
| Dev B – Tích hợp & xử lý nền | ______ | API cho POS/App, PayHub, sự kiện thông báo, log, tìm kiếm CSKH |
| Dev C – Giao diện & Portal | ______ | Màn hình tạo yêu cầu, duyệt, kiểm định; Customer Portal; danh mục thông báo; dữ liệu mẫu |

---

## 0. Ba nguyên tắc để kịp 1 tuần

1. **Khối lượng vừa khít.** 18 FR, 18 BR, 5 tích hợp, Portal và 10 UAT ước tính khoảng 15 ngày công, đúng bằng 3 người × 5 ngày. Không có thời gian để chờ nhau, nên phải chốt thiết kế chung ngay sáng N1.
2. **Chia theo mảng, không chia theo tầng.** Mỗi người làm trọn mảng của mình từ logic đến test. Không chia kiểu 1 người làm object, 1 người làm Apex, 1 người làm UI, vì như vậy người sau phải chờ người trước.
3. **Dùng chung một service Apex.** Mọi quy tắc BR nằm trong service. Màn hình, API và job đêm cùng gọi vào đó, không viết lại logic ở từng kênh hay rải ra Flow. Ưu tiên dùng tính năng có sẵn: Auto Number, Custom Metadata, Named Credential, Platform Event, Field Set.

## 1. Bắt đầu từ đâu: sáng N1, cả 3 người (~3 tiếng)

Chưa code ngay. Làm 4 việc này theo thứ tự:

| # | Việc | Thời gian | Đầu ra |
|---|---|---|---|
| 1 | Cả 3 đọc mục 6 (FR/BR), Phụ lục C (trạng thái), Phụ lục E (API). Sau đó mỗi người đọc kỹ phần mình (mục 4) | 30' | Hiểu chung luồng |
| 2 | Chốt giả định cho 8 vấn đề mở và các điểm chưa rõ (mục 2). Gửi mentor/khách xác nhận song song, **không chờ** trả lời | 30' | `docs/TDD.md` – phần Giả định |
| 3 | Chốt thiết kế dùng chung: tên object/field, giá trị picklist, tên và tham số các hàm service, Platform Event (mục 3) | 60' | `docs/TDD.md` – phần Thiết kế |
| 4 | Dựng môi trường: repo Git + SFDX project; mỗi người 1 org để code (Developer Edition hoặc org công ty cấp); 1 org chung để ghép và demo, đặt Time Zone GMT+7, Locale Vietnamese, tiền VND | 60' | Ai cũng deploy được |

Công cụ: VS Code + Salesforce Extension Pack, Salesforce CLI (`sf`), Git, Postman.

**Cuối N1, org chung phải có:** data model, cấu hình, dữ liệu mẫu và các hàm service dạng stub (trả dữ liệu giả). Dev B và Dev C gọi stub để code tiếp. Khi Dev A viết xong hàm thật, phía Dev B và Dev C không phải sửa gì.

## 2. Giả định cho các điểm chưa chốt

### 2.1 Tám vấn đề mở (mục 10 BRD)

Phần lớn đã có câu trả lời ngầm trong chính BRD:

| OI | Giả định đề xuất | Căn cứ |
|---|---|---|
| OI-01 Vài sản phẩm không đủ điều kiện | Tại quầy: dòng đó bị khóa, không nhập được. Qua API: trả 400 kèm lỗi từng SKU, không tạo yêu cầu | D.1 bước 3; ví dụ lỗi ở E.1 |
| OI-02 Ngưỡng duyệt áp trước hay sau kiểm định | Áp trên tiền dự kiến lúc tạo; không duyệt lại sau kiểm định | Duyệt diễn ra trước kiểm định; Phụ lục C không có đường Inspecting → Pending Approval |
| OI-03 Đơn mua tại quầy không có ngày giao | Tính hạn từ ngày mua (`Order.EffectiveDate`) | A.1: Delivery_Date__c trống với đơn mang về tại quầy |
| OI-04 Thanh toán nhiều hình thức, quà tặng kèm | Gửi 1 lệnh hoàn tổng tiền, PayHub hoàn về phương thức gốc. Quà tặng không xử lý riêng, ghi vào Ghi chú nội bộ | Mục 11: PayHub hoàn về phương thức thanh toán gốc |
| OI-05 CHT vắng thì ai duyệt | Không làm ủy quyền; quá 24 giờ tự chuyển lên QLV | BR-11, FR-16 |
| OI-06 PayHub đã hoàn nhưng Salesforce bị timeout | Gửi lại với cùng Idempotency-Key; PayHub trả kết quả lần đầu, không hoàn thêm | BR-13, E.3 |
| OI-07 Hủy khi đang Refund Processing | Không cho hủy | Phụ lục C: chỉ hủy được từ New, Pending Approval, Awaiting Goods |
| OI-08 Hai người cùng sửa/duyệt | Người lưu trước được giữ; người sau nhận MSG-13 và phải tải lại | MSG-13 ở Phụ lục F |

### 2.2 Điểm BRD chưa rõ, nên hỏi thêm

| Điểm | Vấn đề | Đề xuất |
|---|---|---|
| BR-09 – cờ Rủi ro | Nếu chỉ job đêm cập nhật cờ, khách tạo yêu cầu thứ 4 trong ngày sẽ chưa bị gắn cờ, UAT-03 dễ trượt. BRD chưa nói đếm yêu cầu ở trạng thái nào, tiền là dự kiến hay thực tế | Tính lại ngay lúc tạo yêu cầu; đếm mọi yêu cầu trong 30 ngày trừ Cancelled; tiền tính theo dự kiến. Điều kiện: **từ 3** yêu cầu hoặc tổng tiền **trên** 30.000.000đ |
| BR-12 – số lần gửi | "Thử lại tối đa 3 lần" có thể hiểu là 1 + 3 = 4 lần gửi, nhưng UAT-06 ghi "đủ 3 lần lưu vết" | Theo UAT-06: tổng cộng 3 lần gửi |
| Hủy qua App | Phụ lục C cho khách hủy qua App, nhưng mục 7 không có API hủy | Giai đoạn này nhân viên hủy hộ trên Salesforce; hỏi IT có cần API hủy không |
| BR-01 – mã yêu cầu | Dạng RR-YYMM-00000 | Auto Number `RR-{YY}{MM}-{00000}`. Số thứ tự chạy liên tục, không về 0 mỗi tháng, nhưng vẫn không trùng |

## 3. Thiết kế dùng chung (chốt trong sáng N1)

Tên Apex dùng tiền tố `SR_`, LWC dùng tiền tố `sr`, API name tiếng Anh, label tiếng Việt. Bảng dưới đây phản ánh field trong metadata Salesforce hiện tại; các API name và đặc tính quan trọng được ghi theo metadata. Giá trị picklist dùng đúng chuỗi trong JSON ở Phụ lục E (`NOT_SATISFIED`, `OPENED`, `INSPECTING`…) để API khỏi phải chuyển đổi; label hiển thị tiếng Việt.

### 3.1 Object

| Object | Field chính | Phục vụ |
|---|---|---|
| `Return_Request__c` | Name (Text; không phải Auto Number), Account__c (Lookup Account), Order__c (Lookup Order), Store__c (Lookup Store__c), Channel__c (Picklist: COUNTER/POS/APP, bắt buộc), Status__c (Picklist, bắt buộc), External_Request_Id__c (Text, Unique; không bật External ID)<br>Estimated_Refund__c / Actual_Refund__c (Summary SUM từ các dòng), Approval_Level__c (AUTO/CHT/QLV), Assigned_Approver__c, Approved_By__c, Submitted_At__c, Approval_Due_At__c, Goods_Due_Date__c<br>Rejection_Reason__c, Internal_Note__c, PayHub_Refund_Id__c, Refund_Attempts__c, Next_Retry_At__c, Last_Refund_Error__c, Inspection_Completed_At__c, Refund_Final_Event_Sent__c, Version_Token__c<br>Approval_Overdue__c / Assigned_To_Me__c (formula checkbox) | BR-01, 06–13, 18 |
| `Return_Request_Line__c` (Master-Detail với `Return_Request__c`) | Return_Request__c, Order_Product__c (Lookup OrderItem), Product__c (Lookup Product2), Quantity__c, Unit_Price__c, Reason__c<br>Declared_Condition__c, Actual_Condition__c, Refund_Rate__c, Estimated_Refund__c, Actual_Refund_Rate__c, Actual_Refund__c<br>Inspection_Result__c, Inspection_Note__c | BR-04, 05; FR-10 |
| `Return_Request_History__c` | Return_Request__c (Master-Detail với `Return_Request__c`), From_Status__c, To_Status__c, Changed_By__c (Lookup User)<br>Changed_At__c (bắt buộc, mặc định NOW), Last_Modified_At__c (bắt buộc, mặc định NOW), Note__c, Correlation_Id__c | FR-06, NFR-08 |
| `Integration_Log__c` | Return_Request__c (Lookup `Return_Request__c`), System__c, Direction__c, Endpoint__c, Request_Body__c, Response_Body__c<br>Http_Status__c, Duration_Ms__c, Result__c, Attempt_No__c, Correlation_Id__c | BR-14 |
| `Application_Log__c` (đổi tên từ `Error_Log__c`) | Class_Method__c, Message__c, Stack_Trace__c, Record_Id__c, User__c (Lookup User)<br>Context__c, Correlation_Id__c, Level__c | NFR-09 |
| Account (thêm field) | Risk_Flag__c, Risk_Flag_Updated_At__c | BR-09 |

Lưu ý đối chiếu: `Return_Request__c.Name` hiện là Text nên định dạng mã yêu cầu RR-YYMM-00000 phải được tạo bởi logic ứng dụng nếu vẫn giữ yêu cầu đó; `External_Request_Id__c` là Unique nhưng chưa bật External ID. Dòng sản phẩm dùng API name `Order_Product__c` (không phải `Order_Item__c`); object log lỗi hiện có là `Application_Log__c` (không phải `Error_Log__c`).

Trước các object mới, phải tạo các object/field có sẵn ở Phụ lục A.1 (Store__c, field trên Order, User.Store_Code__c, giá trị Product2.Family).

### 3.2 Cấu hình (Phụ lục B) bằng Custom Metadata

Admin sửa trong Setup, có hiệu lực ngay, không cần deploy (FR-15, NFR-10). Code chỉ đọc cấu hình qua class `SR_Config`, không hard-code con số nào.

| Custom Metadata | Nội dung |
|---|---|
| `SR_Category_Policy__mdt` | Ngành hàng → có được trả không, số ngày (B.1) |
| `SR_Refund_Rate__mdt` | Lý do × tình trạng → tỷ lệ hoàn (B.2) |
| `SR_Setting__mdt` (1 bản ghi) | Tham số B.3 (ngưỡng 2tr/20tr, cờ rủi ro, hạn duyệt 24h, hạn mang hàng 7 ngày, PayHub 10s/3 lần/15') và 3 công tắc B.4 |

### 3.3 Các hàm dùng chung

```apex
// Dev A viết – Dev B (API) và Dev C (LWC) gọi, không ai viết lại logic
SR_ReturnRequestService.getReturnableLines(Id orderId)              // D.1: dòng nào trả được, hạn, SL còn lại, lý do bị khóa
SR_ReturnRequestService.createRequests(List<CreateRequestDTO> reqs)  // xử lý nhiều yêu cầu, trả kết quả từng cái (UI, API, import)
SR_ApprovalService.previewLevel(...)                                 // D.1: cấp duyệt dự kiến
SR_ApprovalService.decide(List<Id> ids, Boolean approve, String reason)
SR_InspectionService.complete(Id requestId, List<LineResultDTO> lines)
SR_StatusMachine.change(List<Return_Request__c> reqs, String toStatus, String note) // chặn chuyển sai (MSG-20), ghi lịch sử

// Dev B viết
SR_RefundService.enqueue(Set<Id> requestIds)        // Dev A gọi khi kiểm định xong
SR_EventPublisher.publishResult(List<Return_Request__c> reqs)
SR_Logger.error(...);  SR_IntegrationLogger.log(...)
```

Platform Event `Return_Request_Event__e` (Request_Number__c, Result__c, Amount__c, Store_Code__c, Event_Time__c) dùng chung cho INT-05 (POS/App) và FR-09 (màn hình duyệt). Đặt Publish Behavior = **Publish After Commit** để event chỉ được gửi khi dữ liệu đã lưu (BR-15).

### 3.4 Ai được sửa file nào (tránh conflict Git)

- Object, field, permission set: chỉ **Dev A** sửa. Ai cần thêm field thì nhắn Dev A.
- Custom Labels (MSG-xx), Lightning page, layout, Experience site: chỉ **Dev C** sửa.
- Named Credential, Connected App, Platform Event: chỉ **Dev B** sửa.
- Class và LWC: ai tạo thì người đó giữ; muốn sửa file của người khác thì báo trước.

## 4. Việc của từng người theo ngày

### Dev A – Nền tảng & nghiệp vụ (kiêm lead)

| Ngày | Việc | BRD |
|---|---|---|
| N1 | Object/field A.1 (**xong trước 11h** để Dev C làm dữ liệu mẫu) và A.2, gồm cả 2 object log; Custom Metadata + `SR_Config`; stub các hàm ở mục 3.3; `SR_TestDataFactory` | A.1, A.2, B |
| N2 | `createRequests`: kiểm tra hạn và ngành hàng (hạn = ngày giao + N ngày, tính hết ngày), số lượng còn trả được (khóa Order bằng `FOR UPDATE`), tính tiền và làm tròn xuống 1.000đ, chống trùng `externalRequestId`, cờ rủi ro. `SR_StatusMachine` theo Phụ lục C + ghi lịch sử | FR-02, 06; BR-01–06, 09 |
| N3 | Định tuyến duyệt (tự duyệt ≤ 2tr, CHT, QLV, khách rủi ro → QLV). `decide` cho nhiều yêu cầu: kết quả từng dòng (MSG-11), chống ghi đè (MSG-13), không tự duyệt (MSG-10). `SR_InspectionService`: tính lại tiền; mọi dòng Không đạt → Rejected, còn lại → Refund Processing rồi gọi `enqueue` | FR-07, 10; BR-07–10 |
| N4 | Phân quyền: OWD Private, chia sẻ theo cửa hàng/vùng (Apex Managed Sharing), permission set cho 6 vai trò + integration user, Kế toán/CSKH chỉ được xem, ẩn Ghi chú nội bộ. Job đêm 01:00: hủy Awaiting Goods quá 7 ngày, cập nhật cờ rủi ro, chuyển cấp yêu cầu quá hạn duyệt và báo QLV, gửi tiếp yêu cầu đang dừng ở Inspecting khi công tắc PayHub được bật lại | FR-15, 16; BR-11, 16, 18 |
| N5 | Chạy UAT chéo (phần của Dev B); sửa lỗi; deploy lên org sạch theo `docs/DEPLOY.md` | NFR-12 |

### Dev B – Tích hợp & xử lý nền

| Ngày | Việc | BRD |
|---|---|---|
| N1 | `SR_Logger`, `SR_IntegrationLogger`; Named Credential + External Credential cho PayHub; `SR_PayHubClient` (interface) và bản mock giả lập SUCCESS / PENDING / 422 / 500 / timeout (vì PayHub chưa có môi trường test); tạo Platform Event | NFR-06, 09; BR-14 |
| N2 | `SR_RefundService`: Queueable cho phép callout, timeout 10s, Idempotency-Key = mã yêu cầu; xử lý kết quả theo bảng E.3. Thử lại cách nhau ≥ 15' (4 scheduled job ở phút 00/15/30/45 quét `Next_Retry_At__c`); hết lượt → Refund Failed và giao việc cho Kế toán kèm lỗi. Nút để Kế toán nhập mã giao dịch khi đã hoàn thủ công (Refund Failed → Completed). Gửi event khi Completed hoặc Refund Failed | FR-11, 13, 14; BR-12–15; INT-03, 05; NFR-04 |
| N3 | INT-01 POST và INT-02 GET `/smartreturn/v1/return-requests` đúng JSON và mã lỗi ở E.1/E.2 (gửi trùng → 200 với nội dung lần đầu; không trả Ghi chú nội bộ). Connected App OAuth 2.0, mỗi hệ thống 1 integration user. INT-04 `/refund-callback` (gọi lặp không làm đổi dữ liệu; merchantRef không tồn tại → 404) | FR-03, 04, 12; INT-01, 02, 04 |
| N4 | Tìm kiếm cho CSKH: SOSL trên 3 nhóm, từ 3 ký tự, tối đa 20 kết quả mỗi nhóm, cột lấy theo Field Set, ẩn field người dùng không có quyền. Import 200 yêu cầu có vài bản ghi lỗi (UAT-01). Postman collection cho mọi API. Đo thời gian phản hồi API ≤ 2s | FR-17, 18; NFR-02, 03 |
| N5 | Chạy UAT chéo (phần của Dev C); sửa lỗi; hỗ trợ deploy | |

### Dev C – Giao diện & Portal

| Ngày | Việc | BRD |
|---|---|---|
| N1 | Custom Labels cho toàn bộ MSG-xx. Script dữ liệu mẫu (3 vùng, 4–6 cửa hàng, user cho mỗi vai trò, đơn đủ các ngành hàng với ngày giao khác nhau, có đơn mua tại quầy) – làm sau 11h khi đã có A.1. Tạo Experience Cloud site (kiểm tra org có license cho khách đăng nhập; nếu chưa có thì làm phần khách vãng lai trước). Khung LWC tạo yêu cầu | Phụ lục F |
| N2 | D.1 Tạo yêu cầu tại quầy: Quick Action trên Order; dòng bị khóa hiển thị mờ kèm lý do; tiền và cấp duyệt dự kiến cập nhật ngay; báo MSG-01 rồi mở trang yêu cầu. D.3 Kiểm định: Đạt/Không đạt, ghi chú bắt buộc khi Không đạt, sửa tình trạng thì tính lại tiền, nút Hoàn tất có hỏi xác nhận. Nút Nhận hàng (Awaiting Goods → Inspecting) và nút Hủy | FR-01, 02, 10 |
| N3 | D.2 Màn hình duyệt cho CHT/QLV: bộ lọc mặc định, các cột, sắp xếp, tô đỏ yêu cầu quá hạn, biểu tượng cờ rủi ro, duyệt/từ chối hàng loạt (từ chối bắt buộc nhập lý do), báo kết quả từng dòng, phân trang 50 dòng | FR-08 |
| N4 | D.4 Customer Portal: khách vãng lai tra bằng mã + 4 số cuối SĐT (mọi trường hợp sai đều báo MSG-40, không hiện số tiền và SĐT); khách đăng nhập xem danh sách của mình; khóa 15' sau 5 lần sai; thuộc tính cấu hình trong Experience Builder. Thông báo realtime trên D.2 bằng `lightning/empApi` | FR-05, 09; BR-17; NFR-07 |
| N5 | Chạy UAT chéo (phần của Dev A); kiểm tra trên tablet và tiếng Việt; chuẩn bị demo | NFR-11 |

## 5. Lịch chung và mốc kiểm tra

| | Dev A | Dev B | Dev C | Mốc cuối ngày trên org chung |
|---|---|---|---|---|
| N1 | Data model, cấu hình, stub | Log, PayHub mock | Labels, dữ liệu mẫu, site | Cả team có môi trường và dữ liệu |
| N2 | Tạo yêu cầu, trạng thái | Gửi lệnh PayHub, thử lại | Màn hình tạo yêu cầu, kiểm định | Tạo yêu cầu tại quầy chạy thật |
| N3 | Duyệt, kiểm định | API cho POS/App, callback | Màn hình duyệt | **Chuyện 1** (đơn nhỏ tự duyệt) chạy trọn |
| N4 | Phân quyền, job đêm | Tìm kiếm CSKH, import | Portal, realtime | **Chuyện 2** (đơn lớn, PayHub lỗi) chạy trọn; dừng thêm tính năng |
| N5 | UAT chéo, deploy | UAT chéo, sửa lỗi | UAT chéo, demo | Đạt 10/10 UAT, có hướng dẫn deploy |

Hai câu chuyện ở đầu BRD dùng luôn làm kịch bản demo.

Nhịp làm việc: standup 15' lúc 9h. 16h30 mọi người merge vào `main`, Dev A deploy lên org chung và chạy thử luồng chính. Kẹt quá 30 phút thì hỏi ngay. N3 của Dev B và N4 của Dev A là hai ngày nặng nhất; ai xong sớm thì vào hỗ trợ.

## 6. UAT chéo ngày 5

Người không viết phần đó sẽ đi test, để bắt lỗi khách quan hơn.

| UAT | Nội dung | Người test |
|---|---|---|
| 01, 05, 06, 10 | Import 200, gửi trùng, PayHub lỗi 3 lần, tắt gửi PayHub | Dev A |
| 07, 09 | Thông báo realtime cho CHT, khách vãng lai nhập sai | Dev B |
| 02, 03, 04, 08 | Tự duyệt, khách rủi ro → QLV, quá hạn đổi trả, xem chéo cửa hàng | Dev C |

Feature chỉ được nghiệm thu khi đạt cả 10 kịch bản.

## 7. Thế nào là "xong" một task

- Chạy được trên org chung, không chỉ trên org cá nhân.
- Có test class, gồm cả trường hợp sai; cả project đạt ≥ 75% coverage.
- Thông báo dùng đúng mã MSG-xx; ngưỡng và tỷ lệ đọc từ Custom Metadata.
- Commit/PR ghi ID trong BRD (FR/BR/INT) để tra ngược.

## 8. Nếu trễ thì cắt gì

Chỉ cắt phần Should/Could. Mọi FR mức Must và toàn bộ BR giữ nguyên. Thứ tự cắt:

1. FR-18 (Could): Admin chọn cột kết quả tìm kiếm → để cột cố định.
2. Khóa tra cứu 15' sau 5 lần sai trên Portal (Should).
3. FR-17 (Should): ô tìm kiếm cho CSKH → tạm dùng Global Search có sẵn.
4. FR-09 (Should): thông báo realtime → phải báo trước, vì UAT-07 kiểm tra đúng phần này.

## 9. Lưu ý kỹ thuật dễ vấp

- **Callout sau DML:** Salesforce không cho gọi API ngoài sau khi đã ghi dữ liệu trong cùng transaction, nên gửi lệnh PayHub bằng Queueable. Cách này cũng đáp ứng NFR-04 (người dùng không phải chờ PayHub).
- **Thử lại mỗi 15 phút:** một Scheduled Apex job không đặt được lịch "mỗi 15 phút", nên tạo 4 job ở phút 00, 15, 30, 45.
- **Hai giao dịch cùng lúc:** dùng `SELECT … FOR UPDATE` để khóa Order khi tính số lượng còn trả (BR-04) và khóa yêu cầu trước khi gửi PayHub (BR-13).
- **Xử lý 200 bản ghi:** không để SOQL/DML trong vòng lặp; báo lỗi theo từng bản ghi (`addError`, `Database.insert(list, false)`) để bản ghi đúng vẫn được lưu (NFR-02).
- **Token PayHub:** dùng Named Credential + External Credential với header `Authorization: Bearer …`, để đổi token 90 ngày/lần không phải sửa code (NFR-06, yêu cầu của IT ở mục 7).
- **Phân quyền:** yêu cầu tạo từ POS/App do integration user sở hữu, nên không dựa vào owner được; phải chia sẻ theo Store__c. UAT-08 test cả qua link lẫn qua API.
- **Portal:** profile Guest không có quyền trên object; controller `without sharing` chỉ trả về các field được phép (BR-17, NFR-07).
- **Múi giờ:** Time Zone của org và của user chạy job là GMT+7, để job 01:00 và các hạn 24 giờ / 7 ngày tính đúng.
- **empApi:** chỉ dùng cho màn hình nội bộ (D.2), không dùng trong Portal.

## 10. Ma trận truy vết BRD → người phụ trách

| Người | FR | BR | INT / NFR | UAT |
|---|---|---|---|---|
| Dev A | 02, 06, 07, 15, 16 | 01–11, 16, 18 | NFR-01, 05, 08, 10, 12 | 02, 03, 04, 08 |
| Dev B | 03, 04, 11, 12, 13, 14, 17, 18 | 12–15 | INT-01–05; NFR-02, 03 (API, tìm kiếm), 04, 06, 09 | 01, 05, 06, 10 |
| Dev C | 01, 05, 08, 09, 10 | 17 | NFR-03 (màn hình), 07, 11 | 07, 09 |

FR-08 và FR-10: Dev C làm màn hình, Dev A làm phần xử lý (`decide`, `SR_InspectionService`).
