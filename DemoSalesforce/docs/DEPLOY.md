# Deploy SmartReturn lên org mới

Tài liệu cho người cài SmartReturn lên một org Salesforce mới (Developer Edition, sandbox hoặc scratch org). Làm lần lượt từ mục 1 đến mục 6 là cài xong; mỗi bước có lệnh kiểm tra kết quả. Production xem thêm mục 9.

Đã chạy thử trọn tài liệu trên 2 scratch org sạch ngày 28/10/2026: deploy 8 bước thành công, **578/578 test đạt**. Những phần chưa làm được vì code chưa có trong repo được đánh dấu ⚠ và liệt kê ở mục 8.

Thời gian: khoảng 45 phút (deploy 8 bước ~5 phút, chạy test ~10 phút, còn lại là các bước sau deploy).

**Tóm tắt**

| Mục | Việc                                           | Lệnh / nơi làm                                   |
| --- | ---------------------------------------------- | ------------------------------------------------ |
| 1   | Chuẩn bị máy và org                            | Setup, `sf org login web`                        |
| 3   | Deploy 8 bước theo thứ tự                      | `npm run deploy -- -o <alias>`                   |
| 4   | Chạy toàn bộ test                              | `npm run deploy -- -o <alias> --run-tests`       |
| 5.1 | URL + token PayHub                             | Setup › Named Credentials                        |
| 5.2 | Gán permission set                             | `sf org assign permset`                          |
| 5.3 | Integration user + External Client App         | Setup › Users, External Client App Manager       |
| 5.4 | Group Kế toán (⚠ group cửa hàng/vùng chờ code) | Setup › Public Groups                            |
| 5.5 | Đặt lịch job đêm + 4 job thử lại               | `sf apex run -f scripts/apex/schedule-jobs.apex` |
| 5.6 | Publish site                                   | `sf community publish`                           |
| 6   | Kiểm tra sau cài đặt                           | bảng ở mục 6                                     |

Trong tài liệu, `sr-clean` là alias của org đích; đổi thành alias của bạn.

---

## 1. Chuẩn bị

### 1.1 Máy

- Git, Node.js 18 trở lên, Salesforce CLI v2 (`sf --version` ra `@salesforce/cli/2.x`).
- Lấy code và cài thư viện. Thư mục SFDX là `DemoSalesforce/` trong repo; **mọi lệnh trong tài liệu chạy ở thư mục này**.

```bash
git clone https://github.com/javis-ngo/DemoSalesforce.git
```

```bash
cd DemoSalesforce/DemoSalesforce
```

```bash
npm install
```

### 1.2 Org

Chọn một trong hai cách.

**Cách A – scratch org** (nhanh nhất để thử; cần 1 org Dev Hub đã đăng nhập). File `config/project-scratch-def.json` đã bật Digital Experiences.

```bash
sf org login web -a sr-devhub
```

```bash
sf org create scratch -f config/project-scratch-def.json -a sr-clean -v sr-devhub -y 7 -w 15
```

**Cách B – Developer Edition hoặc sandbox mới**

```bash
sf org login web -a sr-clean
```

Sandbox thì thêm `-r https://test.salesforce.com`. Sau đó vào Setup của org:

1. Setup › **Digital Experiences** › **Settings** › tick **Enable Digital Experiences** › Save (bỏ qua nếu đã bật).

### 1.3 Thiết lập org (cả hai cách)

1. Setup › **Company Information** › Edit:
   - Default Time Zone: `(GMT+07:00) Indochina Time (Asia/Ho_Chi_Minh)`
   - Default Locale: `Vietnamese (Vietnam)`
   - Currency Locale: `Vietnamese (Vietnam) - VND` (chỉ đổi được khi org chưa bật Multi-Currency)
2. Đặt Time Zone GMT+7 cho user admin sẽ deploy và đặt lịch job (cron của job tính theo giờ của user đặt lịch). Làm trong Setup › Users, hoặc:

```bash
sf data update record -o sr-clean -s User -w "Username='<username admin>'" -v "TimeZoneSidKey=Asia/Ho_Chi_Minh"
```

3. Kiểm tra license. Cần **Customer Community** (khách đăng nhập Portal) và **Salesforce Integration** (integration user, mục 5.3); license Guest có sau khi tạo site ở bước 8:

