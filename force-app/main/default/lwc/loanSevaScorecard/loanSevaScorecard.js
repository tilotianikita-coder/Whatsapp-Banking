import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LoanSevaDecisionModal from 'c/loanSevaDecisionModal';
import getScorecard from '@salesforce/apex/LoanSevaDecisionService.getScorecard';
import approve from '@salesforce/apex/LoanSevaDecisionService.approve';
import reject from '@salesforce/apex/LoanSevaDecisionService.reject';
import rerunUnderwriting from '@salesforce/apex/LoanSevaDecisionService.rerunUnderwriting';

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
    busy = false;

    @wire(getRecord, { recordId: '$recordId', fields: ['Loan_Application__c.LastModifiedDate'] })
    recordChanged({ data }) {
        if (data) {
            this.load();
        }
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

    get memo() {
        return this.data ? this.data.memo : null;
    }

    get headline() {
        return this.memo ? this.memo.headline : '';
    }

    get checkTally() {
        const checks = (this.data && this.data.checks) || [];
        const n = (results) => checks.filter((c) => results.includes(c.Result__c)).length;
        return checks.length ? n(['Pass']) + ' passed · ' + n(['Refer', 'Pending']) + ' to review · ' + n(['Fail']) + ' failed' : '';
    }

    async handleApprove() {
        await this.decide('Approved', approve, 'Approved. Loan account created and customer notified.');
    }

    async handleReject() {
        await this.decide('Rejected', reject, 'Rejected. Customer notified.');
    }

    /** Shows the credit summary first; notes are required when going against the recommendation. */
    async decide(decision, method, success) {
        const result = await LoanSevaDecisionModal.open({
            size: 'medium',
            label: decision === 'Approved' ? 'Approve application' : 'Reject application',
            decision,
            memo: this.memo,
            terms: this.terms.slice(0, 4)
        });
        if (result) {
            await this.act(method, success, result.notes);
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

    async act(method, success, notes) {
        this.busy = true;
        try {
            this.data = await method({ applicationId: this.recordId, notes });
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
