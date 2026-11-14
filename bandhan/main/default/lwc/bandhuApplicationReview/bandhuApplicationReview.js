import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getReview from '@salesforce/apex/BandhuConsoleController.getReview';
import decide from '@salesforce/apex/BandhuConsoleController.decide';
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
        const c = (this.card && this.card.color) || '#C8102E';
        return `background: linear-gradient(135deg, ${c} 0%, ${c}cc 55%, #1b2a4a 140%);`;
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
