/**
 * SmartReturn – chạy script dữ liệu mẫu trong scripts/apex (DUC-02).
 *   npm run seed            → dựng toàn bộ dữ liệu mẫu: seed 1 → 4, dừng ở bước đầu tiên bị lỗi
 *                             (trừ seed 3 – group: lỗi thì báo rồi chạy tiếp seed 4).
 *                             Chạy lại được nhiều lần (seed 2 xóa đơn + yêu cầu cũ của khách mẫu rồi tạo lại).
 *   npm run seed:doi-vai -- <NV|CHT|QLV|KETOAN|CSKH> [--user <tên>] [--store <mã cửa hàng>]
 *                           → đổi vai cho 1 user test (seed-doi-vai.apex) rồi cập nhật group (seed 3).
 * Mặc định chạy trên target-org của project; org khác thì thêm -o <alias>, vd: npm run seed -- -o sr-shared
 * Chỉ in các dòng "SEED | ..." trong debug log của từng script.
 * Owner: Dev C
 */
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const APEX_DIR = path.join(__dirname, 'apex');
const ROLES = ['NV', 'CHT', 'QLV', 'KETOAN', 'CSKH'];
// optional: lỗi thì báo rồi chạy tiếp bước sau (group chỉ phục vụ chia sẻ, chưa có thì vẫn demo được)
const SEED_STEPS = [
    { file: 'seed-1-users.apex', title: 'User cho từng vai trò + permission set' },
    { file: 'seed-2-data.apex', title: 'Cửa hàng, sản phẩm + giá, khách hàng, đơn hàng' },
    {
        file: 'seed-3-groups.apex',
        title: 'Group cửa hàng / vùng (cần SR_SharingService của Đức – Dev A)',
        optional: true
    },
    { file: 'seed-4-requests.apex', title: 'Yêu cầu đổi trả mẫu (SR_ReturnRequestService.createRequests của Đức – Dev A)' }
];
const SKIP_HINT = 'Bỏ qua bước này, chạy tiếp. Chạy lại "npm run seed" khi Đức đã deploy SR_SharingService.';
const GROUP_STEP = SEED_STEPS[2];

// Các dòng System.debug('SEED | ...') trong debug log
function seedLines(logs) {
    return String(logs || '')
        .split('\n')
        .filter((line) => line.includes('|USER_DEBUG|') && line.includes('SEED |'))
        .map((line) => line.substring(line.indexOf('SEED |')));
}

// Chạy 1 file Apex ẩn danh bằng sf apex run; trả về true nếu chạy xong không lỗi
function runApex(file, title, step, orgArgs) {
    console.log(`\n${step} ${title}`);
    const useShell = process.platform === 'win32'; // Windows: sf là sf.cmd nên phải chạy qua shell
    const run = spawnSync('sf', ['apex', 'run', '--file', useShell ? `"${file}"` : file, '--json', ...orgArgs], {
        cwd: ROOT,
        encoding: 'utf8',
        shell: useShell,
        maxBuffer: 64 * 1024 * 1024
    });
    if (run.error) {
        console.error(`  Không chạy được Salesforce CLI (sf): ${run.error.message}`);
        return false;
    }
    let output;
    try {
        output = JSON.parse(run.stdout);
    } catch {
        console.error(`  sf không trả về JSON:\n${run.stdout}${run.stderr}`);
        return false;
    }
    const result = output.result || {};
    seedLines(result.logs).forEach((line) => console.log(`  ${line}`));
    if (output.status === 0 && result.success) {
        return true;
    }
    if (result.compiled === false) {
        console.error(`  LỖI biên dịch (dòng ${result.line}, cột ${result.column}): ${result.compileProblem}`);
    } else if (result.exceptionMessage) {
        console.error(`  LỖI khi chạy: ${result.exceptionMessage}\n  ${result.exceptionStackTrace || ''}`);
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
            continue;
        }
        if (step.optional) {
            console.warn(`  ${SKIP_HINT}`);
            skipped.push(step.file);
            continue;
        }
        console.error(`\nDừng ở ${step.file}. Sửa lỗi rồi chạy lại "npm run seed".`);
        return 1;
    }
    if (skipped.length > 0) {
        console.log(`\nDựng xong dữ liệu mẫu, trừ: ${skipped.join(', ')}.`);
        return 0;
    }
    console.log('\nDựng xong dữ liệu mẫu.');
    return 0;
}

// Thay giá trị biến cấu hình ở đầu seed-doi-vai.apex, vd: String role = 'KETOAN';
function setVariable(code, name, value) {
    const pattern = new RegExp(`^(String ${name} = )'[^']*'`, 'm');
    if (!pattern.test(code)) {
        throw new Error(`Không thấy biến ${name} trong seed-doi-vai.apex`);
    }
    return code.replace(pattern, `$1'${value}'`);
}

function doiVai(args) {
    const options = { role: '', user: '', store: 'HCM-012' };
    const orgArgs = [];
    for (let i = 0; i < args.length; i += 1) {
        if (args[i] === '--user' || args[i] === '--store') {
            options[args[i].substring(2)] = args[i + 1] || '';
            i += 1;
        } else if (args[i].startsWith('-')) {
            // cờ của sf, vd -o sr-shared: giữ cả giá trị đi kèm
            orgArgs.push(args[i]);
            if (args[i + 1] && !args[i + 1].startsWith('-')) {
                orgArgs.push(args[i + 1]);
                i += 1;
            }
        } else if (!options.role) {
            options.role = args[i].toUpperCase();
        }
    }
    if (!ROLES.includes(options.role)) {
        console.error(
            `Thiếu hoặc sai vai. Dùng: npm run seed:doi-vai -- <${ROLES.join('|')}> [--user <tên>] [--store <mã cửa hàng>] [-o <org>]`
        );
        return 1;
    }
    const safe = /^[A-Za-z0-9._@-]*$/;
    if (!safe.test(options.user) || !safe.test(options.store)) {
        console.error('--user và --store chỉ gồm chữ, số và các ký tự . _ @ -');
        return 1;
    }

    let code = fs.readFileSync(path.join(APEX_DIR, 'seed-doi-vai.apex'), 'utf8');
    code = setVariable(code, 'role', options.role);
    code = setVariable(code, 'userKey', options.user);
    code = setVariable(code, 'storeCode', options.store);
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sr-seed-'));
    const tmpFile = path.join(tmpDir, 'seed-doi-vai.apex');
    fs.writeFileSync(tmpFile, code);
    try {
        if (!runApex(tmpFile, `Đổi vai user test sang ${options.role}`, '[1/2]', orgArgs)) {
            return 1;
        }
        // Group cửa hàng/vùng tính theo Store_Code__c và permission set Kế toán nên chạy lại seed 3
        if (!runApex(path.join(APEX_DIR, GROUP_STEP.file), GROUP_STEP.title, '[2/2]', orgArgs)) {
            console.warn('\nĐã đổi vai nhưng chưa cập nhật được group cửa hàng/vùng (seed 3).');
            console.warn(`  ${SKIP_HINT}`);
        }
    } finally {
        fs.rmSync(tmpDir, { recursive: true, force: true });
    }
    console.log('\nĐổi vai xong.');
    return 0;
}

const args = process.argv.slice(2);
process.exitCode = args[0] === 'doi-vai' ? doiVai(args.slice(1)) : seedAll(args);