```bash
sf data query -o sr-clean -q "SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense WHERE Name IN ('Customer Community','Salesforce Integration')"
```

Developer Edition và scratch org chỉ có 1 license Salesforce Integration; xem cách xử lý ở mục 5.3.

---

## 2. Trước khi deploy

- **URL PayHub**: `force-app/main/default/namedCredentials/PayHub.namedCredential-meta.xml` đang để `https://payhub.example.com`. Có URL thật thì sửa ở mục 5.1 sau khi deploy (không cần sửa file). Repo không chứa token hay secret nào.
- **Email người gửi của site**: Network `SmartReturn Portal` cần một email người gửi. Trong git, field này là `__SR_PORTAL_SENDER_EMAIL__` và được thay lúc deploy (`replacements` trong `sfdx-project.json`) bằng biến môi trường `SR_PORTAL_SENDER_EMAIL`. Script ở mục 3 tự lấy email của user đang deploy nếu bạn không đặt biến này.
- Deploy lại lên org **đã có lịch job** thì đọc mục 7, lỗi "This schedulable class has jobs pending".

---

## 3. Deploy theo thứ tự

```bash
npm run deploy -- -o sr-clean
```

Script `scripts/deploy.js` deploy 8 bước dưới đây, mỗi bước một lần `sf project deploy start` với `--test-level NoTestRun`, dừng ở bước đầu tiên bị lỗi. Sửa lỗi xong thì chạy tiếp từ bước đó, ví dụ `npm run deploy -- -o sr-clean --from 4`. Xem danh sách bước: `npm run deploy -- --list`.

Kết quả đúng: mỗi bước in `OK – N thành phần (job 0Af…)`, cuối cùng in `Deploy xong 8 bước`.

| Bước | Nội dung                                                                                                                                | Thư mục trong `force-app/main/default/`                                                                          |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| 1    | Object và field; field thêm trên Account, Order, User; Global Value Set mà picklist dùng                                                | `globalValueSets`, `objects/` (7 object `__c`, `Account`, `Order`, `User`)                                       |
| 2    | Custom Metadata Type kèm bản ghi (SR_Setting, SR_Category_Policy, SR_Refund_Rate)                                                       | `objects/SR_*__mdt`, `customMetadata`                                                                            |
| 3    | Platform Event, Flow ghi log từ event, External Credential, Named Credential                                                            | `objects/*__e`, `flows`, `externalCredentials`, `namedCredentials`                                               |
| 4    | Apex, kèm Custom Label, Custom Permission, Notification Type mà Apex dùng                                                               | `labels`, `customPermissions`, `notificationtypes`, `classes`, `triggers`                                        |
| 5    | LWC                                                                                                                                     | `lwc`                                                                                                            |
| 6    | Permission set                                                                                                                          | `permissionsets`                                                                                                 |
| 7    | App, tab, Lightning page, layout, quick action, path; cài đặt Path và ngôn ngữ; profile Admin (app, tab, FLS)                           | `settings`, `quickActions`, `layouts`, `flexipages`, `tabs`, `pathAssistants`, `applications`, `profiles/Admin…` |
| 8    | Experience site: tạo site nếu chưa có, rồi deploy cấu hình site, trang LWR, profile Guest, profile Customer Community User, sharing set | `networks`, `sites`, `digitalExperienceConfigs`, `digitalExperiences`, 2 profile, `sharingSets`                  |

Ghi chú:

- **Bước 8** tự chạy `sf community create` (template _Build Your Own (LWR)_, đường dẫn `doitra`) khi org chưa có site _SmartReturn Portal_, rồi chờ site tạo xong (2–5 phút). Lần đầu chạy lệnh này, CLI tự cài plugin `community`. Network không tạo mới được bằng metadata nên không bỏ được bước tạo site.
- Script luôn thêm `--ignore-conflicts`: scratch org theo dõi thay đổi, mỗi lần deploy object thì Salesforce tự đổi profile Admin, lần deploy sau sẽ báo "conflicts detected". Repo là bản đúng nên ghi đè.
- **Language settings** (bước 7) bật _End-User Languages_: site Portal dùng Tiếng Việt làm ngôn ngữ mặc định, mà Tiếng Việt chỉ có khi bật tùy chọn này. Thiếu thì deploy vẫn qua nhưng publish site lỗi (mục 7).
- **Profile Admin** mang FLS cho mọi field SmartReturn. Bắt buộc: Apex ở API 68 truy vấn ở USER_MODE, field deploy bằng metadata không được cấp FLS cho profile nào, nên thiếu bước này thì màn hình lỗi và ~110 test hỏng với `No such column 'X__c'`.

