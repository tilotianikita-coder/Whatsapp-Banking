import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getPanel from '@salesforce/apex/BandhuCreditApproval.getPanel';
import propose from '@salesforce/apex/BandhuCreditApproval.propose';
import submitRequest from '@salesforce/apex/BandhuCreditApproval.submitRequest';
import decideRequest from '@salesforce/apex/BandhuCreditApproval.decideRequest';
import withdrawRequest from '@salesforce/apex/BandhuCreditApproval.withdrawRequest';

const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const inr = (v) => (v == null || v === '' ? '—' : INR.format(v));

function errorMessage(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

export default class BandhuCreditApproval extends LightningElement {
    @api recordId;
    panel;
    error;
    loading = true;
    busy = false;
    composing = false;
    showMatrix = false;
    // the proposal
    direction = 'Upgrade';
    picked = [];       // downgrade: the mismatch keys relied on
    card;
    limit;
    proposal;
    approverId;
    reasonCode;
    findings = '';
    mitigants = '';
    proposeTimer;
    // the decision
    decisionNotes = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.panel = await getPanel({ applicationId: this.recordId });
            this.error = undefined;
            // deep link for demos: ?c__propose=Downgrade opens the form
            const want = new URL(window.location.href).searchParams.get('c__propose');
            if (want && this.panel.eligible && !this.composing) {
                this.handleCompose({ currentTarget: { dataset: { dir: want } } });
            }
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    async refreshRecord() {
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        // the review panel above (a sibling on the page) re-reads the application
        window.dispatchEvent(new CustomEvent('bandhuapplicationchange', { detail: { recordId: this.recordId } }));
    }

    // ------------------------------------------------------------------ state
    get p() {
        return this.panel || {};
    }

    get hasPanel() {
        return !!this.panel;
    }

    get open() {
        return this.p.open;
    }

    get pending() {
        return this.open && this.open.Status__c === 'Pending';
    }

    get awaitingConsent() {
        return this.open && this.open.Status__c === 'Approved' && this.open.Customer_Consent__c === 'Pending';
    }

    get canPropose() {
        return this.p.eligible && !this.composing;
    }

    get myLevelText() {
        return this.p.myLevel ? `You: L${this.p.myLevel}` : 'You: not in the card credit hierarchy';
    }

    get policyText() {
        return `${this.p.currentCard || '—'} · policy limit ${inr(this.p.policyLimit)} · income ${inr(this.p.income)}/month`;
    }

    get history() {
        return (this.p.history || [])
            .filter((r) => !this.open || r.Id !== this.open.Id)
            .map((r) => this.decorate(r));
    }

    get hasHistory() {
        return this.history.length > 0;
    }

    get hasNoOpen() {
        return !this.open;
    }

    get stepTwoCls() {
        const s = this.open && this.open.Status__c;
        return 'step ' + (s === 'Pending' ? 'now' : s === 'Approved' ? 'done' : s === 'Rejected' ? 'stop' : '');
    }

    get stepThreeCls() {
        const r = this.open;
        if (!r) {
            return 'step';
        }
        if (r.Customer_Consent__c === 'Not needed') {
            return 'step ' + (r.Status__c === 'Approved' ? 'done' : '');
        }
        return 'step ' + (r.Customer_Consent__c === 'Pending' && r.Status__c === 'Approved' ? 'now' : r.Customer_Consent__c === 'Accepted' ? 'done' : '');
    }

    get stepThreeText() {
        const r = this.open;
        if (!r) {
            return '';
        }
        if (r.Customer_Consent__c === 'Not needed') {
            return 'Card issued at the approved limit';
        }
        return r.Direction__c === 'Downgrade' ? 'Accepts the counter-offer on WhatsApp (No closes it)' : 'Accepts the upgrade on WhatsApp (consent)';
    }

    get openView() {
        return this.open ? this.decorate(this.open) : null;
    }

    decorate(r) {
        const s = r.Status__c;
        const consent = s === 'Approved' && r.Customer_Consent__c === 'Pending';
        const down = r.Direction__c === 'Downgrade';
        return {
            ...r,
            change: (r.Proposed_Card__c !== r.Current_Card__c ? `${r.Current_Card__c} → ${r.Proposed_Card__c}` : r.Current_Card__c)
                + ` · ${inr(r.Policy_Limit__c)} → ${inr(r.Proposed_Limit__c)}`,
            over: r.Over_Policy_Pct__c ? `${r.Over_Policy_Pct__c}% over policy` : 'within policy',
            multiple: r.Income_Multiple__c ? `${r.Income_Multiple__c}x income` : '',
            levelText: `L${r.Required_Level__c} ${r.Required_Title__c || ''}`,
            levelReasons: (r.Level_Reasons__c || '').split('\n').filter((x) => x).map((t, i) => ({ key: 'l' + i, text: t })),
            statusText: consent ? 'Approved · waiting for the customer'
                : s === 'Approved' && r.Customer_Consent__c === 'Declined' ? (down ? 'Approved · customer declined, application closed' : 'Approved · customer kept the original card')
                : s,
            isDowngrade: down,
            dirText: down ? '↓ Downgrade · counter-offer' : '↑ Upgrade',
            dirCls: 'b-pill ' + (down ? 'b-pill-orange' : 'b-pill-blue'),
            mismatchItems: (r.Mismatches__c || '').split('\n').filter((x) => x).map((t, i) => ({ key: 'x' + i, text: t.replace(/^• /, '') })),
            evidenceLine: down && r.Assessed_Income__c ? `Assessed income ${inr(r.Assessed_Income__c)}/month · the evidence supports ${r.Suggested_Card__c || 'no card'}${r.Suggested_Limit__c ? ' at ' + inr(r.Suggested_Limit__c) : ''}` : null,
            statusCls: 'b-pill ' + (s === 'Pending' || consent ? 'b-pill-amber' : s === 'Approved' ? 'b-pill-green' : s === 'Rejected' ? 'b-pill-red' : 'b-pill-grey'),
            statusIcon: s === 'Pending' || consent ? '◷' : s === 'Approved' ? '✓' : s === 'Rejected' ? '✕' : '↺',
            by: r.Requested_By__r ? r.Requested_By__r.Name : '—',
            to: r.Owner ? r.Owner.Name : '—',
            decidedBy: r.Decided_By__r ? r.Decided_By__r.Name : null
        };
    }

    // ------------------------------------------------------------------ propose
    get isDowngrade() {
        return this.direction === 'Downgrade';
    }

    get cardOptions() {
        const cur = this.p.currentCard;
        if (this.isDowngrade) {
            const opts = [{ label: `${cur} (applied for) · lower limit only`, value: cur }];
            (this.p.downgradeCards || []).slice().reverse().forEach((c) => opts.push({ label: `Downgrade to ${c}`, value: c }));
            return opts;
        }
        const opts = [{ label: `${cur} (applied for) · higher limit only`, value: cur }];
        (this.p.upgradeCards || []).forEach((c) => opts.push({ label: `Upgrade to ${c}`, value: c }));
        return opts;
    }

    get directionOptions() {
        return [
            { label: '↑ Upgrade / higher limit', value: 'Upgrade', cls: 'seg' + (this.direction === 'Upgrade' ? ' on' : '') },
            { label: '↓ Downgrade / lower limit', value: 'Downgrade', cls: 'seg' + (this.direction === 'Downgrade' ? ' on' : '') }
        ];
    }

    get ev() {
        return this.p.evidence || { mismatches: [] };
    }

    get hasMismatches() {
        return (this.ev.mismatches || []).length > 0;
    }

    get mismatchCount() {
        return (this.ev.mismatches || []).length;
    }

    get mismatchRows() {
        return (this.ev.mismatches || []).map((m) => ({
            ...m,
            checked: this.picked.includes(m.key),
            kindCls: 'kind kind-' + (m.kind || '').toLowerCase(),
            strength: m.stop ? 'Stop · fraud control' : m.fraudSignal ? 'Fraud signal' : m.hard ? 'Evidence' : 'Soft signal',
            strengthCls: 'b-pill ' + (m.stop || m.fraudSignal ? 'b-pill-red' : m.hard ? 'b-pill-blue' : 'b-pill-grey'),
            supports: m.supportedIncome ? `supports ${inr(m.supportedIncome)}/month` : null
        }));
    }

    get evidenceText() {
        const e = this.ev;
        if (!e.assessedIncome) {
            return null;
        }
        const from = e.assessedFrom ? ` (${e.assessedFrom})` : '';
        const fit = e.suggestedCard ? `the evidence supports the ${e.suggestedCard} at ${inr(e.suggestedLimit)}` : 'no card fits the evidence (decline instead)';
        return `Declared ${inr(e.declaredIncome)}/month · assessed ${inr(e.assessedIncome)}/month${from} → ${fit}`;
    }

    handleDirection(evt) {
        this.direction = evt.currentTarget.dataset.value;
        this.defaults();
        this.runProposal();
    }

    defaults() {
        if (this.isDowngrade) {
            const e = this.ev;
            const lower = this.p.downgradeCards || [];
            this.card = e.suggestedCard && lower.includes(e.suggestedCard) ? e.suggestedCard
                : e.suggestedCard === this.p.currentCard ? this.p.currentCard : lower.length ? lower[lower.length - 1] : this.p.currentCard;
            this.limit = e.suggestedCard === this.card && e.suggestedLimit ? e.suggestedLimit : null;
            this.picked = (e.mismatches || []).filter((m) => !m.stop).map((m) => m.key);
            this.reasonCode = this.firstReason();
        } else {
            this.card = this.p.upgradeCards && this.p.upgradeCards.length ? this.p.upgradeCards[0] : this.p.currentCard;
            this.limit = this.p.policyLimit ? Math.round((this.p.policyLimit * 1.5) / 5000) * 5000 : null;
            this.picked = [];
            this.reasonCode = undefined;
        }
    }

    firstReason() {
        const map = { aa_income: 'Income lower than declared', tax: 'Tax / GST records lower', gst: 'Tax / GST records lower', doc_income: 'Income documents mismatch',
            employer: 'Employer mismatch', obligations: 'High existing obligations', spend: 'Spend lower than declared', banking: 'Banking anomalies',
            bureau: 'Bureau concerns', address: 'Address mismatch' };
        const first = (this.ev.mismatches || []).find((m) => map[m.key]);
        return first ? map[first.key] : undefined;
    }

    handleMismatch(evt) {
        const key = evt.target.dataset.key;
        this.picked = evt.target.checked ? [...this.picked, key] : this.picked.filter((k) => k !== key);
        this.runProposal();
    }

    handleCompose(evt) {
        this.composing = true;
        this.direction = evt && evt.currentTarget && evt.currentTarget.dataset.dir ? evt.currentTarget.dataset.dir : 'Upgrade';
        this.findings = '';
        this.mitigants = '';
        this.approverId = undefined;
        this.defaults();
        this.runProposal();
    }

    handleCancelCompose() {
        this.composing = false;
        this.proposal = undefined;
    }

    handleCard(e) {
        this.card = e.detail.value;
        this.runProposal();
    }

    handleLimit(e) {
        this.limit = e.detail.value === '' ? null : Number(e.detail.value);
        clearTimeout(this.proposeTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.proposeTimer = setTimeout(() => this.runProposal(), 400);
    }

    async runProposal() {
        try {
            this.proposal = await propose({ applicationId: this.recordId, proposedCard: this.card, proposedLimit: this.limit,
                mismatchKeys: this.isDowngrade ? this.picked : null });
            const ids = (this.proposal.approvers || []).map((a) => a.id);
            if (!ids.includes(this.approverId)) {
                this.approverId = ids.length ? ids[0] : undefined;
            }
        } catch (e) {
            this.proposal = undefined;
            this.toast('Could not check the rules', errorMessage(e), 'error');
        }
    }

    get a() {
        return this.proposal ? this.proposal.assessment : null;
    }

    get assessmentCls() {
        return 'level ' + (this.a && !this.a.allowed ? 'level-stop' : 'level-ok');
    }

    get levelHeadline() {
        if (!this.a) {
            return '';
        }
        return this.a.allowed ? `Needs L${this.a.level} · ${this.a.title} or above` : 'Not allowed: a hard stop applies';
    }

    get reasonItems() {
        return this.a ? this.a.reasons.map((t, i) => ({ key: 'r' + i, text: t })) : [];
    }

    get stopItems() {
        return this.a ? this.a.hardStops.map((t, i) => ({ key: 's' + i, text: t })) : [];
    }

    get hasStops() {
        return this.stopItems.length > 0;
    }

    get proposalFacts() {
        if (!this.a) {
            return '';
        }
        if (this.a.direction === 'Downgrade') {
            const d = [this.a.requestType, `policy ${inr(this.a.policyLimit)} on ${this.p.currentCard}`, `offer ${inr(this.a.proposedLimit)}`];
            if (this.a.assessedIncome) {
                d.push(`assessed income ${inr(this.a.assessedIncome)}/month`);
            }
            return d.join(' · ');
        }
        const parts = [this.a.requestType, `policy ${inr(this.a.policyLimit)}`];
        if (this.a.overPolicyPct) {
            parts.push(`${this.a.overPolicyPct}% over policy`);
        }
        if (this.a.incomeMultiple) {
            parts.push(`${this.a.incomeMultiple}x monthly income`);
        }
        return parts.join(' · ');
    }

    get approverOptions() {
        return ((this.proposal && this.proposal.approvers) || []).map((x) => ({
            label: `${x.name} · L${x.level} ${x.title}${x.inChain ? ' · your line manager chain' : ''}`,
            value: x.id
        }));
    }

    get noApprovers() {
        return this.a && this.a.allowed && this.approverOptions.length === 0;
    }

    get reasonOptions() {
        return (this.p.reasonCodes || []).map((r) => ({ label: r, value: r }));
    }

    get submitDisabled() {
        return this.busy || !this.a || !this.a.allowed || !this.approverId || !this.reasonCode || (this.findings || '').trim().length < 20;
    }

    get findingsLabel() {
        return this.isDowngrade
            ? 'Your findings (required): what does not add up, and why this card / limit fits the customer instead of a decline'
            : 'Your findings (required): what you saw and why the deviation is justified';
    }

    get findingsPlaceholder() {
        return this.isDowngrade
            ? 'e.g. Declared ₹1,00,000 a month but the salary credits are ₹68,000 (AIS agrees at ₹8.4L a year). EMIs take 45% of income. The Ignite at ₹1.5L fits what we can verify; a decline would lose a customer with a clean CIBIL.'
            : 'e.g. Salary credits from Infosys of ₹91,200 for 24 months, growing 8% a year; card-able spend of ₹62,000 a month, mostly travel abroad, which the Flare limit would cap. No missed EMIs.';
    }

    get submitLabel() {
        return this.isDowngrade ? 'Send counter-offer for approval' : 'Send for approval';
    }

    get findingsHint() {
        const n = (this.findings || '').trim().length;
        return n >= 20 ? `${n} characters` : `At least 20 characters (${n})`;
    }

    handleApprover(e) {
        this.approverId = e.detail.value;
    }

    handleReason(e) {
        this.reasonCode = e.detail.value;
    }

    handleFindings(e) {
        this.findings = e.target.value;
    }

    handleMitigants(e) {
        this.mitigants = e.target.value;
    }

    async handleSubmit() {
        this.busy = true;
        try {
            this.panel = await submitRequest({
                applicationId: this.recordId, proposedCard: this.card, proposedLimit: this.limit, approverId: this.approverId,
                reasonCode: this.reasonCode, findings: this.findings, mitigants: this.mitigants, mismatchKeys: this.isDowngrade ? this.picked : null
            });
            this.composing = false;
            this.proposal = undefined;
            this.toast('Sent for approval', `Assigned to ${this.open ? this.open.Owner.Name : 'the approver'}.`, 'success');
            this.refreshRecord();
        } catch (e) {
            this.toast('Could not send for approval', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ decide
    handleDecisionNotes(e) {
        this.decisionNotes = e.target.value;
    }

    get onBehalfNote() {
        return this.p.onBehalf ? 'You are recording this decision on behalf of the assigned approver (demo setting; logged on the request).' : null;
    }

    handleApprove() {
        this.decide('Approved');
    }

    handleReturn() {
        this.decide('Returned');
    }

    handleReject() {
        this.decide('Rejected');
    }

    async decide(decision) {
        this.busy = true;
        try {
            this.panel = await decideRequest({ requestId: this.open.Id, decision, notes: this.decisionNotes });
            this.decisionNotes = '';
            const msg = decision === 'Approved'
                ? 'Approved. ' + (this.awaitingConsent ? 'The customer is offered the upgrade on WhatsApp.' : 'The card is issued at the approved limit.')
                : decision === 'Returned' ? 'Returned to the underwriter for more information.' : 'Rejected: the application is back in the underwriter queue.';
            this.toast('Credit request ' + decision.toLowerCase(), msg, 'success');
            this.refreshRecord();
        } catch (e) {
            this.toast('Could not record the decision', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleWithdraw() {
        this.busy = true;
        try {
            this.panel = await withdrawRequest({ requestId: this.open.Id });
            this.toast('Request withdrawn', 'The application is back in the underwriter queue.', 'success');
            this.refreshRecord();
        } catch (e) {
            this.toast('Could not withdraw', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ the authority matrix
    get matrixLabel() {
        return this.showMatrix ? 'Hide the approval rules' : 'Show the approval rules';
    }

    toggleMatrix() {
        this.showMatrix = !this.showMatrix;
    }

    get matrix() {
        return (this.p.matrix || []).map((m) => ({
            ...m,
            key: 'm' + m.level,
            maxLimitText: inr(m.maxLimit),
            overText: m.maxOverPolicyPct ? `up to ${m.maxOverPolicyPct}%` : 'at policy',
            multText: `${m.maxIncomeMultiple}x`,
            tiersText: m.maxUpgradeTiers ? `${m.maxUpgradeTiers} tier${m.maxUpgradeTiers > 1 ? 's' : ''}` : 'none',
            incomeText: m.maxUpgradeTiers ? `≥ ${m.minIncomePctUpgrade}%` : '—',
            downText: `${m.maxDowngradeTiers} tier${m.maxDowngradeTiers === 1 ? '' : 's'}${m.beyondEvidence ? ', below the evidence' : ', within the evidence'}`,
            mine: this.p.myLevel === m.level,
            mineCls: this.p.myLevel === m.level ? 'mine' : ''
        }));
    }
}
