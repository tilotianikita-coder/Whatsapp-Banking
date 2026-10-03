import { api } from 'lwc';
import LightningModal from 'lightning/modal';

/** Approve / Reject confirmation that puts the credit summary in front of the RM. Closes with { notes } or null. */
export default class LoanSevaDecisionModal extends LightningModal {
    @api decision;
    @api memo;
    @api terms;
    notes = '';
    showError = false;

    get approving() {
        return this.decision === 'Approved';
    }

    get title() {
        return this.approving ? 'Approve and create loan account' : 'Reject application';
    }

    get confirmLabel() {
        return this.approving ? 'Approve & create LAN' : 'Reject';
    }

    get confirmVariant() {
        return this.approving ? 'success' : 'destructive';
    }

    get m() {
        return this.memo || { strengths: [], risks: [], conditions: [] };
    }

    get deviation() {
        return this.approving ? this.m.approveIsDeviation : this.m.rejectIsDeviation;
    }

    get guidance() {
        return this.approving ? this.m.approveGuidance : this.m.rejectGuidance;
    }

    get guidanceClass() {
        return 'slds-box slds-box_x-small slds-m-top_small ' + (this.deviation ? 'guidance guidance_warn' : 'guidance');
    }

    get guidanceIcon() {
        return this.deviation ? 'utility:warning' : 'utility:info';
    }

    get notesLabel() {
        return this.deviation ? 'Reason for going against the recommendation (required, internal)' : 'Decision notes (optional, internal - never sent to the customer)';
    }

    get recommendationClass() {
        const r = this.m.recommendation;
        return 'slds-badge ' + (r === 'Approve' ? 'slds-theme_success' : r === 'Decline' ? 'slds-theme_error' : 'slds-theme_warning');
    }

    get strengths() {
        return (this.m.strengths || []).map((text, i) => ({ key: 's' + i, text }));
    }

    get risks() {
        return (this.m.risks || []).map((text, i) => ({ key: 'r' + i, text }));
    }

    get conditions() {
        return (this.m.conditions || []).map((text, i) => ({ key: 'c' + i, text, n: i + 1 }));
    }

    get hasStrengths() {
        return this.strengths.length > 0;
    }

    get hasRisks() {
        return this.risks.length > 0;
    }

    get hasConditions() {
        return this.approving && this.conditions.length > 0;
    }

    get hasTerms() {
        return this.approving && this.terms && this.terms.length > 0;
    }

    handleNotes(event) {
        this.notes = event.target.value;
        this.showError = false;
    }

    handleCancel() {
        this.close(null);
    }

    handleConfirm() {
        if (this.deviation && !(this.notes || '').trim()) {
            this.showError = true;
            return;
        }
        this.close({ notes: this.notes });
    }
}
