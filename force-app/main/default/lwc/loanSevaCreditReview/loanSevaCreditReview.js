import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getScorecard from '@salesforce/apex/LoanSevaDecisionService.getScorecard';

const GATES = [
    { key: 'PAN Verification', label: 'KYC', provider: 'NSDL' },
    { key: 'Credit Bureau', label: 'Bureau', provider: 'CIBIL' },
    { key: 'Bank Statement Analysis', label: 'Banking', provider: 'Perfios' },
    { key: 'Employment Verification', label: 'Employment', provider: 'EPFO / GST' },
    { key: 'Policy & FOIR', label: 'Policy', provider: 'FOIR' },
    { key: 'Dedupe & Fraud', label: 'Fraud', provider: 'Hunter' }
];
const TONE_OF_RESULT = { Pass: 'green', Refer: 'yellow', Pending: 'yellow', Fail: 'red' };
const SYMBOL = { green: '✓', yellow: '!', red: '✕', blue: '●', grey: '○' };
const BADGE = { green: 'slds-badge slds-theme_success', yellow: 'slds-badge gate-badge_yellow', red: 'slds-badge slds-theme_error', blue: 'slds-badge slds-badge_inverse', grey: 'slds-badge' };
const FACT_CLASS = { good: 'fact-value fact-value_good', warn: 'fact-value fact-value_warn', bad: 'fact-value fact-value_bad' };
const FLAG_ICON = { good: 'utility:success', warn: 'utility:warning', bad: 'utility:error' };
const FLAG_VARIANT = { good: 'success', warn: 'warning', bad: 'error' };
const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const WHEN = new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata' });
const FIELDS = ['Loan_Application__c.LastModifiedDate'];
const NEW_LOAN = 'New Loan';
/** New-loan underwriting inputs a pre-approved Top-Up never asks for. */
const TOP_UP_HIDDEN = ['PAN', 'Date of birth', 'Existing EMIs', 'Bureau consent', 'Email', 'City'];

export default class LoanSevaCreditReview extends LightningElement {
    @api recordId;
    data;
    error;
    selected;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    recordChanged({ data }) {
        if (data) {
            this.load();
        }
    }

