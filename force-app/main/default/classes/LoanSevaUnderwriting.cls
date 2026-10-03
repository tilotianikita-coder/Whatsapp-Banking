/**
 * Mock underwriting run on a submitted new-loan application: PAN (NSDL), credit bureau (CIBIL), bank statement
 * analysis (Perfios), employment (EPFO / GST), policy and FOIR, dedupe and fraud (Hunter). No external calls are
 * made: every check is deterministic so a demo can show each outcome on purpose (demo PANs in SETUP_STEPS.md),
 * and each one stores a full mock provider report (LoanSevaReport) for the RM. The provider names only label
 * what a real integration would call, each behind its own Named Credential.
 * Recommendation: any Fail -> Decline; any Refer or Pending -> Refer; else Approve. The RM makes the decision.
 */
public with sharing class LoanSevaUnderwriting implements Queueable {
    public static final List<String> CATEGORY_A_EMPLOYERS = new List<String>{
        'infosys', 'tcs', 'tata consultancy', 'wipro', 'accenture', 'cognizant', 'hcl', 'tech mahindra', 'reliance',
        'google', 'microsoft', 'amazon', 'ibm', 'deloitte', 'capgemini', 'larsen', 'l&t', 'kotak'
    };
    private static final List<String> LENDERS = new List<String>{ 'ICICI Bank', 'Axis Bank', 'SBI Card', 'Bajaj Finance', 'IDFC FIRST Bank', 'Kotak Mahindra Bank' };
    private static final List<String> BANKS = new List<String>{ 'ICICI Bank', 'Axis Bank', 'State Bank of India', 'Kotak Mahindra Bank' };
    private static final Set<String> DISPOSABLE_EMAIL = new Set<String>{ 'mailinator.com', 'yopmail.com', 'tempmail.com', '10minutemail.com', 'guerrillamail.com' };

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
            SELECT Id, Name, Applicant_Name__c, Mobile__c, Email__c, PAN__c, Date_Of_Birth__c, Monthly_Income__c, Existing_EMIs__c,
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

    private static Underwriting_Check__c check(String name, String provider, String result, Decimal score, String summary,
            List<String> details, LoanSevaReport report) {
        return new Underwriting_Check__c(
            Check__c = name, Provider__c = provider, Result__c = result, Score__c = score,
            Summary__c = summary, Details__c = String.join(details, '\n'), Report_Data__c = report.json()
        );
    }

    private static Integer panDigits(String pan) {
        return pan != null && pan.length() >= 9 && pan.substring(5, 9).isNumeric() ? Integer.valueOf(pan.substring(5, 9)) : 0;
    }

    private static String month(Integer monthsAgo) {
        return LoanSevaReport.formatDate(LoanSevaI18n.todayIst().addMonths(-monthsAgo), 'MMM yyyy');
    }

    private static String ordinal(Integer day) {
        return day + (day == 1 || day == 21 ? 'st' : day == 2 || day == 22 ? 'nd' : day == 3 || day == 23 ? 'rd' : 'th');
    }

    // ------------------------------------------------------------------ NSDL
    /** NSDL: valid format, 4th character P (individual), 5th character = surname initial. */
    @TestVisible
    private static Underwriting_Check__c panCheck(Loan_Application__c app) {
        String pan = app.PAN__c == null ? '' : app.PAN__c.toUpperCase();
        String name = app.Applicant_Name__c == null ? '' : app.Applicant_Name__c.normalizeSpace().toUpperCase();
        String provider = 'NSDL PAN (mock)';
        List<String> details = new List<String>{ 'PAN: ' + LoanSevaNewLoan.maskPan(pan), 'Name on application: ' + name };
        LoanSevaReport r = new LoanSevaReport().fact('PAN', LoanSevaNewLoan.maskPan(pan)).fact('Name on application', name);
        if (!LoanSevaNewLoan.PAN_FORMAT.matcher(pan).matches()) {
            r.fact('NSDL response', 'Invalid PAN structure', LoanSevaReport.BAD).flag(LoanSevaReport.BAD, 'PAN does not match the AAAAA9999A format');
            return check('PAN Verification', provider, 'Fail', null, 'PAN format invalid', details, r);
        }
        String holder = pan.substring(3, 4);
        details.add('Holder type: ' + (holder == 'P' ? 'Individual (P)' : holder));
        r.fact('PAN status', 'E - Existing and valid', LoanSevaReport.GOOD)
            .fact('Holder type', holder == 'P' ? 'Individual (P)' : 'Non-individual (' + holder + ')', holder == 'P' ? LoanSevaReport.GOOD : LoanSevaReport.WARN);
        if (holder != 'P') {
            r.flag(LoanSevaReport.WARN, 'PAN belongs to a company, firm or trust - a personal loan needs an individual PAN');
            return check('PAN Verification', provider, 'Refer', null, 'PAN is not an individual PAN', details, r);
        }
        List<String> words = name.split(' ');
        String surnameInitial = words.isEmpty() || String.isBlank(words[words.size() - 1]) ? '' : words[words.size() - 1].left(1);
        Boolean match = pan.substring(4, 5) == surnameInitial;
        LoanSevaReport.Rng rng = new LoanSevaReport.Rng(pan);
        details.add('NSDL status: Valid, Aadhaar seeded: Yes');
        r.fact('Name match score', match ? (96 + rng.next(5)) + '%' : (31 + rng.next(15)) + '%', match ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('Date of birth match', app.Date_Of_Birth__c == null ? 'Not provided' : 'Yes', app.Date_Of_Birth__c == null ? LoanSevaReport.WARN : LoanSevaReport.GOOD)
            .fact('Aadhaar seeded', 'Yes (linked)', LoanSevaReport.GOOD)
            .fact('Last updated at NSDL', LoanSevaReport.formatDate(LoanSevaI18n.todayIst().addDays(-(200 + rng.next(900))), 'd MMM yyyy'));
        if (!match) {
            details.add('Surname initial on PAN: ' + pan.substring(4, 5) + ' / applicant: ' + surnameInitial);
            r.fact('Surname initial', 'PAN ' + pan.substring(4, 5) + ' / applicant ' + surnameInitial, LoanSevaReport.WARN)
                .flag(LoanSevaReport.WARN, 'Name on PAN does not match the applicant - compare with the PAN card image');
            return check('PAN Verification', provider, 'Refer', null, 'Name on PAN does not match the applicant - verify manually', details, r);
        }
        r.flag(LoanSevaReport.GOOD, 'PAN active, individual, Aadhaar-linked and the name matches');
        return check('PAN Verification', provider, 'Pass', 100, 'PAN valid, name matches', details, r);
    }

    // ------------------------------------------------------------------ CIBIL
    /**
     * CIBIL: the PAN's last character sets the demo band: Z -> 630 (fail), R -> 695 (refer),
     * otherwise 740-850 from the PAN digits (pass at Min_Cibil_Score__c and above).
     */
    @TestVisible
    private static Underwriting_Check__c bureauCheck(Loan_Application__c app) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        String pan = app.PAN__c == null ? '' : app.PAN__c.toUpperCase();
        Integer digits = panDigits(pan);
        String band = pan.right(1);
        Integer score = band == 'Z' ? 630 : band == 'R' ? 695 : 740 + Math.mod(digits * 37, 111);
        Decimal emis = app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c;
        Integer loans = emis > 0 ? 1 + Math.mod(digits, 3) : Math.mod(digits, 2);
        Integer historyYears = 2 + Math.mod(digits, 9);
        Integer enquiries = band == 'Z' ? 6 : Math.mod(digits, 3);
        LoanSevaReport.Rng rng = new LoanSevaReport.Rng(pan + 'cibil');
        Date today = LoanSevaI18n.todayIst();

        // Trade lines: declared EMIs spread over the active loans, one credit card, a few closed accounts.
        List<List<String>> lines = new List<List<String>>();
        Decimal sanctioned = 0;
        Decimal outstanding = 0;
        Decimal overdue = 0;
        for (Integer i = 0; i < loans; i++) {
            Decimal emi = (emis / loans).setScale(0);
            Decimal amount = Math.max(LoanSevaReport.roundTo(emi * 40, 10000), 50000.0);
            Decimal balance = LoanSevaReport.roundTo(amount * (25 + rng.next(55)) / 100, 1000);
            sanctioned += amount;
            outstanding += balance;
            lines.add(new List<String>{ rng.pick(LENDERS), rng.pick(new List<String>{ 'Personal Loan', 'Auto Loan', 'Consumer Durable' }),
                month(12 + rng.next(30)), LoanSevaI18n.inr(amount), LoanSevaI18n.inr(balance), emi == 0 ? '—' : LoanSevaI18n.inr(emi), 'Active', '0 (on time 12/12)' });
        }
        Decimal cardLimit = 100000 + 25000 * rng.next(9);
        Integer utilisation = band == 'R' ? 68 : 8 + rng.next(25);
        Decimal cardBalance = LoanSevaReport.roundTo(cardLimit * utilisation / 100, 500);
        sanctioned += cardLimit;
        outstanding += cardBalance;
        lines.add(new List<String>{ 'SBI Card', 'Credit Card', month(historyYears * 12), LoanSevaI18n.inr(cardLimit) + ' limit', LoanSevaI18n.inr(cardBalance), '—',
            'Active', band == 'R' ? '30 in ' + month(3) : '0 (on time 12/12)' });
        if (band == 'Z') {
            overdue = 48000 + 1000 * rng.next(40);
            lines.add(new List<String>{ 'Bajaj Finance', 'Personal Loan', month(30), LoanSevaI18n.inr(150000), LoanSevaI18n.inr(overdue), '—',
                'Written-off', '90+ (written off ' + month(8) + ')' });
        }
        Integer closed = 1 + rng.next(3);
        for (Integer i = 0; i < closed; i++) {
            lines.add(new List<String>{ rng.pick(LENDERS), rng.pick(new List<String>{ 'Consumer Durable', 'Personal Loan', 'Two-wheeler Loan' }),
                month(24 + rng.next(historyYears * 12)), LoanSevaI18n.inr(30000 + 10000 * rng.next(15)), LoanSevaI18n.inr(0), '—', 'Closed', '0' });
        }
        Integer active = loans + 1 + (band == 'Z' ? 1 : 0);

        List<List<String>> enquiryRows = new List<List<String>>{
            new List<String>{ LoanSevaReport.formatDate(today, 'd MMM yyyy'), 'Kotak Mahindra Bank', 'Personal Loan', LoanSevaI18n.inr(app.Offer_Amount__c), 'This application' }
        };
        List<Integer> daysAgo = new List<Integer>();
        for (Integer i = 0; i < enquiries; i++) {
            daysAgo.add(5 + rng.next(170));
        }
        daysAgo.sort();
        for (Integer d : daysAgo) {
            enquiryRows.add(new List<String>{ LoanSevaReport.formatDate(today.addDays(-d), 'd MMM yyyy'), rng.pick(LENDERS),
                rng.pick(new List<String>{ 'Personal Loan', 'Credit Card', 'Consumer Loan' }), LoanSevaI18n.inr(50000 + 25000 * rng.next(20)), '' });
        }

        List<String> details = new List<String>{
            'CIBIL score: ' + score,
            'Active accounts: ' + active + (emis > 0 ? ' (declared EMIs ' + LoanSevaI18n.inr(emis) + '/month)' : ''),
            'Enquiries (last 6 months): ' + enquiries,
            'Max DPD (last 24 months): ' + (band == 'Z' ? '60+' : band == 'R' ? '30' : '0'),
            'Written-off / settled: ' + (band == 'Z' ? 'Yes (1)' : 'None'),
            'Credit history: ' + historyYears + ' years'
        };
        String result = score >= cfg.Min_Cibil_Score__c ? 'Pass' : score >= cfg.Decline_Cibil_Score__c ? 'Refer' : 'Fail';
        String scoreTone = result == 'Pass' ? LoanSevaReport.GOOD : result == 'Refer' ? LoanSevaReport.WARN : LoanSevaReport.BAD;
        LoanSevaReport r = new LoanSevaReport()
            .fact('CIBIL score', score + ' / 900', scoreTone)
            .fact('Report date', LoanSevaReport.formatDate(today, 'd MMM yyyy'))
            .fact('Active accounts', active)
            .fact('Closed accounts', closed)
            .fact('Total sanctioned / limits', LoanSevaI18n.inr(sanctioned))
            .fact('Current balance', LoanSevaI18n.inr(outstanding))
            .fact('Amount overdue', LoanSevaI18n.inr(overdue), overdue > 0 ? LoanSevaReport.BAD : LoanSevaReport.GOOD)
            .fact('Card utilisation', utilisation + '%', utilisation > 50 ? LoanSevaReport.WARN : LoanSevaReport.GOOD)
            .fact('Enquiries (6 months)', enquiries, enquiries >= 4 ? LoanSevaReport.WARN : null)
            .fact('Max DPD (24 months)', band == 'Z' ? '90+' : band == 'R' ? '30' : '0', band == 'Z' ? LoanSevaReport.BAD : band == 'R' ? LoanSevaReport.WARN : LoanSevaReport.GOOD)
            .fact('Written-off / settled', band == 'Z' ? 'Yes (1)' : 'None', band == 'Z' ? LoanSevaReport.BAD : LoanSevaReport.GOOD)
            .fact('Credit history', historyYears + ' years')
            .table('Accounts', new List<String>{ 'Lender', 'Type', 'Opened', 'Sanctioned', 'Balance', 'EMI', 'Status', 'DPD (12 months)' }, lines)
            .table('Enquiries', new List<String>{ 'Date', 'Lender', 'Product', 'Amount', '' }, enquiryRows);
        if (band == 'Z') {
            r.flag(LoanSevaReport.BAD, 'Personal loan with Bajaj Finance written off in ' + month(8) + ' - ' + LoanSevaI18n.inr(overdue) + ' unpaid')
                .flag(LoanSevaReport.WARN, enquiries + ' enquiries in 6 months - credit hungry');
        } else if (band == 'R') {
            r.flag(LoanSevaReport.WARN, '30 days past due on the credit card in ' + month(3))
                .flag(LoanSevaReport.WARN, 'Card utilisation ' + utilisation + '% - above the 50% comfort level');
        } else {
            r.flag(LoanSevaReport.GOOD, 'No missed payment in 24 months across ' + (active + closed) + ' accounts')
                .flag(LoanSevaReport.GOOD, 'Card utilisation ' + utilisation + '% and ' + historyYears + ' years of credit history');
        }
        String summary = 'CIBIL ' + score + (result == 'Pass' ? ' - clean bureau record' : result == 'Refer' ? ' - below ' + cfg.Min_Cibil_Score__c + ', recent 30 DPD' : ' - below ' + cfg.Decline_Cibil_Score__c + ', write-off on record');
        return check('Credit Bureau', 'TransUnion CIBIL (mock)', result, score, summary, details, r);
    }

    // ------------------------------------------------------------------ Perfios
    /** Perfios: needs the bank statement; verified income is 98% of declared, no bounces. */
    @TestVisible
    private static Underwriting_Check__c bankStatementCheck(Loan_Application__c app, Set<String> docs) {
        Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        String provider = 'Perfios (mock)';
        if (!docs.contains('Bank Statement')) {
            LoanSevaReport pending = new LoanSevaReport()
                .fact('Declared income', LoanSevaI18n.inr(income) + '/month')
                .fact('Statement', 'Not received', LoanSevaReport.WARN)
                .flag(LoanSevaReport.WARN, 'Income is self-declared only - ask the customer to share the last 6 months statement on WhatsApp');
            return check('Bank Statement Analysis', provider, 'Pending', null, 'Bank statement not received - request it from the customer',
                new List<String>{ 'Declared income: ' + LoanSevaI18n.inr(income) + '/month', 'Statement: not received' }, pending);
        }
        Decimal verified = (income * 0.98).setScale(0, RoundingMode.HALF_UP);
        Boolean salaried = app.Employment_Type__c == 'Salaried';
        Decimal emis = app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c;
        Decimal averageBalance = (income * 0.6).setScale(0, RoundingMode.HALF_UP);
        LoanSevaReport.Rng rng = new LoanSevaReport.Rng(app.PAN__c + 'perfios');
        String bank = rng.pick(BANKS);
        List<Decimal> swing = salaried ? new List<Decimal>{ 1, 1, 1, 1, 1, 1 } : new List<Decimal>{ 1.08, 0.94, 1.02, 0.96, 1.05, 0.95 };
        Integer creditDay = 1 + rng.next(3);

        List<List<String>> months = new List<List<String>>();
        Decimal lowest = null;
        for (Integer i = 6; i >= 1; i--) {
            Decimal main = (verified * swing[6 - i]).setScale(0, RoundingMode.HALF_UP);
            Decimal other = LoanSevaReport.roundTo(verified * rng.next(9) / 100, 100);
            Decimal debits = LoanSevaReport.roundTo((main + other) * (86 + rng.next(12)) / 100, 100);
            Decimal avg = LoanSevaReport.roundTo(averageBalance * (90 + rng.next(21)) / 100, 100);
            lowest = lowest == null ? main : Math.min(lowest, main);
            months.add(new List<String>{ month(i), LoanSevaI18n.inr(main + other), LoanSevaI18n.inr(main), LoanSevaI18n.inr(debits),
                LoanSevaI18n.inr(emis), LoanSevaI18n.inr(avg), LoanSevaI18n.inr(LoanSevaReport.roundTo(avg * (12 + rng.next(15)) / 100, 100)), '0' });
        }
        List<List<String>> spends = new List<List<String>>();
        List<String> categories = new List<String>{ 'Rent / housing', 'Utilities and bills', 'Shopping and dining', 'Investments (SIP / RD)', 'Cash withdrawals' };
        List<Integer> shares = new List<Integer>{ 18 + rng.next(10), 3 + rng.next(3), 8 + rng.next(8), 5 + rng.next(8), 3 + rng.next(5) };
        for (Integer i = 0; i < categories.size(); i++) {
            spends.add(new List<String>{ categories[i], LoanSevaI18n.inr(LoanSevaReport.roundTo(verified * shares[i] / 100, 100)), shares[i] + '%' });
        }
        spends.add(new List<String>{ 'Loan EMIs (NACH)', LoanSevaI18n.inr(emis), verified == 0 ? '0%' : (emis / verified * 100).setScale(0) + '%' });
        Decimal newEmi = app.EMI__c == null ? 0 : app.EMI__c;
        Decimal bankingFoir = verified == 0 ? 100 : ((emis + newEmi) / verified * 100).setScale(1, RoundingMode.HALF_UP);
        Decimal cover = newEmi == 0 ? null : (averageBalance / newEmi).setScale(1, RoundingMode.HALF_UP);

        List<String> details = new List<String>{
            'Period analysed: last 6 months',
            (salaried ? 'Average salary credit: ' : 'Average business credits: ') + LoanSevaI18n.inr(verified) + '/month (' + (salaried ? 'employer ' + app.Company_Name__c : 'regular') + ')',
            'Average monthly balance: ' + LoanSevaI18n.inr(averageBalance),
            'EMI / NACH debits seen: ' + LoanSevaI18n.inr(emis) + '/month',
            'Cheque / ECS bounces: 0',
            'Gambling or high-risk transactions: none'
        };
        LoanSevaReport r = new LoanSevaReport()
            .fact('Bank', bank + ' · ' + (salaried ? 'Savings' : 'Current') + ' XXXX' + String.valueOf(1000 + rng.next(9000)))
            .fact('Account holder', app.Applicant_Name__c + ' (name matches)', LoanSevaReport.GOOD)
            .fact('Period', month(6) + ' - ' + month(1))
            .fact(salaried ? 'Average salary' : 'Average business credits', LoanSevaI18n.inr(verified) + '/month', LoanSevaReport.GOOD)
            .fact('Declared vs verified', LoanSevaI18n.inr(income) + ' / ' + LoanSevaI18n.inr(verified) + ' (98%)')
            .fact(salaried ? 'Salary credited' : 'Lowest month', salaried
                ? 'Every month, ' + ordinal(creditDay) + ' to ' + ordinal(creditDay + 1) + ' (' + app.Company_Name__c + ')'
                : LoanSevaI18n.inr(lowest))
            .fact('Average balance', LoanSevaI18n.inr(averageBalance))
            .fact('Banking FOIR (with new EMI)', bankingFoir + '%', bankingFoir > 50 ? LoanSevaReport.WARN : LoanSevaReport.GOOD)
            .fact('Cheque / ECS bounces', '0', LoanSevaReport.GOOD)
            .fact('High-risk transactions', 'None (gambling, crypto, loan apps)', LoanSevaReport.GOOD)
            .table('Monthly summary', new List<String>{ 'Month', 'Credits', salaried ? 'Salary' : 'Business credits', 'Debits', 'EMI / NACH', 'Avg balance', 'Min balance', 'Bounces' }, months)
            .table('Spend pattern (average per month)', new List<String>{ 'Category', 'Amount', 'Of income' }, spends)
            .flag(LoanSevaReport.GOOD, salaried ? 'Salary from ' + app.Company_Name__c + ' credited every month for 6 months' : 'Steady business credits - the lowest month is ' + LoanSevaI18n.inr(lowest))
            .flag(LoanSevaReport.GOOD, 'No cheque or ECS bounce in 6 months');
        if (cover != null) {
            r.flag(cover >= 2 ? LoanSevaReport.GOOD : LoanSevaReport.WARN, 'Average balance covers the new EMI ' + cover + ' times');
        }
        return check('Bank Statement Analysis', provider, 'Pass', verified,
            'Income verified ' + LoanSevaI18n.inr(verified) + '/month (98% of declared), no bounces', details, r);
    }

    // ------------------------------------------------------------------ EPFO / GST
    /** Category A employers pass; other salaried need salary slips; self-employed need ITR / GST review. */
    @TestVisible
    private static Underwriting_Check__c employmentCheck(Loan_Application__c app, Set<String> docs) {
        String company = app.Company_Name__c == null ? '' : app.Company_Name__c;
        String provider = 'Karza / EPFO (mock)';
        Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        LoanSevaReport.Rng rng = new LoanSevaReport.Rng(app.PAN__c + 'employment');
        Date today = LoanSevaI18n.todayIst();
        List<String> details = new List<String>{ 'Employment: ' + app.Employment_Type__c, (app.Employment_Type__c == 'Salaried' ? 'Employer: ' : 'Business: ') + company };
        LoanSevaReport r = new LoanSevaReport().fact('Employment', app.Employment_Type__c);
        if (app.Employment_Type__c != 'Salaried') {
            details.add('GST / ITR: not yet verified');
            List<List<String>> filings = new List<List<String>>();
            for (Integer i = 6; i >= 1; i--) {
                filings.add(new List<String>{ 'GSTR-3B ' + month(i), 'Filed', LoanSevaReport.formatDate(today.addMonths(-i + 1).toStartOfMonth().addDays(17 + rng.next(4)), 'd MMM yyyy') });
            }
            r.fact('Business', company)
                .fact('GSTIN', '27' + LoanSevaNewLoan.maskPan(app.PAN__c) + '1Z' + rng.next(10) + ' · Active', LoanSevaReport.GOOD)
                .fact('Registered since', LoanSevaReport.formatDate(today.addMonths(-(30 + rng.next(60))), 'MMM yyyy'))
                .fact('Annual turnover (GST)', LoanSevaI18n.inr(LoanSevaReport.roundTo(income * 12 * (3 + rng.next(3)), 10000)))
                .fact('ITR (2 years)', 'Not yet verified', LoanSevaReport.WARN)
                .table('GST filings', new List<String>{ 'Return', 'Status', 'Filed on' }, filings)
                .flag(LoanSevaReport.GOOD, 'GST returns filed on time for 6 months')
                .flag(LoanSevaReport.WARN, 'Collect ITR with computation for 2 years to confirm income');
            return check('Employment Verification', provider, 'Refer', null, 'Self-employed - verify ITR and GST returns (2 years)', details, r);
        }
        Boolean categoryA = false;
        for (String employer : CATEGORY_A_EMPLOYERS) {
            if (company.toLowerCase().contains(employer)) {
                categoryA = true;
            }
        }
        details.add('Employer category: ' + (categoryA ? 'A' : 'B'));
        details.add('EPFO UAN: active, last contribution this month');
        Decimal share = LoanSevaReport.roundTo(Math.min(income * 0.4, 50000.0) * 0.12, 10);
        List<List<String>> contributions = new List<List<String>>();
        for (Integer i = 6; i >= 1; i--) {
            contributions.add(new List<String>{ month(i), LoanSevaI18n.inr(share), LoanSevaI18n.inr(share),
                'Credited ' + LoanSevaReport.formatDate(today.addMonths(-i + 1).toStartOfMonth().addDays(9 + rng.next(5)), 'd MMM') });
        }
        Integer tenureMonths = 14 + rng.next(70);
        Boolean slips = docs.contains('Salary Slips');
        r.fact('Employer', company)
            .fact('Employer category', categoryA ? 'A (listed / MNC)' : 'B', categoryA ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('EPFO establishment', 'MH/BAN/' + String.valueOf(10000 + rng.next(89999)) + ' · ' + company.toUpperCase())
            .fact('UAN', 'XXXXXXXX' + String.valueOf(1000 + rng.next(9000)) + ' · Active', LoanSevaReport.GOOD)
            .fact('With this employer since', LoanSevaReport.formatDate(today.addMonths(-tenureMonths), 'MMM yyyy') + ' (' + (tenureMonths / 12) + ' yr ' + Math.mod(tenureMonths, 12) + ' mo)', LoanSevaReport.GOOD)
            .fact('Salary slips', slips ? 'Received' : 'Not received', slips ? LoanSevaReport.GOOD : (categoryA ? null : LoanSevaReport.WARN))
            .table('PF contributions', new List<String>{ 'Month', 'Employee share', 'Employer share', 'Status' }, contributions)
            .flag(LoanSevaReport.GOOD, 'PF contributions credited every month for 6 months');
        if (categoryA) {
            r.flag(LoanSevaReport.GOOD, company + ' is a category A employer');
            return check('Employment Verification', provider, 'Pass', null, 'Category A employer, EPFO contributions current', details, r);
        }
        if (slips) {
            details.add('Salary slips: received');
            r.flag(LoanSevaReport.GOOD, 'Salary slips received - net pay in line with declared income');
            return check('Employment Verification', provider, 'Pass', null, 'Employer verified via EPFO and salary slips', details, r);
        }
        details.add('Salary slips: not received');
        r.flag(LoanSevaReport.WARN, 'Category B employer - salary slips needed to confirm net pay');
        return check('Employment Verification', provider, 'Refer', null, 'Category B employer - salary slips needed', details, r);
    }

    // ------------------------------------------------------------------ Policy
    /** Age at application and at maturity, minimum income, FOIR including the new EMI. */
    @TestVisible
    private static Underwriting_Check__c policyCheck(Loan_Application__c app) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Date today = LoanSevaI18n.todayIst();
        Integer tenure = app.Tenure_Months__c == null ? 0 : app.Tenure_Months__c.intValue();
        Integer age = app.Date_Of_Birth__c == null ? null : LoanSevaNewLoan.ageOn(app.Date_Of_Birth__c, today);
        Integer ageAtMaturity = age == null ? null : LoanSevaNewLoan.ageOn(app.Date_Of_Birth__c, today.addMonths(tenure));
        Decimal income = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        Decimal existing = app.Existing_EMIs__c == null ? 0 : app.Existing_EMIs__c;
        Decimal newEmi = app.EMI__c == null ? 0 : app.EMI__c;
        Decimal emis = existing + newEmi;
        Decimal foir = income == 0 ? 100 : (emis / income * 100).setScale(1, RoundingMode.HALF_UP);
        Decimal amount = app.Offer_Amount__c == null ? 0 : app.Offer_Amount__c;
        Decimal maxAmount = Math.min(cfg.New_Loan_Max_Amount__c, income * cfg.New_Loan_Income_Multiple__c);
        List<String> details = new List<String>{
            'Age: ' + age + ' (min ' + cfg.Min_Age__c + '), at maturity: ' + ageAtMaturity + ' (max ' + cfg.Max_Age_At_Maturity__c + ')',
            'Declared income: ' + LoanSevaI18n.inr(income) + ' (min ' + LoanSevaI18n.inr(cfg.New_Loan_Min_Income__c) + ')',
            'FOIR with new EMI: ' + foir + '% (max ' + cfg.Max_FOIR_Pct__c + '%)'
        };
        Boolean ageOk = age != null && age >= cfg.Min_Age__c;
        Boolean maturityOk = ageAtMaturity == null || ageAtMaturity <= cfg.Max_Age_At_Maturity__c;
        Boolean incomeOk = income >= cfg.New_Loan_Min_Income__c;
        Boolean foirOk = foir <= cfg.Max_FOIR_Pct__c;
        List<String> fails = new List<String>();
        if (!ageOk) {
            fails.add('below minimum age');
        }
        if (!maturityOk) {
            fails.add('age at maturity above ' + cfg.Max_Age_At_Maturity__c);
        }
        if (!incomeOk) {
            fails.add('income below minimum');
        }
        LoanSevaReport r = new LoanSevaReport()
            .fact('Proposed EMI', LoanSevaI18n.inr(newEmi) + ' × ' + tenure + ' months')
            .fact('Existing EMIs', LoanSevaI18n.inr(existing))
            .fact('Total obligations', LoanSevaI18n.inr(emis))
            .fact('Income left after EMIs', LoanSevaI18n.inr(income - emis), income - emis < 25000 ? LoanSevaReport.WARN : LoanSevaReport.GOOD)
            .fact('FOIR', foir + '% (max ' + cfg.Max_FOIR_Pct__c + '%)', foirOk ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('Loan to income', income == 0 ? '—' : (amount / income).setScale(1) + '× monthly income')
            .table('Policy grid', new List<String>{ 'Parameter', 'Applicant', 'Policy', 'Result' }, new List<List<String>>{
                new List<String>{ 'Age at application', age == null ? 'Not given' : String.valueOf(age), 'min ' + cfg.Min_Age__c, ageOk ? 'Pass' : 'Fail' },
                new List<String>{ 'Age at maturity', ageAtMaturity == null ? '—' : String.valueOf(ageAtMaturity), 'max ' + cfg.Max_Age_At_Maturity__c, maturityOk ? 'Pass' : 'Fail' },
                new List<String>{ 'Monthly income', LoanSevaI18n.inr(income), 'min ' + LoanSevaI18n.inr(cfg.New_Loan_Min_Income__c), incomeOk ? 'Pass' : 'Fail' },
                new List<String>{ 'FOIR with new EMI', foir + '%', 'max ' + cfg.Max_FOIR_Pct__c + '%', foirOk ? 'Pass' : 'Refer' },
                new List<String>{ 'Loan amount', LoanSevaI18n.inr(amount), 'max ' + LoanSevaI18n.inr(maxAmount), amount <= maxAmount ? 'Pass' : 'Refer' }
            });
        if (!fails.isEmpty()) {
            r.flag(LoanSevaReport.BAD, 'Outside credit policy: ' + String.join(fails, ', '));
            return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Fail', foir, 'Outside policy: ' + String.join(fails, ', '), details, r);
        }
        if (!foirOk) {
            r.flag(LoanSevaReport.WARN, 'FOIR ' + foir + '% is above ' + cfg.Max_FOIR_Pct__c + '% - a lower amount or longer tenure would bring it within policy');
            return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Refer', foir, 'FOIR ' + foir + '% above ' + cfg.Max_FOIR_Pct__c + '%', details, r);
        }
        r.flag(LoanSevaReport.GOOD, 'Within credit policy with ' + (cfg.Max_FOIR_Pct__c - foir).setScale(1) + ' points of FOIR headroom');
        return check('Policy & FOIR', 'Kotak credit policy (mock)', 'Pass', foir, 'Within policy - age ' + age + ', FOIR ' + foir + '%', details, r);
    }

    // ------------------------------------------------------------------ Hunter
    /** The same PAN on another application with a different mobile, or a disposable email, is referred. */
    @TestVisible
    private static Underwriting_Check__c dedupeCheck(Loan_Application__c app) {
        List<Loan_Application__c> others = String.isBlank(app.PAN__c) ? new List<Loan_Application__c>() : [
            SELECT Name, Mobile__c FROM Loan_Application__c
            WHERE PAN__c = :app.PAN__c AND Id != :app.Id AND Mobile__c != :app.Mobile__c LIMIT 5
        ];
        String domain = app.Email__c == null || !app.Email__c.contains('@') ? '' : app.Email__c.substringAfter('@').toLowerCase();
        Boolean disposable = DISPOSABLE_EMAIL.contains(domain);
        LoanSevaReport.Rng rng = new LoanSevaReport.Rng(app.PAN__c + 'hunter');
        List<String> names = new List<String>();
        for (Loan_Application__c o : others) {
            names.add(o.Name);
        }
        Integer hits = (others.isEmpty() ? 0 : 1) + (disposable ? 1 : 0);
        Integer score = 6 + rng.next(14) + 35 * hits;
        List<List<String>> rules = new List<List<String>>{
            new List<String>{ 'PAN-MOB-01', 'Same PAN on another application with a different mobile', others.isEmpty() ? 'Clear' : 'Hit: ' + String.join(names, ', ') },
            new List<String>{ 'MOB-VEL-02', 'Mobile used on 3+ applications in 90 days', 'Clear' },
            new List<String>{ 'EML-DSP-03', 'Disposable or temporary email domain', disposable ? 'Hit: ' + domain : 'Clear' },
            new List<String>{ 'ADR-VEL-04', 'Address used by 3+ unrelated applicants', 'Clear' },
            new List<String>{ 'EMP-NEG-05', 'Employer on the negative list', 'Clear' },
            new List<String>{ 'DOC-TMP-06', 'Document metadata edited after creation', 'Clear' },
            new List<String>{ 'BUR-INC-07', 'Bureau identity inconsistent with application', 'Clear' }
        };
        List<List<String>> watchlists = new List<List<String>>{
            new List<String>{ 'RBI wilful defaulters (CRILC)', 'No match' },
            new List<String>{ 'Kotak internal negative list', 'No match' },
            new List<String>{ 'UN / OFAC sanctions', 'No match' },
            new List<String>{ 'Politically exposed persons', 'No match' }
        };
        List<String> details = new List<String>{ 'Internal dedupe on PAN and mobile', 'Fraud / negative list: no match' };
        LoanSevaReport r = new LoanSevaReport()
            .fact('Hunter fraud score', score + ' / 100', hits == 0 ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('Risk band', hits == 0 ? 'Low' : 'Medium', hits == 0 ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('Rules evaluated', rules.size())
            .fact('Rules hit', hits, hits == 0 ? LoanSevaReport.GOOD : LoanSevaReport.WARN)
            .fact('Watchlists', 'No match on ' + watchlists.size(), LoanSevaReport.GOOD)
            .table('Fraud rules', new List<String>{ 'Rule', 'Description', 'Result' }, rules)
            .table('Watchlist screening', new List<String>{ 'List', 'Result' }, watchlists);
        if (!others.isEmpty()) {
            details.add('Same PAN, different mobile: ' + String.join(names, ', '));
            r.flag(LoanSevaReport.WARN, 'PAN already used on ' + String.join(names, ', ') + ' with a different mobile - confirm the customer owns this number');
        }
        if (disposable) {
            details.add('Disposable email domain: ' + domain);
            r.flag(LoanSevaReport.WARN, 'Email uses a disposable domain (' + domain + ') - ask for a permanent email');
        }
        if (hits > 0) {
            return check('Dedupe & Fraud', 'Hunter (mock)', 'Refer', hits,
                others.isEmpty() ? 'Disposable email domain - ask for a permanent email' : 'PAN used on another application with a different mobile', details, r);
        }
        r.flag(LoanSevaReport.GOOD, 'No fraud rule hit and no watchlist match');
        return check('Dedupe & Fraud', 'Hunter (mock)', 'Pass', 0, 'No duplicate or fraud-list match', details, r);
    }
}
