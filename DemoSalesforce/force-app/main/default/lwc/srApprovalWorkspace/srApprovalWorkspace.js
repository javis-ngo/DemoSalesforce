import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError, isEmpEnabled } from 'lightning/empApi';
import LightningPrompt from 'lightning/prompt';
import getMyStores from '@salesforce/apex/SR_ApprovalUiController.getMyStores';
import getQueue from '@salesforce/apex/SR_ApprovalUiController.getQueue';
import decide from '@salesforce/apex/SR_ApprovalUiController.decide';
import MSG_11 from '@salesforce/label/c.SR_MSG_11';
import MSG_12 from '@salesforce/label/c.SR_MSG_12';
import MSG_30 from '@salesforce/label/c.SR_MSG_30';
import MSG_31 from '@salesforce/label/c.SR_MSG_31';
import { msgFromError } from 'c/srMessages';
import { STATUS_OPTIONS, formatLabel, vnd, reduceErrors } from 'c/srUtils';

// Event của màn hình duyệt (SR_EventPublisher – Dev B), luôn phát. Không nghe Return_Request_Event__e:
// event đó gửi ra POS/App và chỉ phát khi bật công tắc B.4, nghe cả hai sẽ ra 2 toast cho cùng 1 kết quả.
// Cùng kênh có 2 loại: Change_Type__c = CREATED / UPDATED (trigger, yêu cầu vừa tạo / cập nhật) → tải lại bảng;
// Change_Type__c trống = kết quả hoàn tiền (Result__c) → toast MSG-30 / MSG-31.
const CHANNEL = '/event/SR_UI_Notice__e';
const PAGE_SIZE = 50;
// Mất kết nối: subscribe lại sau 5 giây, lỗi tiếp thì chờ gấp đôi, tối đa 1 phút
const RETRY_MIN_MS = 5000;
const RETRY_MAX_MS = 60000;
// Gom các thay đổi đến sát nhau (vd. import 200 yêu cầu) thành 1 lần tải lại
const REFRESH_DELAY_MS = 1000;

// Đánh dấu ở cột Mã yêu cầu; bỏ khi người dùng lọc, sắp xếp, chuyển trang hoặc duyệt
const CHANGE_MARKERS = {
    CREATED: { icon: 'utility:new', label: 'Mới' },
    UPDATED: { icon: 'utility:edit', label: 'Vừa cập nhật' }
};

function isoDay(date) {
    const d = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return d.toISOString().substring(0, 10);
}

// change: CREATED / UPDATED nếu yêu cầu vừa thay đổi (realtime)
function toRow(r, change) {
    const marker = CHANGE_MARKERS[change];
    return {
        ...r,
        recordUrl: `/lightning/r/Return_Request__c/${r.id}/view`,
        riskText: r.risky ? '⚠ Rủi ro' : '',
        rowClass: r.overdue ? 'slds-text-color_error' : '',
        changeIcon: marker?.icon,
        changeLabel: marker?.label
    };
}

// Dòng quá hạn duyệt tô đỏ (D.2 "Cảnh báo")
const CELL = { class: { fieldName: 'rowClass' } };

const COLUMNS = [
    { label: 'Mã yêu cầu', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'requestNumber' } },
      cellAttributes: { ...CELL, iconName: { fieldName: 'changeIcon' }, iconLabel: { fieldName: 'changeLabel' }, iconPosition: 'right' } },
    { label: 'Khách hàng', fieldName: 'customerName', cellAttributes: CELL },
    { label: 'Cửa hàng', fieldName: 'storeName', cellAttributes: CELL },
    { label: 'Kênh', fieldName: 'channel', cellAttributes: CELL },
    { label: 'Tổng tiền dự kiến', fieldName: 'estimatedRefund', type: 'currency', sortable: true,
      typeAttributes: { currencyCode: 'VND', minimumFractionDigits: 0, maximumFractionDigits: 0 }, cellAttributes: CELL },
    { label: 'Cấp duyệt', fieldName: 'approvalLevel', cellAttributes: CELL },
    { label: 'Người duyệt', fieldName: 'approverName', cellAttributes: CELL },
    { label: 'Chờ (giờ)', fieldName: 'waitingHours', type: 'number', sortable: true, cellAttributes: CELL },
    { label: 'Rủi ro', fieldName: 'riskText', cellAttributes: CELL }
];

