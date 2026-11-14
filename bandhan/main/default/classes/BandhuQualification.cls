/**
 * Lead-stage qualification for Bandhu card prospects (new to bank), shown to the RM as stage gates on the Lead.
 * Runs whenever the prospect's Lead is refreshed (OTP verification, recommendation, submission, drop-off).
 *
 *   Gate              Provider                     Needs                       Knock-out (Lead Unqualified, no RM task / nudge)
 *   Serviceability    Bandhu_Region__mdt           PIN code                    PIN outside the serviceable regions
 *   Consent           the customer                 -                           -
 *   Dedupe & Fraud    Bandhan fraud & dedupe       PAN                         internal negative list
 *   Credit Bureau     CIBIL soft pull              PAN and bureau consent      score below Decline_Cibil__c (write-off)
 *   Income            Account Aggregator / salary  monthly income              below the lowest card's minimum
 *   Employment        declared                     employment and company      -
 *   Card Eligibility  BandhuEligibility            income (and CIBIL)          no card at all
 * Cheapest first: once a gate knocks the lead out, the gates after it are not run. A gate whose inputs aren't shared
 * yet stays Pending and is not penalised.
 *
 * Credit score (0-100), scaled over the gates that have data, so missing data lowers confidence, not the score:
 *   CIBIL 40 (780+ 40 | 760+ 34 | 740+ 28 | 720+ 22 | 700+ 16 | 650+ 8) | income 20 (verified 20 | declared 10) |
 *   fraud 15 (Pass 15 | Refer 5) | employment 10 (salaried 10 | self-employed 6) | best eligible card 15 (Lumina 15 ...).
 * Intent score (0-100): income 25 | employment 10 | monthly card spend 10 | age 5 | journey depth 40 | needs shared 10.
 * Rating from the average of the two: 70+ Hot, 40-69 Warm, below 40 Cold; a knocked-out lead is Cold.
 */
