import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import markManualRefund from '@salesforce/apex/SR_RefundManualController.markManualRefund';
import { reduceErrors } from 'c/srUtils';

// B7 – Quick Action cho Kế toán: Refund Failed → Completed khi đã hoàn tay (FR-14). Owner: Dev B
export default class SrManualRefund extends LightningElement {
    @api recordId;
    transactionId = '';
    isSaving = false;

    get isSubmitDisabled() {
        return this.isSaving || !this.transactionId.trim();
    }

    handleChange(event) {
        this.transactionId = event.target.value || '';
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async submit() {
        this.isSaving = true;
        try {
            await markManualRefund({ requestId: this.recordId, payHubTransactionId: this.transactionId.trim() });
            this.dispatchEvent(new ShowToastEvent({ title: 'Đã chuyển sang Hoàn tất', variant: 'success' }));
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.close();
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Không thực hiện được', message: reduceErrors(e), variant: 'error' })
            );
        } finally {
            this.isSaving = false;
        }
    }
}