// D.2 – Màn hình duyệt cho CHT/QLV (FR-08) + thông báo realtime (FR-09); bảng tự cập nhật khi yêu cầu
// được tạo / sửa ở bất kỳ đâu. Owner: Dev C
export default class SrApprovalWorkspace extends LightningElement {
    columns = COLUMNS;
    statusOptions = STATUS_OPTIONS;
    storeOptions = [{ label: 'Tất cả cửa hàng của tôi', value: '' }];
    myStoreCodes = [];
    myStoreIds = [];
    rows = [];
    total = 0;
    selectedIds = [];
    isLoading = false;
    errorMessage;
    sortedBy = 'waitingHours';
    sortedDirection = 'desc';
    pageNumber = 1;
    decisionSummary;
    decisionErrors = [];
    subscription;
    realtimeOn = false;
    errorListenerAdded = false;
    retryDelay = RETRY_MIN_MS;
    retryTimer;
    refreshTimer;
    loadSeq = 0;
    // requestId → CREATED / UPDATED nhận qua realtime, hiện ở cột Mã yêu cầu
    changes = new Map();

    filters = {
        status: 'PENDING_APPROVAL',
        storeId: '',
        fromDate: isoDay(new Date(Date.now() - 30 * 24 * 3600 * 1000)),
        toDate: isoDay(new Date()),
        onlyMine: false
    };

    @wire(getMyStores)
    wiredStores({ data }) {
        if (data) {
            this.storeOptions = [
                { label: 'Tất cả cửa hàng của tôi', value: '' },
                ...data.map((s) => ({ label: s.label, value: s.value }))
            ];
            this.myStoreCodes = data.map((s) => s.storeCode);
            this.myStoreIds = data.map((s) => s.value);
        }
    }

    connectedCallback() {
        this.load();
        this.startRealtime();
    }

    disconnectedCallback() {
        this.stopRealtime();
    }

    get noSelection() {
        return this.selectedIds.length === 0;
    }

    get hasDecisionErrors() {
        return this.decisionErrors.length > 0;
    }

    get pageCount() {
        return Math.max(1, Math.ceil(this.total / PAGE_SIZE));
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.pageCount;
    }

    // silent = tải lại do realtime: không hiện spinner, giữ dòng đang chọn và đánh dấu thay đổi.
    // Người dùng lọc / sắp xếp / chuyển trang / duyệt thì bỏ chọn và bỏ đánh dấu như trước.
    async load({ silent = false } = {}) {
        const seq = ++this.loadSeq;
        if (!silent) {
            this.isLoading = true;
            this.changes = new Map();
            // Lần tải này đã lấy dữ liệu mới nhất: bỏ lần tải ngầm đang chờ
            clearTimeout(this.refreshTimer);
            this.refreshTimer = undefined;
        }
        try {
            let page = await this.fetchQueue();
            // Trang đang xem không còn dòng (vd. người khác vừa duyệt hết): lùi về trang cuối còn dữ liệu
            const lastPage = Math.max(1, Math.ceil(page.total / PAGE_SIZE));
            if (seq === this.loadSeq && this.pageNumber > lastPage) {
                this.pageNumber = lastPage;
                page = await this.fetchQueue();
            }
            if (seq !== this.loadSeq) {
                return; // đã có lần tải mới hơn, bỏ kết quả cũ
            }
            const tokenBefore = new Map(this.rows.map((r) => [r.id, r.versionToken]));
            this.total = page.total;
            this.rows = page.rows.map((r) => toRow(r, this.changes.get(r.id)));
            // Dòng đang chọn mà vừa bị sửa (versionToken đổi) thì bỏ chọn: xem lại rồi mới duyệt (MSG-13)
            this.selectedIds = silent
                ? this.rows
                      .filter((r) => this.selectedIds.includes(r.id) && tokenBefore.get(r.id) === r.versionToken)
                      .map((r) => r.id)
                : [];
            this.errorMessage = undefined;
        } catch (e) {
            if (seq === this.loadSeq) {
                this.errorMessage = reduceErrors(e);
            }
        } finally {
            if (!silent) {
                this.isLoading = false;
            }
        }
    }