<details>
<summary>Làm tay không dùng script (cùng 8 lệnh)</summary>

Chạy lần lượt; `F=force-app/main/default`. Trên Windows PowerShell thay `$F` bằng đường dẫn đầy đủ.

```bash
F=force-app/main/default; O="-o sr-clean --test-level NoTestRun --ignore-conflicts --wait 60"
sf project deploy start $O -d $F/globalValueSets -d $F/objects/Store__c -d $F/objects/Return_Request__c -d $F/objects/Return_Request_Line__c -d $F/objects/Return_Request_History__c -d $F/objects/SR_Lookup_Attempt__c -d $F/objects/Integration_Log__c -d $F/objects/Application_Log__c -d $F/objects/Account -d $F/objects/Order -d $F/objects/User
sf project deploy start $O -d $F/objects/SR_Setting__mdt -d $F/objects/SR_Category_Policy__mdt -d $F/objects/SR_Refund_Rate__mdt -d $F/customMetadata
sf project deploy start $O -d $F/objects/Log_Event__e -d $F/objects/Integration_Log_Event__e -d $F/objects/Return_Request_Event__e -d $F/objects/SR_UI_Notice__e -d $F/flows -d $F/externalCredentials -d $F/namedCredentials
sf project deploy start $O -d $F/labels -d $F/customPermissions -d $F/notificationtypes -d $F/classes -d $F/triggers
sf project deploy start $O -d $F/lwc
sf project deploy start $O -d $F/permissionsets
sf project deploy start $O -d $F/settings -d $F/quickActions -d $F/layouts -d $F/flexipages -d $F/tabs -d $F/pathAssistants -d $F/applications -d "$F/profiles/Admin.profile-meta.xml"
sf community create -o sr-clean --name "SmartReturn Portal" --template-name "Build Your Own (LWR)" --url-path-prefix doitra
# chờ: sf data query -o sr-clean -q "SELECT Status FROM BackgroundOperation WHERE Id = '<jobId lệnh trên trả về>'" ra Complete
SR_PORTAL_SENDER_EMAIL=<email admin> sf project deploy start $O -d $F/networks -d $F/sites -d $F/digitalExperienceConfigs -d $F/digitalExperiences -d "$F/profiles/SmartReturn Portal Profile.profile-meta.xml" -d "$F/profiles/Customer Community User.profile-meta.xml" -d $F/sharingSets
```

</details>

---

## 4. Chạy toàn bộ test

Chạy **sau** bước 8 (test `SR_PortalServiceTest` chạy bằng user Guest của site) và **trước** khi đặt lịch job (mục 5.5).

```bash
npm run deploy -- -o sr-clean --run-tests
```

Lệnh này deploy lại cả `force-app` và chạy mọi test trong org, tương đương:

```bash
SR_PORTAL_SENDER_EMAIL=<email admin> sf project deploy start --source-dir force-app --test-level RunLocalTests --ignore-conflicts --wait 120 -o sr-clean
```

Kết quả đúng: `OK – … thành phần, 578/578 test đạt` (số test có thể tăng theo code). Có test hỏng thì script in tên test và lỗi; xem đầy đủ bằng `sf project deploy report --use-most-recent -o sr-clean`. Chỉ muốn kiểm tra, không ghi gì lên org: thêm `--dry-run` vào lệnh `sf` ở trên.

---

## 5. Sau deploy

### 5.1 PayHub: URL và token

1. URL: Setup › **Named Credentials** › tab _Named Credentials_ › **PayHub** › Edit › URL = địa chỉ PayHub thật (code gọi `callout:PayHub/v1/refunds`) › Save.
2. Token: Setup › **Named Credentials** › tab _External Credentials_ › **PayHub Credential** › khung _Principals_, dòng **PayHubPrincipal** › Edit › _Authentication Parameters_ › Add: Name `Token`, Value = token PayHub › Save. Header gửi đi là `Authorization: Bearer <Token>`.
3. **Đổi token mỗi 90 ngày**: làm lại bước 2, sửa Value của `Token`. Không cần deploy, không đụng code.

