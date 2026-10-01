/**
 * Mock underwriting run on a submitted new-loan application: PAN (NSDL), credit bureau (CIBIL), bank statement
 * analysis (Perfios), employment, policy and FOIR, dedupe and fraud. No external calls are made: every check is
 * deterministic so a demo can show each outcome on purpose (demo PANs in SETUP_STEPS.md). The provider names
 * only label what a real integration would call, each behind its own Named Credential.
 * Recommendation: any Fail -> Decline; any Refer or Pending -> Refer; else Approve. The RM makes the decision.
 */
public with sharing class LoanSevaUnderwriting implements Queueable {
    public static final List<String> CATEGORY_A_EMPLOYERS = new List<String>{
        'infosys', 'tcs', 'tata consultancy', 'wipro', 'accenture', 'cognizant', 'hcl', 'tech mahindra', 'reliance',
        'google', 'microsoft', 'amazon', 'ibm', 'deloitte', 'capgemini', 'larsen', 'l&t', 'kotak'
    };

    private final Id applicationId;

    public LoanSevaUnderwriting(Id applicationId) {
        this.applicationId = applicationId;
    }

    public void execute(QueueableContext context) {
        run(applicationId);
    }

    /** Runs asynchronously when possible, so the customer's WhatsApp reply isn't held up. */
    public static void start(Id applicationId) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new LoanSevaUnderwriting(applicationId));
        } else {
            run(applicationId);
        }
    }

    /** (Re-)runs every check, replacing earlier results, and stores the recommendation on the application. */
    public static void run(Id applicationId) {
        Loan_Application__c app = [
            SELECT Id, Name, Applicant_Name__c, Mobile__c, PAN__c, Date_Of_Birth__c, Monthly_Income__c, Existing_EMIs__c,
                Employment_Type__c, Company_Name__c, Offer_Amount__c, EMI__c, Tenure_Months__c, Status__c,
                (SELECT Document_Type__c FROM Loan_Documents__r)
            FROM Loan_Application__c WHERE Id = :applicationId
        ];
        try {
            delete [SELECT Id FROM Underwriting_Check__c WHERE Loan_Application__c = :applicationId];
            Set<String> docs = new Set<String>();
            for (Loan_Document__c d : app.Loan_Documents__r) {
                docs.add(d.Document_Type__c);
            }
            List<Underwriting_Check__c> checks = new List<Underwriting_Check__c>{
                panCheck(app), bureauCheck(app), bankStatementCheck(app, docs), employmentCheck(app, docs), policyCheck(app), dedupeCheck(app)
            };
            Datetime now = Datetime.now();
            Set<String> outcomes = new Set<String>();
            List<String> lines = new List<String>();
            for (Integer i = 0; i < checks.size(); i++) {
                Underwriting_Check__c c = checks[i];
                c.Loan_Application__c = app.Id;
                c.Sort_Order__c = i + 1;
                c.Run_At__c = now;
                c.Request_Id__c = c.Provider__c.left(4).toUpperCase().replaceAll('[^A-Z]', '') + '-' + now.formatGmt('yyMMddHHmmss') + '-' + String.valueOf(i + 1).leftPad(2, '0');
                c.Summary__c = c.Summary__c.abbreviate(255);
                outcomes.add(c.Result__c);
                lines.add(icon(c.Result__c) + ' ' + c.Check__c + ': ' + c.Result__c + ' - ' + c.Summary__c);
            }
            insert checks;
            String recommendation = outcomes.contains('Fail') ? 'Decline' : (outcomes.contains('Refer') || outcomes.contains('Pending')) ? 'Refer' : 'Approve';
            app.Recommendation__c = recommendation;
            app.CIBIL_Score__c = checks[1].Score__c;
            app.Underwriting_Status__c = 'Completed';
            app.Underwriting_Summary__c = 'Recommendation: ' + recommendation + '\n' + String.join(lines, '\n');
            if (app.Status__c == 'Application Submitted') {
                app.Status__c = 'Under Review';
            }
            update app;
        } catch (Exception e) {
            update new Loan_Application__c(Id = applicationId, Underwriting_Status__c = 'Error',
                Underwriting_Summary__c = ('Underwriting failed: ' + e.getMessage()).abbreviate(32000));
        }
    }

    private static String icon(String result) {
        return result == 'Pass' ? '✅' : result == 'Fail' ? '❌' : '⚠️';
    }

    private static Underwriting_Check__c check(String name, String provider, String result, Decimal score, String summary, List<String> details) {
        return new Underwriting_Check__c(
            Check__c = name, Provider__c = provider, Result__c = result, Score__c = score,
            Summary__c = summary, Details__c = String.join(details, '\n')
        );
    }

    /** NSDL: valid format, 4th character P (individual), 5th character = surname initial. */
    @TestVisible
    private static Underwriting_Check__c panCheck(Loan_Application__c app) {
        String pan = app.PAN__c == null ? '' : app.PAN__c.toUpperCase();
        String name = app.Applicant_Name__c == null ? '' : app.Applicant_Name__c.normalizeSpace().toUpperCase();
        List<String> details = new List<String>{ 'PAN: ' + LoanSevaNewLoan.maskPan(pan), 'Name on application: ' + name };
        if (!LoanSevaNewLoan.PAN_FORMAT.matcher(pan).matches()) {
            return check('PAN Verification', 'NSDL PAN (mock)', 'Fail', null, 'PAN format invalid', details);
        }
        details.add('Holder type: ' + (pan.substring(3, 4) == 'P' ? 'Individual (P)' : pan.substring(3, 4)));
        if (pan.substring(3, 4) != 'P') {
            return check('PAN Verification', 'NSDL PAN (mock)', 'Refer', null, 'PAN is not an individual PAN', details);
        }
        List<String> words = name.split(' ');
        String surnameInitial = words.isEmpty() || String.isBlank(words[words.size() - 1]) ? '' : words[words.size() - 1].left(1);
        details.add('NSDL status: Valid, Aadhaar seeded: Yes');
        if (pan.substring(4, 5) != surnameInitial) {
            details.add('Surname initial on PAN: ' + pan.substring(4, 5) + ' / applicant: ' + surnameInitial);
            return check('PAN Verification', 'NSDL PAN (mock)', 'Refer', null, 'Name on PAN does not match the applicant - verify manually', details);
        }
        return check('PAN Verification', 'NSDL PAN (mock)', 'Pass', 100, 'PAN valid, name matches', details);
    }

    /**
     * CIBIL: the PAN's last character sets the demo band: Z -> 630 (fail), R -> 695 (refer),
     * otherwise 740-850 from the PAN digits (pass at Min_Cibil_Score__c and above).
     */
    @TestVisible
    private static Underwriting_Check__c bureauCheck(Loan_Application__c app) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        String pan = app.PAN__c == null ? '' : app.PAN__c.toUpperCase();
        Integer digits = pan.length() >= 9 && pan.substring(5, 9).isNumeric() ? Integer.valueOf(pan.substring(5, 9)) : 0;
        String band = pan.right(1);
        Integer score = band == 'Z' ? 630 : band == 'R' ? 695 : 740 + Math.mod(digits * 37, 111);
        Decimal emis = app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c;
        Integer accounts = emis > 0 ? 1 + Math.mod(digits, 3) : Math.mod(digits, 2);
        List<String> details = new List<String>{
            'CIBIL score: ' + score,
            'Active accounts: ' + accounts + (emis > 0 ? ' (declared EMIs ' + LoanSevaI18n.inr(emis) + '/month)' : ''),
            'Enquiries (last 6 months): ' + (band == 'Z' ? 6 : Math.mod(digits, 3)),
            'Max DPD (last 24 months): ' + (band == 'Z' ? '60+' : band == 'R' ? '30' : '0'),
            'Written-off / settled: ' + (band == 'Z' ? 'Yes (1)' : 'None'),
            'Credit history: ' + (2 + Math.mod(digits, 9)) + ' years'
        };
        String result = score >= cfg.Min_Cibil_Score__c ? 'Pass' : score >= cfg.Decline_Cibil_Score__c ? 'Refer' : 'Fail';
        String summary = 'CIBIL ' + score + (result == 'Pass' ? ' - clean bureau record' : result == 'Refer' ? ' - below ' + cfg.Min_Cibil_Score__c + ', recent 30 DPD' : ' - below ' + cfg.Decline_Cibil_Score__c + ', write-off on record');
        return check('Credit Bureau', 'TransUnion CIBIL (mock)', result, score, summary, details);
    }

    /** Perfios: needs the bank statement; verified income is 98% of declared, no bounces. */
    @TestVisible
    private static Underwriting_Check__c bankStatementCheck(Loan_Application__c app, Set<String> docs) {
        Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        if (!docs.contains('Bank Statement')) {
            return check('Bank Statement Analysis', 'Perfios (mock)', 'Pending', null,
                'Bank statement not received - request it from the customer',
                new List<String>{ 'Declared income: ' + LoanSevaI18n.inr(income) + '/month', 'Statement: not received' });
        }
        Decimal verified = (income * 0.98).setScale(0, RoundingMode.HALF_UP);
        Boolean salaried = app.Employment_Type__c == 'Salaried';
        List<String> details = new List<String>{
            'Period analysed: last 6 months',
            (salaried ? 'Average salary credit: ' : 'Average business credits: ') + LoanSevaI18n.inr(verified) + '/month (' + (salaried ? 'employer ' + app.Company_Name__c : 'regular') + ')',
            'Average monthly balance: ' + LoanSevaI18n.inr((income * 0.6).setScale(0, RoundingMode.HALF_UP)),
            'EMI / NACH debits seen: ' + LoanSevaI18n.inr(app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c) + '/month',
            'Cheque / ECS bounces: 0',
            'Gambling or high-risk transactions: none'
        };
        return check('Bank Statement Analysis', 'Perfios (mock)', 'Pass', verified,
            'Income verified ' + LoanSevaI18n.inr(verified) + '/month (98% of declared), no bounces', details);
    }

    /** Category A employers pass; other salaried need salary slips; self-employed need ITR / GST review. */
    @TestVisible
    private static Underwriting_Check__c employmentCheck(Loan_Application__c app, Set<String> docs) {
        String company = app.Company_Name__c == null ? '' : app.Company_Name__c;
        List<String> details = new List<String>{ 'Employment: ' + app.Employment_Type__c, (app.Employment_Type__c == 'Salaried' ? 'Employer: ' : 'Business: ') + company };
        if (app.Employment_Type__c != 'Salaried') {
            details.add('GST / ITR: not yet verified');
            return check('Employment Verification', 'Karza / EPFO (mock)', 'Refer', null, 'Self-employed - verify ITR and GST returns (2 years)', details);
        }
        Boolean categoryA = false;
        for (String employer : CATEGORY_A_EMPLOYERS) {
            if (company.toLowerCase().contains(employer)) {
                categoryA = true;
            }
        }
        details.add('Employer category: ' + (categoryA ? 'A' : 'B'));
        details.add('EPFO UAN: active, last contribution this month');
        if (categoryA) {
            return check('Employment Verification', 'Karza / EPFO (mock)', 'Pass', null, 'Category A employer, EPFO contributions current', details);
        }
        if (docs.contains('Salary Slips')) {
            details.add('Salary slips: received');
            return check('Employment Verification', 'Karza / EPFO (mock)', 'Pass', null, 'Employer verified via EPFO and salary slips', details);
        }
        details.add('Salary slips: not received');
        return check('Employment Verification', 'Karza / EPFO (mock)', 'Refer', null, 'Category B employer - salary slips needed', details);
    }

    /** Age at application and at maturity, minimum income, FOIR including the new EMI. */
    @TestVisible
    private static Underwriting_Check__c policyCheck(Loan_Application__c app) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Date today = LoanSevaI18n.todayIst();
        Integer tenure = app.Tenure_Months__c == null ? 0 : app.Tenure_Months__c.intValue();
        Integer age = app.Date_Of_Birth__c == null ? null : LoanSevaNewLoan.ageOn(app.Date_Of_Birth__c, today);
        Integer ageAtMaturity = age == null ? null : LoanSevaNewLoan.ageOn(app.Date_Of_Birth__c, today.addMonths(tenure));
        Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        Decimal emis = (app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c) + (app.EMI__c == null ? 0 : app.EMI__c);
        Decimal foir = income == 0 ? 100 : (emis / income * 100).setScale(1, RoundingMode.HALF_UP);
        List<String> details = new List<String>{
            'Age: ' + age + ' (min ' + cfg.Min_Age__c + '), at maturity: ' + ageAtMaturity + ' (max ' + cfg.Max_Age_At_Maturity__c + ')',
            'Declared income: ' + LoanSevaI18n.inr(income) + ' (min ' + LoanSevaI18n.inr(cfg.New_Loan_Min_Income__c) + ')',
            'FOIR with new EMI: ' + foir + '% (max ' + cfg.Max_FOIR_Pct__c + '%)'
        };
        List<String> fails = new List<String>();
        if (age == null || age < cfg.Min_Age__c) {
            fails.add('below minimum age');
        }
        if (ageAtMaturity != null && ageAtMaturity > cfg.Max_Age_At_Maturity__c) {
            fails.add('age at maturity above ' + cfg.Max_Age_At_Maturity__c);
        }
        if (income < cfg.New_Loan_Min_Income__c) {
            fails.add('income below minimum');
        }
        if (!fails.isEmpty()) {
            return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Fail', foir, 'Outside policy: ' + String.join(fails, ', '), details);
        }
        if (foir > cfg.Max_FOIR_Pct__c) {
            return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Refer', foir, 'FOIR ' + foir + '% above ' + cfg.Max_FOIR_Pct__c + '%', details);
        }
        return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Pass', foir, 'Within policy - age ' + age + ', FOIR ' + foir + '%', details);
    }

    /** The same PAN on another application with a different mobile is referred. */
    @TestVisible
    private static Underwriting_Check__c dedupeCheck(Loan_Application__c app) {
        List<Loan_Application__c> others = String.isBlank(app.PAN__c) ? new List<Loan_Application__c>() : [
            SELECT Name, Mobile__c FROM Loan_Application__c
            WHERE PAN__c = :app.PAN__c AND Id != :app.Id AND Mobile__c != :app.Mobile__c LIMIT 5
        ];
        List<String> details = new List<String>{ 'Internal dedupe on PAN and mobile', 'Fraud / negative list: no match' };
        if (!others.isEmpty()) {
            List<String> names = new List<String>();
            for (Loan_Application__c o : others) {
                names.add(o.Name);
            }
            details.add('Same PAN, different mobile: ' + String.join(names, ', '));
            return check('Dedupe & Fraud', 'Hunter (mock)', 'Refer', others.size(), 'PAN used on another application with a different mobile', details);
        }
        return check('Dedupe & Fraud', 'Hunter (mock)', 'Pass', 0, 'No duplicate or fraud-list match', details);
    }
}
