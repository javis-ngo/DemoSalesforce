import { createElement } from '@lwc/engine-dom';
import SrCreateReturnRequest from 'c/srCreateReturnRequest';
import getReturnableOrder from '@salesforce/apex/SR_ReturnUiController.getReturnableOrder';
import previewCreate from '@salesforce/apex/SR_ReturnUiController.previewCreate';

jest.mock(
    '@salesforce/apex/SR_ReturnUiController.getReturnableOrder',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/SR_ReturnUiController.previewCreate', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/label/c.SR_MSG_03', () => ({ default: 'Ngành hàng {0} không áp dụng đổi trả.' }), {
    virtual: true
});
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
            category: 'Laptop',
            purchasedQuantity: 1,
            previouslyReturnedQuantity: 0,
            returnableQuantity: 1,
            returnDeadline: '2026-10-30',
            eligible: true
        },
        {
            orderItemId: CARD,
            productName: 'Thẻ cào Viettel 100K',
            sku: 'TC-VT-100K',
            category: 'Thẻ cào',
            purchasedQuantity: 2,
            previouslyReturnedQuantity: 0,
            returnableQuantity: 0,
            returnDeadline: null,
            eligible: false,
            lockCode: 'NOT_RETURNABLE',
            lockMessage: 'Ngành hàng {0} không áp dụng đổi trả.'
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
    getReturnableOrder.emit(INFO);
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

    it('đổi SL / lý do / tình trạng → previewCreate sau 300ms, hiện tiền, cấp duyệt và lỗi MSG-04 tại dòng', async () => {
        jest.useFakeTimers();
        previewCreate.mockResolvedValue({
            success: true,
            estimatedRefund: 25000000,
            approvalLevel: 'QLV',
            riskFlag: false,
            lines: [{ orderItemId: LAPTOP, sku: 'LT-15-PRO', refundAmount: 25000000 }],
            errors: []
        });
        const element = await render();

        change(field(element, 'lightning-input', LAPTOP), '1');
        const [reason, condition] = element.shadowRoot.querySelectorAll(`lightning-combobox[data-id="${LAPTOP}"]`);
        change(reason, 'DEFECT');
        change(condition, 'SEALED');
        await flushPromises();
        expect(previewCreate).not.toHaveBeenCalled(); // còn trong 300ms debounce

        jest.advanceTimersByTime(300);
        await flushPromises();
        expect(previewCreate).toHaveBeenCalledTimes(1);
        expect(JSON.parse(previewCreate.mock.calls[0][0].draftJson)).toEqual({
            orderId: '801000000000001AAA',
            lines: [{ orderItemId: LAPTOP, quantity: 1, reason: 'DEFECT', condition: 'SEALED' }]
        });
        expect(element.shadowRoot.textContent).toContain('25.000.000đ');
        expect(element.shadowRoot.textContent).toContain('Quản lý vùng duyệt');
        expect(submitButton(element).disabled).toBe(false);

        // Service của Dev A báo lỗi theo SKU, không gửi params: màn hình tự điền tên + SL còn trả được
        previewCreate.mockResolvedValue({
            success: false,
            lines: [],
            errors: [{ sku: 'LT-15-PRO', code: 'QUANTITY_EXCEEDED', message: 'Số lượng trả của {0} vượt quá…' }]
        });
        change(field(element, 'lightning-input', LAPTOP), '2');
        jest.advanceTimersByTime(300);
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain(
            'Số lượng trả của Laptop 15 inch Pro vượt quá số lượng còn được trả (1).'
        );
    });
});
