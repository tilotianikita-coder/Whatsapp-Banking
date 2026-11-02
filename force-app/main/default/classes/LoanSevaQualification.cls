/**
 * Lead-stage qualification, run during the WhatsApp journey once the customer has answered the bureau consent
 * question (asked right after PAN for a new loan, after loan confirmation for a Top-Up), again when the questions are
 * done, and at drop-off. The RM sees the result as stage gates on the Lead.
 *
 *   Gate             Provider                   Needs                     Knock-out (lead Unqualified, no RM task)
 *   Serviceability   LoanSeva_Region__mdt       PIN code                  PIN outside the serviceable regions
 *   Consent          the customer               -                         -
 *   Dedupe & Fraud   Hunter                     PAN                       internal negative list / watchlist match
 *   Credit Bureau    CIBIL soft pull            PAN and consent           score below Decline_Cibil_Score__c, write-off
 *   Income & FOIR    Perfios or declared        income, EMIs (or CIBIL)   income below minimum, EMIs above Max_FOIR_Pct__c
 *   Employment       Karza / EPFO / GST         employment and company    -
 *
 * Cheapest first: once a gate knocks the lead out, the providers after it are not called. A gate whose inputs aren't
 * shared yet stays Pending and is not penalised. A Top-Up customer is already a Kotak customer: only consent, fraud
 * and the bureau refresh apply.
 *
 * Credit score, 0-100, scaled over the gates that have data (so missing data lowers confidence, not the score):
 *   CIBIL 40 (780+ 40 | 750+ 34 | 720+ 28 | 650+ 15) | FOIR 25 (<20% 25 | <40% 18 | within max 8) |
 *   employment 15 (Pass 15 | Refer 8) | fraud 10 (Pass 10 | Refer 3) | bank statement verified 10.
 *
 * A CIBIL pull for the same PAN within Cache_Days__c (LoanSeva_Provider__mdt.CIBIL) is reused here and by underwriting,
 * so the customer sees one enquiry. Providers with Callout__c run only in this class's queueable; inline runs (drop-off,
 * voice notes) use their cached result or leave the gate Pending.
 *
 * Without sharing: the agent user reads earlier pulls across customers for the cache and updates RM-owned Leads.
 */