public inherited sharing class BandhuQualification {
    public static final String GATE_SERVICEABILITY = 'Serviceability';
    public static final String GATE_CONSENT = 'Consent';
    public static final String GATE_FRAUD = 'Dedupe & Fraud';
    public static final String GATE_BUREAU = 'Credit Bureau';
    public static final String GATE_INCOME = 'Income';
    public static final String GATE_EMPLOYMENT = 'Employment';
    public static final String GATE_ELIGIBILITY = 'Card Eligibility';
    public static final List<String> GATES = new List<String>{
        GATE_SERVICEABILITY, GATE_CONSENT, GATE_FRAUD, GATE_BUREAU, GATE_INCOME, GATE_EMPLOYMENT, GATE_ELIGIBILITY };
    public static final Integer HOT = 70;
    public static final Integer WARM = 40;

    public class Region {
        public String name;
        public Boolean serviceable;
        public String rmUsername;
    }

    public class Outcome {
        public List<Bandhu_Lead_Check__c> checks = new List<Bandhu_Lead_Check__c>();
        public Integer intent = 0;
        public Integer credit;
        public List<String> intentLines = new List<String>();
        public String knockedOutAt;
        public String knockoutReason;
        public Region region;
        public String confidence;

        public Boolean knockedOut() {
            return knockedOutAt != null;
        }

        public Integer combined() {
            return credit == null ? intent : Math.round((intent + credit) / 2.0);
        }

        public String rating() {
            return knockedOut() ? 'Cold' : combined() >= HOT ? 'Hot' : combined() >= WARM ? 'Warm' : 'Cold';
        }

        public String stageGate() {
            if (knockedOut()) {
                return 'Knocked out at ' + knockedOutAt;
            }
            for (Bandhu_Lead_Check__c c : checks) {
                if (c.Result__c == 'Pending') {
                    return 'Waiting at ' + c.Gate__c;
                }
            }
            return 'Qualified';
        }

        public String detail() {
            List<String> lines = new List<String>{ 'Intent ' + intent + '/100' };
            lines.addAll(intentLines);
            lines.add('Credit ' + (credit == null ? 'n/a (no gate with data yet)' : credit + '/100') + ' · confidence ' + confidence);
            for (Bandhu_Lead_Check__c c : checks) {
                if (c.Max_Points__c != null && c.Max_Points__c > 0 && c.Result__c != 'Pending' && c.Result__c != 'Skipped') {
                    lines.add('  ' + c.Gate__c + ': ' + c.Points__c.intValue() + '/' + c.Max_Points__c.intValue() + ' (' + c.Summary__c + ')');
                }
            }
            return String.join(lines, '\n');
        }
    }

    public static Outcome evaluate(Card_Journey__c j) {
        Outcome o = new Outcome();
        o.region = region(j.PIN_Code__c);
        add(o, serviceability(j, o.region));
        add(o, o.knockedOut() ? notRun(GATE_CONSENT) : consent(j));
        add(o, o.knockedOut() ? notRun(GATE_FRAUD) : fraud(j));
        add(o, o.knockedOut() ? notRun(GATE_BUREAU) : bureau(j));
        add(o, o.knockedOut() ? notRun(GATE_INCOME) : income(j));
        add(o, o.knockedOut() ? notRun(GATE_EMPLOYMENT) : employment(j));
        add(o, o.knockedOut() ? notRun(GATE_ELIGIBILITY) : eligibility(j));
        Integer pts = 0;
        Integer max = 0;
        Integer withData = 0;
        for (Bandhu_Lead_Check__c c : o.checks) {
            c.Card_Journey__c = j.Id;
            c.Lead__c = j.Lead__c;
            if (c.Max_Points__c != null && c.Max_Points__c > 0 && c.Result__c != 'Pending' && c.Result__c != 'Skipped') {
                pts += c.Points__c == null ? 0 : c.Points__c.intValue();
                max += c.Max_Points__c.intValue();
                withData++;
            }
        }
        o.credit = max == 0 ? null : Math.round(pts * 100.0 / max);
        o.confidence = withData >= 4 ? 'High' : withData >= 2 ? 'Medium' : 'Low';
        intent(o, j);
        return o;
    }

    // ------------------------------------------------------------------ gates
    private static Bandhu_Lead_Check__c serviceability(Card_Journey__c j, Region r) {
        if (String.isBlank(j.PIN_Code__c)) {
            return gate(GATE_SERVICEABILITY, 'PIN code serviceability', 'Bandhan regions', 'Pending', null, 0, 0, 'PIN code not shared yet', null);
        }
        if (!r.serviceable) {
            Bandhu_Lead_Check__c c = gate(GATE_SERVICEABILITY, 'PIN code serviceability', 'Bandhan regions', 'Fail', null, 0, 0,
                'PIN ' + j.PIN_Code__c + ' (' + r.name + ') is outside the card footprint', null);
            c.Knockout__c = true;
            return c;
        }
        return gate(GATE_SERVICEABILITY, 'PIN code serviceability', 'Bandhan regions', 'Pass', null, 0, 0,
            'PIN ' + j.PIN_Code__c + ' · ' + r.name, 'Region: ' + r.name);
    }

    private static Bandhu_Lead_Check__c consent(Card_Journey__c j) {
        if (!j.Consent__c) {
            return gate(GATE_CONSENT, 'DPDP and bureau consent', 'Customer', 'Pending', null, 0, 0, 'DPDP consent not given yet', null);
        }
        if (j.Bureau_Consent__c) {
            return gate(GATE_CONSENT, 'DPDP and bureau consent', 'Customer', 'Pass', null, 0, 0, 'DPDP consent and soft credit check consent given', null);
        }
        Boolean asked = j.Step__c != null && !new Set<String>{ 'menu', 'consent', 'name', 'mobile', 'otp', 'spend', 'monthly_spend', 'fee',
            'employment', 'income', 'company', 'pan', 'dob', 'pincode', 'bureau' }.contains(j.Step__c);
        return asked
            ? gate(GATE_CONSENT, 'DPDP and bureau consent', 'Customer', 'Refer', null, 0, 0, 'Soft credit check skipped: the bureau is pulled on apply', null)
            : gate(GATE_CONSENT, 'DPDP and bureau consent', 'Customer', 'Pending', null, 0, 0, 'Soft credit check not asked yet', null);
    }

    private static Bandhu_Lead_Check__c fraud(Card_Journey__c j) {
        if (String.isBlank(j.PAN__c)) {
            return gate(GATE_FRAUD, 'Fraud & dedupe', 'Bandhan fraud & dedupe (mock)', 'Pending', null, 0, 15, 'PAN not shared yet', null);
        }
        BandhuProviders.Report r = BandhuProviders.fraud(j.PAN__c, j.Mobile__c, j.Card_Application__c);
        Bandhu_Lead_Check__c c = gate(GATE_FRAUD, 'Fraud & dedupe', r.provider, r.result, r.score, r.result == 'Pass' ? 15 : r.result == 'Refer' ? 5 : 0, 15, r.summary, null);
        c.Knockout__c = r.result == 'Fail';
        return c;
    }

    private static Bandhu_Lead_Check__c bureau(Card_Journey__c j) {
        BandhuBureau.Report report = BandhuBureau.fromJourney(j);
        if (report != null && (report.noHit || !BandhuBureau.assess(report).reviews.isEmpty() || report.maxDpd24 > 90)) {
            BandhuBureau.Assessment a = BandhuBureau.assess(report);
            Bandhu_Lead_Check__c c = gate(GATE_BUREAU, 'CIBIL soft pull', BandhuBureau.PROVIDER, a.result, report.score,
                a.result == 'Fail' ? 0 : report.noHit ? 8 : 10, 40, a.summary, String.join(report.lines(), '\n'));
            c.Knockout__c = a.result == 'Fail';
            return c;
        }
        if (j.CIBIL_Score__c == null) {
            return gate(GATE_BUREAU, 'CIBIL soft pull', 'TransUnion CIBIL (mock)', 'Pending', null, 0, 40,
                String.isBlank(j.PAN__c) ? 'PAN not shared yet' : j.Bureau_Consent__c ? 'Soft pull pending' : 'No soft-check consent yet', null);
        }
        Integer s = j.CIBIL_Score__c.intValue();
        Decimal decline = BandhuConfig.get().Decline_Cibil__c == null ? 650 : BandhuConfig.get().Decline_Cibil__c;
        Integer pts = s >= 780 ? 40 : s >= 760 ? 34 : s >= 740 ? 28 : s >= 720 ? 22 : s >= 700 ? 16 : s >= decline ? 8 : 0;
        String result = s >= 720 ? 'Pass' : s >= decline ? 'Refer' : 'Fail';
        Bandhu_Lead_Check__c c = gate(GATE_BUREAU, 'CIBIL soft pull', 'TransUnion CIBIL (mock)', result, s, pts, 40,
            'CIBIL ' + s + (result == 'Pass' ? ' - clean record' : result == 'Refer' ? ' - recent delays' : ' - below ' + decline.intValue() + ', write-off on record'), null);
        c.Knockout__c = result == 'Fail';
        return c;
    }

    private static Bandhu_Lead_Check__c income(Card_Journey__c j) {
        Decimal declared = j.Monthly_Income__c;
        if (declared == null) {
            return gate(GATE_INCOME, 'Monthly income', 'Declared', 'Pending', null, 0, 20, 'Income not shared yet', null);
        }
        Decimal floor = null;
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            if (c.Secured__c == true) {
                continue;   // the FD-backed card has no income floor; the gate is about unsecured cards
            }
            floor = floor == null || c.Min_Monthly_Income__c < floor ? c.Min_Monthly_Income__c : floor;
        }
        Decimal income = j.Verified_Income__c != null ? j.Verified_Income__c : declared;
        Boolean verified = j.Verified_Income__c != null;
        String provider = verified ? (j.Customer_Type__c == BandhuJourneyService.EXISTING ? 'Bandhan salary credits' : 'Account Aggregator (mock)') : 'Declared';
        if (floor != null && income < floor) {
            Bandhu_Lead_Check__c c = gate(GATE_INCOME, 'Monthly income', provider, 'Fail', income.intValue(), 0, 20,
                BandhuI18n.inr(income) + '/month, below the ' + BandhuI18n.inr(floor) + ' minimum for any card', null);
            c.Knockout__c = true;
            return c;
        }
        return gate(GATE_INCOME, 'Monthly income', provider, verified ? 'Pass' : 'Refer', income.intValue(), verified ? 20 : 10, 20,
            BandhuI18n.inr(income) + '/month ' + (verified ? 'verified' : 'declared, to verify'), null);
    }

    private static Bandhu_Lead_Check__c employment(Card_Journey__c j) {
        if (String.isBlank(j.Employment_Type__c) || String.isBlank(j.Company_Name__c)) {
            return gate(GATE_EMPLOYMENT, 'Employment', 'Declared', 'Pending', null, 0, 10, 'Employment not shared yet', null);
        }
        Boolean salaried = j.Employment_Type__c == 'Salaried';
        return gate(GATE_EMPLOYMENT, 'Employment', 'Declared', salaried ? 'Pass' : 'Refer', null, salaried ? 10 : 6, 10,
            j.Employment_Type__c + ' @ ' + j.Company_Name__c + (salaried ? '' : ' - verify ITR'), null);
    }

    private static Bandhu_Lead_Check__c eligibility(Card_Journey__c j) {
        if (j.Monthly_Income__c == null) {
            return gate(GATE_ELIGIBILITY, 'Card eligibility', 'Bandhu eligibility rules', 'Pending', null, 0, 15, 'Income not shared yet', null);
        }
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        if (out.best == null) {
            Bandhu_Lead_Check__c c = gate(GATE_ELIGIBILITY, 'Card eligibility', 'Bandhu eligibility rules', 'Fail', null, 0, 15,
                'Not eligible for any card: ' + out.blockedReason, null);
            c.Knockout__c = true;
            return c;
        }
        Integer top = 0;
        String topName;
        for (BandhuEligibility.Option opt : out.options) {
            if (opt.eligible && opt.card.Tier__c.intValue() > top) {
                top = opt.card.Tier__c.intValue();
                topName = opt.card.DeveloperName;
            }
        }
        Integer pts = new Map<Integer, Integer>{ 1 => 6, 2 => 9, 3 => 12, 4 => 15 }.get(top);
        return gate(GATE_ELIGIBILITY, 'Card eligibility', 'Bandhu eligibility rules', 'Pass', top, pts, 15,
            'Eligible up to ' + topName + ' · best fit ' + out.best.card.DeveloperName, 'Eligible: ' + String.join(out.eligibleNames(), ', '));
    }

    private static Bandhu_Lead_Check__c notRun(String g) {
        return gate(g, g, '-', 'Skipped', null, 0, 0, 'Not run: the lead is already knocked out', null);
    }

    private static Bandhu_Lead_Check__c gate(String g, String check, String provider, String result, Decimal score, Integer pts, Integer max,
            String summary, String details) {
        return new Bandhu_Lead_Check__c(Gate__c = g, Check__c = check, Provider__c = provider, Result__c = result, Score__c = score,
            Points__c = pts, Max_Points__c = max, Summary__c = summary == null ? null : summary.abbreviate(255), Details__c = details,
            Sort_Order__c = GATES.indexOf(g) + 1, Run_At__c = Datetime.now(), Knockout__c = false);
    }

    private static void add(Outcome o, Bandhu_Lead_Check__c c) {
        o.checks.add(c);
        if (c.Knockout__c && o.knockedOutAt == null) {
            o.knockedOutAt = c.Gate__c;
            o.knockoutReason = c.Summary__c;
        }
    }

    // ------------------------------------------------------------------ intent
    private static void intent(Outcome o, Card_Journey__c j) {
        Decimal income = j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c;
        Integer p = income == null ? 0 : income >= 200000 ? 25 : income >= 75000 ? 20 : income >= 40000 ? 15 : income >= 25000 ? 10 : 0;
        line(o, 'Monthly income ' + (income == null ? 'not shared' : BandhuI18n.inr(income)), p, 25);
        p = j.Employment_Type__c == 'Salaried' ? 10 : j.Employment_Type__c == 'Self-employed' ? 6 : 0;
        line(o, 'Employment ' + (j.Employment_Type__c == null ? 'not shared' : j.Employment_Type__c), p, 10);
        Decimal spend = j.Monthly_Spend__c;
        p = spend == null ? 0 : spend > 100000 ? 10 : spend >= 50000 ? 8 : spend >= 15000 ? 5 : 2;
        line(o, 'Monthly card spend ' + (spend == null ? 'not shared' : BandhuI18n.inrShort(spend)), p, 10);
        Integer age = BandhuJourneyService.age(j.Date_Of_Birth__c);
        p = age != null && age >= 21 && age <= 60 ? 5 : 0;
        line(o, 'Age ' + (age == null ? 'not shared' : String.valueOf(age)), p, 5);
        Integer done = BandhuJourneyService.fieldsDone(j);
        p = (j.OTP_Verified__c ? 5 : 0) + done * 2 + (j.Recommended_Card__c != null ? 10 : 0) + (j.Chosen_Card__c != null ? 5 : 0);
        line(o, 'Journey depth: ' + (j.OTP_Verified__c ? 'verified, ' : '') + done + '/10 details' + (j.Recommended_Card__c != null ? ', saw a recommendation' : '')
            + (j.Chosen_Card__c != null ? ', chose ' + j.Chosen_Card__c : ''), Math.min(40, p), 40);
        p = (String.isNotBlank(j.Spend_Focus__c) ? 5 : 0) + (String.isNotBlank(j.Fee_Preference__c) ? 5 : 0);
        line(o, 'Needs ' + (String.isBlank(j.Spend_Focus__c) ? 'not shared' : j.Spend_Focus__c.replace(';', ', ')), p, 10);
    }

    private static void line(Outcome o, String label, Integer pts, Integer max) {
        o.intent += pts;
        o.intentLines.add('  ' + label + ': ' + pts + '/' + max);
    }

    // ------------------------------------------------------------------ regions
    @TestVisible
    private static List<Bandhu_Region__mdt> regions;

    public static Region region(String pin) {
        if (regions == null) {
            regions = Bandhu_Region__mdt.getAll().values();
        }
        String digits = pin == null ? '' : pin.replaceAll('[^0-9]', '');
        Bandhu_Region__mdt best;
        Integer bestLength = -1;
        for (Bandhu_Region__mdt r : regions) {
            for (String prefix : String.isBlank(r.PIN_Prefixes__c) ? new List<String>() : r.PIN_Prefixes__c.split(',')) {
                prefix = prefix.trim();
                Integer len = prefix == '*' ? 0 : prefix.length();
                if (String.isNotBlank(digits) && (prefix == '*' || digits.startsWith(prefix)) && len > bestLength) {
                    best = r;
                    bestLength = len;
                }
            }
        }
        Region out = new Region();
        out.name = best == null ? (String.isBlank(digits) ? 'PIN not shared yet' : 'Outside the card footprint') : best.MasterLabel;
        out.serviceable = best == null ? String.isBlank(digits) : best.Serviceable__c;
        out.rmUsername = best == null ? null : best.RM_Username__c;
        return out;
    }
}