    async load() {
        try {
            this.data = await getScorecard({ applicationId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not load the credit review';
        }
    }

    get loaded() {
        return !!this.data;
    }

    get app() {
        return this.data ? this.data.application : {};
    }

    get memo() {
        return this.data && this.data.memo ? this.data.memo : { strengths: [], risks: [], conditions: [] };
    }

    get checksByName() {
        const map = {};
        ((this.data && this.data.checks) || []).forEach((c) => {
            map[c.Check__c] = c;
        });
        return map;
    }

    get requiredDocs() {
        return this.app.Employment_Type__c === 'Salaried' ? ['PAN Card', 'Bank Statement', 'Salary Slips'] : ['PAN Card', 'Bank Statement'];
    }

    /** Top-Ups are pre-approved from the existing loan: no documents or underwriting gates. */
    get isTopUp() {
        return this.loaded && this.app.Application_Type__c !== NEW_LOAN;
    }

    get loan() {
        return this.app.Existing_Loan__r || {};
    }

    /** Application -> Identity -> Pre-approval -> KYC & bureau on file -> Offer -> RM callback -> Disbursal. */
    get topUpGates() {
        const a = this.app;
        const loan = this.loan;
        const accepted = !!a.Reference_Number__c;
        const verified = accepted || (a.Loan_Journey__r && a.Loan_Journey__r.OTP_Verified__c);
        const track = loan.EMIs_Due__c ? loan.EMIs_Paid_On_Time__c + '/' + loan.EMIs_Due__c + ' EMIs on time' : 'Existing customer';
        return [
            { key: 'application', label: 'Application', provider: 'WhatsApp', tone: 'green', status: a.Reference_Number__c || a.Name },
            { key: 'identity', label: 'Identity', provider: 'OTP', tone: verified ? 'green' : 'yellow', status: verified ? 'Verified' : 'Pending' },
            { key: 'preapproval', label: 'Pre-approval', provider: 'Existing loan', tone: 'green', status: loan.Pre_Approved_Limit__c != null ? INR.format(loan.Pre_Approved_Limit__c) + ' limit' : track },
            { key: 'kyc', label: 'KYC & bureau', provider: 'On file', tone: 'green', status: 'Existing customer' },
            { key: 'offer', label: 'Offer', provider: 'Customer', tone: accepted ? 'green' : 'yellow', status: accepted ? 'Accepted' : 'Presented' },
            {
                key: 'callback',
                label: 'RM callback',
                provider: 'Branch RM',
                tone: a.Loan_Account__c ? 'green' : a.Callback_DateTime__c ? 'blue' : 'grey',
                status: a.Callback_DateTime__c ? WHEN.format(new Date(a.Callback_DateTime__c)) : '—'
            },
            { key: 'lan', label: 'Disbursal', provider: 'LAN', tone: a.Loan_Account__c ? 'green' : 'grey', status: a.Loan_Account__c ? this.data.maskedLan || 'Created' : '—' }
        ];
    }

    /** The detail panel for a Top-Up gate. */
    get topUpPanel() {
        const a = this.app;
        const loan = this.loan;
        const fact = (label, value) => ({ key: label, label, value: value == null || value === '' ? '—' : value, className: 'fact-value' });
        const money = (v) => (v != null ? INR.format(v) : null);
        switch (this.selectedKey) {
            case 'identity':
                return { title: 'Identity', text: 'Verified with a one-time password sent to the mobile registered on the existing loan.', facts: [fact('Mobile', a.Mobile__c), fact('Applicant', a.Applicant_Name__c)] };
            case 'kyc':
                return { title: 'KYC & bureau', text: 'Already on file from the existing Kotak loan. A pre-approved Top-Up needs no fresh KYC, CIBIL pull or document upload.', facts: [fact('Existing loan', loan.Masked_Account__c)] };
            case 'offer':
                return {
                    title: 'Offer',
                    text: a.Reference_Number__c ? 'Accepted by the customer on WhatsApp.' : 'Presented on WhatsApp; not yet accepted.',
                    facts: [fact('Amount', money(a.Offer_Amount__c)), fact('Rate', a.Rate__c != null ? a.Rate__c + '% p.a.' : null), fact('Tenure', a.Tenure_Months__c != null ? a.Tenure_Months__c + ' months' : null), fact('EMI', money(a.EMI__c)), fact('Reference', a.Reference_Number__c)]
                };
            case 'callback':
                return { title: 'RM callback', text: a.Callback_DateTime__c ? 'The customer booked this slot. Call to confirm the terms and send the e-sign link.' : 'No callback booked yet.', facts: [fact('Slot', a.Callback_DateTime__c ? WHEN.format(new Date(a.Callback_DateTime__c)) : null), fact('Mobile', a.Mobile__c)] };
            case 'lan':
                return { title: 'Disbursal', text: a.Loan_Account__c ? 'Top-Up loan account created.' : 'Disbursed after the callback and e-sign.', facts: [fact('Loan account', this.data.maskedLan)] };
            default:
                return {
                    title: 'Pre-approval',
                    text: 'Priced from the existing loan\'s repayment track and pre-approved limit.',
                    facts: [
                        fact('Existing loan', loan.Masked_Account__c),
                        fact('Pre-approved limit', money(loan.Pre_Approved_Limit__c)),
                        fact('Repayment track', loan.EMIs_Due__c ? loan.EMIs_Paid_On_Time__c + ' of ' + loan.EMIs_Due__c + ' EMIs on time' : null),
                        fact('Outstanding', money(loan.Outstanding_Principal__c)),
                        fact('Current EMI', money(loan.Current_EMI__c)),
                        fact('Top-Up offer', money(a.Offer_Amount__c))
                    ]
                };
        }
    }

    get isTopUpPanelSelected() {
        return this.isTopUp && this.selectedKey !== 'application';
    }

    /** Application -> Documents -> six underwriting gates -> RM decision -> LAN. */
    get rawGates() {
        if (this.isTopUp) {
            return this.topUpGates;
        }
        const a = this.app;
        const gates = [];
        gates.push({ key: 'application', label: 'Application', provider: 'WhatsApp', tone: 'green', status: a.Reference_Number__c || a.Name });

        const received = new Set(((this.data && this.data.documents) || []).map((d) => d.Document_Type__c));
        const have = this.requiredDocs.filter((t) => received.has(t)).length;
        gates.push({ key: 'documents', label: 'Documents', provider: 'KYC files', tone: have === this.requiredDocs.length ? 'green' : 'yellow', status: have + ' of ' + this.requiredDocs.length });

        const checks = this.checksByName;
        GATES.forEach((g) => {
            const c = checks[g.key];
            let status = 'Not run';
            if (c) {
                status = g.key === 'Credit Bureau' && c.Score__c != null ? 'CIBIL ' + c.Score__c : g.key === 'Policy & FOIR' && c.Score__c != null ? 'FOIR ' + c.Score__c + '%' : c.Result__c;
            }
            gates.push({ key: g.key, label: g.label, provider: g.provider, tone: c ? TONE_OF_RESULT[c.Result__c] || 'yellow' : 'grey', status });
        });

        const decision = a.Decision__c;
        gates.push({
            key: 'decision',
            label: 'RM decision',
            provider: 'Credit',
            tone: decision === 'Approved' ? 'green' : decision === 'Rejected' ? 'red' : decision === 'Referred' ? 'yellow' : this.data && this.data.canDecide ? 'blue' : 'grey',
            status: decision || (this.data && this.data.canDecide ? 'Awaiting' : '—')
        });
        gates.push({
            key: 'lan',
            label: 'Loan account',
            provider: 'LAN',
            tone: a.Loan_Account__c ? 'green' : 'grey',
            status: a.Loan_Account__c ? (this.data.maskedLan || 'Created') : '—'
        });
        return gates;
    }

    get selectedKey() {
        if (this.selected) {
            return this.selected;
        }
        if (this.isTopUp) {
            return 'preapproval';
        }
        const gates = this.rawGates;
        const worst = gates.find((g) => g.tone === 'red' && GATES.some((x) => x.key === g.key)) || gates.find((g) => g.tone === 'yellow' && GATES.some((x) => x.key === g.key));
        return worst ? worst.key : 'Credit Bureau';
    }

    get gates() {
        const selected = this.selectedKey;
        return this.rawGates.map((g, i) => ({
            ...g,
            symbol: SYMBOL[g.tone],
            className: 'gate gate_' + g.tone + (i === 0 ? ' gate_first' : '') + (g.key === selected ? ' gate_selected' : ''),
            title: g.label + ' · ' + g.provider + ': ' + g.status
        }));
    }

    get tally() {
        const checks = Object.values(this.checksByName);
        const count = (tones) => checks.filter((c) => tones.includes(TONE_OF_RESULT[c.Result__c])).length;
        return { green: count(['green']), yellow: count(['yellow']), red: count(['red']) };
    }

    get recommendationClass() {
        const r = this.isTopUp ? 'Approve' : this.app.Recommendation__c;
        return 'verdict ' + (r === 'Approve' ? 'verdict_green' : r === 'Decline' ? 'verdict_red' : r === 'Refer' ? 'verdict_yellow' : 'verdict_grey');
    }

    get recommendationLabel() {
        if (this.isTopUp) {
            return 'Pre-approved Top-Up';
        }
        return this.app.Recommendation__c || (this.app.Underwriting_Status__c === 'Error' ? 'Underwriting error' : 'Underwriting pending');
    }

    // ------------------------------------------------------------------ selected gate panel
    get isCheckSelected() {
        return !this.isTopUp && GATES.some((g) => g.key === this.selectedKey);
    }

    get isApplicationSelected() {
        return this.selectedKey === 'application';
    }

    get isDocumentsSelected() {
        return this.selectedKey === 'documents';
    }

    get isDecisionSelected() {
        return !this.isTopUp && this.selectedKey === 'decision' || this.selectedKey === 'lan';
    }

    get selectedCheck() {
        const c = this.checksByName[this.selectedKey];
        if (!c) {
            return null;
        }
        let report = { facts: [], tables: [], flags: [] };
        try {
            report = c.Report_Data__c ? JSON.parse(c.Report_Data__c) : report;
        } catch (e) {
            // older checks have no structured report; the detail lines are shown instead
        }
        const tone = TONE_OF_RESULT[c.Result__c] || 'yellow';
        return {
            ...c,
            badge: BADGE[tone],
            facts: (report.facts || []).map((f, i) => ({ ...f, key: 'f' + i, className: FACT_CLASS[f.tone] || 'fact-value' })),
            flags: (report.flags || []).map((f, i) => ({ ...f, key: 'g' + i, icon: FLAG_ICON[f.tone] || 'utility:info', variant: FLAG_VARIANT[f.tone] })),
            tables: (report.tables || []).map((t, i) => ({
                key: 't' + i,
                title: t.title,
                columns: t.columns.map((col, j) => ({ key: 'c' + j, label: col })),
                rows: t.rows.map((row, r) => ({
                    key: 'r' + r,
                    cells: row.map((v, j) => ({ key: 'v' + j, value: v, className: this.cellClass(v) }))
                }))
            })),
            hasReport: !!c.Report_Data__c,
            detailLines: (c.Details__c || '').split('\n').map((line, i) => ({ key: 'd' + i, line }))
        };
    }

    cellClass(value) {
        const v = String(value || '');
        if (/^(Fail|Written-off|Hit)/.test(v) || v.startsWith('90+')) {
            return 'cell cell_bad';
        }
        if (/^(Refer|30 in)/.test(v)) {
            return 'cell cell_warn';
        }
        if (/^(Pass|Clear|No match|Filed|Credited)/.test(v)) {
            return 'cell cell_good';
        }
        return 'cell';
    }

    get applicationFacts() {
        const a = this.app;
        return [
            ['Applicant', a.Applicant_Name__c],
            ['Mobile', a.Mobile__c],
            ['Email', a.Email__c],
            ['City', [a.City__c, a.PIN_Code__c].filter(Boolean).join(' ')],
            ['PAN', this.data.maskedPan],
            ['Date of birth', a.Date_Of_Birth__c],
            ['Employment', [a.Employment_Type__c, a.Company_Name__c].filter(Boolean).join(' · ')],
            ['Monthly income', a.Monthly_Income__c != null ? INR.format(a.Monthly_Income__c) : null],
            ['Existing EMIs', a.Existing_EMIs__c != null ? INR.format(a.Existing_EMIs__c) : null],
            ['Purpose', a.Purpose__c],
            ['Amount', a.Offer_Amount__c != null ? INR.format(a.Offer_Amount__c) : null],
            ['Rate', a.Rate__c != null ? a.Rate__c + '% p.a.' : null],
            ['Tenure', a.Tenure_Months__c != null ? a.Tenure_Months__c + ' months' : null],
            ['EMI', a.EMI__c != null ? INR.format(a.EMI__c) : null],
            ['Bureau consent', a.Bureau_Consent__c ? 'Given on WhatsApp' : 'Not recorded'],
            ['Status', a.Status__c]
        ]
            .filter(([label]) => !this.isTopUp || !TOP_UP_HIDDEN.includes(label))
            .map(([label, value]) => ({ key: label, label, value: value || '—', className: 'fact-value' }));
    }

    get documentRows() {
        const docs = (this.data && this.data.documents) || [];
        return this.requiredDocs
            .concat(docs.map((d) => d.Document_Type__c).filter((t) => !this.requiredDocs.includes(t)))
            .filter((t, i, all) => all.indexOf(t) === i)
            .map((type) => {
                const files = docs.filter((d) => d.Document_Type__c === type);
                return {
                    key: type,
                    type,
                    received: files.length > 0,
                    icon: files.length ? 'utility:success' : 'utility:warning',
                    variant: files.length ? 'success' : 'warning',
                    files: files.map((f) => ({ key: f.Id, name: f.File_Name__c, url: f.Content_Document_Id__c ? '/lightning/r/ContentDocument/' + f.Content_Document_Id__c + '/view' : null })),
                    note: files.length ? '' : 'Not received - skipped by the customer'
                };
            });
    }

    get decided() {
        return !!this.app.Decision__c;
    }

    get decisionText() {
        const a = this.app;
        if (a.Decision__c === 'Approved') {
            return 'Approved - loan account ' + (this.data.maskedLan || '') + ' created as Sanctioned.';
        }
        if (a.Decision__c === 'Rejected') {
            return 'Rejected - the customer was sent a polite decline.';
        }
        if (a.Decision__c === 'Referred') {
            return 'Referred - more details or documents are needed before a final decision. Re-run underwriting once they arrive, then Approve or Reject.';
        }
        return 'Awaiting the RM decision. Review the summary, then Approve or Reject from the scorecard.';
    }

    get decidedBy() {
        return this.app.Decision_By__r ? this.app.Decision_By__r.Name : '';
    }

    // ------------------------------------------------------------------ memo
    get hasStrengths() {
        return this.memo.strengths && this.memo.strengths.length > 0;
    }

    get hasRisks() {
        return this.memo.risks && this.memo.risks.length > 0;
    }

    get hasConditions() {
        return this.memo.conditions && this.memo.conditions.length > 0;
    }

    get strengths() {
        return (this.memo.strengths || []).map((s, i) => ({ key: 's' + i, text: s }));
    }

    get risks() {
        return (this.memo.risks || []).map((s, i) => ({ key: 'r' + i, text: s }));
    }

    get conditions() {
        return (this.memo.conditions || []).map((s, i) => ({ key: 'c' + i, text: s, n: i + 1 }));
    }

    selectGate(event) {
        this.selected = event.currentTarget.dataset.key;
    }

    handleRefresh() {
        this.load();
    }
}
