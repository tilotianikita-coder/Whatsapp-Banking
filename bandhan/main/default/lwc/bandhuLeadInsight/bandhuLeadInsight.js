import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getLeadInsight from '@salesforce/apex/BandhuConsoleController.getLeadInsight';
import nudge from '@salesforce/apex/BandhuConsoleController.nudge';

function errorMessage(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function tile(label, value) {
    const v = value == null ? null : Math.round(Number(value));
    const pct = v == null ? 0 : Math.max(0, Math.min(100, v));
    return { label, value: v == null ? '—' : v, barStyle: `width: ${pct}%;` };
}

export default class BandhuLeadInsight extends NavigationMixin(LightningElement) {
    @api recordId;
    insight;
    error;
    loading = true;
    sending = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.insight = await getLeadInsight({ leadId: this.recordId });
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

    get i() {
        return this.insight || {};
    }

    get ready() {
        return !!this.insight && !this.error;
    }

    get hasJourney() {
        return this.ready && this.insight.hasJourney;
    }

    get noJourney() {
        return this.ready && !this.insight.hasJourney;
    }

    get ratingClass() {
        const r = this.i.rating;
        return 'b-pill ' + (r === 'Hot' ? 'b-pill-solid' : r === 'Warm' ? 'b-pill-orange' : r === 'Cold' ? 'b-pill-grey' : 'b-pill-white');
    }

    get rating() {
        return this.i.rating || 'Not rated';
    }

    get tiles() {
        return [
            { key: 'intent', cls: 'b-tile', ...tile('Intent', this.i.intent) },
            { key: 'credit', cls: 'b-tile', ...tile('Credit', this.i.credit) },
            { key: 'combined', cls: 'b-tile b-tile-main', ...tile('Combined', this.i.combined) }
        ];
    }

    get details() {
        return this.i.detailsDone == null ? '—' : this.i.detailsDone + '/10';
    }

    get facts() {
        const i = this.i;
        return [
            ['CIBIL', i.cibil != null ? String(i.cibil) : null],
            ['Recommended card', i.recommended],
            ['Eligible cards', i.eligible],
            ['Needs', i.needs],
            ['Income', i.income],
            ['Indicative limit', i.creditLimit],
            ['Current step', i.step],
            ['Drop point', i.dropPoint],
            ['Channel', i.channel],
            ['Mobile', i.mobile],
            ['Details shared', this.details]
        ]
            .filter(([, v]) => v)
            .map(([label, value]) => ({ label, value, keyL: label + '-l', keyV: label + '-v' }));
    }

    get scoreLines() {
        return (this.i.scoreLines || []).filter((l) => l && l.trim()).map((text, idx) => ({ key: 's' + idx, text }));
    }

    get hasScoreLines() {
        return this.scoreLines.length > 0;
    }

    get canNudge() {
        return this.i.canNudge;
    }

    openApplication() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.i.applicationId, objectApiName: 'Card_Application__c', actionName: 'view' }
        });
    }

    async handleNudge() {
        this.sending = true;
        try {
            const message = await nudge({ leadId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Nudge sent on WhatsApp', message: message || 'Message sent.', variant: 'success' }));
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not send the nudge', message: errorMessage(e), variant: 'error' }));
        } finally {
            this.sending = false;
        }
    }
}
