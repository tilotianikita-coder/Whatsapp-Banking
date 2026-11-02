import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getInsight from '@salesforce/apex/LoanSevaLeadInsight.getInsight';
import nudge from '@salesforce/apex/LoanSevaLeadInsight.nudge';

const RATING_CLASS = { Hot: 'k-pill k-pill-red', Warm: 'k-pill k-pill-amber', Cold: 'k-pill k-pill-grey' };
const RESULT_CLASS = { Pass: 'k-result k-pass', Refer: 'k-result k-refer', Fail: 'k-result k-fail' };
const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const WHEN = new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export default class LoanSevaLeadInsight extends LightningElement {
    @api recordId;
    data;
    error;
    busy = false;

    @wire(getRecord, { recordId: '$recordId', fields: ['Lead.LastModifiedDate'] })
    recordChanged({ data }) {
        if (data) {
            this.load();
        }
    }

    async load() {
        try {
            this.data = await getInsight({ leadId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = this.message(e);
        }
    }

    get loaded() {
        return !!this.data;
    }

    get hasGates() {
        return this.data && this.data.gates && this.data.gates.length > 0;
    }

    get hasCredit() {
        return this.data && this.data.creditLines && this.data.creditLines.length > 0;
    }

    get hasIntent() {
        return this.data && this.data.scoreLines && this.data.scoreLines.length > 0;
    }

    get ratingClass() {
        return RATING_CLASS[this.data.rating] || 'k-pill k-pill-grey';
    }

    get ratingLabel() {
        return this.data.rating ? this.data.rating + ' lead' : 'Not scored';
    }

    get serviceClass() {
        return this.data.serviceable ? 'k-pill k-pill-green' : 'k-pill k-pill-bad';
    }

    get serviceLabel() {
        return this.data.serviceable ? 'Serviceable' : 'Not serviceable';
    }

    get progressStyle() {
        const d = this.data;
        return 'width:' + (d.detailsTotal ? Math.round((100 * d.detailsDone) / d.detailsTotal) : 0) + '%';
    }

    get tiles() {
        const d = this.data;
        const score = (v) => (v === null || v === undefined ? '—' : v + '/100');
        return [
            { label: 'Combined score', value: score(d.score), sub: d.rating || '', cls: 'k-tile k-tile-main' },
            { label: 'Intent', value: score(d.intentScore), sub: 'from the chat', cls: 'k-tile' },
            { label: 'Credit', value: score(d.creditScore), sub: d.creditConfidence ? d.creditConfidence + ' confidence' : 'no data yet', cls: 'k-tile' },
            { label: 'CIBIL', value: d.cibil || '—', sub: 'soft pull', cls: 'k-tile' },
            { label: 'Eligibility', value: d.eligibility ? INR.format(d.eligibility) : '—', sub: 'indicative', cls: 'k-tile' }
        ];
    }

    /** The Apex path class says done, current, lost or not reached; drawn as Kotak chevrons with the name always shown. */
    get gateSteps() {
        return this.data.gates.map((g) => {
            const c = g.pathClass || '';
            const state = c.includes('slds-is-lost') ? 'lost' : c.includes('slds-is-complete') ? 'done' : c.includes('slds-is-current') ? 'current' : 'todo';
            return {
                key: g.gate,
                cls: 'k-step k-' + state,
                title: (state === 'done' ? '✓ ' : state === 'lost' ? '✕ ' : '') + g.gate,
                tip: g.gate + ': ' + (g.summary || g.result)
            };
        });
    }

    get gateRows() {
        return this.data.gates.map((g) => ({ ...g, cls: RESULT_CLASS[g.result] || 'k-result k-pending' }));
    }

    get showPreview() {
        return this.data.preview && this.data.canNudge;
    }

    get dropLine() {
        const d = this.data;
        if (!d.currentStep || d.journeyStatus !== 'Dropped') {
            return null;
        }
        return 'Dropped off at ' + d.currentStep + (d.detailsTotal ? ' (' + d.detailsDone + ' of ' + d.detailsTotal + ' details shared)' : '')
            + (d.droppedAt ? ' on ' + this.when(d.droppedAt) : '');
    }

    get journeyFacts() {
        const d = this.data;
        return this.keyed([
            { label: 'Journey', value: d.journeyName ? d.journeyName + ' (' + d.journeyStatus + ')' : '—' },
            { label: 'Stopped at', value: d.currentStep || '—' },
            { label: 'Details shared', value: d.detailsTotal ? d.detailsDone + ' of ' + d.detailsTotal : '—' },
            { label: 'Dropped', value: this.when(d.droppedAt) },
            { label: 'Last nudged', value: this.when(d.lastNudged) },
            { label: 'Picked up again', value: this.when(d.resumedAt) }
        ]);
    }

    get leadFacts() {
        const d = this.data;
        return this.keyed([
            { label: 'Lead status', value: d.leadStatus },
            { label: 'Assigned RM', value: d.ownerName },
            { label: 'Region', value: d.region || '—' },
            { label: 'Credit check consent', value: d.consent || 'Not asked yet' },
            { label: 'Eligibility', value: d.eligibility ? INR.format(d.eligibility) + ' (subject to verification)' : '—' }
        ]);
    }

    keyed(facts) {
        return facts.map((f) => ({ ...f, valueKey: f.label + '-value' }));
    }

    get journeyUrl() {
        return this.data.journeyId ? '/lightning/r/Loan_Journey__c/' + this.data.journeyId + '/view' : null;
    }

    get nudgeDisabled() {
        return this.busy || !this.data.canNudge;
    }

    async handleNudge() {
        this.busy = true;
        try {
            await nudge({ leadId: this.recordId });
            this.toast('Nudge sent on WhatsApp', 'The customer can reply Continue to pick up from ' + this.data.currentStep + '.', 'success');
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            this.toast('Nudge not sent', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleRefresh() {
        this.load();
    }

    when(value) {
        return value ? WHEN.format(new Date(value)) : '—';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    message(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong';
    }
}