Cách dùng lệnh thay cho bước 2 (lần đầu dùng `POST`, đổi token dùng `PUT`); tạo file tạm ngoài repo rồi xóa ngay:

```json
{
  "externalCredential": "PayHub_Credential",
  "principalName": "PayHubPrincipal",
  "principalType": "NamedPrincipal",
  "credentials": { "Token": { "value": "<token>", "encrypted": true } }
}
```

```bash
sf api request rest "/services/data/v68.0/named-credentials/credential" --method POST --body @/duong-dan/token.json -o sr-clean
```

Kết quả đúng: JSON trả về có `"Token": { "encrypted": true, … "revision": 1 }` (không hiện giá trị token).

**Chưa có PayHub thật** (demo, UAT): bật mock. Setup › **Custom Metadata Types** › _SR Setting_ › Manage Records › **Default** › Edit › tick _PayHub Use Mock_, _PayHub Mock Scenario_ = `SUCCESS` › Save. Lưu ý: deploy lại `customMetadata` sẽ ghi đè các giá trị sửa trong Setup bằng giá trị trong git.

### 5.2 Gán permission set

| Ai                                                                 | Permission set                                                                                                                                    | Vì sao                                                                   |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Admin đặt lịch job (mục 5.5)                                       | `SR_PayHub_Callout`                                                                                                                               | Job chạy dưới quyền người đặt lịch và gọi PayHub qua External Credential |
| NV, CHT hoàn tất kiểm định                                         | `SR_PayHub_Callout` + permission set vai trò                                                                                                      | Lệnh hoàn tiền chạy Queueable dưới quyền người bấm                       |
| NV, CHT, QLV, Kế toán, CSKH, Admin, integration user, khách Portal | ⚠ `SR_Store_Staff`, `SR_Store_Manager`, `SR_Regional_Manager`, `SR_Accountant`, `SR_CSKH`, `SR_Admin`, `SR_Integration_API`, `SR_Portal_Customer` | Chưa có trong git (mục 8). Khi có, gán như lệnh dưới                     |
| Chỉ dev                                                            | `SmartReturn_Dev_Access`                                                                                                                          | Toàn quyền object SmartReturn để code; không gán ở production            |

```bash
sf org assign permset -n SR_PayHub_Callout -o sr-clean
```

Gán cho user khác: thêm `-b <username>`. Kiểm tra:

```bash
sf data query -o sr-clean -q "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SR%'"
```

### 5.3 Integration user và External Client App

Mỗi hệ thống gọi API (POS, App, PayHub gọi `/refund-callback`) dùng 1 integration user và 1 External Client App riêng, OAuth 2.0 Client Credentials. Dùng **External Client App** (Setup › External Client App Manager), không dùng Connected App kiểu cũ. Client Secret không đưa vào repo.

API của SmartReturn:

- `POST /services/apexrest/smartreturn/v1/return-requests` (INT-01) và `GET /services/apexrest/smartreturn/v1/return-requests/<mã yêu cầu>` (INT-02)
- `POST /services/apexrest/smartreturn/v1/refund-callback` (INT-04, PayHub gọi)

**Integration user** (làm cho từng hệ thống: `SR POS`, `SR App`, `SR PayHub`):

1. Setup › **Users** › New User: Last Name `SR POS Integration`; Email: email người quản trị; Username dạng `sr.pos@<tên-org>.integration`; User License **Salesforce Integration**; Profile **Minimum Access - API Only Integrations** › Save.
2. Trên trang user: _Permission Set License Assignments_ › Edit Assignments › tick **Salesforce API Integration** › Save.
3. _Permission Set Assignments_ › Edit Assignments › thêm ⚠ `SR_Integration_API` (chưa có trong git, mục 8) › Save.

Developer Edition và scratch org chỉ có 1 license Salesforce Integration: tạo 1 user dùng chung cho cả 3 app khi demo và ghi rõ hạn chế này.

**External Client App** (mỗi hệ thống 1 app: `SR_POS`, `SR_App`, `SR_PayHub`):

