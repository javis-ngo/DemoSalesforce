import { createElement } from '@lwc/engine-dom';
import SrInspection from 'c/srInspection';
import getInspectionData from '@salesforce/apex/SR_ReturnUiController.getInspectionData';
import calcLineRefund from '@salesforce/apex/SR_ReturnUiController.calcLineRefund';

jest.mock('@salesforce/apex/SR_ReturnUiController.getInspectionData', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/SR_ReturnUiController.calcLineRefund', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/SR_ReturnUiController.completeInspection', () => ({ default: jest.fn() }), {
    virtual: true
});
// Stub mặc định của lightning/navigation không ghi lại lần điều hướng nên tự giả lập để kiểm tra nút về Portal
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](pageReference, replace) {
                mockNavigate(pageReference, replace);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});
jest.mock('@salesforce/label/c.SR_MSG_22',() => ({ default: 'Vui lòng ghi kết quả kiểm định cho tất cả sản phẩm.' }), {
    virtual: true
});

const LINE_ID = 'a01000000000001AAA';
const DATA = {
    status: 'INSPECTING',
    canInspect: true,
    lines: [
        {
            lineId: LINE_ID,
            productName: 'Nồi chiên không dầu 5L',
            sku: 'AF-PH-5L',
            quantity: 1,
            reason: 'NOT_SATISFIED',
            declaredCondition: 'OPENED',
            actualCondition: 'OPENED',
            inspectionResult: null,
            inspectionNote: null,
            estimatedRefund: 1992000,
            actualRefund: 1992000
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

function render() {
    const element = createElement('c-sr-inspection', { is: SrInspection });
    element.recordId = 'a00000000000001AAA';
    document.body.appendChild(element);
    return element;
}

const refundCell = (element) => [...element.shadowRoot.querySelectorAll('tbody td')].pop().textContent;
const actualTotal = (element) => element.shadowRoot.querySelector('b').textContent;

describe('c-sr-inspection', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('đổi tình trạng thực tế thì lấy tiền dòng từ Apex, tổng thực tế chỉ cộng dòng Đạt', async () => {
        getInspectionData.mockResolvedValue(DATA);
        calcLineRefund.mockResolvedValue(1494000);
        const element = render();
        await flushPromises();
        expect(refundCell(element)).toBe('0'); // chưa chọn Đạt / Không đạt

        element.shadowRoot
            .querySelector('lightning-radio-group')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'PASSED' } }));
        await flushPromises();
        expect(refundCell(element)).toBe('1.992.000');
        expect(actualTotal(element)).toBe('1.992.000đ');

        element.shadowRoot
            .querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'USED' } }));
        await flushPromises();
        expect(calcLineRefund).toHaveBeenCalledWith({ lineId: LINE_ID, actualCondition: 'USED' });
        expect(refundCell(element)).toBe('1.494.000');
        expect(actualTotal(element)).toBe('1.494.000đ');
    });

    it('còn dòng chưa có kết quả thì tắt nút Hoàn tất và nhắc MSG-22', async () => {
        getInspectionData.mockResolvedValue(DATA);
        const element = render();
        await flushPromises();
        const completeButton = () =>
            [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Hoàn tất kiểm định');
        const hint = () => element.shadowRoot.querySelector('span.slds-text-color_weak');
        expect(completeButton().disabled).toBe(true);
        expect(hint().textContent).toBe('Vui lòng ghi kết quả kiểm định cho tất cả sản phẩm.');

        element.shadowRoot
            .querySelector('lightning-radio-group')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'FAILED' } }));
        await flushPromises();
        expect(completeButton().disabled).toBe(false);
        expect(hint()).toBeNull();
    });

    it('đã hoàn tất kiểm định thì ẩn hẳn component', async () => {
        getInspectionData.mockResolvedValue({ ...DATA, canInspect: false });
        const element = render();
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    });

    it('khách portal lỡ vào trang thì báo Unauthorized và có nút về Portal', async () => {
        const portalUrl = 'https://example.my.site.com/doitra/';
        getInspectionData.mockResolvedValue({ unauthorized: true, canInspect: false, portalUrl, lines: [] });
        const element = render();
        await flushPromises();
        expect(element.shadowRoot.querySelector('p.slds-text-color_error').textContent).toBe(
            'c.SR_ERR_UNAUTHORIZED'
        );
        expect(element.shadowRoot.querySelector('table')).toBeNull();

        const backButton = element.shadowRoot.querySelector('lightning-button');
        expect(backButton.label).toBe('Về trang Portal');
        backButton.click();
        expect(mockNavigate).toHaveBeenCalledWith({ type: 'standard__webPage', attributes: { url: portalUrl } }, true);
    });

    it('Apex tính tiền lỗi thì giữ lại tình trạng cũ', async () => {
        getInspectionData.mockResolvedValue(DATA);
        calcLineRefund.mockRejectedValue({ body: { message: 'Lỗi tính tiền' } });
        const element = render();
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'USED' } }));
        await flushPromises();
        expect(combobox.value).toBe('OPENED');
    });
});
