/**
 * Quy ước:
 *  - Mọi hàm tạo hàng loạt dùng 1 DML cho mỗi object; không có SOQL/DML trong vòng lặp.
 *  - Factory không chứa nghiệp vụ (không tự tính tiền hoàn, không định tuyến duyệt): giá trị đến từ tham số.
 *  - Refund_Rate__c là kiểu Percent: truyền 80 nghĩa là 80%.
 *  - Tạo User là DML thiết lập (setup): factory bọc trong System.runAs để không gây MIXED_DML_OPERATION.
 *  - Mọi DML tạo dữ liệu test chạy explicit SYSTEM_MODE; business identity được test qua System.runAs.
 *  - Org dev có ít license: factory ưu tiên profile 'Standard Platform User', rồi 'Standard User'
 *    (xem PROFILE_PREFERENCE). Mỗi user test vẫn tốn 1 license, nên giữ số user mỗi test nhỏ.
 */
@IsTest
public with sharing class SR_TestDataFactory {
    // ---- Vai trò (Phụ lục / DUC-08) và permission set tương ứng ----
    public static final String ROLE_STORE_STAFF      = 'STORE_STAFF';
    public static final String ROLE_STORE_MANAGER    = 'STORE_MANAGER';
    public static final String ROLE_REGIONAL_MANAGER = 'REGIONAL_MANAGER';
    public static final String ROLE_ACCOUNTANT       = 'ACCOUNTANT';
    public static final String ROLE_CSKH             = 'CSKH';
    public static final String ROLE_ADMIN            = 'ADMIN';
    public static final String ROLE_INTEGRATION      = 'INTEGRATION';
    private static final Map<String, String> PERMISSION_SET_BY_ROLE = new Map<String, String>{
        ROLE_STORE_STAFF      => 'SR_Store_Staff',
        ROLE_STORE_MANAGER    => 'SR_Store_Manager',
        ROLE_REGIONAL_MANAGER => 'SR_Regional_Manager',
        ROLE_ACCOUNTANT       => 'SR_Accountant',
        ROLE_CSKH             => 'SR_CSKH',
        ROLE_ADMIN            => 'SR_Admin',
        ROLE_INTEGRATION      => 'SR_Integration_API'
    };
    /** Thứ tự ưu tiên profile cho user test (license Salesforce của org dev đã hết chỗ). */
    @TestVisible
    private static final List<String> PROFILE_PREFERENCE = new List<String>{
        'System Administrator', 'Standard Platform User', 'Standard User'
    };
    // ---- Vùng (API value của Store__c.Region__c; label tiếng Việt là Bắc / Trung / Nam) ----
    public static final String REGION_NORTH   = 'North';
    public static final String REGION_CENTRAL = 'Central';
    public static final String REGION_SOUTH   = 'South';
    private static final Set<String> REGIONS = new Set<String>{ REGION_NORTH, REGION_CENTRAL, REGION_SOUTH };
    // ---- Ngành hàng (Product2.Family, B.1) ----
    public static final String FAMILY_PHONE     = 'Điện thoại';
    public static final String FAMILY_LAPTOP    = 'Laptop';
    public static final String FAMILY_APPLIANCE = 'Gia dụng';
    public static final String FAMILY_ACCESSORY = 'Phụ kiện';
    public static final String FAMILY_PREPAID   = 'Thẻ cào';
    public static final String FAMILY_SOFTWARE  = 'Phần mềm';
    // ---- Kênh và trạng thái yêu cầu (Phụ lục C / E) ----
    public static final String CHANNEL_COUNTER = 'COUNTER';
    public static final String CHANNEL_POS     = 'POS';
    public static final String CHANNEL_APP     = 'APP';
    private static final Set<String> CHANNELS = new Set<String>{ CHANNEL_COUNTER, CHANNEL_POS, CHANNEL_APP };
    public static final String STATUS_NEW               = 'NEW';
    public static final String STATUS_PENDING_APPROVAL  = 'PENDING_APPROVAL';
    public static final String STATUS_AWAITING_GOODS    = 'AWAITING_GOODS';
    public static final String STATUS_INSPECTING        = 'INSPECTING';
    public static final String STATUS_REFUND_PROCESSING = 'REFUND_PROCESSING';
    public static final String STATUS_COMPLETED         = 'COMPLETED';
    public static final String STATUS_REFUND_FAILED     = 'REFUND_FAILED';
    public static final String STATUS_REJECTED          = 'REJECTED';
    public static final String STATUS_CANCELLED         = 'CANCELLED';
    public static final List<String> ALL_STATUSES = new List<String>{
        STATUS_NEW, STATUS_PENDING_APPROVAL, STATUS_AWAITING_GOODS, STATUS_INSPECTING,
        STATUS_REFUND_PROCESSING, STATUS_COMPLETED, STATUS_REFUND_FAILED, STATUS_REJECTED, STATUS_CANCELLED
    };
    private static final String ORDER_STATUS_DRAFT     = 'Draft';
    private static final String ORDER_STATUS_ACTIVATED = 'Activated';
    private static Integer sequence = 0;
    private static Map<Id, PricebookEntry> standardEntryByProductId = new Map<Id, PricebookEntry>();
    private static Integer nextSequence() {
        sequence++;
        return sequence;
    }
    public static User createUser(String role, String storeCode) {
        return createUsers(role, storeCode, 1, true)[0];
    }
    /**
     * Tạo count user cùng vai trò. doInsert = true: insert, rồi gán permission set của vai trò
     * nếu permission set đó đã có trong org (chưa có thì bỏ qua, không lỗi).
     */
    public static List<User> createUsers(String role, String storeCode, Integer count, Boolean doInsert) {
        validateRole(role);
        if (count == null || count < 1) {
            throw new IllegalArgumentException('SR_TestDataFactory.createUsers: count phải >= 1.');
        }
        List<User> users = new List<User>();
        List<String> roles = new List<String>();
        Id profileId = resolveProfileId();
        for (Integer i = 0; i < count; i++) {
            users.add(buildUser(role, storeCode, profileId));
            roles.add(role);
        }
        if (doInsert == true) {
            saveUsers(users, roles);
        }
        return users;
    }
    /** Tên permission set (DUC-08) mà vai trò được gán khi permission set đó đã tồn tại trong org. */
    public static String permissionSetNameFor(String role) {
        validateRole(role);
        return PERMISSION_SET_BY_ROLE.get(role);
    }
    private static void validateRole(String role) {
        if (role == null || !PERMISSION_SET_BY_ROLE.containsKey(role)) {
            throw new IllegalArgumentException('SR_TestDataFactory: vai trò không hợp lệ: ' + role);
        }
    }
    private static Id resolveProfileId() {
        Map<String, Id> idByName = new Map<String, Id>();
        for (Profile profileValue : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN :PROFILE_PREFERENCE
        ]) {
            idByName.put(profileValue.Name, profileValue.Id);
        }
        for (String name : PROFILE_PREFERENCE) {
            if (idByName.containsKey(name)) {
                return idByName.get(name);
            }
        }
        return UserInfo.getProfileId();
    }
    private static User buildUser(String role, String storeCode, Id profileId) {
        Integer n = nextSequence();
        String randomSuffix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        String username = 'sr.' + role.toLowerCase() + '.' + n + '.' + randomSuffix + '@smartreturn.test';
        return new User(
            Username          = username,
            Email             = username,
            LastName          = 'SR ' + role + ' ' + n,
            Alias             = 'sr' + String.valueOf(n).leftPad(4, '0'),
            ProfileId         = profileId,
            TimeZoneSidKey    = 'Asia/Bangkok', // GMT+7 như múi giờ Việt Nam (không có DST)
            LocaleSidKey      = 'vi_VN',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            Store_Code__c     = storeCode
        );
    }
    /** DML thiết lập (User, PermissionSetAssignment) nằm trong runAs riêng để tránh MIXED_DML_OPERATION. */
    private static void saveUsers(List<User> users, List<String> roles) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Database.SaveResult> userResults = Database.insert(
                users,
                false,
                AccessLevel.SYSTEM_MODE
            );
            assertSetupDmlSucceeded('User insert', userResults);
            assignRolePermissionSetsIfPresent(users, roles);
        }
    }

    private static void assignRolePermissionSetsIfPresent(
        List<User> users,
        List<String> roles
    ) {
        Set<String> names = new Set<String>();
        for (String role : roles) {
            names.add(PERMISSION_SET_BY_ROLE.get(role));
        }

        Map<String, Id> idByName = new Map<String, Id>();
        for (PermissionSet permissionValue : [
            SELECT Id, Name, IsOwnedByProfile
            FROM PermissionSet
            WHERE Name IN :names
              AND IsOwnedByProfile = false
        ]) {
            idByName.put(permissionValue.Name, permissionValue.Id);
        }

        List<PermissionSetAssignment> assignments =
            new List<PermissionSetAssignment>();
        for (Integer i = 0; i < users.size(); i++) {
            Id permissionSetId = idByName.get(
                PERMISSION_SET_BY_ROLE.get(roles[i])
            );
            if (permissionSetId != null) {
                assignments.add(new PermissionSetAssignment(
                    AssigneeId = users[i].Id,
                    PermissionSetId = permissionSetId
                ));
            }
        }

        if (!assignments.isEmpty()) {
            assertSetupDmlSucceeded(
                'PermissionSetAssignment insert',
                Database.insert(
                    assignments,
                    false,
                    AccessLevel.SYSTEM_MODE
                )
            );
        }
    }
    /**
     * Produces a useful failure message for every factory DML operation, including
     * validation rules, duplicate values, unavailable licenses and automation errors.
     */
    private static void assertSetupDmlSucceeded(
        String operation,
        List<Database.SaveResult> results
    ) {
        List<String> failures = new List<String>();
        for (Integer rowIndex = 0; rowIndex < results.size(); rowIndex++) {
            Database.SaveResult result = results[rowIndex];
            if (result.isSuccess()) {
                continue;
            }
            for (Database.Error errorValue : result.getErrors()) {
                failures.add(
                    operation
                    + ' row=' + rowIndex
                    + ' status=' + String.valueOf(errorValue.getStatusCode())
                    + ' fields=' + String.valueOf(errorValue.getFields())
                    + ' message=' + errorValue.getMessage()
                );
            }
        }
        if (!failures.isEmpty()) {
            Assert.fail(String.join(failures, '\\\\\\\\n'));
        }
    }
    // =====================================================================
    // Dòng 40 – Store kèm CHT và QLV
    // =====================================================================
    /** Kết quả của createStoreSetup: cửa hàng cùng các user liên quan. */
    public class StoreSetup {
        public Store__c store;
        public User storeManager;     // CHT
        public User regionalManager;  // QLV
        public User staff;            // Nhân viên cửa hàng
    }
    /** Tạo cửa hàng không kèm user (dùng khi chỉ cần Store__c, tiết kiệm license). */
    public static Store__c createStore(String storeCode, String region) {
        return createStore(storeCode, region, null, null);
    }
    public static Store__c createStore(String storeCode, String region, Id storeManagerId, Id regionalManagerId) {
        if (!REGIONS.contains(region)) {
            throw new IllegalArgumentException('SR_TestDataFactory: vùng không hợp lệ: ' + region);
        }
        Store__c store = new Store__c(
            Name                = 'SR Test Store ' + storeCode,
            Store_Code__c       = storeCode,
            Region__c           = region,
            Store_Manager__c    = storeManagerId,
            Regional_Manager__c = regionalManagerId
        );
        assertSetupDmlSucceeded(
            'Store__c insert',
            Database.insert(
                new List<Store__c>{ store },
                false,
                AccessLevel.SYSTEM_MODE
            )
        );
        return store;
    }
    /** Cửa hàng + CHT + QLV mới + 1 nhân viên cửa hàng (3 user). */
    public static StoreSetup createStoreSetup(String storeCode, String region) {
        return createStoreSetup(storeCode, region, null);
    }
    /**
     * Như trên nhưng dùng lại QLV đã có (nhiều cửa hàng cùng vùng dùng chung 1 QLV);
     * regionalManager = null thì tạo QLV mới. Chỉ tạo CHT và nhân viên cửa hàng (2 user).
     */
    public static StoreSetup createStoreSetup(String storeCode, String region, User regionalManager) {
        if (!REGIONS.contains(region)) {
            throw new IllegalArgumentException('SR_TestDataFactory: vùng không hợp lệ: ' + region);
        }
        Id profileId = resolveProfileId();
        List<User> users = new List<User>{
            buildUser(ROLE_STORE_MANAGER, storeCode, profileId),
            buildUser(ROLE_STORE_STAFF, storeCode, profileId)
        };
        List<String> roles = new List<String>{ ROLE_STORE_MANAGER, ROLE_STORE_STAFF };
        if (regionalManager == null) {
            users.add(buildUser(ROLE_REGIONAL_MANAGER, null, profileId));
            roles.add(ROLE_REGIONAL_MANAGER);
        }
        saveUsers(users, roles);
        StoreSetup result = new StoreSetup();
        result.storeManager = users[0];
        result.staff = users[1];
        result.regionalManager = regionalManager == null ? users[2] : regionalManager;
        result.store = createStore(storeCode, region, result.storeManager.Id, result.regionalManager.Id);
        return result;
    }
    // =====================================================================
    // Dòng 40 – Account có SĐT
    // =====================================================================
    /** Tạo count khách hàng, mỗi người một SĐT duy nhất (10 số, bắt đầu 090). */
    public static List<Account> createAccounts(Integer count, Boolean riskFlag, Boolean doInsert) {
        if (count == null || count < 1) {
            throw new IllegalArgumentException('SR_TestDataFactory.createAccounts: count phải >= 1.');
        }
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Integer n = nextSequence();
            accounts.add(buildAccount('SR Test Customer ' + n, buildPhone(n), riskFlag));
        }
        if (doInsert == true) {
            assertSetupDmlSucceeded(
                'Account insert',
                Database.insert(accounts, false, AccessLevel.SYSTEM_MODE)
            );
        }
        return accounts;
    }
    /** Tạo và insert 1 khách hàng với tên và SĐT chỉ định. */
    public static Account createAccount(String name, String phone, Boolean riskFlag) {
        Account account = buildAccount(name, phone, riskFlag);
        assertSetupDmlSucceeded(
            'Account insert',
            Database.insert(
                new List<Account>{ account },
                false,
                AccessLevel.SYSTEM_MODE
            )
        );
        return account;
    }
    private static Account buildAccount(String name, String phone, Boolean riskFlag) {
        Boolean flagged = riskFlag == true;
        return new Account(
            Name                   = name,
            Phone                  = phone,
            Risk_Flag__c           = flagged,
            Risk_Flag_Updated_At__c = flagged ? Datetime.now() : null
        );
    }
    private static String buildPhone(Integer n) {
        return '090' + String.valueOf(n).leftPad(7, '0');
    }
    // =====================================================================
    // Dòng 40 – Product2 đủ 6 ngành hàng + PricebookEntry
    // =====================================================================
    /** Mô tả một sản phẩm cần tạo. */
    public class ProductSeed {
        public String family;
        public String sku;
        public String name;
        public Decimal price;
        public ProductSeed(String family, String sku, String name, Decimal price) {
            this.family = family;
            this.sku = sku;
            this.name = name;
            this.price = price;
        }
    }
    /** Mỗi ngành hàng một sản phẩm; SKU/giá lấy theo ví dụ trong BRD (nồi chiên, thẻ cào, laptop 25 triệu...). */
    public static List<ProductSeed> defaultCatalogSeeds() {
        return new List<ProductSeed>{
            new ProductSeed(FAMILY_PHONE,     'DT-PH-001',  'Điện thoại SR Test',  12000000),
            new ProductSeed(FAMILY_LAPTOP,    'LT-PH-001',  'Laptop SR Test',      25000000),
            new ProductSeed(FAMILY_APPLIANCE, 'AF-PH-5L',   'Nồi chiên không dầu 5L', 2490000),
            new ProductSeed(FAMILY_ACCESSORY, 'PK-CB-001',  'Cáp sạc SR Test',       350000),
            new ProductSeed(FAMILY_PREPAID,   'TC-VT-100K', 'Thẻ cào 100K',         100000),
            new ProductSeed(FAMILY_SOFTWARE,  'SW-OF-001',  'Phần mềm văn phòng',   1500000)
        };
    }
    /** Tạo đủ 6 ngành hàng (kèm PricebookEntry trong Standard Pricebook). Trả về theo Family. */
    public static Map<String, Product2> createProductCatalog() {
        Map<String, Product2> productByFamily = new Map<String, Product2>();
        for (Product2 product : createProducts(defaultCatalogSeeds())) {
            productByFamily.put(product.Family, product);
        }
        return productByFamily;
    }
    public static Product2 createProduct(String family, String sku, String name, Decimal price) {
        return createProducts(new List<ProductSeed>{ new ProductSeed(family, sku, name, price) })[0];
    }
    /** Hàng loạt: 1 DML cho Product2, 1 DML cho PricebookEntry. */
    public static List<Product2> createProducts(List<ProductSeed> seeds) {
        if (seeds == null || seeds.isEmpty()) {
            throw new IllegalArgumentException('SR_TestDataFactory.createProducts: danh sách sản phẩm rỗng.');
        }
        List<Product2> products = new List<Product2>();
        for (ProductSeed seed : seeds) {
            products.add(new Product2(
                Name             = seed.name,
                Family           = seed.family,
                ProductCode      = seed.sku,
                StockKeepingUnit = seed.sku,
                IsActive         = true
            ));
        }
        assertSetupDmlSucceeded(
            'Product2 insert',
            Database.insert(products, false, AccessLevel.SYSTEM_MODE)
        );
        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Integer i = 0; i < products.size(); i++) {
            entries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id   = products[i].Id,
                UnitPrice    = seeds[i].price,
                IsActive     = true
            ));
        }
        assertSetupDmlSucceeded(
            'PricebookEntry insert',
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE)
        );
        for (PricebookEntry entry : entries) {
            standardEntryByProductId.put(entry.Product2Id, entry);
        }
        return products;
    }
    // =====================================================================
    // Dòng 40 – Order + OrderItem (ngày giao tùy chọn)
    // =====================================================================
    /** Một dòng sản phẩm của đơn. unitPrice = null thì lấy giá trong Standard Pricebook. */
    public class ItemSpec {
        public Id productId;
        public Decimal quantity = 1;
        public Decimal unitPrice;
        public ItemSpec(Id productId, Decimal quantity) {
            this.productId = productId;
            this.quantity = quantity;
        }
        public ItemSpec(Id productId, Decimal quantity, Decimal unitPrice) {
            this(productId, quantity);
            this.unitPrice = unitPrice;
        }
    }
    /**
     * Mô tả một đơn hàng. deliveryDate = null tạo đơn không có ngày giao (mua mang về tại quầy – OI-03).
     */
    public class OrderSpec {
        public Id accountId;
        public Id storeId;
        public Date effectiveDate = Date.today();
        public Date deliveryDate;
        public String paymentMethod = 'Cash';
        public List<ItemSpec> items = new List<ItemSpec>();
        public OrderSpec(Id accountId, Id storeId) {
            this.accountId = accountId;
            this.storeId = storeId;
        }
    }
    public static Order createOrder(OrderSpec spec) {
        return createOrders(new List<OrderSpec>{ spec })[0];
    }
    /**
     * Tạo hàng loạt đơn: insert Order ở Draft → insert OrderItem → chuyển Activated
     * (Salesforce chỉ cho thêm dòng khi đơn còn Draft). Tổng cộng 3 DML.
     */
    public static List<Order> createOrders(List<OrderSpec> specs) {
        if (specs == null || specs.isEmpty()) {
            throw new IllegalArgumentException('SR_TestDataFactory.createOrders: danh sách đơn rỗng.');
        }
        Set<Id> productIds = new Set<Id>();
        for (OrderSpec spec : specs) {
            if (spec == null || spec.accountId == null) {
                throw new IllegalArgumentException('SR_TestDataFactory.createOrders: mỗi đơn cần accountId.');
            }
            if (spec.items == null || spec.items.isEmpty()) {
                throw new IllegalArgumentException('SR_TestDataFactory.createOrders: mỗi đơn cần ít nhất 1 dòng sản phẩm.');
            }
            for (ItemSpec item : spec.items) {
                if (item == null || item.productId == null) {
                    throw new IllegalArgumentException('SR_TestDataFactory.createOrders: dòng sản phẩm thiếu productId.');
                }
                productIds.add(item.productId);
            }
        }
        Map<Id, PricebookEntry> entryByProductId = resolveStandardEntries(productIds);
        Id standardPricebookId = Test.getStandardPricebookId();
        List<Order> orders = new List<Order>();
        for (OrderSpec spec : specs) {
            orders.add(new Order(
                AccountId        = spec.accountId,
                EffectiveDate    = spec.effectiveDate,
                Status           = ORDER_STATUS_DRAFT,
                Pricebook2Id     = standardPricebookId,
                Store__c         = spec.storeId,
                Delivery_Date__c = spec.deliveryDate,
                Payment_Method__c = spec.paymentMethod
            ));
        }
        assertSetupDmlSucceeded(
            'Order insert',
            Database.insert(orders, false, AccessLevel.SYSTEM_MODE)
        );
        List<OrderItem> orderItems = new List<OrderItem>();
        for (Integer i = 0; i < specs.size(); i++) {
            for (ItemSpec item : specs[i].items) {
                PricebookEntry entry = entryByProductId.get(item.productId);
                orderItems.add(new OrderItem(
                    OrderId          = orders[i].Id,
                    Product2Id       = item.productId,
                    PricebookEntryId = entry.Id,
                    Quantity         = item.quantity,
                    UnitPrice        = item.unitPrice != null ? item.unitPrice : entry.UnitPrice
                ));
            }
        }
        assertSetupDmlSucceeded(
            'OrderItem insert',
            Database.insert(orderItems, false, AccessLevel.SYSTEM_MODE)
        );
        for (Order ord : orders) {
            ord.Status = ORDER_STATUS_ACTIVATED;
        }
        assertSetupDmlSucceeded(
            'Order activation update',
            Database.update(orders, false, AccessLevel.SYSTEM_MODE)
        );
        return orders;
    }
    /** PricebookEntry trong Standard Pricebook của các sản phẩm; chỉ query phần chưa có trong cache. */
    private static Map<Id, PricebookEntry> resolveStandardEntries(Set<Id> productIds) {
        Set<Id> missing = new Set<Id>();
        for (Id productId : productIds) {
            if (!standardEntryByProductId.containsKey(productId)) {
                missing.add(productId);
            }
        }
        if (!missing.isEmpty()) {
            Id standardPricebookId = Test.getStandardPricebookId();
            for (PricebookEntry entry : [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :standardPricebookId AND Product2Id IN :missing
            ]) {
                standardEntryByProductId.put(entry.Product2Id, entry);
            }
        }
        Map<Id, PricebookEntry> result = new Map<Id, PricebookEntry>();
        for (Id productId : productIds) {
            PricebookEntry entry = standardEntryByProductId.get(productId);
            if (entry == null) {
                throw new IllegalArgumentException(
                    'SR_TestDataFactory: sản phẩm ' + productId + ' chưa có PricebookEntry trong Standard Pricebook.'
                );
            }
            result.put(productId, entry);
        }
        return result;
    }
    // =====================================================================
    // Dòng 40 – Yêu cầu đổi trả ở trạng thái bất kỳ
    // =====================================================================
    /**
     * Một dòng yêu cầu. Giá trị mặc định chỉ để insert được; test nào cần số liệu cụ thể thì tự đặt.
     * refundRate theo đơn vị phần trăm (80 = 80%).
     */
    public class LineSpec {
        public Id orderItemId;
        public Id productId;
        public Decimal quantity = 1;
        public Decimal unitPrice;
        public String reason = 'DEFECT';
        public String declaredCondition = 'SEALED';
        public String actualCondition;
        public Decimal refundRate;
        public Decimal estimatedRefund;
        public Decimal actualRefund;
        public String inspectionResult = 'NOT_INSPECTED';
        public String inspectionNote;
    }
    public class RequestSpec {
        public Id accountId;
        public Id orderId;
        public Id storeId;
        public String channel = CHANNEL_COUNTER;
        public String status = STATUS_NEW;
        public String approvalLevel;          // null: dùng giá trị mặc định của field
        public String externalRequestId;      // null: tự sinh giá trị duy nhất
        public Id assignedApproverId;
        public Id approvedById;
        public Datetime submittedAt;
        public Datetime approvalDueAt;
        public Datetime goodsDueDate;
        public String rejectionReason;
        public List<LineSpec> lines = new List<LineSpec>();
    }
    /**
     * Dựng sẵn RequestSpec cho từng đơn: mỗi OrderItem của đơn thành 1 dòng (SL 1, đơn giá của dòng đơn).
     * 1 SOQL cho tất cả đơn. Đơn truyền vào phải là Order do createOrders trả về (có AccountId, Store__c).
     */
    public static List<RequestSpec> requestSpecsForOrders(List<Order> orders, String status, String channel) {
        Map<Id, List<OrderItem>> itemsByOrderId = new Map<Id, List<OrderItem>>();
        Set<Id> orderIds = new Map<Id, Order>(orders).keySet();
        for (OrderItem item : [
            SELECT Id, OrderId, Product2Id, UnitPrice
            FROM OrderItem
            WHERE OrderId IN :orderIds
        ]) {
            if (!itemsByOrderId.containsKey(item.OrderId)) {
                itemsByOrderId.put(item.OrderId, new List<OrderItem>());
            }
            itemsByOrderId.get(item.OrderId).add(item);
        }
        List<RequestSpec> specs = new List<RequestSpec>();
        for (Order ord : orders) {
            RequestSpec spec = new RequestSpec();
            spec.accountId = ord.AccountId;
            spec.orderId = ord.Id;
            spec.storeId = ord.Store__c;
            spec.status = status;
            spec.channel = channel;
            List<OrderItem> items = itemsByOrderId.get(ord.Id);
            if (items != null) {
                for (OrderItem item : items) {
                    LineSpec line = new LineSpec();
                    line.orderItemId = item.Id;
                    line.productId = item.Product2Id;
                    line.unitPrice = item.UnitPrice;
                    spec.lines.add(line);
                }
            }
            specs.add(spec);
        }
        return specs;
    }
    public static Return_Request__c createReturnRequest(RequestSpec spec) {
        return createReturnRequests(new List<RequestSpec>{ spec })[0];
    }
    /**
     * Tạo hàng loạt yêu cầu và các dòng của chúng (2 DML). Status__c được ghi thẳng khi insert,
     * nên các giá trị ngoài NEW cần picklist Status__c đã có đủ 9 trạng thái (xem DUNG-02) và,
     * khi trigger chặn sửa Status__c (DUC-05) được triển khai, cần cơ chế bỏ qua cho test.
     */
    public static List<Return_Request__c> createReturnRequests(List<RequestSpec> specs) {
        if (specs == null || specs.isEmpty()) {
            throw new IllegalArgumentException('SR_TestDataFactory.createReturnRequests: danh sách yêu cầu rỗng.');
        }
        List<Return_Request__c> requests = new List<Return_Request__c>();
        for (RequestSpec spec : specs) {
            if (spec == null || spec.accountId == null || spec.orderId == null) {
                throw new IllegalArgumentException(
                    'SR_TestDataFactory.createReturnRequests: mỗi yêu cầu cần accountId và orderId.'
                );
            }
            if (!ALL_STATUSES.contains(spec.status)) {
                throw new IllegalArgumentException('SR_TestDataFactory: trạng thái không hợp lệ: ' + spec.status);
            }
            if (!CHANNELS.contains(spec.channel)) {
                throw new IllegalArgumentException('SR_TestDataFactory: kênh không hợp lệ: ' + spec.channel);
            }
            Return_Request__c request = new Return_Request__c(
                Account__c             = spec.accountId,
                Order__c               = spec.orderId,
                Store__c               = spec.storeId,
                Channel__c             = spec.channel,
                Status__c              = spec.status,
                External_Request_Id__c = spec.externalRequestId != null
                    ? spec.externalRequestId
                    : 'SR-TEST-' + nextSequence(),
                Assigned_Approver__c   = spec.assignedApproverId,
                Approved_By__c         = spec.approvedById,
                Submitted_At__c        = spec.submittedAt,
                Approval_Due_At__c     = spec.approvalDueAt,
                Goods_Due_Date__c      = spec.goodsDueDate,
                Rejection_Reason__c    = spec.rejectionReason
            );
            if (spec.approvalLevel != null) {
                request.Approval_Level__c = spec.approvalLevel;
            }
            requests.add(request);
        }
        assertSetupDmlSucceeded(
            'Return_Request__c insert',
            Database.insert(requests, false, AccessLevel.SYSTEM_MODE)
        );
        List<Return_Request_Line__c> lines = new List<Return_Request_Line__c>();
        for (Integer i = 0; i < specs.size(); i++) {
            for (LineSpec line : specs[i].lines) {
                lines.add(new Return_Request_Line__c(
                    Return_Request__c      = requests[i].Id,
                    Order_Product__c       = line.orderItemId,
                    Product__c             = line.productId,
                    Quantity__c            = line.quantity,
                    Unit_Price__c          = line.unitPrice,
                    Reason__c              = line.reason,
                    Declared_Condition__c  = line.declaredCondition,
                    Actual_Condition__c    = line.actualCondition,
                    Refund_Rate__c         = line.refundRate,
                    Estimated_Refund__c    = line.estimatedRefund,
                    Actual_Refund__c       = line.actualRefund,
                    Inspection_Result__c   = line.inspectionResult,
                    Inspection_Note__c     = line.inspectionNote
                ));
            }
        }
        if (!lines.isEmpty()) {
            assertSetupDmlSucceeded(
                'Return_Request_Line__c insert',
                Database.insert(lines, false, AccessLevel.SYSTEM_MODE)
            );
        }
        return requests;
    }
    // =====================================================================
    // Dòng 41 – Ghi đè cấu hình cho test qua SR_Config
    // =====================================================================
    /**
     * Ghi đè một tham số của SR_Setting__mdt trong test hiện tại, không cần deploy metadata.
     * Ví dụ: SR_TestDataFactory.overrideConfig(SR_Setting__mdt.Enable_PayHub__c, false);
     */
    public static void overrideConfig(Schema.SObjectField field, Object value) {
        SR_Config.setOverride(field, value);
    }
    /** Bỏ mọi giá trị ghi đè; tham số quay về giá trị trong Custom Metadata. */
    public static void resetConfig() {
        SR_Config.clearOverrides();
        SR_Config.setCategoryPolicyOverrides(null);
        SR_Config.setRefundRateOverrides(null);
        SR_Config.clearCache();
    }
    /**
     * Cấu hình tối thiểu để test DUC-04 không phụ thuộc bản ghi Custom Metadata trên org.
     */
    public static void seedSmartReturnTestConfig() {
        SR_Config.setCategoryPolicyOverrides(new Map<String, SR_CategoryPolicy>{
            FAMILY_PHONE => new SR_CategoryPolicy(FAMILY_PHONE, true, 30, true),
            FAMILY_LAPTOP => new SR_CategoryPolicy(FAMILY_LAPTOP, true, 30, true),
            FAMILY_APPLIANCE => new SR_CategoryPolicy(FAMILY_APPLIANCE, true, 7, true),
            FAMILY_ACCESSORY => new SR_CategoryPolicy(FAMILY_ACCESSORY, true, 7, true),
            FAMILY_PREPAID => new SR_CategoryPolicy(FAMILY_PREPAID, false, 0, true),
            FAMILY_SOFTWARE => new SR_CategoryPolicy(FAMILY_SOFTWARE, false, 0, true)
        });
        SR_Config.setRefundRateOverrides(new Map<String, Decimal>{
            'DEFECT|SEALED' => 100,
            'WRONG_ITEM|SEALED' => 100,
            'NOT_SATISFIED|OPENED' => 80,
            'CUSTOMER_DAMAGE|USED' => 0
        });
        overrideConfig(SR_Setting__mdt.Auto_Approval_Threshold__c, 2000000);
        overrideConfig(SR_Setting__mdt.Store_Manager_Max_Threshold__c, 20000000);
        overrideConfig(SR_Setting__mdt.Risk_Request_Count__c, 3);
        overrideConfig(SR_Setting__mdt.Risk_Total_Amount__c, 30000000);
        overrideConfig(SR_Setting__mdt.Risk_Window_Days__c, 30);
        overrideConfig(SR_Setting__mdt.Approval_SLA_Hours__c, 24);
        overrideConfig(SR_Setting__mdt.Goods_Due_Days__c, 7);
        overrideConfig(SR_Setting__mdt.PayHub_Timeout_Seconds__c, 10);
        overrideConfig(SR_Setting__mdt.PayHub_Max_Total_Attempts__c, 3);
        overrideConfig(SR_Setting__mdt.PayHub_Retry_Interval_Minutes__c, 15);
        overrideConfig(SR_Setting__mdt.Enable_Auto_Approval__c, true);
        overrideConfig(SR_Setting__mdt.Enable_PayHub__c, true);
    }
}