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
    { id: 'a00000000000001AAA', requestNumber: 'RR-2610-00001', lastModified: '2026-10-22T01:00:00.000Z' },
    { id: 'a00000000000002AAA', requestNumber: 'RR-2610-00002', lastModified: '2026-10-22T02:00:00.000Z' }
];

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
        decide.mockResolvedValue({ succeeded: 1, errors: [{ requestId: ROWS[1].id, code: 'SELF_APPROVAL' }] });
        const element = render();
        const toasts = collectToasts(element);
        await flushPromises();

        element.shadowRoot
            .querySelector('lightning-datatable')
            .dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: ROWS } }));
        [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Duyệt').click();
        await flushPromises();

        expect(decide).toHaveBeenCalledWith({
            itemsJson: JSON.stringify(ROWS.map((r) => ({ requestId: r.id, lastModified: r.lastModified }))),
            approve: true,
            reason: null
        });
        const summary = 'Đã xử lý 1/2 yêu cầu. Không xử lý được: 1.';
        expect(toasts).toEqual([expect.objectContaining({ title: summary, variant: 'warning' })]);
        expect(element.shadowRoot.querySelector('p.slds-text-title_bold').textContent).toBe(summary);
        const reasons = [...element.shadowRoot.querySelectorAll('li')].map((li) => li.textContent);
        expect(reasons).toEqual(['RR-2610-00002: Bạn không thể duyệt yêu cầu do chính mình tạo.']);
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
});