1. Setup › **External Client App Manager** › **New External Client App**.
2. Basic Information: Name `SR_POS`, Contact Email, Distribution State **Local**.
3. API (Enable OAuth Settings): tick _Enable OAuth_; Callback URL `https://login.salesforce.com/services/oauth2/callback` (bắt buộc nhập, flow này không dùng); OAuth Scopes: **Manage user data via APIs (api)**; Flow Enablement: tick **Enable Client Credentials Flow** › Create.
4. Tab **Policies** › Edit › OAuth Policies: tick _Enable Client Credentials Flow_, **Run As** = integration user của hệ thống đó › Save.
5. Tab **Settings** › OAuth Settings › **Consumer Key and Secret** (Salesforce gửi mã xác minh qua email) › gửi Key và Secret cho đội của hệ thống đó qua kênh bảo mật.
6. Thử (thay `<MyDomain>` bằng My Domain của org; Client Credentials không chạy qua `login.salesforce.com`):

```bash
curl -s https://<MyDomain>.my.salesforce.com/services/oauth2/token -d grant_type=client_credentials -d client_id=<Consumer Key> -d client_secret=<Consumer Secret>
```

```bash
curl -s https://<MyDomain>.my.salesforce.com/services/apexrest/smartreturn/v1/return-requests/<mã yêu cầu> -H "Authorization: Bearer <access_token>"
```

Kết quả đúng: lệnh 1 trả `access_token`; lệnh 2 trả JSON của yêu cầu, hoặc 404 `REQUEST_NOT_FOUND` nếu mã không tồn tại. Lỗi 403/`INSUFFICIENT_ACCESS` nghĩa là user chưa có `SR_Integration_API`.

### 5.4 Group cửa hàng, vùng, Kế toán

- **SR_Accounting** (Kế toán nhận việc khi hoàn tiền thất bại, FR-14): Setup › **Public Groups** › New › Label `SR Kế toán`, Group Name `SR_Accounting` › thêm các user Kế toán › Save. Tạo group bằng lệnh (thêm thành viên vẫn làm trong Setup):

```bash
sf data create record -o sr-clean -s Group -v "Name='SR Kế toán' DeveloperName=SR_Accounting Type=Regular"
```

- ⚠ **Group cửa hàng `SR_Store_<mã>` và vùng `SR_Region_<vùng>`**: tạo bằng `SR_SharingService` (Dev A – Đức, DUNG-13), chưa có trong repo (mục 8). Khi có: dữ liệu mẫu thì `npm run seed -- -o sr-clean` (seed 3 tạo group); dữ liệu thật thì chạy batch tính lại share của `SR_SharingService`.

Kiểm tra:

```bash
sf data query -o sr-clean -q "SELECT DeveloperName, Name FROM Group WHERE Type = 'Regular' AND DeveloperName LIKE 'SR%'"
```

### 5.5 Đặt lịch job đêm và 4 job thử lại

Trước khi chạy: user chạy lệnh đã có `SR_PayHub_Callout` (5.2) và Time Zone GMT+7 (1.3). Đã chạy xong mục 4 (đặt lịch rồi thì không deploy lại class đó được, xem mục 7).

```bash
sf apex run -f scripts/apex/schedule-jobs.apex -o sr-clean
```

Script đặt 4 job `SR PayHub retry :00/:15/:30/:45` (BR-12, gửi lại lệnh hoàn tiền lỗi mỗi 15 phút) và job đêm `SR Nightly 01:00`. ⚠ Job đêm cần class `SR_NightlyJob` (Dev A – Đức, DUNG-14), chưa có trong repo: script tự bỏ qua, chạy lại script khi class đã deploy. Chạy lại nhiều lần không tạo job trùng.

Kiểm tra (đúng: 4 dòng `SR PayHub retry`, thêm 1 dòng `SR Nightly 01:00` khi đã có job đêm):

```bash
sf data query -o sr-clean -q "SELECT CronJobDetail.Name, CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE 'SR %' ORDER BY CronJobDetail.Name"
```

### 5.6 Publish site

```bash
sf community publish -n "SmartReturn Portal" -o sr-clean
```

Lệnh trả về ngay ("We're publishing your changes now") **kể cả khi publish lỗi**; publish chạy nền 1–3 phút. Kiểm tra kết quả, đúng khi `Status` = `Complete`:

```bash
sf data query -o sr-clean -q "SELECT Status, Error, CreatedDate FROM BackgroundOperation WHERE Name = 'Connect API Site Publish' ORDER BY CreatedDate DESC LIMIT 1"
```

`Error` thì xem mục 7. Lấy địa chỉ site:

```bash
sf data query -o sr-clean -q "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE PathPrefix = '/doitra'"
```

