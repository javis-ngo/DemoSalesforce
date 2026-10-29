/**
 * SmartReturn – chạy script dữ liệu mẫu trong scripts/apex (DUC-02).
 *   npm run seed            → dựng toàn bộ dữ liệu mẫu: seed 1 → 5, dừng ở bước đầu tiên bị lỗi
 *                             (trừ seed 3 – group: lỗi thì báo rồi chạy tiếp seed 4).
 *                             Chạy lại được nhiều lần (seed 2 xóa đơn + yêu cầu cũ của khách mẫu rồi tạo lại).
 *                             Seed 5 xong thì sinh postman/import-200-return-requests.json theo OrderNumber mới.
 *   npm run seed:import-json → chỉ sinh lại file JSON import từ các đơn "SR-IMPORT" đang có trong org
 *                             (200 yêu cầu, 6 dòng lỗi cố ý – NFR-02, UAT-01, B11).
 *   npm run seed:doi-vai -- <NV|CHT|QLV|KETOAN|CSKH> [--user <tên>] [--store <mã cửa hàng>]
 *                           → đổi vai cho 1 user test (seed-doi-vai.apex) rồi cập nhật group (seed 3).
 * Mặc định chạy trên target-org của project; org khác thì thêm -o <alias>, vd: npm run seed -- -o sr-shared
 * Chỉ in các dòng "SEED | ..." trong debug log của từng script.
 * Owner: Dev C
 */
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const APEX_DIR = path.join(__dirname, "apex");
const ROLES = ["NV", "CHT", "QLV", "KETOAN", "CSKH"];
// optional: lỗi thì báo rồi chạy tiếp bước sau (group chỉ phục vụ chia sẻ, chưa có thì vẫn demo được)
const SEED_STEPS = [
  {
    file: "seed-1-users.apex",
    title: "User cho từng vai trò + permission set"
  },
  {
    file: "seed-2-data.apex",
    title: "Cửa hàng, sản phẩm + giá, khách hàng, đơn hàng"
  },
  {
    file: "seed-3-groups.apex",
    title: "Group cửa hàng / vùng (cần SR_SharingService của Đức – Dev A)",
    optional: true
  },
  {
    file: "seed-4-requests.apex",
    title:
      "Yêu cầu đổi trả mẫu (SR_ReturnRequestService.createRequests của Đức – Dev A)"
  },
  {
    file: "seed-5-import-data.apex",
    title:
      'Cửa hàng + đơn hàng "SR-IMPORT" cho test import, rồi sinh file JSON import',
    after: (orgArgs) => writeImportJson(orgArgs)
  }
];
const SKIP_HINT =
  'Bỏ qua bước này, chạy tiếp. Chạy lại "npm run seed" khi Đức đã deploy SR_SharingService.';
const GROUP_STEP = SEED_STEPS[2];

// Debug log mã hóa ký tự đặc biệt trong System.debug: '|' thành '&#124;', '"' thành '&quot;'...
function decodeEntities(text) {
  return text
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) =>
      String.fromCodePoint(parseInt(code, 16))
    )
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

// Các dòng System.debug('SEED | ...') trong debug log
function seedLines(logs) {
  return String(logs || "")
    .split("\n")
    .filter((line) => line.includes("|USER_DEBUG|"))
    .map(decodeEntities)
    .filter((line) => line.includes("SEED |"))
    .map((line) => line.substring(line.indexOf("SEED |")));
}

// Chạy sf ... --json; trả về JSON đã parse, hoặc null (đã in lỗi) nếu không chạy được
function runSf(args, orgArgs) {
  const useShell = process.platform === "win32"; // Windows: sf là sf.cmd nên phải chạy qua shell
  // Qua shell thì tham số có khoảng trắng (đường dẫn, câu SOQL) phải bọc trong ngoặc kép
  const quoted = useShell
    ? args.map((arg) => (/\s/.test(arg) ? `"${arg}"` : arg))
    : args;
  const run = spawnSync("sf", [...quoted, "--json", ...orgArgs], {
    cwd: ROOT,
    encoding: "utf8",
    shell: useShell,
    maxBuffer: 64 * 1024 * 1024
  });
  if (run.error) {
    console.error(
      `  Không chạy được Salesforce CLI (sf): ${run.error.message}`
    );
    return null;
  }
  try {
    return JSON.parse(run.stdout);
  } catch {
    console.error(`  sf không trả về JSON:\n${run.stdout}${run.stderr}`);
    return null;
  }
}