    fetchQueue() {
        return getQueue({
            filtersJson: JSON.stringify({
                ...this.filters,
                storeId: this.filters.storeId || null,
                // "Chờ (giờ)" giảm dần = Submitted_At tăng dần = chờ lâu nhất lên đầu
                sortBy: this.sortedBy === 'estimatedRefund' ? 'AMOUNT' : 'WAIT',
                sortDir: this.sortedBy === 'estimatedRefund'
                    ? this.sortedDirection
                    : this.sortedDirection === 'desc' ? 'asc' : 'desc',
                pageNumber: this.pageNumber
            })
        });
    }

    handleFilter(event) {
        const field = event.target.dataset.field;
        const value = field === 'onlyMine' ? event.target.checked : event.detail.value;
        this.filters = { ...this.filters, [field]: value };
        this.pageNumber = 1;
        this.decisionErrors = [];
        this.load();
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.load();
    }

    handleSelection(event) {
        this.selectedIds = event.detail.selectedRows.map((r) => r.id);
    }

    prevPage() {
        this.pageNumber -= 1;
        this.load();
    }

    nextPage() {
        this.pageNumber += 1;
        this.load();
    }

    async handleApprove() {
        await this.submitDecision(true, null);
    }

    async handleReject() {
        const reason = await LightningPrompt.open({
            message: 'Lý do từ chối (áp dụng cho mọi dòng đã chọn)',
            label: 'Từ chối yêu cầu',
            theme: 'warning'
        });
        if (reason === null) {
            return; // bấm Hủy
        }
        if (!reason.trim()) {
            this.toast(MSG_12, 'error');
            return;
        }
        await this.submitDecision(false, reason.trim());
    }

    async submitDecision(approve, reason) {
        const selected = this.rows.filter((r) => this.selectedIds.includes(r.id));
        const numberOf = new Map(selected.map((r) => [r.id, r.requestNumber]));
        const items = selected.map((r) => ({ requestId: r.id, versionToken: r.versionToken }));
        this.decisionErrors = [];
        this.isLoading = true;
        try {
            const result = await decide({ itemsJson: JSON.stringify(items), approve, reason });
            // MSG-11 (số thành công / tổng) + lý do của từng dòng lỗi (MSG-10, MSG-13…)
            const errors = result.errors || [];
            const succeeded = result.succeeded ?? items.length - errors.length;
            this.decisionSummary = result.summary || formatLabel(MSG_11, succeeded, items.length, errors.length);
            this.decisionErrors = errors.map((e, index) => {
                const requestNumber = e.requestNumber || numberOf.get(e.requestId);
                const text = msgFromError(e);
                return { key: String(index), text: requestNumber ? `${requestNumber}: ${text}` : text };
            });
            this.toast(this.decisionSummary, errors.length === 0 ? 'success' : 'warning');
        } catch (e) {
            this.toast(reduceErrors(e), 'error');
        } finally {
            this.isLoading = false;
        }
        await this.load();
    }

    // FR-09: hoàn tiền xong/lỗi → hiện thông báo góc màn hình, không cần tải lại trang.
    // FR-08: yêu cầu vừa tạo / cập nhật → bảng tự tải lại và đánh dấu dòng thay đổi.
    async startRealtime() {
        this.realtimeOn = true;
        if (!this.errorListenerAdded) {
            onError((error) => this.handleRealtimeError(error));
            this.errorListenerAdded = true;
        }
        if (await isEmpEnabled()) {
            this.subscribeRealtime();
        }
    }