Mở `https://<Domain>/doitra/` bằng cửa sổ ẩn danh: thấy ô tra cứu yêu cầu (khách vãng lai, không cần đăng nhập). Site LWR giữ nguyên phiên bản LWC và Custom Label lúc publish, nên **mỗi lần deploy lại LWC `srPortal*`, `srUtils` hoặc label thì publish lại**.

⚠ Khách **đăng nhập** Portal (trang _Yêu cầu của tôi_) còn thiếu: permission set `SR_Portal_Customer` và thêm profile _Customer Community User_ vào Members của site (mục 8).

### 5.7 Dữ liệu mẫu (tuỳ chọn, cho demo)

```bash
npm run seed -- -o sr-clean
```

Tạo user theo vai, cửa hàng, sản phẩm, khách, đơn hàng và 5 yêu cầu mẫu (xem đầu file `scripts/seed.js`). Thiếu license thì seed 1 bỏ qua vai không tạo được user; seed 3 (group) báo lỗi rồi chạy tiếp cho đến khi có `SR_SharingService`.

---

## 6. Kiểm tra sau cài đặt

| Kiểm tra                          | Cách                                                                                                                                                                                                                                                                    | Đúng khi                                                        |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Test                              | mục 4                                                                                                                                                                                                                                                                   | 578/578 đạt                                                     |
| App                               | App Launcher › **SmartReturn**                                                                                                                                                                                                                                          | Có 4 tab: Return Requests, Duyệt yêu cầu, Tìm kiếm CSKH, Stores |
| Ghi log qua Platform Event + Flow | `echo "SR_Logger l = SR_Logger.getInstance(); l.info('DeployCheck', 'DeployCheck', null, 'ok', null); l.push();" \| sf apex run -o sr-clean` rồi `sf data query -o sr-clean -q "SELECT Level__c, Message__c FROM Application_Log__c ORDER BY CreatedDate DESC LIMIT 1"` | Có 1 dòng `INFO`, `ok`                                          |
| Token PayHub                      | mục 5.1                                                                                                                                                                                                                                                                 | `"Token"` có `revision`                                         |
| Job                               | lệnh kiểm tra ở mục 5.5                                                                                                                                                                                                                                                 | 4 job `SR PayHub retry` (+ job đêm khi có)                      |
| Site                              | mở `https://<Domain>/doitra/` ẩn danh                                                                                                                                                                                                                                   | Trang tra cứu hiện ra, không đòi đăng nhập                      |

---

## 7. Lỗi thường gặp

| Lỗi                                                                                                                               | Nguyên nhân                                                                        | Cách sửa                                                                                                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LỖI: fetch failed` (hoặc `ECONNRESET`, `socket hang up`) rồi `Dừng ở bước N`                                                     | Mạng chập chờn, CLI mất kết nối với org                                            | Script đã tự thử lại 3 lần. Vẫn lỗi thì xem lần deploy gần nhất đã tới org chưa: `sf project deploy report --use-most-recent -o sr-clean`; đang chạy thì chờ xong, rồi chạy lại `npm run deploy -- -o sr-clean --from N` (deploy lại một bước không hại gì)          |
| `The global picklist cannot be resolved`                                                                                          | Deploy object mà chưa có Global Value Set `Log_Level`, `SR_Condition`              | Deploy bằng script (bước 1 có `globalValueSets`)                                                                                                                                                                                                                     |
| `Required fields are missing: [Portal_Lock_Minutes__c]`                                                                           | Bản ghi `SR_Setting.Default` để trống field bắt buộc                               | Đã sửa trong git (15 phút, 5 lần); lấy code mới nhất                                                                                                                                                                                                                 |
| `N conflicts detected`                                                                                                            | Scratch org theo dõi thay đổi                                                      | Thêm `--ignore-conflicts` (script đã có)                                                                                                                                                                                                                             |
| `Network …: Required field is missing: emailSenderAddress`                                                                        | Thiếu email người gửi của site                                                     | Đặt `SR_PORTAL_SENDER_EMAIL` hoặc dùng script                                                                                                                                                                                                                        |
| `"SR_PORTAL_SENDER_EMAIL" is in sfdx-project.json as a value for "replaceWithEnv" property, but it's not set in your environment` | Deploy file Network bằng `sf` trực tiếp mà không đặt biến                          | `SR_PORTAL_SENDER_EMAIL=<email> sf project deploy start …`                                                                                                                                                                                                           |
| `no Network named SmartReturn Portal found`, `no UserLicense named Guest User License found`                                      | Chưa tạo site                                                                      | Chạy bước 8 bằng script, hoặc `sf community create` như mục 3                                                                                                                                                                                                        |
| Test hỏng `No such column 'X__c'`, `fields being inaccessible`                                                                    | User chạy test không có FLS trên field SmartReturn                                 | Deploy bước 7 (profile Admin). User deploy không dùng profile System Administrator thì cấp FLS cho profile đó                                                                                                                                                        |
| `This schedulable class has jobs pending or in progress`                                                                          | Deploy lại class có job đang lên lịch (`SR_RefundRetryJob`, `SR_RefundService`, …) | Hủy lịch, deploy, đặt lại: `echo "SR_RefundRetryJob.unscheduleAll();" \| sf apex run -o sr-clean` → deploy → chạy lại mục 5.5. Hoặc Setup › **Deployment Settings** › tick _Allow deployments of components when corresponding Apex jobs are pending or in progress_ |
| Publish site `Error`: `Something went wrong… error <số>`; mở `/doitra/` bị chuyển sang `/doitravforcesite/login`                  | Org chưa bật End-User Languages, site Tiếng Việt không publish được                | Deploy bước 7 (`settings/Language.settings-meta.xml`) hoặc Setup › **Language Settings** › tick _Enable End-User Languages_; rồi publish lại                                                                                                                         |
| Site vẫn chạy bản cũ sau khi deploy LWC/label                                                                                     | Site LWR giữ bản lúc publish                                                       | Publish lại (mục 5.6)                                                                                                                                                                                                                                                |

