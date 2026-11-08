import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReturnableOrder from '@salesforce/apex/SR_ReturnUiController.getReturnableOrder';
import previewCreate from '@salesforce/apex/SR_ReturnUiController.previewCreate';
import createFromCounter from '@salesforce/apex/SR_ReturnUiController.createFromCounter';
import { MSG_01, MSG_05, MSG_06, formatLabel, msgFromError } from 'c/srMessages';
import {
    REASON_OPTIONS,
    CONDITION_OPTIONS,
    LEVEL_LABELS,
    labelOf,
    vnd,
    formatDate,
    reduceErrors
} from 'c/srUtils';

const PREVIEW_DELAY_MS = 300;
const EMPTY = '—';

// Tham số {0}, {1} của label theo mã lỗi (SR_ErrorCode): service của Dev A chỉ gửi mã + SKU,
// màn hình điền tên sản phẩm, ngành hàng, hạn đổi trả, số lượng còn trả được
function lineMessage(code, line, message) {
    const params = {
        RETURN_WINDOW_EXPIRED: [line.productName, formatDate(line.returnDeadline)],
        NOT_RETURNABLE: [line.category],
        QUANTITY_EXCEEDED: [line.productName, line.returnableQuantity ?? 0]
    }[code];
    return msgFromError({ code, params, message });
}

// D.1 – Tạo yêu cầu trả hàng tại quầy (FR-01, FR-02). Quick Action trên Order. Owner: Dev C
// Tiền hoàn và cấp duyệt luôn do Apex tính (SR_ReturnRequestService.previewCreate của Dev A); JS chỉ hiển thị.
export default class SrCreateReturnRequest extends NavigationMixin(LightningElement) {
    @api recordId; // Id đơn hàng
    info;
    lines = [];
    loadError;
    preview; // kết quả previewCreate gần nhất, chỉ giữ khi tính được (success)
    submitErrors = [];
    isPreviewing = false;
    isSaving = false;
    reasonOptions = REASON_OPTIONS;
    conditionOptions = CONDITION_OPTIONS;
    noLineMessage = MSG_06;
    previewTimer;
    previewSeq = 0;

    // recordId của Quick Action có thể đến muộn, nên dùng @wire với '$recordId'
    @wire(getReturnableOrder, { orderId: '$recordId' })
    wiredInfo({ data, error }) {
        if (data) {
            this.info = data;
            this.lines = (data.lines || []).map((l) => ({
                ...l,
                locked: !l.eligible,
                rowClass: l.eligible ? '' : 'sr-row_locked',
                deadlineText: formatDate(l.returnDeadline),
                lockText: l.eligible ? null : lineMessage(l.lockCode, l, l.lockMessage),
                qty: 0,
                reason: null,
                condition: null,
                refundText: EMPTY,
                error: null,
                hint: null
            }));
            this.loadError = undefined;
        } else if (error) {
            this.loadError = reduceErrors(error);
        }
    }

    disconnectedCallback() {
        clearTimeout(this.previewTimer);
    }

    get isLoading() {
        return !this.info && !this.loadError;
    }

    get purchaseDateText() {
        return formatDate(this.info?.purchaseDate);
    }

    get deliveryDateText() {
        return this.info?.deliveryDate ? formatDate(this.info.deliveryDate) : 'Mua tại quầy';
    }

    get chosenLines() {
        return this.lines.filter((l) => l.qty > 0);
    }

    // Dòng đủ thông tin để Apex tính tiền (SR_CreateLineDTO)
    get draftLines() {
        return this.chosenLines
            .filter((l) => l.reason && l.condition)
            .map((l) => ({ orderItemId: l.orderItemId, quantity: l.qty, reason: l.reason, condition: l.condition }));
    }

    get showNoLineHint() {
        return !!this.info && this.chosenLines.length === 0;
    }

    get submitDisabled() {
        return this.isSaving || this.chosenLines.length === 0;
    }

    get totalText() {
        if (this.isPreviewing) {
            return 'Đang tính…';
        }
        if (this.preview) {
            return `${vnd(this.preview.estimatedRefund)}đ`;
        }
        return this.draftLines.length > 0 ? EMPTY : '0đ';
    }

    get levelText() {
        if (this.isPreviewing) {
            return 'Đang tính…';
        }
        const level = this.preview && this.preview.approvalLevel;
        if (!level) {
            return EMPTY;
        }
        const label = LEVEL_LABELS[level] || level;
        return this.preview.riskFlag ? `${label} (khách có cờ Rủi ro)` : label;
    }

    handleQty(event) {
        this.updateLine(event.target.dataset.id, { qty: Number(event.detail.value) || 0 });
    }

    handleReason(event) {
        this.updateLine(event.target.dataset.id, { reason: event.detail.value });
    }

    handleCondition(event) {
        this.updateLine(event.target.dataset.id, { condition: event.detail.value });
    }

    updateLine(orderItemId, changes) {
        this.lines = this.lines.map((l) => (l.orderItemId === orderItemId ? { ...l, ...changes } : l));
        this.submitErrors = [];
        this.schedulePreview();
    }

