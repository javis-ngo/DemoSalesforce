/**
 * srMessages – thông báo dùng chung của SmartReturn (Phụ lục F, NFR-11). 
 * Module không có giao diện: chỉ export label và hàm thay {0}, {1}, {2}.
 *
 * Cách dùng trong LWC khác:
 *   import { MSG_06, MSG_20, msg, formatLabel } from 'c/srMessages';
 *
 *   msg('MSG-01', 'RR-2610-00001', '1.992.000');
 *   // → "Đã tạo yêu cầu RR-2610-00001. Số tiền hoàn dự kiến 1.992.000đ."
 *   formatLabel(MSG_20, 'Hoàn tất', 'Đang kiểm định');
 *   // → "Không thể chuyển yêu cầu từ Hoàn tất sang Đang kiểm định."
 *   this.errorMessage = MSG_06; // label không có {0} thì dùng thẳng
 *
 *   // Lỗi service trả về dạng { sku, code, params } → câu hiển thị
 *   this.resultErrors = result.errors.map(msgFromError);
 *
 * Trong HTML: trong JS gán `label = LABELS;` rồi dùng {label.SR_MSG_06}.
 * Số tiền truyền vào phải định dạng sẵn (vd "1.992.000"), vì label đã có chữ "đ".
 * Nội dung label sửa trong Setup › Custom Labels, không sửa ở file này.
 */
import SR_MSG_01 from '@salesforce/label/c.SR_MSG_01';
import SR_MSG_02 from '@salesforce/label/c.SR_MSG_02';
import SR_MSG_03 from '@salesforce/label/c.SR_MSG_03';
import SR_MSG_04 from '@salesforce/label/c.SR_MSG_04';
import SR_MSG_05 from '@salesforce/label/c.SR_MSG_05';
import SR_MSG_06 from '@salesforce/label/c.SR_MSG_06';
import SR_MSG_10 from '@salesforce/label/c.SR_MSG_10';
import SR_MSG_11 from '@salesforce/label/c.SR_MSG_11';
import SR_MSG_12 from '@salesforce/label/c.SR_MSG_12';
import SR_MSG_13 from '@salesforce/label/c.SR_MSG_13';
import SR_MSG_20 from '@salesforce/label/c.SR_MSG_20';
import SR_MSG_21 from '@salesforce/label/c.SR_MSG_21';
import SR_MSG_22 from '@salesforce/label/c.SR_MSG_22';
import SR_MSG_30 from '@salesforce/label/c.SR_MSG_30';
import SR_MSG_31 from '@salesforce/label/c.SR_MSG_31';
import SR_MSG_40 from '@salesforce/label/c.SR_MSG_40';
import SR_MSG_41 from '@salesforce/label/c.SR_MSG_41';
import SR_MSG_90 from '@salesforce/label/c.SR_MSG_90';
import SR_ERR_ORDER_NOT_FOUND from '@salesforce/label/c.SR_ERR_ORDER_NOT_FOUND';
import SR_ERR_NOT_APPROVER from '@salesforce/label/c.SR_ERR_NOT_APPROVER';

export const MSG_01 = SR_MSG_01; 
export const MSG_02 = SR_MSG_02; 
export const MSG_03 = SR_MSG_03; 
export const MSG_04 = SR_MSG_04; 
export const MSG_05 = SR_MSG_05;
export const MSG_06 = SR_MSG_06; 
export const MSG_10 = SR_MSG_10;
export const MSG_11 = SR_MSG_11; 
export const MSG_12 = SR_MSG_12; 
export const MSG_13 = SR_MSG_13; 
export const MSG_20 = SR_MSG_20; 
export const MSG_21 = SR_MSG_21; 
export const MSG_22 = SR_MSG_22; 
export const MSG_30 = SR_MSG_30; 
export const MSG_31 = SR_MSG_31; 
export const MSG_40 = SR_MSG_40; 
export const MSG_41 = SR_MSG_41; 
export const MSG_90 = SR_MSG_90; 
export const ERR_ORDER_NOT_FOUND = SR_ERR_ORDER_NOT_FOUND; 
export const ERR_NOT_APPROVER = SR_ERR_NOT_APPROVER; 

// Tra theo tên label, giống System.Label.SR_MSG_01 bên Apex
export const LABELS = Object.freeze({
    SR_MSG_01,
    SR_MSG_02,
    SR_MSG_03,
    SR_MSG_04,
    SR_MSG_05,
    SR_MSG_06,
    SR_MSG_10,
    SR_MSG_11,
    SR_MSG_12,
    SR_MSG_13,
    SR_MSG_20,
    SR_MSG_21,
    SR_MSG_22,
    SR_MSG_30,
    SR_MSG_31,
    SR_MSG_40,
    SR_MSG_41,
    SR_MSG_90,
    SR_ERR_ORDER_NOT_FOUND,
    SR_ERR_NOT_APPROVER
});

