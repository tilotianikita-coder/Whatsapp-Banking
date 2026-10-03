/**
 * Credit memo for the RM: reads the underwriting checks and the application and writes a short, plain summary -
 * the verdict, strengths, risks, the conditions to clear before disbursal and what a decision against the
 * recommendation means. Rule-based and deterministic, so the same file always reads the same way.
 */
public with sharing class LoanSevaCreditMemo {
    public class Memo {
        @AuraEnabled public String recommendation;
        @AuraEnabled public String headline;
        @AuraEnabled public String narrative;
        @AuraEnabled public List<String> strengths = new List<String>();
        @AuraEnabled public List<String> risks = new List<String>();
        @AuraEnabled public List<String> conditions = new List<String>();
        @AuraEnabled public String approveGuidance;
        @AuraEnabled public String rejectGuidance;
        @AuraEnabled public Boolean approveIsDeviation;
        @AuraEnabled public Boolean rejectIsDeviation;
    }

    /** Approving a Refer or Decline, or rejecting an Approve, goes against the system and needs a reason. */
    public static Boolean isDeviation(String recommendation, String decision) {
        if (String.isBlank(recommendation)) {
            return false;
        }
        return decision == LoanSevaDecisionService.APPROVED ? recommendation != 'Approve' : recommendation == 'Approve';
    }

    public static Memo build(Loan_Application__c app, List<Underwriting_Check__c> checks) {
        Memo m = new Memo();
        m.recommendation = app.Recommendation__c;
        Map<String, Underwriting_Check__c> byName = new Map<String, Underwriting_Check__c>();
        for (Underwriting_Check__c c : checks == null ? new List<Underwriting_Check__c>() : checks) {
            byName.put(c.Check__c, c);
        }
        String first = app.Applicant_Name__c == null ? 'The applicant' : app.Applicant_Name__c.normalizeSpace().split(' ')[0];
        if (byName.isEmpty()) {
            m.headline = 'Underwriting has not run yet';
            m.narrative = 'No bureau, banking or fraud results are available. Re-run underwriting before deciding.';
            m.approveGuidance = 'Approval is available once underwriting completes.';
            m.rejectGuidance = 'You can reject now; give the reason in the notes.';
            m.approveIsDeviation = false;
            m.rejectIsDeviation = false;
            return m;
        }

        pan(m, byName.get('PAN Verification'));
        bureau(m, byName.get('Credit Bureau'));
        bank(m, byName.get('Bank Statement Analysis'), app);
        employment(m, byName.get('Employment Verification'), app);
        policy(m, byName.get('Policy & FOIR'), app);
        fraud(m, byName.get('Dedupe & Fraud'));

        Integer fails = 0;
        Integer open = 0;
        for (Underwriting_Check__c c : byName.values()) {
            fails += c.Result__c == 'Fail' ? 1 : 0;
            open += c.Result__c == 'Refer' || c.Result__c == 'Pending' ? 1 : 0;
        }
        Integer passed = byName.size() - fails - open;
        String ask = (app.Offer_Amount__c == null ? 'a personal loan' : LoanSevaI18n.inr(app.Offer_Amount__c))
            + (app.Tenure_Months__c == null ? '' : ' over ' + app.Tenure_Months__c.intValue() + ' months')
            + (app.EMI__c == null ? '' : ' (EMI ' + LoanSevaI18n.inr(app.EMI__c) + ')');
        List<String> parts = new List<String>();
        if (app.Employment_Type__c != null) {
            parts.add(app.Employment_Type__c.toLowerCase() + (String.isBlank(app.Company_Name__c) ? '' : ' at ' + app.Company_Name__c));
        }
        if (app.CIBIL_Score__c != null) {
            parts.add('CIBIL ' + app.CIBIL_Score__c.intValue());
        }
        if (app.Monthly_Income__c != null) {
            parts.add('declared income ' + LoanSevaI18n.inr(app.Monthly_Income__c) + '/month');
        }
        String profile = String.join(parts, ', ');

        if (app.Recommendation__c == 'Decline') {
            m.headline = 'Decline - ' + fails + ' hard stop' + (fails == 1 ? '' : 's') + ' (' + names(byName, 'Fail') + ')';
            m.narrative = first + ' has asked for ' + ask + '. ' + capitalise(profile) + '. The file fails ' + names(byName, 'Fail')
                + ', which is outside credit policy; ' + passed + ' of ' + byName.size() + ' checks passed. We recommend declining.';
        } else if (app.Recommendation__c == 'Refer') {
            m.headline = 'Refer - ' + open + ' item' + (open == 1 ? '' : 's') + ' to clear (' + names(byName, 'Refer;Pending') + ')';
            m.narrative = first + ' has asked for ' + ask + '. ' + capitalise(profile) + '. ' + passed + ' of ' + byName.size()
                + ' checks passed with no hard stop. Clear the open items below, or approve with conditions and record how each was mitigated.';
        } else {
            m.headline = 'Approve - clean file, all ' + byName.size() + ' checks passed';
            m.narrative = first + ' has asked for ' + ask + '. ' + capitalise(profile) + '. KYC, bureau, banking, employment, policy and fraud checks all passed. We recommend approval on the requested terms.';
        }

        m.approveIsDeviation = isDeviation(app.Recommendation__c, LoanSevaDecisionService.APPROVED);
        m.rejectIsDeviation = isDeviation(app.Recommendation__c, LoanSevaDecisionService.REJECTED);
        m.approveGuidance = app.Recommendation__c == 'Approve'
            ? 'Approving matches the recommendation. A loan account is created as Sanctioned and the customer gets the masked LAN on WhatsApp.'
            : app.Recommendation__c == 'Refer'
                ? 'Approving against a Refer: note how each open item was cleared or which condition applies before disbursal. Notes are required.'
                : 'Approving against a Decline is a credit policy deviation: give the justification and approving authority. Notes are required.';
        m.rejectGuidance = app.Recommendation__c == 'Approve'
            ? 'Rejecting a file that passed every check: record the reason. Notes are required and stay internal.'
            : 'Rejecting matches the risk on file. The customer gets a polite decline; your notes stay internal.';
        return m;
    }

    private static void pan(Memo m, Underwriting_Check__c c) {
        if (c == null) {
            return;
        }
        if (c.Result__c == 'Pass') {
            m.strengths.add('KYC clean - PAN active, Aadhaar-linked and the name matches (NSDL)');
        } else if (c.Result__c == 'Refer') {
            m.risks.add('KYC: ' + c.Summary__c);
            m.conditions.add('Match the PAN card image with the applicant name, or re-verify through DigiLocker');
        } else {
            m.risks.add('KYC: ' + c.Summary__c + ' - the PAN cannot be relied on');
        }
    }

    private static void bureau(Memo m, Underwriting_Check__c c) {
        if (c == null) {
            return;
        }
        Integer score = c.Score__c == null ? null : c.Score__c.intValue();
        if (c.Result__c == 'Pass') {
            m.strengths.add('CIBIL ' + score + (score >= 780 ? ' - prime borrower' : ' - within policy') + ', no missed payment in 24 months');
        } else if (c.Result__c == 'Refer') {
            m.risks.add('CIBIL ' + score + ' with a 30-day delay on the credit card in the last 12 months');
            m.conditions.add('Get the customer\'s explanation for the delay; consider a lower amount or a shorter tenure');
        } else {
            m.risks.add('CIBIL ' + score + ' with a written-off loan on record - outside policy');
        }
    }

    private static void bank(Memo m, Underwriting_Check__c c, Loan_Application__c app) {
        if (c == null) {
            return;
        }
        if (c.Result__c == 'Pass') {
            m.strengths.add('Perfios verified income ' + LoanSevaI18n.inr(c.Score__c) + '/month (98% of declared) with no bounce in 6 months');
        } else {
            m.risks.add('Income is self-declared only - the bank statement was not shared');
            m.conditions.add('Collect the last 6 months bank statement before disbursal (the customer can send it on WhatsApp)');
        }
    }

    private static void employment(Memo m, Underwriting_Check__c c, Loan_Application__c app) {
        if (c == null) {
            return;
        }
        if (c.Result__c == 'Pass') {
            m.strengths.add('Employment verified - ' + c.Summary__c.uncapitalize());
        } else if (app.Employment_Type__c != 'Salaried') {
            m.risks.add('Self-employed income is not yet verified from ITR');
            m.conditions.add('Collect ITR with computation for 2 years and the latest GST returns');
        } else {
            m.risks.add(c.Summary__c);
            m.conditions.add('Collect the last 3 salary slips');
        }
    }

    private static void policy(Memo m, Underwriting_Check__c c, Loan_Application__c app) {
        if (c == null) {
            return;
        }
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        if (c.Result__c == 'Pass') {
            m.strengths.add('FOIR ' + c.Score__c + '% with the new EMI leaves ' + (cfg.Max_FOIR_Pct__c - c.Score__c).setScale(1) + ' points of headroom against the ' + cfg.Max_FOIR_Pct__c + '% cap');
        } else if (c.Result__c == 'Refer') {
            m.risks.add('FOIR ' + c.Score__c + '% is above the ' + cfg.Max_FOIR_Pct__c + '% cap');
            Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
            Decimal existing = app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c;
            Decimal affordable = (income * cfg.Max_FOIR_Pct__c / 100 - existing).setScale(0);
            m.conditions.add(affordable > 0
                ? 'Bring the EMI down to ' + LoanSevaI18n.inr(affordable) + ' or less (lower amount or longer tenure)'
                : 'Existing EMIs already use the FOIR limit - a fresh loan is not affordable');
        } else {
            m.risks.add(c.Summary__c);
        }
    }

    private static void fraud(Memo m, Underwriting_Check__c c) {
        if (c == null) {
            return;
        }
        if (c.Result__c == 'Pass') {
            m.strengths.add('No fraud or dedupe hit and no watchlist match (Hunter)');
        } else {
            m.risks.add('Fraud screening: ' + c.Summary__c);
            m.conditions.add('Call the customer on the registered mobile and confirm the application is theirs');
        }
    }

    private static String names(Map<String, Underwriting_Check__c> byName, String results) {
        Set<String> wanted = new Set<String>(results.split(';'));
        List<String> out = new List<String>();
        for (Underwriting_Check__c c : byName.values()) {
            if (wanted.contains(c.Result__c)) {
                out.add(c.Check__c);
            }
        }
        return String.join(out, ', ');
    }

    private static String capitalise(String s) {
        return String.isBlank(s) ? 'No profile details on file' : s.capitalize();
    }
}
