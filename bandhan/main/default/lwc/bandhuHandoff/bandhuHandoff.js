import BANDHAN_LOGO from '@salesforce/resourceUrl/BandhanLogoWhite';
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHandoff from '@salesforce/apex/BandhuConsoleController.getHandoff';

function errorMessage(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

export default class BandhuHandoff extends NavigationMixin(LightningElement) {
    logoUrl = BANDHAN_LOGO;
    @api recordId;
    handoff;
    error;
    loading = true;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.handoff = await getHandoff({ sessionId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        this.load();
    }

    get h() {
        return this.handoff || {};
    }

    get hasJourney() {
        return !this.error && this.handoff && this.handoff.hasJourney;
    }

    get noJourney() {
        return !this.error && this.handoff && !this.handoff.hasJourney;
    }

    get typeClass() {
        return 'b-pill ' + ((this.h.customerType || '').startsWith('Existing') ? 'b-pill-green' : 'b-pill-white');
    }

    get answers() {
        return (this.h.answers || []).map((text, idx) => {
            const at = text.indexOf(': ');
            return at > 0 ? { key: 'a' + idx, keyV: 'v' + idx, label: text.substring(0, at), value: text.substring(at + 2) } : { key: 'a' + idx, keyV: 'v' + idx, label: '', value: text };
        });
    }

    get hasAnswers() {
        return this.answers.length > 0;
    }

    get statusClass() {
        const s = this.h.applicationStatus;
        return 'b-pill ' + (s === 'Card Issued' || s === 'Approved' ? 'b-pill-green' : s === 'Declined' ? 'b-pill-red' : 'b-pill-amber');
    }

    navigate(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId, objectApiName, actionName: 'view' } });
    }

    openApplication() {
        this.navigate(this.h.applicationId, 'Card_Application__c');
    }

    openLead() {
        this.navigate(this.h.leadId, 'Lead');
    }

    openContact() {
        this.navigate(this.h.contactId, 'Contact');
    }
}
