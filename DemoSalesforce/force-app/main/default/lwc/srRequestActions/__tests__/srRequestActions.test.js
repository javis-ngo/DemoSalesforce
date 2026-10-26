import { createElement } from '@lwc/engine-dom';
import SrRequestActions from 'c/srRequestActions';
import { getRecord } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import getActionState from '@salesforce/apex/SR_ReturnUiController.getActionState';
import receiveGoods from '@salesforce/apex/SR_ReturnUiController.receiveGoods';
import cancelRequest from '@salesforce/apex/SR_ReturnUiController.cancelRequest';

jest.mock('@salesforce/apex/SR_ReturnUiController.getActionState', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/SR_ReturnUiController.receiveGoods', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/SR_ReturnUiController.cancelRequest', () => ({ default: jest.fn() }), {
    virtual: true
});

const REQUEST_ID = 'a00000000000001AAA';

// Chờ Apex giả lập trả kết quả và component render lại (vài vòng microtask)
async function flushPromises(rounds = 5) {
    await Promise.resolve();
    if (rounds > 1) {
        await flushPromises(rounds - 1);
    }
}

async function render(status) {
    const element = createElement('c-sr-request-actions', { is: SrRequestActions });
    element.recordId = REQUEST_ID;
    document.body.appendChild(element);
    getRecord.emit({ fields: { Status__c: { value: status } } });
    await flushPromises();
    return element;
}

const button = (element, label) =>
    [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);

function collectToasts(element) {
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    return toasts;
}

describe('c-sr-request-actions', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.restoreAllMocks();
    });

    it('không có nút nào được phép thì không hiện gì', async () => {
        getActionState.mockResolvedValue({ canReceiveGoods: false, canCancel: false });
        const element = await render('INSPECTING');
        expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    });

    it('Nhận hàng phải xác nhận rồi mới gọi Apex, sau đó hỏi lại nút theo trạng thái mới', async () => {
        getActionState.mockResolvedValue({ canReceiveGoods: true, canCancel: true });
        receiveGoods.mockResolvedValue();
        const confirm = jest.spyOn(LightningConfirm, 'open').mockResolvedValueOnce(false).mockResolvedValueOnce(true);
        const element = await render('AWAITING_GOODS');
        const toasts = collectToasts(element);

        button(element, 'Nhận hàng').click();
        await flushPromises();
        expect(confirm).toHaveBeenCalledTimes(1);
        expect(receiveGoods).not.toHaveBeenCalled(); // bấm Hủy trong hộp xác nhận

        button(element, 'Nhận hàng').click();
        await flushPromises();
        expect(receiveGoods).toHaveBeenCalledWith({ requestId: REQUEST_ID });
        expect(toasts).toEqual([expect.objectContaining({ variant: 'success' })]);

        getActionState.mockResolvedValue({ canReceiveGoods: false, canCancel: false });
        getRecord.emit({ fields: { Status__c: { value: 'INSPECTING' } } });
        await flushPromises();
        expect(getActionState).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    });

    it('Hủy cần lý do: bấm Hủy hoặc để trống thì không gọi Apex', async () => {
        getActionState.mockResolvedValue({ canReceiveGoods: false, canCancel: true });
        cancelRequest.mockResolvedValue();
        jest.spyOn(LightningPrompt, 'open')
            .mockResolvedValueOnce(null)
            .mockResolvedValueOnce('   ')
            .mockResolvedValueOnce(' Khách đổi ý ');
        const element = await render('PENDING_APPROVAL');
        const toasts = collectToasts(element);
        expect(button(element, 'Nhận hàng')).toBeUndefined();

        button(element, 'Hủy yêu cầu').click();
        await flushPromises();
        button(element, 'Hủy yêu cầu').click();
        await flushPromises();
        expect(cancelRequest).not.toHaveBeenCalled();
        expect(toasts).toEqual([expect.objectContaining({ variant: 'error' })]);

        button(element, 'Hủy yêu cầu').click();
        await flushPromises();
        expect(cancelRequest).toHaveBeenCalledWith({ requestId: REQUEST_ID, reason: 'Khách đổi ý' });
    });
});
