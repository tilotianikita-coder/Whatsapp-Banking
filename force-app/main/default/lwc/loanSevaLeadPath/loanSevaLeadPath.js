import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STATUS from '@salesforce/schema/Lead.Status';
import CONVERTED from '@salesforce/schema/Lead.IsConverted';
import NUDGED from '@salesforce/schema/Lead.LoanSeva_Last_Nudged__c';
import GATE from '@salesforce/schema/Lead.LoanSeva_Stage_Gate__c';

const OPEN_STEPS = ['New', 'Working', 'Qualified'];
const STATE_CLASS = { complete: 'done', current: 'current', incomplete: 'todo', lost: 'lost', won: 'won' };

/**
 * Lead status for LoanSeva WhatsApp leads, in place of the standard path: New -> Working -> Qualified, then a closing
 * step that is Converted (won) or Unqualified (lost). Unqualified never shows Qualified as done, and every step keeps
 * its name (the standard path shows only a tick on completed steps).
 */
export default class LoanSevaLeadPath extends LightningElement {
    @api recordId;
    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS], optionalFields: [CONVERTED, NUDGED, GATE] })
    wired({ data, error }) {
        this.record = data;
        this.error = error ? 'Lead status could not be loaded.' : undefined;
    }

    get status() {
        return getFieldValue(this.record, STATUS);
    }

    get unqualified() {
        return this.status === 'Unqualified';
    }

    get converted() {
        return getFieldValue(this.record, CONVERTED) === true || this.status === 'Converted';
    }

    get steps() {
        if (!this.record) {
            return [];
        }
        const current = OPEN_STEPS.indexOf(this.status);
        const nudged = !!getFieldValue(this.record, NUDGED);
        const steps = OPEN_STEPS.map((label, index) => {
            let state;
            if (this.converted) {
                state = 'complete';
            } else if (this.unqualified) {
                // reached New; Working only if the RM nudged; never Qualified
                state = index === 0 || (index === 1 && nudged) ? 'complete' : 'incomplete';
            } else if (index < current) {
                state = 'complete';
            } else {
                state = index === current ? 'current' : 'incomplete';
            }
            return { label, state };
        });
        if (this.unqualified) {
            steps.push({ label: 'Unqualified', state: 'lost' });
        } else {
            steps.push({ label: 'Converted', state: this.converted ? 'won' : 'incomplete' });
        }
        return steps.map((s) => ({
            ...s,
            key: s.label,
            itemClass: 'k-step k-' + STATE_CLASS[s.state],
            title: (s.state === 'complete' || s.state === 'won' ? '✓ ' : s.state === 'lost' ? '✕ ' : '') + s.label
        }));
    }

    get note() {
        if (!this.unqualified) {
            return null;
        }
        const gate = getFieldValue(this.record, GATE);
        return gate ? 'Unqualified: ' + gate.charAt(0).toLowerCase() + gate.slice(1) + '. No RM call or WhatsApp nudge.' : 'Unqualified.';
    }
}
