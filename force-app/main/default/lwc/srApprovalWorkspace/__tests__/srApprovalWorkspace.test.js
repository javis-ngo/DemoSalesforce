import { createElement } from '@lwc/engine-dom';
import SrApprovalWorkspace from 'c/srApprovalWorkspace';
import { subscribe, onError, isEmpEnabled } from 'lightning/empApi';
import getMyStores from '@salesforce/apex/SR_ApprovalUiController.getMyStores';
import getQueue from '@salesforce/apex/SR_ApprovalUiController.getQueue';
import decide from '@salesforce/apex/SR_ApprovalUiController.decide';

jest.mock(
    '@salesforce/apex/SR_ApprovalUiController.getMyStores',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/SR_ApprovalUiController.getQueue', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SR_ApprovalUiController.decide', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/label/c.SR_MSG_10', () => ({ default: 'Bạn không thể duyệt yêu cầu do chính mình tạo.' }), {
    virtual: true
});
jest.mock('@salesforce/label/c.SR_MSG_11', () => ({ default: 'Đã xử lý {0}/{1} yêu cầu. Không xử lý được: {2}.' }), {
    virtual: true
});
jest.mock('@salesforce/label/c.SR_MSG_30', () => ({ default: 'Yêu cầu {0} đã hoàn tiền thành công {1}đ.' }), {
    virtual: true
});

const ROWS = [
    { id: 'a00000000000001AAA', requestNumber: 'RR-2610-00001', versionToken: '1761094800000' },
    { id: 'a00000000000002AAA', requestNumber: 'RR-2610-00002', versionToken: '1761098400000' }
];
const NEW_ROW = { id: 'a00000000000003AAA', requestNumber: 'RR-2610-00003', versionToken: '1761102000000' };
const STORE = { label: 'HCM-012 – Quận 1', value: 'a0S000000000001AAA', storeCode: 'HCM-012' };
const OTHER_STORE_ID = 'a0S000000000002AAA';

// Chờ Apex giả lập trả kết quả và component render lại (vài vòng microtask)
async function flushPromises(rounds = 5) {
    await Promise.resolve();
    if (rounds > 1) {
        await flushPromises(rounds - 1);
    }
}

function render() {
    const element = createElement('c-sr-approval-workspace', { is: SrApprovalWorkspace });
    document.body.appendChild(element);
    return element;
}

function collectToasts(element) {
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    return toasts;
}

function datatable(element) {
    return element.shadowRoot.querySelector('lightning-datatable');
}

// Bật empApi giả lập; trả về hàm gửi 1 event SR_UI_Notice__e vào component
function mockRealtime() {
    let handler;
    isEmpEnabled.mockResolvedValue(true);
    subscribe.mockImplementation((channel, replayId, callback) => {
        handler = callback;
        return Promise.resolve({ channel });
    });
    return (payload) => handler({ data: { payload } });
}

// Thông báo thay đổi do ReturnRequestTrigger phát (SR_EventPublisher.publishChanges)
function change(type, requestId, status, oldStatus, storeId = STORE.value) {
    return { Change_Type__c: type, Request_Id__c: requestId, Store_Id__c: storeId, Status__c: status, Old_Status__c: oldStatus };
}

// Mở màn hình của CHT cửa hàng STORE, chờ lần tải đầu
async function renderWithRealtime() {
    jest.useFakeTimers();
    const send = mockRealtime();
    const element = render();
    getMyStores.emit([STORE]);
    await flushPromises();
    return { element, send };
}

