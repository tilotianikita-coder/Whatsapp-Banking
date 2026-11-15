import BANDHAN_LOGO from '@salesforce/resourceUrl/BandhanLogoWhite';
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getReview from '@salesforce/apex/BandhuConsoleController.getReview';
import decide from '@salesforce/apex/BandhuConsoleController.decide';
import generateBrief from '@salesforce/apex/BandhuConsoleController.generateBrief';
import BandhuDecisionModal from 'c/bandhuDecisionModal';

// Stage gates in order; check = Card_Check__c.Check__c name for the provider gates
const GATES = [
    { key: 'app', label: 'Application' },
    { key: 'pan', label: 'PAN', check: 'PAN Verification' },
    { key: 'aadhaar', label: 'Aadhaar eKYC', check: 'Aadhaar eKYC' },
    { key: 'bureau', label: 'Credit Bureau', check: 'Credit Bureau' },
    { key: 'income', label: 'Income', check: 'Income Verification' },
    { key: 'vkyc', label: 'Video KYC', check: 'Video KYC' },
    { key: 'fraud', label: 'Fraud & Dedupe', check: 'Dedupe & Fraud' },
    { key: 'cdd', label: 'Due Diligence', check: 'Customer Due Diligence' },
    { key: 'score', label: 'Bandhan Score', check: 'Bandhan Score' },
    { key: 'policy', label: 'Card Policy', check: 'Card Policy' },
    { key: 'decision', label: 'Decision' },
    { key: 'issued', label: 'Card issued' }
];
const RESULT_CLASS = { Pass: 'gate gate-pass', Refer: 'gate gate-refer', Fail: 'gate gate-fail', Pending: 'gate gate-pending' };
const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });

