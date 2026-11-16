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
        return r.Customer_Consent__c === 'Not needed' ? 'Card issued at the approved limit' : 'Accepts the upgrade on WhatsApp (consent)';
    }

    get openView() {
        return this.open ? this.decorate(this.open) : null;
    }

    decorate(r) {
        const s = r.Status__c;
        const consent = s === 'Approved' && r.Customer_Consent__c === 'Pending';
        return {
            ...r,
            change: (r.Proposed_Card__c !== r.Current_Card__c ? `${r.Current_Card__c} → ${r.Proposed_Card__c}` : r.Current_Card__c)
                + ` · ${inr(r.Policy_Limit__c)} → ${inr(r.Proposed_Limit__c)}`,
            over: r.Over_Policy_Pct__c ? `${r.Over_Policy_Pct__c}% over policy` : 'within policy',
            multiple: r.Income_Multiple__c ? `${r.Income_Multiple__c}x income` : '',
            levelText: `L${r.Required_Level__c} ${r.Required_Title__c || ''}`,
            levelReasons: (r.Level_Reasons__c || '').split('\n').filter((x) => x).map((t, i) => ({ key: 'l' + i, text: t })),
            statusText: consent ? 'Approved · waiting for the customer' : s === 'Approved' && r.Customer_Consent__c === 'Declined' ? 'Approved · customer kept the original card' : s,
            statusCls: 'b-pill ' + (s === 'Pending' || consent ? 'b-pill-amber' : s === 'Approved' ? 'b-pill-green' : s === 'Rejected' ? 'b-pill-red' : 'b-pill-grey'),
            statusIcon: s === 'Pending' || consent ? '◷' : s === 'Approved' ? '✓' : s === 'Rejected' ? '✕' : '↺',
            by: r.Requested_By__r ? r.Requested_By__r.Name : '—',
            to: r.Owner ? r.Owner.Name : '—',
            decidedBy: r.Decided_By__r ? r.Decided_By__r.Name : null
        };
    }

    // ------------------------------------------------------------------ propose
    get cardOptions() {
        const cur = this.p.currentCard;
        const opts = [{ label: `${cur} (applied for) · higher limit only`, value: cur }];
        (this.p.upgradeCards || []).forEach((c) => opts.push({ label: `Upgrade to ${c}`, value: c }));
        return opts;
    }

    handleCompose() {
        this.composing = true;
        this.card = this.p.upgradeCards && this.p.upgradeCards.length ? this.p.upgradeCards[0] : this.p.currentCard;
        this.limit = this.p.policyLimit ? Math.round((this.p.policyLimit * 1.5) / 5000) * 5000 : null;
        this.findings = '';
        this.mitigants = '';
        this.reasonCode = undefined;
        this.approverId = undefined;
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
            this.proposal = await propose({ applicationId: this.recordId, proposedCard: this.card, proposedLimit: this.limit });
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
                reasonCode: this.reasonCode, findings: this.findings, mitigants: this.mitigants
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
            mine: this.p.myLevel === m.level,
            mineCls: this.p.myLevel === m.level ? 'mine' : ''
        }));
    }
}