    // Đổi SL / lý do / tình trạng: chờ 300ms không đổi nữa mới gọi Apex (debounce)
    schedulePreview() {
        clearTimeout(this.previewTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.previewTimer = setTimeout(() => {
            this.runPreview();
        }, PREVIEW_DELAY_MS);
    }

    async runPreview() {
        const seq = ++this.previewSeq; // chỉ nhận kết quả của lần gọi mới nhất
        const draftLines = this.draftLines;
        if (draftLines.length === 0) {
            this.isPreviewing = false;
            this.applyPreview(null);
            return;
        }
        this.isPreviewing = true;
        try {
            const result = await previewCreate({
                draftJson: JSON.stringify({ orderId: this.recordId, lines: draftLines })
            });
            if (seq === this.previewSeq) {
                this.applyPreview(result);
            }
        } catch (e) {
            if (seq === this.previewSeq) {
                this.applyPreview(null);
                this.submitErrors = [{ key: 'preview', text: reduceErrors(e) }];
            }
        } finally {
            if (seq === this.previewSeq) {
                this.isPreviewing = false;
            }
        }
    }

    // Lỗi tại dòng (theo SKU): tỷ lệ 0% là NOT_RETURNABLE trên dòng vốn trả được → MSG-05
    previewLineError(error, line) {
        if (error.code === 'NOT_RETURNABLE' && line.eligible) {
            return formatLabel(
                MSG_05,
                line.productName,
                labelOf(REASON_OPTIONS, line.reason),
                labelOf(CONDITION_OPTIONS, line.condition)
            );
        }
        return lineMessage(error.code, line, error.message);
    }

    // Tách lỗi của service: có SKU thì gắn vào dòng, không có SKU thì hiện dưới bảng
    splitErrors(errors) {
        const bySku = new Map();
        const others = [];
        (errors || []).forEach((e) => {
            if (e.sku && !bySku.has(e.sku)) {
                bySku.set(e.sku, e);
            } else if (!e.sku) {
                others.push(e);
            }
        });
        return { bySku, others };
    }

    // Gắn tiền từng dòng và lỗi tại dòng (MSG-04 vượt số lượng, MSG-05 tỷ lệ 0%) từ kết quả Apex
    applyPreview(result) {
        this.preview = result && result.success ? result : null;
        const amountOf = new Map(((result && result.lines) || []).map((p) => [p.orderItemId, p.refundAmount]));
        const { bySku, others } = this.splitErrors(result && result.errors);
        this.lines = this.lines.map((l) => {
            const chosen = l.qty > 0;
            const amount = chosen ? amountOf.get(l.orderItemId) : undefined;
            const error = chosen ? bySku.get(l.sku) : undefined;
            return {
                ...l,
                refundText: amount !== undefined && amount !== null ? `${vnd(amount)}đ` : EMPTY,
                error: error ? this.previewLineError(error, l) : null,
                hint: chosen && (!l.reason || !l.condition) ? 'Chọn lý do và tình trạng để tính tiền' : null
            };
        });
        this.submitErrors = others.map((e, index) => ({ key: `preview-${index}`, text: msgFromError(e) }));
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSubmit() {
        const chosen = this.chosenLines;
        if (chosen.length === 0) {
            this.submitErrors = [{ key: 'msg06', text: MSG_06 }];
            return;
        }
        const missing = chosen.find((l) => !l.reason || !l.condition);
        if (missing) {
            this.submitErrors = [{ key: 'missing', text: `Vui lòng chọn lý do và tình trạng cho ${missing.productName}.` }];
            return;
        }
        const withError = chosen.find((l) => l.error);
        if (withError) {
            this.submitErrors = [{ key: 'line', text: withError.error }];
            return;
        }

        clearTimeout(this.previewTimer);
        this.isSaving = true;
        this.submitErrors = [];
        try {
            const result = await createFromCounter({
                draftJson: JSON.stringify({ orderId: this.recordId, lines: this.draftLines })
            });
            if (result && result.success) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: formatLabel(MSG_01, result.requestNumber, vnd(result.estimatedRefund)),
                        variant: 'success'
                    })
                );
                this.dispatchEvent(new CloseActionScreenEvent());
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: result.requestId, objectApiName: 'Return_Request__c', actionName: 'view' }
                });
            } else {
                const lineOf = new Map(this.lines.map((l) => [l.sku, l]));
                const texts = ((result && result.errors) || []).map((e) => {
                    const line = e.sku ? lineOf.get(e.sku) : undefined;
                    return line ? this.previewLineError(e, line) : msgFromError(e);
                });
                this.submitErrors = (texts.length ? texts : [msgFromError({ code: 'INTERNAL_ERROR' })]).map(
                    (text, index) => ({ key: String(index), text })
                );
            }
        } catch (e) {
            this.submitErrors = [{ key: 'error', text: reduceErrors(e) }];
        } finally {
            this.isSaving = false;
        }
    }
}
