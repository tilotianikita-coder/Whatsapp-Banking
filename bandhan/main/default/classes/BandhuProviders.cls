/**
 * Mock external services for the demo: CIBIL, PAN verification (NSDL), Aadhaar eKYC (UIDAI), Account Aggregator,
 * Video KYC, dedupe/fraud and card issuance. Deterministic on the PAN so a demo can be repeated:
 *   PAN ending Z -> CIBIL 630 (decline every card), Y -> 690 (Sparks on refer only), R -> 730 (refer for Flare / Lumina),
 *   X -> on the internal negative list; anything else 765-820. 4th character P = individual PAN.
 * Going live replaces each method with a callout behind the same signature.
 */
public inherited sharing class BandhuProviders {
    public class Report {
        public String result;      // Pass / Refer / Fail / Pending
        public Integer score;
        public String provider;
        public String summary;
        public List<String> details = new List<String>();
        public String data;        // raw report / analysis JSON, stored on the check
    }

    public static Integer cibil(String pan) {
        String p = pan == null ? '' : pan.toUpperCase();
        String last = p.right(1);
        if (last == 'Z') {
            return 630;
        }
        if (last == 'Y') {
            return 690;
        }
        if (last == 'R') {
            return 730;
        }
        Integer digits = p.length() >= 9 && p.substring(5, 9).isNumeric() ? Integer.valueOf(p.substring(5, 9)) : 0;
        return 765 + Math.mod(digits * 7, 56);
    }

    /** Hard pull at submission: the full report, assessed by BandhuBureau's rules. */
    public static Report bureau(String pan) {
        return bureauReport(BandhuBureau.pull(pan, 'Hard'));
    }

    public static Report bureauReport(BandhuBureau.Report b) {
        BandhuBureau.Assessment a = BandhuBureau.assess(b);
        Report r = new Report();
        r.provider = BandhuBureau.PROVIDER;
        r.score = b.score;
        r.result = a.result;
        r.summary = a.summary;
        r.details = b.lines();
        r.data = JSON.serialize(b, true);
        return r;
    }

    public static Report panCheck(String pan, String name) {
        Report r = new Report();
        r.provider = 'NSDL PAN (mock)';
        String p = pan == null ? '' : pan.toUpperCase();
        if (!Pattern.matches('[A-Z]{5}[0-9]{4}[A-Z]', p)) {
            r.result = 'Fail';
            r.summary = 'PAN format invalid';
            return r;
        }
        r.details.add('PAN: ' + BandhuI18n.maskPan(p) + ' · status: E (existing and valid)');
        r.details.add('Name on application: ' + (name == null ? '' : name.toUpperCase()));
        if (p.substring(3, 4) != 'P') {
            r.result = 'Refer';
            r.summary = 'Not an individual PAN';
        } else {
            r.result = 'Pass';
            r.summary = 'PAN valid, individual, Aadhaar-linked';
        }
        return r;
    }

    public static Report aadhaar(String last4, Boolean existing) {
        Report r = new Report();
        r.provider = existing ? 'Bandhan Bank KYC on file' : 'UIDAI Aadhaar eKYC (mock)';
        r.result = 'Pass';
        r.summary = existing ? 'Customer KYC already on file' : (last4 == null ? 'Aadhaar' : 'Aadhaar XXXX XXXX ' + last4) + ' eKYC: name and address matched';
        return r;
    }

    /** Account Aggregator (mock): verified monthly income is 96% of declared, rounded to ₹100. */
    public static Decimal verifiedIncome(Decimal declared) {
        return declared == null ? null : (declared * 0.96 / 100).round(System.RoundingMode.DOWN) * 100;
    }

    /** Income verification plus the AIS / GST cross-checks: a flagged cross-check refers. */
    public static Report income(Card_Journey__c j) {
        Report r = incomeSource(j);
        List<String> flags = new List<String>();
        for (BandhuRisk.IncomeCheck c : BandhuRisk.incomeChecks(j)) {
            r.details.addAll(c.lines);
            if (c.flagged) {
                flags.add(c.source);
            }
        }
        if (!flags.isEmpty() && r.result == 'Pass') {
            r.result = 'Refer';
            r.summary = (r.summary + ' · ' + String.join(flags, ', ') + ' disagree').abbreviate(255);
        }
        return r;
    }

    private static Report incomeSource(Card_Journey__c j) {
        Report r = new Report();
        if (j.Customer_Type__c == 'Existing' && j.Verified_Income__c != null) {
            r.provider = 'Bandhan Bank salary credits';
            r.result = 'Pass';
            r.summary = 'Salary credits ' + BandhuI18n.inr(j.Verified_Income__c) + '/month';
        } else if (BandhuCashFlow.fromJourney(j) != null) {
            BandhuCashFlow.Analysis a = BandhuCashFlow.fromJourney(j);
            r.provider = BandhuAccountAggregator.PROVIDER;
            r.result = a.anomalies.isEmpty() && a.netMonthlyIncome > 0 ? 'Pass' : 'Refer';
            r.summary = 'Verified ' + BandhuI18n.inr(a.netMonthlyIncome) + '/month from ' + a.months + ' months of statements · stability '
                + a.incomeStability + '/100 · FOIR ' + a.foirPct.intValue() + '%' + (a.anomalies.isEmpty() ? '' : ' · ' + a.anomalies.size() + ' flag(s) to review');
            r.details = a.summaryLines();
            r.data = j.AA_Insights__c;
        } else if (j.Verified_Income__c != null) {
            r.provider = 'Account Aggregator (mock)';
            r.result = 'Pass';
            r.summary = 'Verified ' + BandhuI18n.inr(j.Verified_Income__c) + '/month (declared ' + BandhuI18n.inr(j.Monthly_Income__c) + ')';
        } else {
            r.provider = 'Declared';
            r.result = 'Refer';
            r.summary = 'Income self-declared (' + BandhuI18n.inr(j.Monthly_Income__c) + '/month) - verify';
        }
        r.score = j.Verified_Income__c == null ? null : j.Verified_Income__c.intValue();
        return r;
    }

    /** Existing customers: tier, relationship and the bank's own repayment track; new to bank: no internal history. */
    public static Report dueDiligence(Card_Journey__c j) {
        Report r = new Report();
        r.provider = 'Bandhan core banking (mock)';
        BandhuCustomer.Insight i = j.Contact__c == null ? null : BandhuCustomer.forContact(j.Contact__c);
        if (i == null) {
            r.result = 'Pass';
            r.summary = 'New to bank: identity through PAN, Aadhaar eKYC and Video KYC; no internal history';
            return r;
        }
        r.details = i.lines();
        r.score = i.score;
        if (i.blocker != null) {
            r.result = 'Fail';
            r.summary = 'On hold: ' + i.blocker;
        } else if ((i.tier == BandhuCustomer.MICROFINANCE && i.maxDpd > 0) || i.maxDpd > 30) {
            r.result = 'Refer';
            r.summary = i.tier + ' customer with DPD ' + i.maxDpd + ' on a Bandhan loan in 12 months';
        } else {
            r.result = 'Pass';
            r.summary = i.tier + ' customer · relationship score ' + i.score + '/100 · ' + i.vintageMonths + ' months with Bandhan';
        }
        return r;
    }

    public static Report videoKyc(Card_Journey__c j) {
        Report r = new Report();
        r.provider = 'Video KYC (mock)';
        if (j.Customer_Type__c == 'Existing') {
            r.result = 'Pass';
            r.summary = 'Not needed - existing customer with full KYC';
        } else if (j.KYC_Status__c == 'Complete') {
            r.result = 'Pass';
            r.summary = 'Completed with the KYC officer; liveness and geo-tag passed';
        } else {
            r.result = 'Pending';
            r.summary = 'Video KYC not completed yet';
        }
        return r;
    }

    public static Report fraud(String pan, String mobile, Id applicationId) {
        Report r = new Report();
        r.provider = 'Bandhan fraud & dedupe (mock)';
        String p = pan == null ? '' : pan.toUpperCase();
        Integer others = [
            SELECT COUNT() FROM Card_Application__c
            WHERE PAN__c = :p AND Id != :applicationId AND Status__c IN ('Submitted', 'Under Review', 'Approved', 'Card Issued')
        ];
        if (p.right(1) == 'X') {
            r.result = 'Fail';
            r.summary = 'PAN on the internal negative list';
        } else if (others > 0) {
            r.result = 'Refer';
            r.summary = 'Another open card application on this PAN';
        } else {
            r.result = 'Pass';
            r.summary = 'No dedupe or watchlist match';
        }
        r.score = others;
        return r;
    }

    /** Virtual card number, masked: BIN prefix, then the last 4 digits (deterministic per application). */
    public static String issueCard(Card_Application__c app) {
        Bandhu_Config__mdt cfg = BandhuConfig.get();
        String bin = String.isBlank(cfg.Card_Bin__c) ? '524193' : cfg.Card_Bin__c;
        Integer seed = Math.abs(String.valueOf(app.Id).hashCode());
        String last4 = String.valueOf(1000 + Math.mod(seed, 9000));
        return bin.left(4) + ' XXXX XXXX ' + last4;
    }
}
