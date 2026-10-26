import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchAll from '@salesforce/apex/SR_CustomerSearchController.searchAll';
import { reduceErrors } from 'c/srUtils';

const MIN_TERM_LENGTH = 3;
const DEBOUNCE_MS = 300;

const OPEN_COLUMN = {
    type: 'button',
    initialWidth: 80,
    typeAttributes: { label: 'Mở', name: 'open', variant: 'base' }
};

// D.5 – Ô tìm kiếm cho CSKH (FR-17, FR-18). Cột do Apex trả theo Field Set. Owner: Dev B
export default class SrCustomerSearch extends NavigationMixin(LightningElement) {
    term = '';
    groups = [];
    isLoading = false;
    errorMessage;
    timer;
    searchSeq = 0;

    disconnectedCallback() {
        clearTimeout(this.timer);
    }

    handleChange(event) {
        this.term = event.target.value || '';
        clearTimeout(this.timer);
        // Chờ người dùng ngừng gõ 300ms rồi mới tìm, đỡ gọi server liên tục
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.runSearch(), DEBOUNCE_MS);
    }

    async runSearch() {
        const text = this.term.trim();
        const seq = ++this.searchSeq;
        this.errorMessage = undefined;
        if (text.length < MIN_TERM_LENGTH) {
            this.groups = [];
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        try {
            const result = await searchAll({ term: text });
            // Kết quả của lần gõ cũ về sau lần gõ mới thì bỏ
            if (seq !== this.searchSeq) {
                return;
            }
            this.groups = (result || []).map((g) => ({
                objectName: g.objectName,
                title: g.title,
                count: g.rows.length,
                hasRows: g.rows.length > 0,
                rows: g.rows,
                columns: [
                    ...g.columns.map((c) => ({ label: c.label, fieldName: c.fieldName, type: c.type || 'text' })),
                    OPEN_COLUMN
                ]
            }));
        } catch (e) {
            if (seq === this.searchSeq) {
                this.groups = [];
                this.errorMessage = reduceErrors(e);
            }
        } finally {
            if (seq === this.searchSeq) {
                this.isLoading = false;
            }
        }
    }

    handleRowAction(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail.row.Id, actionName: 'view' }
        });
    }
}
