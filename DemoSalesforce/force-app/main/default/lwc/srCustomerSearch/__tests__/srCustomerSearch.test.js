import { createElement } from '@lwc/engine-dom';
import SrCustomerSearch from 'c/srCustomerSearch';
import searchAll from '@salesforce/apex/SR_CustomerSearchController.searchAll';

jest.mock('@salesforce/apex/SR_CustomerSearchController.searchAll', () => ({ default: jest.fn() }), {
    virtual: true
});
// Stub mặc định của lightning/navigation không ghi lại lần điều hướng nên tự giả lập
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

const GROUPS = [
    {
        objectName: 'Account',
        title: 'Khách hàng',
        columns: [
            { fieldName: 'Name', label: 'Tên', type: 'text' },
            { fieldName: 'Phone', label: 'Điện thoại', type: 'phone' }
        ],
        rows: [{ Id: '001000000000001AAA', Name: 'Chị Lan', Phone: '0901234567' }]
    },
    { objectName: 'Order', title: 'Đơn hàng', columns: [], rows: [] }
];

async function flushPromises(rounds = 5) {
    await Promise.resolve();
    if (rounds > 1) {
        await flushPromises(rounds - 1);
    }
}

function render() {
    const element = createElement('c-sr-customer-search', { is: SrCustomerSearch });
    document.body.appendChild(element);
    return element;
}

// Gõ rồi chờ hết thời gian debounce
async function type(element, value) {
    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await flushPromises();
}

describe('c-sr-customer-search', () => {
    beforeEach(() => {
        jest.useFakeTimers();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('dưới 3 ký tự thì không gọi Apex', async () => {
        const element = render();
        await type(element, '09');
        expect(searchAll).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelectorAll('lightning-datatable')).toHaveLength(0);
    });

    it('từ 3 ký tự: hiện từng nhóm, nhóm rỗng báo không có kết quả, thêm cột Mở', async () => {
        searchAll.mockResolvedValue(GROUPS);
        const element = render();
        await type(element, ' 0901 ');

        expect(searchAll).toHaveBeenCalledWith({ term: '0901' });
        const headings = [...element.shadowRoot.querySelectorAll('h3')].map((h) => h.textContent);
        expect(headings).toEqual(['Khách hàng (1)', 'Đơn hàng (0)']);

        const tables = element.shadowRoot.querySelectorAll('lightning-datatable');
        expect(tables).toHaveLength(1);
        expect(tables[0].columns.map((c) => c.fieldName || c.type)).toEqual(['Name', 'Phone', 'button']);
        expect(element.shadowRoot.querySelector('p.slds-text-color_weak').textContent).toBe('Không có kết quả');
    });

    it('bấm Mở thì mở trang chi tiết bản ghi', async () => {
        searchAll.mockResolvedValue(GROUPS);
        const element = render();
        await type(element, 'Lan');

        const table = element.shadowRoot.querySelector('lightning-datatable');
        table.dispatchEvent(
            new CustomEvent('rowaction', { detail: { action: { name: 'open' }, row: GROUPS[0].rows[0] } })
        );

        expect(mockNavigate).toHaveBeenCalledTimes(1);
        const pageReference = mockNavigate.mock.calls[0][0];
        expect(pageReference.type).toBe('standard__recordPage');
        expect(pageReference.attributes.recordId).toBe('001000000000001AAA');
    });

    it('Apex lỗi thì hiện câu lỗi', async () => {
        searchAll.mockRejectedValue({ body: { message: 'Đã có lỗi xảy ra (mã lỗi E1)' } });
        const element = render();
        await type(element, 'RR-2610');

        expect(element.shadowRoot.querySelector('p.slds-text-color_error').textContent).toBe(
            'Đã có lỗi xảy ra (mã lỗi E1)'
        );
    });
});
