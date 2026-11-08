import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import STATUS_FIELD from '@salesforce/schema/Return_Request__c.Status__c';
import getActionState from '@salesforce/apex/SR_ReturnUiController.getActionState';
import receiveGoods from '@salesforce/apex/SR_ReturnUiController.receiveGoods';
import cancelRequest from '@salesforce/apex/SR_ReturnUiController.cancelRequest';
import { reduceErrors } from 'c/srUtils';

// Nút Nhận hàng (Awaiting Goods → Inspecting) và Hủy (New / Pending Approval / Awaiting Goods – OI-07)
// trên trang yêu cầu. Nút nào được hiện do Apex quyết định; trạng thái đổi thì hỏi lại Apex. Owner: Dev C
export default class SrRequestActions extends LightningElement {
    @api recordId;
    state = {};
    status;
    isBusy = false;

    // Nhận trạng thái mới mỗi khi bản ghi đổi (kể cả sau notifyRecordUpdateAvailable)
    @wire(getRecord, { recordId: '$recordId', fields: [STATUS_FIELD] })
    wiredRecord({ data }) {
        if (data && getFieldValue(data, STATUS_FIELD) !== this.status) {
            this.status = getFieldValue(data, STATUS_FIELD);
            this.loadState();
        }
    }

    get hasActions() {
        return this.state.canReceiveGoods || this.state.canCancel;
    }

    async loadState() {
        try {
            this.state = await getActionState({ requestId: this.recordId });
        } catch (e) {
            this.state = {};
            this.toast(reduceErrors(e), 'error');
        }
    }

    async handleReceive() {
        const ok = await LightningConfirm.open({
            message: 'Xác nhận đã nhận hàng khách mang tới? Yêu cầu sẽ chuyển sang Đang kiểm định.',
            label: 'Nhận hàng',
            theme: 'info'
        });
        if (ok) {
            await this.run(() => receiveGoods({ requestId: this.recordId }), 'Đã nhận hàng, chuyển sang kiểm định');
        }
    }

    async handleCancel() {
        const reason = await LightningPrompt.open({
            message: 'Nhập lý do hủy yêu cầu',
            label: 'Hủy yêu cầu',
            theme: 'warning'
        });
        if (reason === null) {
            return; // bấm Hủy trong hộp thoại
        }
        if (!reason.trim()) {
            this.toast('Vui lòng nhập lý do hủy yêu cầu.', 'error');
            return;
        }
        await this.run(() => cancelRequest({ requestId: this.recordId, reason: reason.trim() }), 'Đã hủy yêu cầu');
    }

    // Gọi Apex, báo kết quả rồi làm mới trang; lỗi (vd MSG-20 khi người khác vừa đổi trạng thái) hiện bằng toast
    async run(action, successMessage) {
        this.isBusy = true;
        try {
            await action();
            this.toast(successMessage, 'success');
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.toast(reduceErrors(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
