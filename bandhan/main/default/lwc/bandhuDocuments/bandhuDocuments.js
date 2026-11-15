import { LightningElement, api, track } from 'lwc';
import BANDHAN_LOGO from '@salesforce/resourceUrl/BandhanLogoWhite';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import upload from '@salesforce/apex/BandhuDocuments.upload';
import documents from '@salesforce/apex/BandhuDocuments.documents';

const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });

/** Income documents for a card application: upload, OCR read (mock) and the cross-check against the declared income. */
export default class BandhuDocuments extends LightningElement {
    @api recordId;
    logoUrl = BANDHAN_LOGO;
    @track docs = [];
    docType = 'Salary slip';
    busy = false;

    get typeOptions() {
        return ['Salary slip', 'Form 16', 'ITR', 'Bank statement'].map((t) => ({ label: t, value: t }));
    }

    get countText() {
        return this.docs.length === 1 ? '1 document' : this.docs.length + ' documents';
    }

    get hasDocs() {
        return this.docs.length > 0;
    }

    connectedCallback() {
        this.load();
    }

    async load() {
        const rows = await documents({ applicationId: this.recordId });
        this.docs = rows.map((d) => ({
            ...d,
            income: d.Extracted_Monthly_Income__c != null ? INR.format(d.Extracted_Monthly_Income__c) + '/month' : '',
            badge: 'b-pill ' + (d.Result__c === 'Pass' ? 'b-pill-green' : 'b-pill-amber'),
            pan: d.PAN_Match__c ? '✓ PAN matches' : '✕ PAN mismatch',
            panClass: d.PAN_Match__c ? 'ok' : 'bad'
        }));
    }

    handleType(e) {
        this.docType = e.detail.value;
    }

    async handleUploadFinished(e) {
        const files = e.detail.files || [];
        this.busy = true;
        try {
            for (const f of files) {
                const d = await upload({ applicationId: this.recordId, docType: this.docType, contentDocumentId: f.documentId });
                this.dispatchEvent(new ShowToastEvent({ title: d.Type__c + ': ' + d.Result__c, message: d.Summary__c, variant: d.Result__c === 'Pass' ? 'success' : 'warning' }));
            }
            await this.load();
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not read the document', message: err?.body?.message || String(err), variant: 'error' }));
        } finally {
            this.busy = false;
        }
    }
}
