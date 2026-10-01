import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import getScorecard from '@salesforce/apex/LoanSevaDecisionService.getScorecard';
import approve from '@salesforce/apex/LoanSevaDecisionService.approve';
import reject from '@salesforce/apex/LoanSevaDecisionService.reject';
import rerunUnderwriting from '@salesforce/apex/LoanSevaDecisionService.rerunUnderwriting';

const RESULT_STYLE = {
    Pass: { icon: 'utility:success', variant: 'success', badge: 'slds-badge slds-theme_success' },
    Refer: { icon: 'utility:warning', variant: 'warning', badge: 'slds-badge slds-theme_warning' },
    Pending: { icon: 'utility:clock', variant: 'warning', badge: 'slds-badge slds-theme_warning' },
    Fail: { icon: 'utility:error', variant: 'error', badge: 'slds-badge slds-theme_error' }
};
const RECOMMENDATION_BADGE = {
    Approve: 'slds-badge slds-theme_success',
    Refer: 'slds-badge slds-theme_warning',
    Decline: 'slds-badge slds-theme_error'
};
const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });

export default class LoanSevaScorecard extends LightningElement {
    @api recordId;
    data;
    error;
    notes = '';
    busy = false;
    expanded = {};

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.data = await getScorecard({ applicationId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = this.message(e);
        }
    }

    get app() {
        return this.data ? this.data.application : {};
    }

    get loaded() {
        return !!this.data;
    }

    get hasChecks() {
        return this.checks.length > 0;
    }

    get checks() {
        return (this.data && this.data.checks ? this.data.checks : []).map((c) => {
            const style = RESULT_STYLE[c.Result__c] || RESULT_STYLE.Pending;
            return {
                ...c,
                icon: style.icon,
                variant: style.variant,
                badge: style.badge,
                open: !!this.expanded[c.Id],
                toggleIcon: this.expanded[c.Id] ? 'utility:chevrondown' : 'utility:chevronright',
                detailLines: (c.Details__c || '').split('\n').map((line, i) => ({ key: c.Id + i, line }))
            };
        });
    }

    get documents() {
        return (this.data && this.data.documents ? this.data.documents : []).map((d) => ({
            ...d,
            url: d.Content_Document_Id__c ? '/lightning/r/ContentDocument/' + d.Content_Document_Id__c + '/view' : null
        }));
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get recommendationBadge() {
        return RECOMMENDATION_BADGE[this.app.Recommendation__c] || 'slds-badge';
    }

    get underwritingRunning() {
        return this.app.Underwriting_Status__c === 'In Progress' || this.app.Underwriting_Status__c === 'Not Started';
    }

    get underwritingError() {
        return this.app.Underwriting_Status__c === 'Error';
    }

    get canDecide() {
        return this.data && this.data.canDecide;
    }

    get approveDisabled() {
        return this.busy || this.app.Underwriting_Status__c !== 'Completed';
    }

    get decided() {
        return !!this.app.Decision__c;
    }

    get approved() {
        return this.app.Decision__c === 'Approved';
    }

    get decidedBy() {
        return this.app.Decision_By__r ? this.app.Decision_By__r.Name : '';
    }

    get terms() {
        const a = this.app;
        return [
            { label: 'Amount', value: a.Offer_Amount__c != null ? INR.format(a.Offer_Amount__c) : '—' },
            { label: 'Rate', value: a.Rate__c != null ? a.Rate__c + '% p.a.' : '—' },
            { label: 'Tenure', value: a.Tenure_Months__c != null ? a.Tenure_Months__c + ' months' : '—' },
            { label: 'EMI', value: a.EMI__c != null ? INR.format(a.EMI__c) : '—' },
            { label: 'CIBIL', value: a.CIBIL_Score__c != null ? String(a.CIBIL_Score__c) : '—' },
            { label: 'PAN', value: this.data.maskedPan || '—' },
            { label: 'Income', value: a.Monthly_Income__c != null ? INR.format(a.Monthly_Income__c) + '/month' : '—' },
            { label: 'Employment', value: [a.Employment_Type__c, a.Company_Name__c].filter(Boolean).join(' · ') || '—' }
        ];
    }

    toggle(event) {
        const id = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }

    handleNotes(event) {
        this.notes = event.target.value;
    }

    async handleApprove() {
        const ok = await LightningConfirm.open({
            label: 'Approve and create loan account?',
            message: 'A loan account (LAN) is created as Sanctioned and the customer is told on WhatsApp.',
            theme: 'success'
        });
        if (ok) {
            await this.act(approve, 'Approved. Loan account created and customer notified.');
        }
    }

    async handleReject() {
        const ok = await LightningConfirm.open({
            label: 'Reject this application?',
            message: 'The customer receives a polite decline on WhatsApp. Your notes stay internal.',
            theme: 'error'
        });
        if (ok) {
            await this.act(reject, 'Rejected. Customer notified.');
        }
    }

    async handleRerun() {
        this.busy = true;
        try {
            this.data = await rerunUnderwriting({ applicationId: this.recordId });
            this.toast('Underwriting re-run', 'Checks refreshed with the latest documents.', 'success');
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.toast('Could not re-run underwriting', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleRefresh() {
        this.load();
    }

    async act(method, success) {
        this.busy = true;
        try {
            this.data = await method({ applicationId: this.recordId, notes: this.notes });
            this.toast(success, '', 'success');
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.toast('Decision not saved', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    message(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unexpected error';
    }
}
