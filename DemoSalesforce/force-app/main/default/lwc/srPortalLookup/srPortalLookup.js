import { LightningElement, api } from 'lwc';
import lookup from '@salesforce/apex/SR_PortalController.lookup';
import { reduceErrors } from 'c/srUtils';

// D.4 – Khách vãng lai tra cứu yêu cầu trên Customer Portal (FR-05, BR-17). Owner: Dev C
export default class SrPortalLookup extends LightningElement {
    // Admin chỉnh trong Experience Builder
    @api title = 'Tra cứu yêu cầu đổi trả';
    @api showProducts = false;

    requestNumber = '';
    phoneLast4 = '';
    result;
    message;
    isLoading = false;

    handleCode(event) {
        this.requestNumber = event.target.value;
    }

    handlePhone(event) {
        this.phoneLast4 = event.target.value;
    }

    async handleLookup() {
        this.isLoading = true;
        this.result = undefined;
        this.message = undefined;
        try {
            const res = await lookup({ requestNumber: this.requestNumber, phoneLast4: this.phoneLast4 });
            if (res.found) {
                this.result = res;
            } else {
                this.message = res.message;   // MSG-40 hoặc MSG-41
            }
        } catch (e) {
            this.message = reduceErrors(e);
        } finally {
            this.isLoading = false;
        }
    }
}
