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

    public static Report bureau(String pan) {
        Report r = new Report();
        r.provider = 'TransUnion CIBIL (mock)';
        r.score = cibil(pan);
        r.result = r.score >= 700 ? 'Pass' : r.score >= 650 ? 'Refer' : 'Fail';
        Integer active = Math.mod(r.score, 3) + 1;
        r.details.add('CIBIL score: ' + r.score);
        r.details.add('Active credit lines: ' + active + ' · enquiries in 6 months: ' + (r.score < 700 ? 5 : Math.mod(r.score, 2)));
        r.details.add('Max DPD (24 months): ' + (r.score < 650 ? '90+ (written off)' : r.score < 700 ? '30' : '0'));
        r.summary = 'CIBIL ' + r.score + (r.score >= 700 ? ' - clean record' : r.score >= 650 ? ' - recent delays' : ' - write-off on record');
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

    public static Report income(Card_Journey__c j) {
        Report r = new Report();
        if (j.Customer_Type__c == 'Existing' && j.Verified_Income__c != null) {
            r.provider = 'Bandhan Bank salary credits';
            r.result = 'Pass';
            r.summary = 'Salary credits ' + BandhuI18n.inr(j.Verified_Income__c) + '/month';
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
