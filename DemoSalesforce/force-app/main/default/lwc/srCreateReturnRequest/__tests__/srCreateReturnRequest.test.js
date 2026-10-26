import { createElement } from '@lwc/engine-dom';
import SrCreateReturnRequest from 'c/srCreateReturnRequest';
import getReturnableLines from '@salesforce/apex/SR_ReturnUiController.getReturnableLines';
import previewLevel from '@salesforce/apex/SR_ReturnUiController.previewLevel';

jest.mock(
    '@salesforce/apex/SR_ReturnUiController.getReturnableLines',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/SR_ReturnUiController.previewLevel', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SR_ReturnUiController.createFromCounter', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock(
    '@salesforce/label/c.SR_MSG_04',
    () => ({ default: 'Số lượng trả của {0} vượt quá số lượng còn được trả ({1}).' }),
    { virtual: true }
);
jest.mock('@salesforce/label/c.SR_MSG_06', () => ({ default: 'Vui lòng chọn ít nhất 1 sản phẩm để trả.' }), {
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

const LAPTOP = '802000000000001AAA';
const CARD = '802000000000002AAA';
const INFO = {
    orderNumber: '00000101',
    customerName: 'Anh Minh',
    customerPhone: '0912345678',
    purchaseDate: '2026-10-22',
    deliveryDate: '2026-10-23',
    storeName: 'Phương Nam Quận 1',
    lines: [
        {
            orderItemId: LAPTOP,
            productName: 'Laptop 15 inch Pro',
            sku: 'LT-15-PRO',
            family: 'Laptop',
            purchasedQty: 1,
            alreadyReturnedQty: 0,
            deadline: '2026-10-30',
            returnable: true
        },
        {
            orderItemId: CARD,
            productName: 'Thẻ cào Viettel 100K',
            sku: 'TC-VT-100K',
            family: 'Thẻ cào',
            purchasedQty: 2,
            alreadyReturnedQty: 0,
            deadline: null,
            returnable: false,
            blockReason: 'Ngành hàng Thẻ cào không áp dụng đổi trả.'
        }
    ]
};

// Chờ Apex giả lập trả kết quả và component render lại (vài vòng microtask)
async function flushPromises(rounds = 5) {
    await Promise.resolve();
    if (rounds > 1) {
        await flushPromises(rounds - 1);
    }
}

async function render() {
    const element = createElement('c-sr-create-return-request', { is: SrCreateReturnRequest });
    element.recordId = '801000000000001AAA';
    document.body.appendChild(element);
    getReturnableLines.emit(INFO);
    await flushPromises();
    return element;
}

function field(element, tag, orderItemId) {
    return element.shadowRoot.querySelector(`${tag}[data-id="${orderItemId}"]`);
}

function submitButton(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Tạo yêu cầu');
}

function change(target, value) {
    target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-sr-create-return-request', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('dòng không đổi trả được bị khóa kèm lý do, nút Tạo yêu cầu tắt khi chưa có SL trả (MSG-06)', async () => {
        const element = await render();

        expect(field(element, 'lightning-input', LAPTOP).disabled).toBe(false);
        expect(field(element, 'lightning-input', CARD).disabled).toBe(true);
        expect(field(element, 'lightning-combobox', CARD).disabled).toBe(true);
        expect(element.shadowRoot.textContent).toContain('Ngành hàng Thẻ cào không áp dụng đổi trả.');
        expect(element.shadowRoot.textContent).toContain('Vui lòng chọn ít nhất 1 sản phẩm để trả.');
        expect(submitButton(element).disabled).toBe(true);
    });

    it('đổi SL / lý do / tình trạng → previewLevel sau 300ms, hiện tiền, cấp duyệt và lỗi MSG-04 tại dòng', async () => {
        jest.useFakeTimers();
        previewLevel.mockResolvedValue({
            totalRefund: 25000000,
            approvalLevel: 'QLV',
            customerRisky: false,
            lines: [{ orderItemId: LAPTOP, refundAmount: 25000000 }]
        });
        const element = await render();

        change(field(element, 'lightning-input', LAPTOP), '1');
        const [reason, condition] = element.shadowRoot.querySelectorAll(`lightning-combobox[data-id="${LAPTOP}"]`);
        change(reason, 'DEFECT');
        change(condition, 'SEALED');
        await flushPromises();
        expect(previewLevel).not.toHaveBeenCalled(); // còn trong 300ms debounce

        jest.advanceTimersByTime(300);
        await flushPromises();
        expect(previewLevel).toHaveBeenCalledTimes(1);
        expect(JSON.parse(previewLevel.mock.calls[0][0].draftJson)).toEqual({
            orderId: '801000000000001AAA',
            lines: [{ orderItemId: LAPTOP, quantity: 1, reason: 'DEFECT', condition: 'SEALED' }]
        });
        expect(element.shadowRoot.textContent).toContain('25.000.000đ');
        expect(element.shadowRoot.textContent).toContain('Quản lý vùng duyệt');
        expect(submitButton(element).disabled).toBe(false);

        previewLevel.mockResolvedValue({
            totalRefund: 0,
            approvalLevel: 'QLV',
            lines: [{ orderItemId: LAPTOP, errorCode: 'QUANTITY_EXCEEDED', errorParams: ['Laptop 15 inch Pro', 1] }]
        });
        change(field(element, 'lightning-input', LAPTOP), '2');
        jest.advanceTimersByTime(300);
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain(
            'Số lượng trả của Laptop 15 inch Pro vượt quá số lượng còn được trả (1).'
        );
    });
});
