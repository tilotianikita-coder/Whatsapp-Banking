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
            ['Lead status', i.leadStatus],
            ['Region', i.region],
            ['Credit confidence', i.confidence],
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

    get stageText() {
        return this.i.stageGate || 'Not qualified yet';
    }

    get stageClass() {
        const s = this.i.stageGate || '';
        return 'b-stage ' + (s.startsWith('Knocked') ? 'b-stage-fail' : s === 'Qualified' ? 'b-stage-pass' : 'b-stage-wait');
    }

    get pathSteps() {
        const at = this.i.pathIndex == null ? -1 : this.i.pathIndex;
        return (this.i.path || []).map((label, idx) => ({
            key: 'p' + idx,
            label,
            mark: idx < at || (idx === at && idx === 6) ? '✓' : String(idx + 1),
            cls: 'b-path-step ' + (idx < at || (idx === at && idx === 6) ? 'done' : idx === at ? 'current' : '')
        }));
    }

    get gates() {
        const RESULT = { Pass: 'b-pill b-pill-green', Refer: 'b-pill b-pill-orange', Fail: 'b-pill b-pill-red', Pending: 'b-pill b-pill-white', Skipped: 'b-pill b-pill-grey' };
        return (this.i.gates || []).map((g, idx) => ({
            ...g,
            key: 'g' + idx,
            cls: RESULT[g.result] || 'b-pill b-pill-white',
            resultText: g.knockout ? 'Knock-out' : g.result,
            showPoints: g.maxPoints > 0 && g.result !== 'Pending' && g.result !== 'Skipped',
            pointsText: `${g.points}/${g.maxPoints}`
        }));
    }

    get hasGates() {
        return this.gates.length > 0;
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
