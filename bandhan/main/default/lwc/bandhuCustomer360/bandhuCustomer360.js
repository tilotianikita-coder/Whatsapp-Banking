import { LightningElement, api } from 'lwc';
import BANDHAN_LOGO from '@salesforce/resourceUrl/BandhanLogoWhite';
import BANDHU_CARDS from '@salesforce/resourceUrl/BandhuCards';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import get from '@salesforce/apex/BandhuCustomer360.get';
import startApplication from '@salesforce/apex/BandhuCustomer360.startApplication';

/** RM 360: the relationship, bureau, cash flow, Bandhan Score and the card to pitch, with a branch-assisted start. */
const CARD_IMG = (name) => (['Sparks', 'Ignite', 'Flare', 'Lumina'].includes(name) ? `${BANDHU_CARDS}/${name}.png` : null);

export default class BandhuCustomer360 extends NavigationMixin(LightningElement) {
    @api recordId;
    logoUrl = BANDHAN_LOGO;
    view;
    error;
    busy = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.view = await get({ contactId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = e?.body?.message || String(e);
        }
    }

    get relBar() {
        return `width:${Math.max(0, Math.min(100, (this.view && this.view.relationshipScore) || 0))}%`;
    }

    get cardImage() {
        return CARD_IMG(this.view && this.view.pitchName);
    }

    get pitchStyle() {
        const c = (this.view && this.view.pitchColor) || '#0A3152';
        return `background: linear-gradient(135deg, ${c} 0%, ${c} 35%, #061A2C 135%);`;
    }

    get scoreText() {
        return this.view?.bandhanScore != null ? `${this.view.bandhanScore}/1000 · band ${this.view.band}` : '';
    }

    get eligibleText() {
        return this.view?.eligible?.length ? this.view.eligible.join(', ') : 'none';
    }

    get weakestText() {
        return this.view?.scoreWeakest?.length ? this.view.scoreWeakest.join(', ') : '';
    }

    get cannotStart() {
        return !this.view?.canStart || this.busy;
    }

    get hasHistory() {
        return this.view?.history?.length > 0;
    }

    async handleStart() {
        this.busy = true;
        try {
            const journeyId = await startApplication({ contactId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Application started', message: 'The customer has the pitch on WhatsApp and continues there.', variant: 'success' }));
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: journeyId, objectApiName: 'Card_Journey__c', actionName: 'view' } });
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not start', message: e?.body?.message || String(e), variant: 'error' }));
        } finally {
            this.busy = false;
        }
    }
}
