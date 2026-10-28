import { createElement } from '@lwc/engine-dom';
import SrManualRefund from 'c/srManualRefund';
import markManualRefund from '@salesforce/apex/SR_RefundManualController.markManualRefund';

jest.mock('@salesforce/apex/SR_RefundManualController.markManualRefund', () => ({ default: jest.fn() }), {
    virtual: true
});
// sfdx-lwc-jest chưa có stub lightning/actions: giả lập CloseActionScreenEvent là event "close"
jest.mock(
    'lightning/actions',
    () => ({
        CloseActionScreenEvent: class extends CustomEvent {
            constructor() {
                super('close');
            }
        }
    }),
    { virtual: true }
);

const REQUEST_ID = 'a00000000000001AAA';

async function flushPromises(rounds = 5) {
    await Promise.resolve();
    if (rounds > 1) {
        await flushPromises(rounds - 1);
    }
}

function render() {
    const element = createElement('c-sr-manual-refund', { is: SrManualRefund });
    element.recordId = REQUEST_ID;
    document.body.appendChild(element);
    return element;
}

const button = (element, label) =>
    [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);

async function typeTransactionId(element, value) {
    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

function collectToasts(element) {
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    return toasts;
}

describe('c-sr-manual-refund', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('chưa nhập mã giao dịch thì không bấm được Xác nhận', async () => {
        const element = render();
        await flushPromises();
        expect(button(element, 'Xác nhận').disabled).toBe(true);

        await typeTransactionId(element, '   ');
        expect(button(element, 'Xác nhận').disabled).toBe(true);
    });

    it('xác nhận thành công: gọi Apex với mã đã bỏ khoảng trắng, báo thành công và đóng', async () => {
        markManualRefund.mockResolvedValue(undefined);
        const element = render();
        const toasts = collectToasts(element);
        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);

        await typeTransactionId(element, '  PH-MANUAL-001 ');
        button(element, 'Xác nhận').click();
        await flushPromises();

        expect(markManualRefund).toHaveBeenCalledWith({
            requestId: REQUEST_ID,
            payHubTransactionId: 'PH-MANUAL-001'
        });
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('success');
        expect(closeHandler).toHaveBeenCalled();
    });

    it('Apex báo lỗi: hiện câu lỗi, không đóng', async () => {
        markManualRefund.mockRejectedValue({ body: { message: 'Không thể chuyển yêu cầu từ Hoàn tất sang Hoàn tất.' } });
        const element = render();
        const toasts = collectToasts(element);
        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);

        await typeTransactionId(element, 'PH-1');
        button(element, 'Xác nhận').click();
        await flushPromises();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].message).toBe('Không thể chuyển yêu cầu từ Hoàn tất sang Hoàn tất.');
        expect(closeHandler).not.toHaveBeenCalled();
        expect(button(element, 'Xác nhận').disabled).toBe(false);
    });

    it('bấm Hủy thì đóng', async () => {
        const element = render();
        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);
        await flushPromises();

        button(element, 'Hủy').click();
        expect(closeHandler).toHaveBeenCalled();
        expect(markManualRefund).not.toHaveBeenCalled();
    });
});