public without sharing class LoanSevaQualification implements Queueable, Database.AllowsCallouts {
    public static final String GATE_SERVICEABILITY = 'Serviceability';
    public static final String GATE_CONSENT = 'Consent';
    public static final String GATE_FRAUD = 'Dedupe & Fraud';
    public static final String GATE_BUREAU = 'Credit Bureau';
    public static final String GATE_INCOME = 'Income & FOIR';
    public static final String GATE_EMPLOYMENT = 'Employment';
    public static final List<String> GATES = new List<String>{
        GATE_SERVICEABILITY, GATE_CONSENT, GATE_FRAUD, GATE_BUREAU, GATE_INCOME, GATE_EMPLOYMENT
    };
    public static final String QUALIFIED = 'Qualified';
    public static final String IN_PROGRESS = 'In Progress';
    public static final String KNOCKED_OUT = 'Knocked Out';
    public static final String CONSENT_GIVEN = 'Given';
    public static final String CONSENT_SKIPPED = 'Skipped';
    private static final Set<String> PULLED = new Set<String>{ 'Pass', 'Refer', 'Fail' };

    public class Outcome {
        public List<Qualification_Check__c> checks = new List<Qualification_Check__c>();
        public String status = IN_PROGRESS;
        public String gate;
        public String knockout;
        public Decimal cibil;
        public Decimal eligibility;
        public Credit credit = new Credit();

        public Boolean knockedOut() {
            return status == KNOCKED_OUT;
        }

        /** For the Lead and the RM: "Qualified", "Knocked out at Credit Bureau", "Waiting at Income & FOIR". */
        public String stageGate() {
            return status == QUALIFIED ? 'Qualified' : status == KNOCKED_OUT ? 'Knocked out at ' + gate : 'Waiting at ' + gate;
        }
    }

    public class Credit {
        public Integer points = 0;
        public Integer available = 0;
        public List<String> lines = new List<String>();

        /** Out of 100 over the data available; null when no gate has data yet. */
        public Integer score() {
            return available == 0 ? null : (points * 100.0 / available).round(System.RoundingMode.HALF_UP).intValue();
        }

        public String confidence() {
            return available >= 80 ? 'High' : available >= 40 ? 'Medium' : 'Low';
        }

        public String detail() {
            return String.join(lines, '\n') + '\nCredit score: ' + (score() == null ? 'no data yet' : score() + '/100 (' + confidence() + ' confidence, '
                + available + ' of 100 points of data)');
        }

        private void add(String label, Integer pts, Integer max) {
            points += pts;
            available += max;
            lines.add(label + ': ' + pts + '/' + max);
        }
    }

    private final Id journeyId;

    public LoanSevaQualification(Id journeyId) {
        this.journeyId = journeyId;
    }

    public void execute(QueueableContext context) {
        run(journeyId, true);
    }

    /**
     * Runs in the background so the customer's reply isn't held up. Inside a queueable (a voice note) it runs inline
     * with the providers that make no callouts: that queueable's one child job sends the customer's reply.
     */
    public static void start(Loan_Journey__c j) {
        if (j == null || j.Id == null || String.isBlank(j.Bureau_Consent__c)) {
            return;
        }
        if (!System.isQueueable() && !System.isFuture() && !System.isBatch() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new LoanSevaQualification(j.Id));
        } else {
            Outcome o = run(j.Id, false);
            if (o != null) {
                apply(j, o);
            }
        }
    }

    /** Evaluates, replaces the journey's checks, and updates the journey and its Lead. Never throws. */
    public static Outcome run(Id journeyId, Boolean allowCallouts) {
        try {
            Loan_Journey__c j = LoanSevaJourneyService.byId(journeyId);
            if (j == null) {
                return null;
            }
            Outcome o = evaluate(j, allowCallouts);
            save(new List<Loan_Journey__c>{ j }, new List<Outcome>{ o });
            Loan_Journey__c changes = new Loan_Journey__c(Id = j.Id);
            apply(changes, o);
            update changes;
            for (Lead l : [SELECT Id, Status, LoanSeva_Serviceable__c FROM Lead WHERE Id = :j.Lead__c AND IsConverted = FALSE]) {
                fillLead(l, j, o, LoanSevaLeadScoring.score(j));
                if (o.knockedOut()) {
                    l.Status = LoanSevaLeadService.STATUS_UNQUALIFIED;
                }
                update l;
            }
            return o;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoanSeva qualification failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return null;
        }
    }

    /** Qualification fields on the journey (in memory). */
    public static void apply(Loan_Journey__c j, Outcome o) {
        j.Qualification_Status__c = o.status;
        j.Qualification_Gate__c = o.gate == null ? null : o.gate.abbreviate(80);
        j.Knockout_Reason__c = o.knockout == null ? null : o.knockout.abbreviate(255);
        j.Credit_Score__c = o.credit.score();
        j.CIBIL_Score__c = o.cibil;
        j.Indicative_Eligibility__c = o.eligibility;
        j.Qualified_At__c = Datetime.now();
    }

    /**
     * Scores, grade and stage gate on the Lead (in memory): the intent score, the credit score and the two combined.
     * The combined score is their average once the credit score has Medium confidence (40+ points of data), so a credit
     * score built on fraud and employment alone doesn't lift the rating; until then it is the intent score.
     */
    public static void fillLead(Lead l, Loan_Journey__c j, Outcome o, LoanSevaLeadScoring.Score intent) {
        Integer credit = o.credit.score();
        Integer combined = credit == null || o.credit.available < 40
            ? intent.points
            : ((intent.points + credit) / 2.0).round(System.RoundingMode.HALF_UP).intValue();
        l.LoanSeva_Score__c = intent.points;
        l.LoanSeva_Score_Detail__c = intent.detail().abbreviate(2000);
        l.LoanSeva_Credit_Score__c = credit;
        l.LoanSeva_Combined_Score__c = combined;
        l.Rating = o.knockedOut() ? 'Cold' : LoanSevaLeadScoring.rating(combined);
        l.LoanSeva_CIBIL_Score__c = o.cibil;
        l.LoanSeva_Eligibility__c = o.knockedOut() ? null : o.eligibility;
        l.LoanSeva_Stage_Gate__c = o.stageGate().abbreviate(120);
        l.LoanSeva_Bureau_Consent__c = j.Bureau_Consent__c;
    }

    /** Replaces each journey's checks with its outcome's, linked to the journey's Lead. */
    public static void save(List<Loan_Journey__c> journeys, List<Outcome> outcomes) {
        Set<Id> ids = new Set<Id>();
        List<Qualification_Check__c> rows = new List<Qualification_Check__c>();
        for (Integer i = 0; i < journeys.size(); i++) {
            ids.add(journeys[i].Id);
            for (Qualification_Check__c c : outcomes[i].checks) {
                c.Loan_Journey__c = journeys[i].Id;
                c.Lead__c = journeys[i].Lead__c;
                rows.add(c);
            }
        }
        delete [SELECT Id FROM Qualification_Check__c WHERE Loan_Journey__c IN :ids];
        insert rows;
    }

    // ------------------------------------------------------------------ Evaluation
    /** Runs the gates in order. No DML, so the providers' callouts can follow the queries. */
    public static Outcome evaluate(Loan_Journey__c j, Boolean allowCallouts) {
        Outcome o = new Outcome();
        Boolean topUp = !LoanSevaJourneyService.isNewLoan(j);
        String pan = topUp ? kycPan(j) : j.PAN__c;
        Loan_Application__c subject = subject(j, pan);
        Set<String> docs = documents(j);
        Datetime now = Datetime.now();

        add(o, topUp ? pass(GATE_SERVICEABILITY, 'Existing customer', 'LoanSeva regions', 'Existing Kotak customer') : serviceability(j));
        add(o, consent(j));

        // Dedupe & fraud: internal data, no consent needed
        if (!topUp && String.isBlank(pan)) {
            add(o, pending(GATE_FRAUD, 'Dedupe and fraud screening', 'PAN not shared yet'));
        } else {
            add(o, provider(o, GATE_FRAUD, LoanSevaProviders.HUNTER, allowCallouts, subject, docs, null));
        }

        // Bureau soft pull: only with consent; reused for 30 days
        if (j.Bureau_Consent__c == CONSENT_SKIPPED) {
            add(o, row(GATE_BUREAU, 'CIBIL soft pull', 'TransUnion CIBIL', 'Skipped', 'Customer skipped consent: the bureau is pulled when the application is submitted'));
        } else if (j.Bureau_Consent__c != CONSENT_GIVEN) {
            add(o, pending(GATE_BUREAU, 'CIBIL soft pull', 'Waiting for the customer\'s consent'));
        } else if (!topUp && String.isBlank(pan)) {
            add(o, pending(GATE_BUREAU, 'CIBIL soft pull', 'PAN not shared yet'));
        } else {
            Qualification_Check__c cached = cachedBureau(pan);
            add(o, cached != null && !o.knockedOut() ? reuse(cached) : provider(o, GATE_BUREAU, LoanSevaProviders.CIBIL, allowCallouts, subject, docs, pan));
        }
        Qualification_Check__c bureau = o.checks[o.checks.size() - 1];
        if (PULLED.contains(bureau.Result__c)) {
            o.cibil = bureau.Score__c;
        }

        if (!topUp) {
            add(o, o.knockedOut() ? notRun(o, GATE_INCOME, 'Income and FOIR') : income(o, j, bureau, subject, docs, allowCallouts));
            if (String.isBlank(j.Employment_Type__c) || String.isBlank(j.Company_Name__c)) {
                add(o, pending(GATE_EMPLOYMENT, 'Employment verification', 'Employment and employer not shared yet'));
            } else {
                add(o, provider(o, GATE_EMPLOYMENT, LoanSevaProviders.KARZA, allowCallouts, subject, docs, null));
            }
        }

        // Status, gate and score
        Boolean waiting = false;
        for (Integer i = 0; i < o.checks.size(); i++) {
            Qualification_Check__c c = o.checks[i];
            c.Sort_Order__c = i + 1;
            c.PAN__c = c.Gate__c == GATE_BUREAU || c.Gate__c == GATE_FRAUD ? (String.isBlank(pan) ? null : pan.toUpperCase()) : null;
            if (c.Run_At__c == null) {
                c.Run_At__c = now;
            }
            if (c.Knockout__c && o.status != KNOCKED_OUT) {
                o.status = KNOCKED_OUT;
                o.gate = c.Gate__c;
                o.knockout = c.Summary__c;
            }
            if (!waiting && (c.Result__c == 'Pending' || c.Result__c == 'Skipped')) {
                waiting = true;
                if (o.gate == null) {
                    o.gate = c.Gate__c;
                }
            }
        }
        if (o.status != KNOCKED_OUT && !waiting) {
            o.status = QUALIFIED;
            o.gate = null;
        }
        if (o.knockedOut()) {
            o.eligibility = null;
        }
        o.credit = credit(o.checks);
        return o;
    }

    /** Credit score from saved or fresh checks (also used by the Lead card). */
    public static Credit credit(List<Qualification_Check__c> checks) {
        Credit c = new Credit();
        for (Qualification_Check__c q : checks) {
            Boolean has = PULLED.contains(q.Result__c);
            if (q.Gate__c == GATE_BUREAU && has && q.Score__c != null) {
                Decimal s = q.Score__c;
                c.add('CIBIL ' + s.intValue(), s >= 780 ? 40 : s >= 750 ? 34 : s >= 720 ? 28 : s >= 650 ? 15 : 0, 40);
            } else if (q.Gate__c == GATE_INCOME && has && q.Score__c != null) {
                LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
                Decimal foir = q.Score__c;
                c.add('Existing EMIs ' + foir + '% of income', q.Result__c == 'Fail' ? 0 : foir < 20 ? 25 : foir < 40 ? 18 : foir <= cfg.Max_FOIR_Pct__c ? 8 : 0, 25);
                if (q.Check__c != null && q.Check__c.contains('Perfios')) {
                    c.add('Income verified from the bank statement', 10, 10);
                }
            } else if (q.Gate__c == GATE_EMPLOYMENT && has) {
                c.add('Employment ' + (q.Result__c == 'Pass' ? 'verified' : 'to verify'), q.Result__c == 'Pass' ? 15 : q.Result__c == 'Refer' ? 8 : 0, 15);
            } else if (q.Gate__c == GATE_FRAUD && has) {
                c.add('Fraud and dedupe ' + (q.Result__c == 'Pass' ? 'clear' : q.Result__c == 'Refer' ? 'flag to check' : 'hit'), q.Result__c == 'Pass' ? 10 : q.Result__c == 'Refer' ? 3 : 0, 10);
            }
        }
        return c;
    }

    /** The latest CIBIL pull for this PAN within the cache window, from any journey; null if none. */
    public static Qualification_Check__c cachedBureau(String pan) {
        Integer days = LoanSevaProviders.cacheDays(LoanSevaProviders.CIBIL);
        if (String.isBlank(pan) || days <= 0) {
            return null;
        }
        Datetime since = Datetime.now().addDays(-days);
        List<Qualification_Check__c> rows = [
            SELECT Check__c, Provider__c, Result__c, Score__c, Summary__c, Details__c, Report_Data__c, Request_Id__c, Run_At__c, Knockout__c
            FROM Qualification_Check__c
            WHERE Gate__c = :GATE_BUREAU AND PAN__c = :pan.toUpperCase() AND Result__c IN ('Pass', 'Refer', 'Fail') AND Run_At__c >= :since
            ORDER BY Run_At__c DESC LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // ------------------------------------------------------------------ Gates
    private static Qualification_Check__c serviceability(Loan_Journey__c j) {
        if (String.isBlank(j.PIN_Code__c)) {
            return pending(GATE_SERVICEABILITY, 'PIN code serviceability', 'PIN code not shared yet');
        }
        LoanSevaServiceability.Region region = LoanSevaServiceability.forPin(j.PIN_Code__c);
        LoanSevaReport r = new LoanSevaReport().fact('PIN code', j.PIN_Code__c).fact('Region', region.name, region.serviceable ? LoanSevaReport.GOOD : LoanSevaReport.BAD);
        if (!region.serviceable) {
            Qualification_Check__c c = row(GATE_SERVICEABILITY, 'PIN code serviceability', 'LoanSeva regions', 'Fail', 'PIN ' + j.PIN_Code__c + ' is outside the serviceable regions (' + region.name + ')');
            c.Knockout__c = true;
            c.Report_Data__c = r.flag(LoanSevaReport.BAD, 'Kotak does not offer Personal Loans at this PIN code').json();
            return c;
        }
        Qualification_Check__c c = pass(GATE_SERVICEABILITY, 'PIN code serviceability', 'LoanSeva regions', region.name + ' is serviceable');
        c.Report_Data__c = r.flag(LoanSevaReport.GOOD, 'Served by the ' + region.name + ' team').json();
        return c;
    }

    private static Qualification_Check__c consent(Loan_Journey__c j) {
        String at = j.Bureau_Consent_At__c == null ? '' : ' on ' + j.Bureau_Consent_At__c.format('d MMM yyyy, h:mm a', 'Asia/Kolkata');
        if (j.Bureau_Consent__c == CONSENT_GIVEN) {
            return pass(GATE_CONSENT, 'Bureau consent', 'WhatsApp', 'Customer agreed to a soft credit check' + at);
        }
        if (j.Bureau_Consent__c == CONSENT_SKIPPED) {
            return row(GATE_CONSENT, 'Bureau consent', 'WhatsApp', 'Skipped', 'Customer skipped the soft credit check' + at);
        }
        return pending(GATE_CONSENT, 'Bureau consent', 'Not asked yet');
    }

    /** Declared (or bank-statement verified) income against existing EMIs, declared or from CIBIL; sets the indicative eligibility. */
    private static Qualification_Check__c income(Outcome o, Loan_Journey__c j, Qualification_Check__c bureau, Loan_Application__c subject,
            Set<String> docs, Boolean allowCallouts) {
        Decimal income = subject.Monthly_Income__c;
        if (income == null) {
            return pending(GATE_INCOME, 'Income and FOIR', 'Monthly income not shared yet');
        }
        Boolean pulled = PULLED.contains(bureau.Result__c);
        Decimal emis = j.Existing_EMIs__c != null ? j.Existing_EMIs__c : pulled ? 0 : null;
        if (emis == null) {
            return pending(GATE_INCOME, 'Income and FOIR', 'Existing EMIs not shared yet, and no bureau report to read them from');
        }
        String emiSource = j.Existing_EMIs__c == null ? 'CIBIL: no running EMI' : pulled ? 'declared, matches CIBIL' : 'declared';
        String check = 'Income and FOIR (declared income)';
        String provider = 'Kotak credit policy';
        Underwriting_Check__c bank;
        if (docs.contains('Bank Statement')) {
            bank = call(LoanSevaProviders.PERFIOS, allowCallouts, subject, docs);
            if (bank != null && bank.Result__c == 'Pass' && bank.Score__c != null) {
                income = bank.Score__c;
                check = 'Income and FOIR (Perfios bank statement)';
                provider = bank.Provider__c;
            }
        }
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Decimal foir = income <= 0 ? 100 : (emis * 100 / income).setScale(1, RoundingMode.HALF_UP);
        Boolean incomeOk = income >= cfg.New_Loan_Min_Income__c;
        Boolean foirOk = foir <= cfg.Max_FOIR_Pct__c;
        LoanSevaEligibilityEngine.Result offer = incomeOk && foirOk ? LoanSevaEligibilityEngine.evaluateNew(income, emis, j.Employment_Type__c, null, null) : null;
        o.eligibility = offer != null && offer.eligible ? offer.maxEligible : null;

        LoanSevaReport r = new LoanSevaReport()
            .fact(provider == 'Kotak credit policy' ? 'Declared income' : 'Verified income', LoanSevaI18n.inr(income) + '/month', incomeOk ? LoanSevaReport.GOOD : LoanSevaReport.BAD)
            .fact('Existing EMIs', LoanSevaI18n.inr(emis) + '/month (' + emiSource + ')')
            .fact('FOIR before the new loan', foir + '% (max ' + cfg.Max_FOIR_Pct__c + '%)', foirOk ? LoanSevaReport.GOOD : LoanSevaReport.BAD)
            .fact('Indicative eligibility', o.eligibility == null ? '—' : 'Up to ' + LoanSevaI18n.inr(o.eligibility) + ' (subject to verification)');
        Qualification_Check__c c;
        if (!incomeOk || !foirOk) {
            String why = !incomeOk
                ? 'Income ' + LoanSevaI18n.inr(income) + ' below the minimum ' + LoanSevaI18n.inr(cfg.New_Loan_Min_Income__c)
                : 'Existing EMIs ' + foir + '% of income, above ' + cfg.Max_FOIR_Pct__c + '%';
            c = row(GATE_INCOME, check, provider, 'Fail', why);
            c.Knockout__c = true;
            r.flag(LoanSevaReport.BAD, why + ' - outside credit policy');
        } else {
            c = pass(GATE_INCOME, check, provider, 'FOIR ' + foir + '% on ' + LoanSevaI18n.inr(income) + '/month'
                + (o.eligibility == null ? '' : '; indicative eligibility ' + LoanSevaI18n.inr(o.eligibility)));
            r.flag(LoanSevaReport.GOOD, 'Within FOIR policy with ' + (cfg.Max_FOIR_Pct__c - foir).setScale(1) + ' points of headroom');
        }
        c.Score__c = foir;
        c.Details__c = 'Income: ' + LoanSevaI18n.inr(income) + '/month\nExisting EMIs: ' + LoanSevaI18n.inr(emis) + ' (' + emiSource + ')\nFOIR: ' + foir + '%';
        c.Report_Data__c = bank != null && provider != 'Kotak credit policy' ? bank.Report_Data__c : r.json();
        return c;
    }

    /** A provider gate, unless an earlier gate knocked the lead out (then it isn't called). */
    private static Qualification_Check__c provider(Outcome o, String gate, String provider, Boolean allowCallouts,
            Loan_Application__c subject, Set<String> docs, String pan) {
        if (o.knockedOut()) {
            return notRun(o, gate, gate);
        }
        Underwriting_Check__c result = call(provider, allowCallouts, subject, docs);
        if (result == null) {
            return pending(gate, gate, 'Queued: ' + provider + ' runs in the background');
        }
        Qualification_Check__c c = row(gate, result.Check__c, result.Provider__c, result.Result__c, result.Summary__c);
        c.Score__c = result.Score__c;
        c.Details__c = result.Details__c;
        c.Report_Data__c = result.Report_Data__c;
        c.Request_Id__c = provider.left(4).toUpperCase() + '-' + Datetime.now().formatGmt('yyMMddHHmmss') + '-' + String.valueOf(o.checks.size() + 1).leftPad(2, '0');
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        c.Knockout__c = result.Result__c == 'Fail'
            && (gate == GATE_FRAUD || gate == GATE_BUREAU && (result.Score__c == null || result.Score__c < cfg.Decline_Cibil_Score__c || String.valueOf(result.Details__c).contains('Written-off / settled: Yes')));
        return c;
    }

    /** Calls the provider; null if it calls out and this run can't. */
    private static Underwriting_Check__c call(String provider, Boolean allowCallouts, Loan_Application__c subject, Set<String> docs) {
        if (LoanSevaProviders.makesCallouts(provider) && !allowCallouts) {
            return null;
        }
        if (provider == LoanSevaProviders.CIBIL) {
            return LoanSevaProviders.bureau().pull(subject);
        }
        if (provider == LoanSevaProviders.HUNTER) {
            return LoanSevaProviders.fraud().screen(subject);
        }
        if (provider == LoanSevaProviders.KARZA) {
            return LoanSevaProviders.employment().verify(subject, docs);
        }
        return LoanSevaProviders.bankStatements().analyse(subject, docs);
    }

    private static Qualification_Check__c reuse(Qualification_Check__c cached) {
        Qualification_Check__c c = row(GATE_BUREAU, cached.Check__c, cached.Provider__c, cached.Result__c, cached.Summary__c);
        c.Score__c = cached.Score__c;
        c.Details__c = cached.Details__c;
        c.Report_Data__c = cached.Report_Data__c;
        c.Request_Id__c = cached.Request_Id__c;
        c.Run_At__c = cached.Run_At__c;
        c.Knockout__c = cached.Knockout__c;
        return c;
    }

    private static Qualification_Check__c notRun(Outcome o, String gate, String check) {
        return row(gate, check, null, 'Skipped', 'Not run: knocked out at ' + o.gate);
    }

    private static Qualification_Check__c pending(String gate, String check, String summary) {
        return row(gate, check, null, 'Pending', summary);
    }

    private static Qualification_Check__c pass(String gate, String check, String provider, String summary) {
        return row(gate, check, provider, 'Pass', summary);
    }

    private static Qualification_Check__c row(String gate, String check, String provider, String result, String summary) {
        return new Qualification_Check__c(
            Gate__c = gate, Check__c = check == null ? null : check.abbreviate(80), Provider__c = provider == null ? null : provider.abbreviate(80),
            Result__c = result, Summary__c = summary == null ? null : summary.abbreviate(255), Knockout__c = false
        );
    }

    /** Adds the check; a knock-out sets the gate at once so the gates after it are not run. */
    private static void add(Outcome o, Qualification_Check__c c) {
        o.checks.add(c);
        if (c.Knockout__c && o.status != KNOCKED_OUT) {
            o.status = KNOCKED_OUT;
            o.gate = c.Gate__c;
            o.knockout = c.Summary__c;
        }
    }

    // ------------------------------------------------------------------ Inputs
    /** The journey as an unsaved application, the subject every provider takes. */
    private static Loan_Application__c subject(Loan_Journey__c j, String pan) {
        Decimal income = j.Monthly_Income__c;
        if (income == null && String.isNotBlank(j.Income_Bucket__c)) {
            income = LoanSevaConfig.incomeValues().get(j.Income_Bucket__c);
        }
        return new Loan_Application__c(
            Applicant_Name__c = j.Customer_Name__c, Mobile__c = j.Mobile__c, Email__c = j.Email__c, PAN__c = pan,
            Date_Of_Birth__c = j.Date_Of_Birth__c, Monthly_Income__c = income, Existing_EMIs__c = j.Existing_EMIs__c,
            Employment_Type__c = j.Employment_Type__c, Company_Name__c = j.Company_Name__c, Offer_Amount__c = j.Desired_Amount__c
        );
    }

    /** A Top-Up customer's PAN from KYC on file (an earlier application); null pulls on the KYC record itself. */
    private static String kycPan(Loan_Journey__c j) {
        if (String.isNotBlank(j.PAN__c)) {
            return j.PAN__c;
        }
        if (j.Contact__c == null) {
            return null;
        }
        for (Loan_Application__c a : [
            SELECT PAN__c FROM Loan_Application__c WHERE Contact__c = :j.Contact__c AND PAN__c != null ORDER BY CreatedDate DESC LIMIT 1
        ]) {
            return a.PAN__c;
        }
        return null;
    }

    private static Set<String> documents(Loan_Journey__c j) {
        Set<String> docs = new Set<String>();
        if (j.Loan_Application__c != null) {
            for (Loan_Document__c d : [SELECT Document_Type__c FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c]) {
                docs.add(d.Document_Type__c);
            }
        }
        return docs;
    }
}
