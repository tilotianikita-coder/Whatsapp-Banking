import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getContext from '@salesforce/apex/LoanSevaHandoff.getContext';

const SOURCE_CLASS = { 'On file': 'k-pill k-pill-white k-src-file', Today: 'k-pill k-pill-green', 'Not yet': 'k-pill k-pill-grey' };
const LANGUAGES = { EN: 'English', HI: 'Hindi', MR: 'Marathi' };
const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const WHEN = new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export default class LoanSevaHandoff extends NavigationMixin(LightningElement) {
    @api recordId;
    data;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: ['MessagingSession.Status'] })
    sessionChanged({ data }) {
        if (data) {
            this.load();
        }
    }

    async load() {
        try {
            this.data = await getContext({ sessionId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not load the LoanSeva journey.';
        }
    }

    handleRefresh() {
        this.load();
    }

    get show() {
        return this.data && this.data.hasJourney;
    }

    get empty() {
        return this.data && !this.data.hasJourney && !this.error;
    }

    get subtitle() {
        const who = this.data.existingCustomer ? 'Existing Kotak customer' : this.data.contactId ? 'Kotak customer' : 'New to bank';
        return who + ' · ' + this.data.journeyType + (this.data.journeyType === 'New Loan' ? ' application' : '');
    }

    get customerPill() {
        return this.data.existingCustomer ? 'k-pill k-pill-white' : 'k-pill k-pill-amber';
    }

    get customerLabel() {
        return this.data.existingCustomer ? 'Existing customer' : 'Prospect';
    }

    get reasonLine() {
        if (!this.data.reason) {
            return null;
        }
        return this.data.reason + (this.data.handedOffAt ? ' · ' + WHEN.format(new Date(this.data.handedOffAt)) : '');
    }

    get hasLoan() {
        return !!this.data.loanAccount;
    }

    get loanFacts() {
        const d = this.data;
        return [
            { label: 'Loan account', value: d.loanAccount },
            { label: 'EMI', value: this.inr(d.loanEmi) + ' at ' + d.loanRate + '%' },
            { label: 'Outstanding', value: this.inr(d.loanOutstanding) },
            { label: 'Repayment', value: d.loanTrack || '—' },
            { label: 'Pre-approved Top-Up', value: d.preApproved ? 'up to ' + this.inr(d.preApproved) : '—' },
            { label: 'Earlier applications', value: String(d.earlierApplications) }
        ].map((f) => ({ ...f, valueKey: f.label + '-v' }));
    }

    get journeyFacts() {
        const d = this.data;
        const facts = [
            { label: 'Customer', value: d.customerName || '—' },
            { label: 'WhatsApp', value: d.mobile || '—' },
            { label: 'Language', value: LANGUAGES[d.language] || d.language || '—' },
            { label: 'Waiting on', value: d.currentStep || '—' },
            { label: 'Stage', value: (d.stage || '—') + ' · ' + d.status }
        ];
        if (d.referenceNumber) {
            facts.push({ label: 'Reference', value: d.referenceNumber });
        }
        return facts.map((f) => ({ ...f, valueKey: f.label + '-v' }));
    }

    get hasAnswers() {
        return this.data.answers && this.data.answers.length > 0;
    }

    get answerRows() {
        return this.data.answers.map((a) => ({ ...a, cls: SOURCE_CLASS[a.source], value: a.value || '—' }));
    }

    get answersTitle() {
        return 'Application answers · ' + this.data.onFileCount + ' on file, ' + this.data.todayCount + ' given today';
    }

    get hasOffer() {
        return this.data.offerAmount != null;
    }

    get offerLine() {
        const d = this.data;
        return this.inr(d.offerAmount) + ' at ' + d.offerRate + '% for ' + d.offerTenure + ' months · EMI ' + this.inr(d.offerEmi)
            + (d.offerAccepted ? ' · accepted ✓' : ' · not accepted yet');
    }

    get creditLine() {
        const d = this.data;
        if (!d.qualification && d.cibil == null) {
            return null;
        }
        const parts = [];
        if (d.qualification) {
            parts.push(d.qualification);
        }
        if (d.cibil != null) {
            parts.push('CIBIL ' + d.cibil);
        }
        if (d.creditScore != null) {
            parts.push('credit score ' + d.creditScore + '/100');
        }
        return parts.join(' · ');
    }

    inr(value) {
        return value == null ? '—' : INR.format(value);
    }

    openRecord(event) {
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    get customerRecordId() {
        return this.data.contactId || this.data.leadId;
    }
}