// Chạy 1 file Apex ẩn danh bằng sf apex run; trả về true nếu chạy xong không lỗi
function runApex(file, title, step, orgArgs) {
  console.log(`\n${step} ${title}`);
  const output = runSf(["apex", "run", "--file", file], orgArgs);
  if (!output) {
    return false;
  }
  const result = output.result || {};
  seedLines(result.logs).forEach((line) => console.log(`  ${line}`));
  if (output.status === 0 && result.success) {
    return true;
  }
  if (result.compiled === false) {
    console.error(
      `  LỖI biên dịch (dòng ${result.line}, cột ${result.column}): ${result.compileProblem}`
    );
  } else if (result.exceptionMessage) {
    console.error(
      `  LỖI khi chạy: ${result.exceptionMessage}\n  ${result.exceptionStackTrace || ""}`
    );
  } else {
    console.error(`  LỖI: ${output.message || run.stderr}`);
  }
  return false;
}

function seedAll(orgArgs) {
  const skipped = [];
  for (const [index, step] of SEED_STEPS.entries()) {
    const label = `[${index + 1}/${SEED_STEPS.length}]`;
    if (runApex(path.join(APEX_DIR, step.file), step.title, label, orgArgs)) {
      if (step.after && !step.after(orgArgs)) {
        console.error(
          `\nĐã chạy ${step.file} nhưng bước sau đó bị lỗi. Sửa lỗi rồi chạy lại "npm run seed".`
        );
        return 1;
      }
      continue;
    }
    if (step.optional) {
      console.warn(`  ${SKIP_HINT}`);
      skipped.push(step.file);
      continue;
    }
    console.error(
      `\nDừng ở ${step.file}. Sửa lỗi rồi chạy lại "npm run seed".`
    );
    return 1;
  }
  if (skipped.length > 0) {
    console.log(`\nDựng xong dữ liệu mẫu, trừ: ${skipped.join(", ")}.`);
    return 0;
  }
  console.log("\nDựng xong dữ liệu mẫu.");
  return 0;
}

// ---------- File JSON import 200 yêu cầu (NFR-02, UAT-01, B11) ----------
// Body cho POST /services/apexrest/smartreturn/v1/return-requests/import (Postman: biến importBody).
// OrderNumber tự sinh nên mỗi lần seed 5 tạo lại đơn thì phải sinh lại file này.

const IMPORT_FILE = path.join(
  ROOT,
  "postman",
  "import-200-return-requests.json"
);
const IMPORT_SIZE = 200;
// Đơn seed 5 tên "SR-IMPORT 01".."SR-IMPORT 16"; dùng ký tự đại diện '_' thay '%' để cmd không hiểu nhầm biến
const IMPORT_ORDER_QUERY =
  "SELECT Name, OrderNumber, Account.Phone, Store__r.Store_Code__c, Delivery_Date__c, EffectiveDate, " +
  "(SELECT Product2.ProductCode, Product2.Family, Quantity FROM OrderItems) " +
  "FROM Order WHERE Name LIKE 'SR-IMPORT __' ORDER BY Name";
// Hạn đổi trả tính từ ngày giao (SR_Category_Policy, Phụ lục B.1); ngành không có ở đây thì không đổi trả được
const RETURN_WINDOW_DAYS = {
  "Gia dụng": 30,
  Laptop: 15,
  "Điện thoại": 7,
  "Phụ kiện": 7
};
// Ngành hàng mà 1 dòng có thể trả 2 cái
const MULTI_UNIT_FAMILIES = new Set(["Gia dụng", "Phụ kiện"]);
// Chỉ tổ hợp lý do × tình trạng có tỷ lệ hoàn > 0 (SR_Refund_Rate).
// Chưa dùng USED: picklist Return_Request_Line__c.Declared_Condition__c chưa có giá trị này (lỗi khi lưu dòng).
const REFUND_COMBOS = [
  ["DEFECT", "SEALED"],
  ["DEFECT", "OPENED"],
  ["NOT_SATISFIED", "SEALED"],
  ["NOT_SATISFIED", "OPENED"],
  ["WRONG_ITEM", "SEALED"],
  ["WRONG_ITEM", "OPENED"]
];
// Vị trí (index) 6 dòng lỗi cố ý trong file, theo thứ tự các ca lỗi trong importErrorCases()
const ERROR_INDEXES = [17, 48, 89, 121, 156, 188];
// Cố định seed để cùng bộ đơn thì sinh ra cùng file
const RANDOM_SEED = 20261029;

