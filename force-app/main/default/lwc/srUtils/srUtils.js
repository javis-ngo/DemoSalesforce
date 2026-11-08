
// Hàm dùng chung cho các LWC của SmartReturn.
// Dùng:  import { formatLabel, vnd } from 'c/srUtils';

export const REASON_OPTIONS = [
    { label: 'Lỗi kỹ thuật', value: 'DEFECT' },
    { label: 'Giao sai hàng', value: 'WRONG_ITEM' },
    { label: 'Không vừa ý', value: 'NOT_SATISFIED' },
    { label: 'Hư hỏng do khách', value: 'CUSTOMER_DAMAGE' }
];

export const CONDITION_OPTIONS = [
    { label: 'Nguyên seal', value: 'SEALED' },
    { label: 'Đã mở hộp', value: 'OPENED' },
    { label: 'Có dấu hiệu sử dụng', value: 'USED' }
];

export const STATUS_OPTIONS = [
    { label: 'Mới tạo', value: 'NEW' },
    { label: 'Chờ duyệt', value: 'PENDING_APPROVAL' },
    { label: 'Chờ mang hàng', value: 'AWAITING_GOODS' },
    { label: 'Đang kiểm định', value: 'INSPECTING' },
    { label: 'Đang hoàn tiền', value: 'REFUND_PROCESSING' },
    { label: 'Hoàn tất', value: 'COMPLETED' },
    { label: 'Hoàn tiền lỗi', value: 'REFUND_FAILED' },
    { label: 'Từ chối', value: 'REJECTED' },
    { label: 'Đã hủy', value: 'CANCELLED' }
];

// Cấp duyệt dự kiến (Approval_Level__c) hiển thị ở D.1
export const LEVEL_LABELS = {
    AUTO: 'Tự động duyệt',
    CHT: 'Cửa hàng trưởng duyệt',
    QLV: 'Quản lý vùng duyệt'
};

export function labelOf(options, value) {
    const found = options.find((o) => o.value === value);
    return found ? found.label : value;
}

// Thay {0}, {1}... trong Custom Label, giống SR_Util.format ở Apex
export function formatLabel(template, ...args) {
    if (!template) {
        return '';
    }
    return template.replace(/\{(\d+)\}/g, (match, index) => {
        const value = args[Number(index)];
        return value === undefined || value === null ? '' : String(value);
    });
}

// 1992000 -> "1.992.000"
export function vnd(amount) {
    const n = Math.round(Number(amount) || 0);
    return n.toLocaleString('vi-VN');
}

// "2026-10-08" -> "08/10/2026"
export function formatDate(isoDate) {
    if (!isoDate) {
        return '';
    }
    const [y, m, d] = String(isoDate).substring(0, 10).split('-');
    return `${d}/${m}/${y}`;
}

// Lấy câu lỗi dễ đọc từ lỗi trả về khi gọi Apex
export function reduceErrors(error) {
    if (!error) {
        return '';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    return JSON.stringify(error);
}