    stopRealtime() {
        this.realtimeOn = false;
        clearTimeout(this.retryTimer);
        clearTimeout(this.refreshTimer);
        this.refreshTimer = undefined;
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    subscribeRealtime() {
        subscribe(CHANNEL, -1, (message) => this.handleEvent(message.data.payload))
            .then((sub) => {
                if (!this.realtimeOn) {
                    unsubscribe(sub); // đã rời trang trong lúc chờ subscribe
                    return;
                }
                this.subscription = sub;
                this.retryDelay = RETRY_MIN_MS;
            })
            .catch((error) => this.handleRealtimeError(error));
    }

    // Mất kết nối: bỏ subscription cũ, subscribe lại sau một lúc và làm mới bảng để không sót thay đổi
    handleRealtimeError(error) {
        console.error('empApi error', JSON.stringify(error));
        if (!this.realtimeOn) {
            return;
        }
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
        clearTimeout(this.retryTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.retryTimer = setTimeout(() => {
            if (this.realtimeOn) {
                this.subscribeRealtime();
                this.load({ silent: true });
            }
        }, this.retryDelay);
        this.retryDelay = Math.min(this.retryDelay * 2, RETRY_MAX_MS);
    }

    // Kết quả hoàn tiền: chỉ event của cửa hàng mình; Result__c khác COMPLETED / REFUND_FAILED thì bỏ qua
    handleEvent(p) {
        if (p.Change_Type__c) {
            this.handleChange(p);
            return;
        }
        if (!this.myStoreCodes.includes(p.Store_Code__c)) {
            return;
        }
        if (p.Result__c === 'COMPLETED') {
            this.toast(formatLabel(MSG_30, p.Request_Number__c, vnd(p.Amount__c)), 'success');
        } else if (p.Result__c === 'REFUND_FAILED') {
            this.toast(formatLabel(MSG_31, p.Request_Number__c), 'warning');
        } else {
            return;
        }
        this.scheduleRefresh();
    }

    // Yêu cầu vừa tạo / cập nhật (FR-08, D.2): đánh dấu dòng và tải lại nếu bảng đang xem có thể khác đi.
    // Người không quản lý cửa hàng nào (vd. Admin) thì nhận mọi cửa hàng: dữ liệu vẫn lấy qua getQueue
    // (USER_MODE) nên chỉ thấy yêu cầu được phép xem (BR-16).
    handleChange(p) {
        if (this.myStoreIds.length > 0 && !this.myStoreIds.includes(p.Store_Id__c)) {
            return;
        }
        // Yêu cầu được tạo ở NEW rồi mới chuyển trạng thái trong cùng giao dịch (SR_ReturnRequestService):
        // nhớ CREATED kể cả khi chưa vào bộ lọc để dòng vẫn là "Mới" lúc hiện lên
        if (p.Change_Type__c === 'CREATED') {
            this.changes.set(p.Request_Id__c, 'CREATED');
        }
        if (!this.affectsView(p)) {
            return;
        }
        if (!this.changes.has(p.Request_Id__c)) {
            this.changes.set(p.Request_Id__c, p.Change_Type__c);
        }
        this.scheduleRefresh();
    }

    // Dòng đang hiện, hoặc trạng thái mới / cũ trùng bộ lọc (yêu cầu vào / ra danh sách, đổi tổng số)
    affectsView(p) {
        if (this.rows.some((r) => r.id === p.Request_Id__c)) {
            return true;
        }
        if (this.filters.storeId && this.filters.storeId !== p.Store_Id__c) {
            return false;
        }
        return p.Status__c === this.filters.status || p.Old_Status__c === this.filters.status;
    }

    // Chờ REFRESH_DELAY_MS để gom các event đến sát nhau rồi tải lại 1 lần
    scheduleRefresh() {
        if (this.refreshTimer) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.refreshTimer = setTimeout(() => {
            this.refreshTimer = undefined;
            this.load({ silent: true });
        }, REFRESH_DELAY_MS);
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