// Bộ sinh số ngẫu nhiên có seed (mulberry32)
function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Ngày hôm nay theo giờ Việt Nam, dạng YYYY-MM-DD (so sánh chuỗi được)
function todayInVietnam() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Ho_Chi_Minh"
  }).format(new Date());
}

function addDays(isoDate, days) {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

// Đơn SR-IMPORT từ org, mỗi dòng đơn kèm hạn đổi trả và số lượng còn lại để chia cho các yêu cầu
function loadImportOrders(orgArgs, today) {
  const output = runSf(
    ["data", "query", "--query", IMPORT_ORDER_QUERY],
    orgArgs
  );
  if (!output) {
    return null;
  }
  if (output.status !== 0) {
    console.error(`  LỖI truy vấn đơn SR-IMPORT: ${output.message}`);
    return null;
  }
  return (output.result.records || []).map((r) => ({
    name: r.Name,
    number: r.OrderNumber,
    phone: r.Account?.Phone,
    store: r.Store__r?.Store_Code__c,
    items: (r.OrderItems?.records || []).map((it) => {
      const family = it.Product2?.Family;
      const windowDays = RETURN_WINDOW_DAYS[family];
      const anchor = r.Delivery_Date__c || r.EffectiveDate;
      const deadline =
        windowDays === undefined ? null : addDays(anchor, windowDays);
      return {
        sku: it.Product2?.ProductCode,
        family,
        quantity: it.Quantity,
        remaining: it.Quantity,
        returnable: windowDays !== undefined,
        expired: deadline !== null && today > deadline,
        deadline
      };
    })
  }));
}

function findLine(orders, test) {
  for (const order of orders) {
    const item = order.items.find((it) => test(it, order));
    if (item) {
      return { order, item };
    }
  }
  return null;
}

// 6 ca lỗi, mỗi ca 1 mã lỗi (Phụ lục E.1). Tìm đơn/dòng phù hợp theo dữ liệu thật thay vì theo tên đơn.
function importErrorCases(orders) {
  const valid = findLine(orders, (it) => it.returnable && !it.expired);
  const nonReturnable = findLine(orders, (it) => !it.returnable);
  const expired = findLine(orders, (it) => it.expired);
  const allSkus = [
    ...new Set(
      orders.flatMap((o) =>
        o.items.filter((it) => it.returnable).map((it) => it.sku)
      )
    )
  ];
  let missing = null;
  for (const order of orders) {
    const sku = allSkus.find((s) => !order.items.some((it) => it.sku === s));
    if (sku) {
      missing = { order, sku };
      break;
    }
  }
  if (!valid || !nonReturnable || !expired || !missing) {
    return null;
  }
  return [
    {
      code: "VALIDATION_FAILED",
      note: "channel COUNTER không nhận qua API",
      order: valid.order,
      sku: valid.item.sku,
      quantity: 1,
      channel: "COUNTER"
    },
    {
      code: "ORDER_NOT_FOUND",
      note: "đơn không tồn tại",
      order: valid.order,
      sku: valid.item.sku,
      quantity: 1,
      orderNumber: "99999999"
    },
    {
      code: "SKU_NOT_IN_ORDER",
      note: `${missing.sku} không có trong ${missing.order.name}`,
      order: missing.order,
      sku: missing.sku,
      quantity: 1
    },
    {
      code: "NOT_RETURNABLE",
      note: `${nonReturnable.item.sku} thuộc ngành không đổi trả (MSG-05)`,
      order: nonReturnable.order,
      sku: nonReturnable.item.sku,
      quantity: 1
    },
    {
      code: "RETURN_WINDOW_EXPIRED",
      note: `${expired.item.sku} hết hạn từ ${expired.item.deadline} (MSG-03)`,
      order: expired.order,
      sku: expired.item.sku,
      quantity: 1
    },
    // Luôn vượt số đã mua, bất kể các yêu cầu hợp lệ đã dùng bao nhiêu
    {
      code: "QUANTITY_EXCEEDED",
      note: `trả ${valid.item.quantity + 1} ${valid.item.sku}, đơn chỉ mua ${valid.item.quantity} (MSG-04)`,
      order: valid.order,
      sku: valid.item.sku,
      quantity: valid.item.quantity + 1
    }
  ];
}

function buildImportRequests(orders, today) {
  const random = seededRandom(RANDOM_SEED);
  const pick = (list) => list[Math.floor(random() * list.length)];
  const stamp = today.replace(/-/g, "").slice(2); // YYMMDD
  const usable = (order) =>
    order.items.filter(
      (it) => it.returnable && !it.expired && it.remaining > 0
    );
  const line = (sku, quantity) => {
    const [reason, condition] = pick(REFUND_COMBOS);
    return { sku, quantity, reason, condition };
  };
  const request = (index, order, lines, overrides = {}) => {
    const channel = overrides.channel || pick(["POS", "APP"]);
    return {
      externalRequestId: `${channel === "APP" ? "APP" : "POS"}-IMP-${stamp}-${String(index + 1).padStart(4, "0")}`,
      channel,
      orderNumber: overrides.orderNumber || order.number,
      customerPhone: order.phone,
      storeCode: order.store,
      lines
    };
  };

  const errorCases = importErrorCases(orders);
  if (!errorCases) {
    throw new Error(
      "Đơn SR-IMPORT không đủ dữ liệu cho các dòng lỗi (cần dòng hết hạn, dòng không đổi trả được)."
    );
  }
  const errorAt = new Map(
    ERROR_INDEXES.map((index, k) => [index, errorCases[k]])
  );
  const requests = [];
  let earliestDeadline = null;
  for (let i = 0; i < IMPORT_SIZE; i += 1) {
    const errorCase = errorAt.get(i);
    if (errorCase) {
      // Dòng lỗi không giữ số lượng nên không trừ remaining
      requests.push(
        request(
          i,
          errorCase.order,
          [line(errorCase.sku, errorCase.quantity)],
          errorCase
        )
      );
      continue;
    }
    const candidates = orders.filter((o) => usable(o).length > 0);
    if (candidates.length === 0) {
      throw new Error(
        `Đơn SR-IMPORT hết số lượng còn trả được ở yêu cầu thứ ${i + 1}.`
      );
    }
    const order = pick(candidates);
    const items = usable(order);
    // 1/4 số yêu cầu có 2 dòng
    const count = items.length > 1 && random() < 0.25 ? 2 : 1;
    const chosen = [];
    while (chosen.length < count) {
      const item = pick(items.filter((it) => !chosen.includes(it)));
      chosen.push(item);
    }
    const lines = chosen.map((item) => {
      const quantity =
        item.remaining >= 2 &&
        MULTI_UNIT_FAMILIES.has(item.family) &&
        random() < 0.2
          ? 2
          : 1;
      item.remaining -= quantity;
      if (earliestDeadline === null || item.deadline < earliestDeadline) {
        earliestDeadline = item.deadline;
      }
      return line(item.sku, quantity);
    });
    requests.push(request(i, order, lines));
  }
  return { requests, errorAt, earliestDeadline };
}

// Sinh file JSON import từ đơn SR-IMPORT đang có trong org; trả về true nếu ghi được file
function writeImportJson(orgArgs) {
  console.log(
    `\n  Sinh ${path.relative(ROOT, IMPORT_FILE)} từ các đơn SR-IMPORT trong org`
  );
  const today = todayInVietnam();
  const orders = loadImportOrders(orgArgs, today);
  if (!orders) {
    return false;
  }
  if (orders.length === 0) {
    console.error(
      '  Không có đơn SR-IMPORT nào trong org. Chạy "npm run seed" (seed 5) trước.'
    );
    return false;
  }
  let built;
  try {
    built = buildImportRequests(orders, today);
  } catch (e) {
    console.error(`  LỖI: ${e.message} Chạy lại seed 5 để tạo lại đơn.`);
    return false;
  }
  const { requests, errorAt, earliestDeadline } = built;
  fs.writeFileSync(
    IMPORT_FILE,
    `${JSON.stringify(requests, null, 2)}\n`,
    "utf8"
  );
  const lineCount = requests.reduce((sum, r) => sum + r.lines.length, 0);
  console.log(
    `  IMPORT | ${requests.length} yêu cầu (${requests.length - errorAt.size} hợp lệ, ${errorAt.size} lỗi cố ý), ` +
      `${lineCount} dòng, từ ${orders.length} đơn`
  );
  for (const [index, errorCase] of errorAt) {
    console.log(
      `  IMPORT | Lỗi cố ý #${index} ${requests[index].externalRequestId}: ${errorCase.code} – ${errorCase.note}`
    );
  }
  console.log(
    `  IMPORT | Dùng được đến hết ${earliestDeadline} (hạn đổi trả sớm nhất), sau đó chạy lại "npm run seed".`
  );
  return true;
}

// Thay giá trị biến cấu hình ở đầu seed-doi-vai.apex, vd: String role = 'KETOAN';
function setVariable(code, name, value) {
  const pattern = new RegExp(`^(String ${name} = )'[^']*'`, "m");
  if (!pattern.test(code)) {
    throw new Error(`Không thấy biến ${name} trong seed-doi-vai.apex`);
  }
  return code.replace(pattern, `$1'${value}'`);
}

function doiVai(args) {
  const options = { role: "", user: "", store: "HCM-012" };
  const orgArgs = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--user" || args[i] === "--store") {
      options[args[i].substring(2)] = args[i + 1] || "";
      i += 1;
    } else if (args[i].startsWith("-")) {
      // cờ của sf, vd -o sr-shared: giữ cả giá trị đi kèm
      orgArgs.push(args[i]);
      if (args[i + 1] && !args[i + 1].startsWith("-")) {
        orgArgs.push(args[i + 1]);
        i += 1;
      }
    } else if (!options.role) {
      options.role = args[i].toUpperCase();
    }
  }
  if (!ROLES.includes(options.role)) {
    console.error(
      `Thiếu hoặc sai vai. Dùng: npm run seed:doi-vai -- <${ROLES.join("|")}> [--user <tên>] [--store <mã cửa hàng>] [-o <org>]`
    );
    return 1;
  }
  const safe = /^[A-Za-z0-9._@-]*$/;
  if (!safe.test(options.user) || !safe.test(options.store)) {
    console.error("--user và --store chỉ gồm chữ, số và các ký tự . _ @ -");
    return 1;
  }

  let code = fs.readFileSync(path.join(APEX_DIR, "seed-doi-vai.apex"), "utf8");
  code = setVariable(code, "role", options.role);
  code = setVariable(code, "userKey", options.user);
  code = setVariable(code, "storeCode", options.store);
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sr-seed-"));
  const tmpFile = path.join(tmpDir, "seed-doi-vai.apex");
  fs.writeFileSync(tmpFile, code);
  try {
    if (
      !runApex(
        tmpFile,
        `Đổi vai user test sang ${options.role}`,
        "[1/2]",
        orgArgs
      )
    ) {
      return 1;
    }
    // Group cửa hàng/vùng tính theo Store_Code__c và permission set Kế toán nên chạy lại seed 3
    if (
      !runApex(
        path.join(APEX_DIR, GROUP_STEP.file),
        GROUP_STEP.title,
        "[2/2]",
        orgArgs
      )
    ) {
      console.warn(
        "\nĐã đổi vai nhưng chưa cập nhật được group cửa hàng/vùng (seed 3)."
      );
      console.warn(`  ${SKIP_HINT}`);
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
  console.log("\nĐổi vai xong.");
  return 0;
}

function importJson(orgArgs) {
  if (!writeImportJson(orgArgs)) {
    return 1;
  }
  console.log("\nSinh file JSON import xong.");
  return 0;
}

const args = process.argv.slice(2);
const COMMANDS = { "doi-vai": doiVai, "import-json": importJson };
process.exitCode = COMMANDS[args[0]]
  ? COMMANDS[args[0]](args.slice(1))
  : seedAll(args);
