import { api } from 'lwc';
import LightningModal from 'lightning/modal';

/** Approve / Decline confirmation for the card underwriter. Closes with { notes } or null. */
export default class BandhuDecisionModal extends LightningModal {
    @api decision; // 'Approved' | 'Declined'
    @api recommendation; // 'Approve' | 'Refer' | 'Decline'
    @api deviation = false;
    @api applicantName;
    @api cardName;
    @api creditLimit;
    @api reasons = [];
    notes = '';
    showError = false;

    get approving() {
        return this.decision === 'Approved';
    }

    get title() {
        return this.approving ? 'Approve and issue card' : 'Decline application';
    }

    get confirmLabel() {
        return this.approving ? '✓ Approve & issue card' : '✕ Decline';
    }

    get confirmClass() {
        return this.approving ? 'b-btn-green' : 'b-btn';
    }

    get recommendationClass() {
        const r = this.recommendation;
        return 'b-pill ' + (r === 'Approve' ? 'b-pill-green' : r === 'Decline' ? 'b-pill-red' : 'b-pill-amber');
    }

    get summary() {
        const who = this.applicantName || 'the applicant';
        return this.approving
            ? `Issue a virtual ${this.cardName || ''} card to ${who}${this.creditLimit ? ' with a credit limit of ' + this.creditLimit : ''}.`
            : `Decline ${who}'s application${this.cardName ? ' for the ' + this.cardName + ' card' : ''}.`;
    }

    get guidance() {
        if (this.deviation) {
            return `This goes against the system recommendation (${this.recommendation}). A note explaining why is required.`;
        }
        return this.recommendation === 'Refer'
            ? 'The system referred this application for your judgement. Notes are optional.'
            : 'This matches the system recommendation. Notes are optional.';
    }

    get guidanceClass() {
        return 'b-alert slds-m-top_small ' + (this.deviation ? 'b-alert-warn' : 'b-alert-info');
    }

    get guidanceIcon() {
        return this.deviation ? 'utility:warning' : 'utility:info';
    }

    get notesLabel() {
        return this.deviation ? 'Reason for going against the recommendation (required, internal)' : 'Decision notes (optional, internal)';
    }

    get reasonItems() {
        return (this.reasons || []).map((text, i) => ({ key: 'r' + i, text }));
    }

    get hasReasons() {
        return this.reasonItems.length > 0;
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
        this.close({ notes: (this.notes || '').trim() });
    }
}