function errorMessage(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

export default class BandhuApplicationReview extends LightningElement {
    logoUrl = BANDHAN_LOGO;
    @api recordId;
    review;
    error;
    loading = true;
    busy = false;
    selectedKey;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.review = await getReview({ applicationId: this.recordId });
            this.error = undefined;
            if (!this.selectedKey) {
                const firstIssue = this.gates.find((g) => g.result === 'Fail' || g.result === 'Refer');
                this.selectedKey = firstIssue ? firstIssue.key : 'policy';
            }
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        this.load();
    }

    get app() {
        return (this.review && this.review.application) || {};
    }

    get card() {
        return this.review && this.review.card;
    }

    get hasData() {
        return !!(this.review && this.review.application);
    }

    get statusClass() {
        const s = this.app.Status__c;
        return 'b-pill ' + (s === 'Card Issued' || s === 'Approved' ? 'b-pill-green' : s === 'Declined' ? 'b-pill-solid' : s === 'Under Review' ? 'b-pill-amber' : 'b-pill-white');
    }

    get cardStyle() {
        const c = (this.card && this.card.color) || '#0A3152';
        return `background: linear-gradient(135deg, ${c} 0%, ${c} 35%, #061A2C 135%);`;
    }

    briefBusy = false;
    briefOverride;

    get briefText() {
        return (this.briefOverride && this.briefOverride.AI_Brief__c) || this.app.AI_Brief__c;
    }

    get briefAt() {
        return (this.briefOverride && this.briefOverride.AI_Brief_At__c) || this.app.AI_Brief_At__c;
    }

    get hasBrief() {
        return !!this.briefText;
    }

    get briefLines() {
        const out = [];
        (this.briefText || '').split('\n').map((t) => t.trim().replace(/^\*+|\*+$/g, '')).filter((t) => t).forEach((t) => {
            const m = /^(SUMMARY|STRENGTHS|CONCERNS|SUGGESTED DECISION)\s*:?\s*(.*)$/i.exec(t);
            if (m) {
                out.push({ text: m[1].toUpperCase(), cls: 'brief-h' });
                if (m[2]) {
                    out.push({ text: m[2], cls: 'brief-p' });
                }
            } else {
                out.push({ text: t, cls: t.startsWith('+') ? 'brief-plus' : t.startsWith('-') ? 'brief-minus' : 'brief-p' });
            }
        });
        return out.map((l, i) => ({ ...l, key: 'b' + i }));
    }

    async handleBrief() {
        this.briefBusy = true;
        try {
            this.briefOverride = await generateBrief({ applicationId: this.recordId });
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'AI brief', message: (e && e.body && e.body.message) || String(e), variant: 'error' }));
        } finally {
            this.briefBusy = false;
        }
    }

    get cf() {
        const c = this.review && this.review.cashFlow;
        if (!c) {
            return null;
        }
        return { ...c, spend: (c.spend || []).map((r) => ({ ...r, barStyle: `width:${Math.max(2, r.pct)}%` })) };
    }

    get outflowParts() {
        const parts = (this.cf && this.cf.outflowParts) || [];
        const SHADES = ['#5a6b80', '#8494a6', '#a9b5c3', '#c8d0da', '#dde3ea', '#eef1f5'];
        let k = 0;
        return parts.map((o) => {
            const shade = o.highlight ? '#ef3b23' : SHADES[Math.min(k++, SHADES.length - 1)];
            return {
                ...o,
                segCls: 'ob-seg',
                segStyle: `flex:${Math.max(o.pct, 1)} 1 0;background:${shade}`,
                swCls: 'ob-sw',
                itemCls: 'ob-item' + (o.highlight ? ' hl' : ''),
                tip: `${o.category}: ${o.amount} a month (${o.pct}%)`,
                swStyle: `background:${shade}`
            };
        });
    }

    get outflowLabel() {
        return 'Monthly outflow: ' + this.outflowParts.map((o) => `${o.category} ${o.amount}`).join(', ');
    }

    get stabilityBar() {
        return `width:${(this.cf && this.cf.stability) || 0}%`;
    }

    get hasLifestyle() {
        return !!(this.cf && this.cf.lifestyle && this.cf.lifestyle.length);
    }

    get hasAnomalies() {
        return !!(this.cf && this.cf.anomalies && this.cf.anomalies.length);
    }

    get score() {
        return this.review && this.review.score;
    }

    get factorRows() {
        return ((this.score && this.score.factors) || []).map((f) => ({
            ...f,
            barStyle: `width:${Math.max(2, f.pct)}%`,
            fillCls: 'grp-fill' + (f.pct < 50 ? ' weak' : '')
        }));
    }

    get bandMeaning() {
        return { A: 'limit +0.5x', B: 'standard limit', C: 'limit −0.5x', D: 'manual review' }[this.score && this.score.band] || '';
    }

    get bandPillClass() {
        return 'b-pill sc-band' + (this.score && this.score.band === 'D' ? ' b-pill-amber' : ' b-pill-brand');
    }

    get markerStyle() {
        const v = Math.max(0, Math.min(1000, (this.score && this.score.score) || 0));
        return `left:${v / 10}%`;
    }

    get meterLabel() {
        return this.score ? `Bandhan Score ${this.score.score} of 1000, band ${this.score.band}` : '';
    }

    /* the three sources, ranked by how much they can add */
    get scoreGroups() {
        const GROUPS = [
            { name: 'Credit bureau', sub: 'score, history age, accounts, utilisation, enquiries, repayment',
              factors: ['Bureau score', 'Credit history age', 'Active accounts', 'Card utilisation', 'Enquiries (6 months)', 'Repayment (24 months)'] },
            { name: 'Bank statements (AA)', sub: 'surplus, income trend, EMIs, cash-flow stability',
              factors: ['Monthly surplus', 'Income trend', 'Obligations (FOIR)', 'Cash-flow stability'] },
            { name: 'Income, relationship, channel', sub: 'income level, Bandhan relationship, channel, verified income',
              factors: ['Income level', 'Bandhan relationship', 'Channel', 'Verified income'] }
        ];
        const rows = (this.score && this.score.factors) || [];
        return GROUPS.map((g) => {
            const fs = rows.filter((f) => g.factors.includes(f.name));
            const points = fs.reduce((t, f) => t + f.points, 0);
            const max = fs.reduce((t, f) => t + f.maxPoints, 0);
            const pct = max ? Math.round((points * 100) / max) : 0;
            return { name: g.name, sub: g.sub, points, max, style: `width:${Math.max(2, pct)}%`, tip: `${g.name}: ${points} of ${max} (${pct}%)` };
        });
    }

    get strengths() {
        return ((this.score && this.score.factors) || [])
            .filter((f) => f.maxPoints > 0 && f.points / f.maxPoints >= 0.9)
            .sort((a, b) => b.points - a.points)
            .slice(0, 4);
    }

    get gaps() {
        return ((this.score && this.score.factors) || [])
            .map((f) => ({ ...f, lost: f.maxPoints - f.points }))
            .filter((f) => f.lost > 0)
            .sort((a, b) => b.lost - a.lost)
            .slice(0, 3);
    }

    get hasGaps() {
        return this.gaps.length > 0;
    }

    get cibilBand() {
        const c = this.app.CIBIL_Score__c;
        if (c == null) {
            return '';
        }
        return c >= 750 ? 'Excellent (750-900)' : c >= 700 ? 'Good (700-749)' : c >= 650 ? 'Fair (650-699)' : 'Poor (below 650)';
    }

        get hasScore() {
        return this.app.Bandhan_Score__c != null;
    }

    get whyItems() {
        const w = (this.review && this.review.why) || '';
        return w.split(/\n|(?=✅)|(?=⚖)/).map((t) => t.trim()).filter((t) => t).map((t, i) => ({ key: 'w' + i, text: t }));
    }

    // ------------------------------------------------------------ stage gates
    gateResult(g) {
        const a = this.app;
        if (g.check) {
            const c = ((this.review && this.review.checks) || []).find((x) => x.name === g.check);
            return c ? { result: c.result || 'Pending', check: c } : { result: 'Pending' };
        }
        if (g.key === 'app') {
            return {
                result: a.Submitted_At__c ? 'Pass' : 'Pending',
                check: {
                    provider: 'Bandhu ' + (a.Channel__c || ''),
                    summary: a.Submitted_At__c ? 'Application submitted' : 'Not submitted yet',
                    details: [
                        a.Reference_Number__c && 'Reference: ' + a.Reference_Number__c,
                        a.PAN__c && 'PAN: ' + a.PAN__c,
                        a.Employment_Type__c && 'Employment: ' + a.Employment_Type__c + (a.Company_Name__c ? ' @ ' + a.Company_Name__c : ''),
                        a.City__c && 'City: ' + a.City__c + (a.PIN_Code__c ? ' ' + a.PIN_Code__c : ''),
                        a.Email__c && 'Email: ' + a.Email__c
                    ].filter(Boolean).join('\n')
                }
            };
        }
        const s = a.Status__c;
        if (g.key === 'decision') {
            const result = s === 'Card Issued' || s === 'Approved' ? 'Pass' : s === 'Declined' ? 'Fail' : s === 'Under Review' ? 'Refer' : 'Pending';
            return {
                result,
                check: {
                    provider: a.Decision_By__r ? a.Decision_By__r.Name : 'Bandhu decision engine',
                    summary: a.Decision__c ? a.Decision__c : s === 'Under Review' ? 'Referred to card underwriting' : 'Awaiting checks',
                    details: [a.Recommendation__c && 'System recommendation: ' + a.Recommendation__c, a.Decision_Notes__c && 'Notes: ' + a.Decision_Notes__c].filter(Boolean).join('\n')
                }
            };
        }
        // issued
        return {
            result: a.Card_Number_Masked__c ? 'Pass' : s === 'Declined' ? 'Fail' : 'Pending',
            check: {
                provider: 'Card management system',
                summary: a.Card_Number_Masked__c ? 'Virtual card ' + a.Card_Number_Masked__c : s === 'Declined' ? 'Not issued - application declined' : 'Not issued yet',
                details: a.Card_Product__c ? 'Card: ' + a.Card_Product__c + (this.card && this.card.creditLimit ? '\nCredit limit: ' + this.card.creditLimit : '') : ''
            }
        };
    }

    get gates() {
        if (!this.hasData) {
            return [];
        }
        return GATES.map((g) => {
            const r = this.gateResult(g);
            const selected = g.key === this.selectedKey;
            return {
                ...g,
                result: r.result,
                check: r.check,
                cls: (RESULT_CLASS[r.result] || RESULT_CLASS.Pending) + (selected ? ' gate-selected' : ''),
                title: g.label + ': ' + r.result
            };
        });
    }

    get selectedGate() {
        return this.gates.find((g) => g.key === this.selectedKey);
    }

    get selected() {
        const g = this.selectedGate;
        if (!g) {
            return null;
        }
        const c = g.check || {};
        return {
            label: g.label,
            result: g.result,
            resultClass: 'b-pill ' + ({ Pass: 'b-pill-green', Refer: 'b-pill-amber', Fail: 'b-pill-red' }[g.result] || 'b-pill-grey'),
            provider: c.provider,
            summary: c.summary || (g.check ? '' : 'This check has not run yet.'),
            score: c.score,
            hasScore: c.score !== undefined && c.score !== null,
            lines: (c.details || '').split('\n').filter((l) => l.trim()).map((text, i) => ({ key: 'd' + i, text }))
        };
    }

    get hasSelectedLines() {
        return this.selected && this.selected.lines.length > 0;
    }

    handleGate(event) {
        this.selectedKey = event.currentTarget.dataset.key;
    }

    // ------------------------------------------------------------ recommendation
    get recommendationClass() {
        const r = this.app.Recommendation__c;
        return 'b-pill rec ' + (r === 'Approve' ? 'b-pill-green' : r === 'Decline' ? 'b-pill-red' : 'b-pill-amber');
    }

    get reasons() {
        return (this.app.Recommendation_Reasons__c || '').split('\n').filter((l) => l.trim());
    }

    get reasonItems() {
        return this.reasons.map((text, i) => ({ key: 'r' + i, text }));
    }

    get declaredIncome() {
        return this.app.Monthly_Income__c != null ? INR.format(this.app.Monthly_Income__c) : '—';
    }

    get verifiedIncome() {
        return this.app.Verified_Income__c != null ? INR.format(this.app.Verified_Income__c) : 'Not verified';
    }

    get cibil() {
        return this.app.CIBIL_Score__c != null ? this.app.CIBIL_Score__c : '—';
    }

    get customerType() {
        return this.app.Customer_Type__c === 'Existing' ? 'Existing customer' : this.app.Customer_Type__c === 'New' ? 'New to bank' : '—';
    }

    // ------------------------------------------------------------ decision
    get decided() {
        return this.review && this.review.decided;
    }

    get approved() {
        return this.app.Status__c === 'Card Issued' || this.app.Status__c === 'Approved';
    }

    get outcomeClass() {
        return 'b-alert ' + (this.approved ? 'b-alert-success' : 'b-alert-error');
    }

    get outcomeText() {
        return this.approved ? 'Approved — virtual card ' + (this.app.Card_Number_Masked__c || 'being issued') : 'Declined';
    }

    get decisionBy() {
        return this.app.Decision_By__r ? this.app.Decision_By__r.Name : 'Bandhu (straight-through)';
    }

    handleApprove() {
        this.openDecision('Approved');
    }

    handleDecline() {
        this.openDecision('Declined');
    }

    async openDecision(decision) {
        const approving = decision === 'Approved';
        const result = await BandhuDecisionModal.open({
            size: 'small',
            label: approving ? 'Approve and issue card' : 'Decline application',
            decision,
            recommendation: this.app.Recommendation__c,
            deviation: approving ? !!this.review.approveIsDeviation : !!this.review.declineIsDeviation,
            applicantName: this.app.Applicant_Name__c,
            cardName: this.card ? this.card.name : this.app.Card_Product__c,
            creditLimit: this.card ? this.card.creditLimit : null,
            reasons: this.reasons
        });
        if (!result) {
            return;
        }
        this.busy = true;
        try {
            this.review = await decide({ applicationId: this.recordId, decision, notes: result.notes });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: approving ? 'Card approved' : 'Application declined',
                    message: approving
                        ? 'Virtual card ' + (this.review.application.Card_Number_Masked__c || '') + ' issued to ' + (this.app.Applicant_Name__c || 'the applicant') + '.'
                        : 'The application has been declined.',
                    variant: 'success'
                })
            );
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not record the decision', message: errorMessage(e), variant: 'error' }));
        } finally {
            this.busy = false;
        }
    }
}