Khi **retrieve** Network từ org về (`sf project retrieve start -m "Network:SmartReturn Portal"`), file sẽ chứa email thật thay cho `__SR_PORTAL_SENDER_EMAIL__`: đặt lại placeholder trước khi commit.

---

## 8. Phần còn thiếu trong repo (28/10/2026)

Các mục ⚠ ở trên chưa làm được trên org mới vì code/metadata chưa có trong git. Khi các phần này được merge, cập nhật tài liệu ở mục tương ứng.

| Hạng mục                                                                                                                     | Ảnh hưởng                                                                    | Người làm                    | Trạng thái                                             |
| ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------- | ------------------------------------------------------ |
| 8 permission set vai trò (`SR_Store_Staff` … `SR_Portal_Customer`), profile `SmartReturn Internal/Integration/Customer Base` | 5.2, 5.3, 5.6: user vai trò, integration user, khách đăng nhập chưa có quyền | Dev A – Đức (DUNG-12)        | Có trên org chung từ 28/10, chưa có trong git          |
| `SR_SharingService`, group cửa hàng/vùng                                                                                     | 5.4; seed 3                                                                  | Dev A – Đức (DUNG-13)        | Chưa có                                                |
| `SR_NightlyJob`                                                                                                              | 5.5 (job đêm)                                                                | Dev A – Đức (DUNG-14)        | Chưa có; `schedule-jobs.apex` tự đặt lịch khi class có |
| External Client App + integration user chạy Postman trên org mới                                                             | 5.3                                                                          | Dev B – Đạt (TRI-13, TRI-21) | Chưa kiểm được vì thiếu `SR_Integration_API`           |
| Khách đăng nhập Portal: member profile _Customer Community User_                                                             | 5.6                                                                          | Dev C – Dũng                 | Org chung cũng chưa cấu hình                           |

---

## 9. Production

Chưa chạy thử trên production. Khác với org Developer/sandbox:

- Production không cho `NoTestRun` khi có Apex. Làm theo thứ tự: bật Digital Experiences (1.2 cách B) → tạo site trước bằng `sf community create` như mục 3 → deploy 1 lần cả `force-app` bằng lệnh ở mục 4 (RunLocalTests). Salesforce tự sắp thứ tự các loại metadata trong cùng một lần deploy; test chạy sau khi mọi thành phần đã vào org.
- CI (`.github/workflows/deploy-production.yml`, `validate-salesforce.yml`): chế độ full, hoặc delta có file Network, cần biến môi trường `SR_PORTAL_SENDER_EMAIL` trong job; thiếu thì `sf` báo lỗi ConversionError ở trên.
- Sau đó làm mục 5 như trên.