describe('c-sr-approval-workspace', () => {
    beforeEach(() => {
        getQueue.mockResolvedValue({ rows: ROWS, total: ROWS.length, pageSize: 50 });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('duyệt hàng loạt hiện MSG-11 và lý do của từng dòng lỗi', async () => {
        // Kết quả theo SR_ApprovalQueueService.DecisionSummary; FORBIDDEN chưa có label nên hiện câu của SR_ApprovalService
        decide.mockResolvedValue({
            succeeded: 1,
            total: 2,
            errors: [{ requestId: ROWS[1].id, code: 'FORBIDDEN', message: 'Người tạo yêu cầu không được tự duyệt.' }]
        });
        const element = render();
        const toasts = collectToasts(element);
        await flushPromises();

        element.shadowRoot
            .querySelector('lightning-datatable')
            .dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: ROWS } }));
        [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Duyệt').click();
        await flushPromises();

        expect(decide).toHaveBeenCalledWith({
            itemsJson: JSON.stringify(ROWS.map((r) => ({ requestId: r.id, versionToken: r.versionToken }))),
            approve: true,
            reason: null
        });
        const summary = 'Đã xử lý 1/2 yêu cầu. Không xử lý được: 1.';
        expect(toasts).toEqual([expect.objectContaining({ title: summary, variant: 'warning' })]);
        expect(element.shadowRoot.querySelector('p.slds-text-title_bold').textContent).toBe(summary);
        const reasons = [...element.shadowRoot.querySelectorAll('li')].map((li) => li.textContent);
        expect(reasons).toEqual(['RR-2610-00002: Người tạo yêu cầu không được tự duyệt.']);
    });

    it('chỉ báo COMPLETED / REFUND_FAILED của cửa hàng mình từ SR_UI_Notice__e', async () => {
        let handler;
        isEmpEnabled.mockResolvedValue(true);
        subscribe.mockImplementation((channel, replayId, callback) => {
            handler = callback;
            return Promise.resolve({ channel });
        });
        const element = render();
        const toasts = collectToasts(element);
        getMyStores.emit([{ label: 'HCM-012 – Quận 1', value: 'a0S000000000001AAA', storeCode: 'HCM-012' }]);
        await flushPromises();
        // Chỉ 1 kênh: không nghe thêm Return_Request_Event__e (POS/App), tránh 2 toast cho cùng 1 kết quả
        expect(subscribe).toHaveBeenCalledTimes(1);
        expect(subscribe).toHaveBeenCalledWith('/event/SR_UI_Notice__e', -1, expect.any(Function));

        const send = (payload) => handler({ data: { payload: { Request_Number__c: 'RR-2610-00001', ...payload } } });
        send({ Store_Code__c: 'HCM-012', Result__c: 'COMPLETED', Amount__c: 1992000 });
        send({ Store_Code__c: 'HCM-012', Result__c: 'REFUND_FAILED' });
        send({ Store_Code__c: 'HCM-012', Result__c: 'APPROVED' });
        send({ Store_Code__c: 'HN-001', Result__c: 'COMPLETED', Amount__c: 500000 });

        expect(toasts.map((t) => t.variant)).toEqual(['success', 'warning']);
        expect(toasts[0].title).toBe('Yêu cầu RR-2610-00001 đã hoàn tiền thành công 1.992.000đ.');
    });

    it('mất kết nối thì subscribe lại sau 5 giây', async () => {
        jest.useFakeTimers();
        jest.spyOn(console, 'error').mockImplementation(() => {});
        let errorHandler;
        onError.mockImplementation((callback) => {
            errorHandler = callback;
        });
        isEmpEnabled.mockResolvedValue(true);
        subscribe.mockResolvedValue({ channel: '/event/SR_UI_Notice__e' });
        render();
        await flushPromises();
        expect(subscribe).toHaveBeenCalledTimes(1);

        errorHandler({ error: 'connection lost' });
        jest.advanceTimersByTime(5000);
        expect(subscribe).toHaveBeenCalledTimes(2);
    });

    it('yêu cầu mới của cửa hàng mình hiện trên bảng không cần tải lại trang, có đánh dấu "Mới"', async () => {
        const { element, send } = await renderWithRealtime();
        expect(getQueue).toHaveBeenCalledTimes(1);

        let resolveRefresh;
        getQueue.mockReturnValueOnce(
            new Promise((resolve) => {
                resolveRefresh = resolve;
            })
        );
        // Tạo rồi cập nhật ngay trong cùng giao dịch: gom lại, chỉ tải 1 lần sau 1 giây
        send(change('CREATED', NEW_ROW.id, 'NEW'));
        send(change('UPDATED', NEW_ROW.id, 'PENDING_APPROVAL', 'NEW'));
        jest.advanceTimersByTime(999);
        expect(getQueue).toHaveBeenCalledTimes(1);
        jest.advanceTimersByTime(1);
        await flushPromises();
        expect(getQueue).toHaveBeenCalledTimes(2);
        // Tải ngầm: không hiện spinner trên bảng
        expect(datatable(element).isLoading).toBe(false);

        resolveRefresh({ rows: [...ROWS, NEW_ROW], total: 3, pageSize: 50 });
        await flushPromises();
        const rows = datatable(element).data;
        expect(rows.map((r) => r.changeLabel)).toEqual([undefined, undefined, 'Mới']);
        expect(rows[2].changeIcon).toBe('utility:new');
        const spans = [...element.shadowRoot.querySelectorAll('span')].map((s) => s.textContent);
        expect(spans).toContain('Tổng: 3 yêu cầu');
    });

    it('bỏ qua thay đổi của cửa hàng khác hoặc không làm khác bảng đang xem', async () => {
        const { send } = await renderWithRealtime();

        send(change('CREATED', NEW_ROW.id, 'PENDING_APPROVAL', undefined, OTHER_STORE_ID));
        // Cửa hàng mình nhưng không có trên bảng, trạng thái cũ / mới đều khác bộ lọc "Chờ duyệt"
        send(change('UPDATED', NEW_ROW.id, 'REFUND_PROCESSING', 'INSPECTING'));
        jest.advanceTimersByTime(1000);
        await flushPromises();
        expect(getQueue).toHaveBeenCalledTimes(1);

        // Rời bộ lọc (vừa được duyệt ở máy khác) dù không ở trang này: tải lại để cập nhật tổng số
        send(change('UPDATED', NEW_ROW.id, 'AWAITING_GOODS', 'PENDING_APPROVAL'));
        jest.advanceTimersByTime(1000);
        await flushPromises();
        expect(getQueue).toHaveBeenCalledTimes(2);
    });

    it('tự làm mới giữ dòng đang chọn, bỏ chọn dòng vừa bị người khác sửa', async () => {
        const { element, send } = await renderWithRealtime();
        datatable(element).dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: ROWS } }));

        const edited = { ...ROWS[1], versionToken: '1761105600000' };
        getQueue.mockResolvedValue({ rows: [ROWS[0], edited], total: 2, pageSize: 50 });
        send(change('UPDATED', edited.id, 'PENDING_APPROVAL', 'PENDING_APPROVAL'));
        jest.advanceTimersByTime(1000);
        await flushPromises();

        expect(datatable(element).selectedRows).toEqual([ROWS[0].id]);
        expect(datatable(element).data[1].changeLabel).toBe('Vừa cập nhật');

        // Chỉ duyệt dòng chưa đổi; sau khi duyệt bảng tải lại và bỏ đánh dấu
        decide.mockResolvedValue({ succeeded: 1, total: 1, errors: [] });
        [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Duyệt').click();
        await flushPromises(10);
        expect(decide).toHaveBeenCalledWith({
            itemsJson: JSON.stringify([{ requestId: ROWS[0].id, versionToken: ROWS[0].versionToken }]),
            approve: true,
            reason: null
        });
        expect(datatable(element).data.map((r) => r.changeLabel)).toEqual([undefined, undefined]);
    });
});
