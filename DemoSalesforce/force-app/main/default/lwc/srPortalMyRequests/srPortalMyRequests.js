import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getMyRequests from '@salesforce/apex/SR_PortalController.getMyRequests';
import getMyRequestDetail from '@salesforce/apex/SR_PortalController.getMyRequestDetail';
import { vnd, reduceErrors } from 'c/srUtils';

const COLUMNS = [
    { label: 'Mã yêu cầu', fieldName: 'requestNumber' },
    { label: 'Ngày tạo', fieldName: 'createdDate' },
    { label: 'Trạng thái', fieldName: 'statusLabel' },
    { label: 'Số tiền (đ)', fieldName: 'amountText' },
    { type: 'button', initialWidth: 110, typeAttributes: { label: 'Xem', name: 'view', variant: 'base' } }
];

// D.4 – Khách đăng nhập xem yêu cầu của mình (FR-05). Owner: Dev C
export default class SrPortalMyRequests extends LightningElement {
    // Admin chỉnh trong Experience Builder
    @api title = 'Yêu cầu đổi trả của tôi';
    @api pageSize = 10;

    isGuest = isGuest;
    columns = COLUMNS;
    rows = [];
    pageNumber = 1;
    detail;
    errorMessage;

    connectedCallback() {
        if (!this.isGuest) {
            this.load();
        }
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.rows.length < Number(this.pageSize);
    }

    async load() {
        try {
            const data = await getMyRequests({ pageSize: Number(this.pageSize), pageNumber: this.pageNumber });
            this.rows = data.map((r) => ({ ...r, amountText: vnd(r.amount) }));
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = reduceErrors(e);
        }
    }

    prevPage() {
        this.pageNumber -= 1;
        this.load();
    }

    nextPage() {
        this.pageNumber += 1;
        this.load();
    }

    async handleRowAction(event) {
        try {
            const res = await getMyRequestDetail({ requestId: event.detail.row.id });
            this.detail = res.found ? res : undefined;
            this.errorMessage = res.found ? undefined : res.message;
        } catch (e) {
            this.errorMessage = reduceErrors(e);
        }
    }
}