/**
 * Thay {0}, {1}, {2}... trong label bằng tham số theo thứ tự.
 * Thiếu tham số (undefined/null) thì để trống, giống SR_Util.format bên Apex.
 * formatLabel(MSG_11, 8, 10, 2) → "Đã xử lý 8/10 yêu cầu. Không xử lý được: 2."
 */
export function formatLabel(template, ...args) {
    if (template === undefined || template === null) {
        return '';
    }
    return String(template).replace(/\{(\d+)\}/g, (match, index) => {
        const value = args[Number(index)];
        return value === undefined || value === null ? '' : String(value);
    });
}

// 'SR_MSG_01', 'MSG_01', 'MSG-01', 'msg-01' đều ra 'SR_MSG_01'
function toLabelName(name) {
    const key = String(name).trim().toUpperCase().replace(/-/g, '_');
    return key.startsWith('SR_') ? key : `SR_${key}`;
}

/**
 * Lấy label theo tên rồi thay tham số.
 * msg('MSG-20', 'Hoàn tất', 'Đang kiểm định') → "Không thể chuyển yêu cầu từ Hoàn tất sang Đang kiểm định."
 * Tên không tồn tại thì trả lại chính tên đó, để thấy ngay trên màn hình khi gõ sai.
 */
export function msg(name, ...args) {
    if (name === undefined || name === null || name === '') {
        return '';
    }
    const template = LABELS[toLabelName(name)];
    return template === undefined ? String(name) : formatLabel(template, ...args);
}

/**
 * Bảng map mã lỗi của service (SR_ErrorCode, SR_StatusMachine – Dev A) → label hiển thị trên màn hình.
 * Service trả lỗi dạng SR_ErrorDetailDTO / SR_ActionResultDTO { sku, code, params, message }.
 * params (nếu có) phải đúng thứ tự {0}, {1}, {2} của label; màn hình tự điền params khi biết
 * (vd D.1 điền tên sản phẩm cho MSG-02 / 04). Mã không có ở đây (MISSING_FIELD, INVALID_VALUE,
 * FORBIDDEN, SKU_NOT_IN_ORDER, VALIDATION_FAILED…) dùng message Apex gửi về (xem msgFromError).
 */
export const ERROR_LABELS = Object.freeze({
    // Tạo yêu cầu – SR_ReturnRequestService.previewCreate / createRequests
    NOT_RETURNABLE: 'SR_MSG_03',
    RETURN_WINDOW_EXPIRED: 'SR_MSG_02',
    QUANTITY_EXCEEDED: 'SR_MSG_04',
    ORDER_NOT_FOUND: 'SR_ERR_ORDER_NOT_FOUND',
    // Duyệt / đổi trạng thái – SR_ApprovalService.decide, SR_StatusMachine.change
    REJECTION_REASON_REQUIRED: 'SR_MSG_12',
    STALE_RECORD: 'SR_MSG_13',
    INVALID_STATUS_TRANSITION: 'SR_MSG_20',
    // Lỗi không lường trước
    INTERNAL_ERROR: 'SR_MSG_90'
});

const PLACEHOLDER = /\{\d+\}/;

/**
 * Đổi 1 lỗi của service thành câu hiển thị.
 * Nhận { code, params, message } hoặc chuỗi. Thứ tự ưu tiên:
 *   1. mã có trong ERROR_LABELS → label theo mã, thay params;
 *      label cần tham số mà không có params thì dùng message Apex gửi về (tránh hiện "{0}" trống);
 *   2. mã chưa có label → message Apex gửi về;
 *   3. không có cả hai → MSG-90 kèm mã lỗi, để người dùng báo hỗ trợ.
 * msgFromError({ code: 'QUANTITY_EXCEEDED', params: ['Nồi chiên 5L', 1] })
 * → "Số lượng trả của Nồi chiên 5L vượt quá số lượng còn được trả (1)."
 */
export function msgFromError(error) {
    if (error === undefined || error === null || error === '') {
        return '';
    }
    if (typeof error !== 'object') {
        return String(error);
    }
    const labelName = ERROR_LABELS[error.code];
    if (labelName) {
        let params = [];
        if (Array.isArray(error.params)) {
            params = error.params;
        } else if (error.params !== undefined && error.params !== null) {
            params = [error.params];
        }
        const needsParams = PLACEHOLDER.test(LABELS[labelName]);
        if (!needsParams || params.length > 0 || !error.message) {
            return msg(labelName, ...params);
        }
    }
    if (error.message) {
        return String(error.message);
    }
    return formatLabel(SR_MSG_90, error.code || '');
}