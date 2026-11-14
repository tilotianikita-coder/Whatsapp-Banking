/**
 * Credit bureau report (mock TransUnion CIBIL; going live, a CIBIL / Experian / Equifax API behind pull()).
 * Soft pulls (recommendation) and the hard pull at submission return the same report; ETB reports are cached on the
 * Contact for 30 days so a returning customer is not pulled again.
 *
 * Demo levers on the PAN (with BandhuProviders.cibil for the score: last letter Z 630, Y 690, R 730, others 765-820):
 *   digits ending 5 -> no bureau footprint (new to credit)
 *   digits ending 6 -> 8 enquiries in 6 months across 5 lenders (credit hungry)
 *   digits ending 7 -> a settled credit card 2 years ago (manual review)
 *   digits ending 3 -> card utilisation 92%
 * Rules (assess): score below Decline_Cibil__c or DPD over 90 in 24 months -> decline; write-off or settlement,
 *   6+ enquiries in 6 months or 90%+ utilisation -> manual review (refer); no footprint -> refer (AA / secured route).
 */
public inherited sharing class BandhuBureau {
    public static final String PROVIDER = 'TransUnion CIBIL (mock)';
    public static final Integer CACHE_DAYS = 30;

    public class Tradeline {
        public String accountType;
        public String lender;
        public Decimal sanctioned;
        public Decimal outstanding;
        public Integer openedMonthsAgo;
        public Integer maxDpd24;
        public String status;   // Active / Closed / Written off / Settled
    }

    public class Report {
        public String pan;
        public String pullType;
        public Datetime pulledAt;
        public Integer score;
        public Boolean noHit = false;
        public List<Tradeline> accounts = new List<Tradeline>();
        public Integer activeAccounts = 0;
        public Integer enquiries6m = 0;
        public Integer enquiryLenders6m = 0;
        public Decimal utilisationPct = 0;
        public Integer oldestMonths = 0;
        public Integer maxDpd24 = 0;
        public Boolean writtenOff = false;
        public Boolean settled = false;
        public Decimal monthlyEmi = 0;

        public List<String> lines() {
            List<String> l = new List<String>();
            if (noHit) {
                l.add('No bureau footprint: new to credit (no tradelines, no score)');
                return l;
            }
            l.add('CIBIL ' + score + ' · ' + pullType + ' pull ' + (pulledAt == null ? '' : pulledAt.format('dd/MM/yyyy', BandhuI18n.TIMEZONE)));
            l.add('Active accounts ' + activeAccounts + ' of ' + accounts.size() + ' · oldest ' + oldestMonths + ' months · card utilisation ' + utilisationPct.intValue() + '%');
            l.add('Enquiries: ' + enquiries6m + ' in 6 months (' + enquiryLenders6m + ' lenders) · max DPD (24 months): ' + maxDpd24
                + ' · EMIs ' + BandhuI18n.inr(monthlyEmi) + '/month');
            for (Tradeline t : accounts) {
                l.add('• ' + t.accountType + ' · ' + t.lender + ' · ' + BandhuI18n.inrShort(t.sanctioned) + ' · outstanding ' + BandhuI18n.inrShort(t.outstanding)
                    + ' · ' + t.status + (t.maxDpd24 > 0 ? ' · DPD ' + t.maxDpd24 : ''));
            }
            return l;
        }
    }

    public class Assessment {
        public String result;          // Pass / Refer / Fail
        public List<String> knockouts = new List<String>();
        public List<String> reviews = new List<String>();
        public String summary;
    }

    // ------------------------------------------------------------------ pull
    public static Report pull(String pan, String pullType) {
        Report r = new Report();
        String p = pan == null ? '' : pan.toUpperCase();
        r.pan = p;
        r.pullType = pullType;
        r.pulledAt = Datetime.now();
        String digits = p.length() >= 9 ? p.substring(5, 9) : '0000';
        if (digits.endsWith('5')) {
            r.noHit = true;
            return r;
        }
        r.score = BandhuProviders.cibil(p);
        Integer s = r.score;
        Boolean velocity = digits.endsWith('6');
        Boolean settledCard = digits.endsWith('7');
        Boolean maxedOut = digits.endsWith('3');
        Decimal cardLimit = s >= 760 ? 300000 : s >= 700 ? 150000 : 80000;
        Decimal util = maxedOut ? 0.92 : s >= 760 ? 0.18 : s >= 720 ? 0.42 : s >= 680 ? 0.78 : 0.95;
        r.accounts.add(line('Credit card', 'HDFC Bank', cardLimit, (cardLimit * util).setScale(0), 52, s >= 720 ? 0 : s >= 680 ? 30 : 60, 'Active'));
        r.accounts.add(line('Auto loan', 'Tata Capital', 600000, 280000, 30, 0, 'Active'));
        r.accounts.add(line('Consumer durable', 'Bajaj Finance', 45000, 0, 70, 0, 'Closed'));
        if (s < 650) {
            r.accounts.add(line('Personal loan', 'Moneyview', 150000, 128000, 26, 120, 'Written off'));
        }
        if (settledCard) {
            r.accounts.add(line('Credit card', 'RBL Bank', 60000, 0, 40, 90, 'Settled'));
        }
        r.enquiries6m = velocity ? 8 : s < 700 ? 4 : Math.mod(s, 2);
        r.enquiryLenders6m = velocity ? 5 : Math.min(r.enquiries6m, 2);
        Decimal limits = 0;
        Decimal used = 0;
        for (Tradeline t : r.accounts) {
            if (t.status == 'Active') {
                r.activeAccounts++;
            }
            r.oldestMonths = Math.max(r.oldestMonths, t.openedMonthsAgo);
            r.maxDpd24 = Math.max(r.maxDpd24, t.status == 'Settled' ? 0 : t.maxDpd24);
            r.writtenOff |= t.status == 'Written off';
            r.settled |= t.status == 'Settled';
            if (t.accountType == 'Credit card' && t.status == 'Active') {
                limits += t.sanctioned;
                used += t.outstanding;
            }
            if (t.accountType == 'Auto loan' && t.status == 'Active') {
                r.monthlyEmi += 14500;
            }
        }
        r.utilisationPct = limits == 0 ? 0 : (used / limits * 100).setScale(0);
        return r;
    }

    /** Re-pull after months of clean repayment (mock): +6 points a clean month, up to 60, from the same file. */
    public static Report pullAfterCleanMonths(String pan, Integer months) {
        Report r = pull(pan, 'Soft');
        if (!r.noHit && months >= 6) {
            r.score = Math.min(900, r.score + Math.min(60, months * 6));
            if (r.maxDpd24 <= 60) {
                r.maxDpd24 = 0;
                for (Tradeline t : r.accounts) {
                    t.maxDpd24 = t.status == 'Active' ? 0 : t.maxDpd24;
                }
            }
            r.enquiries6m = Math.min(r.enquiries6m, 1);
            r.enquiryLenders6m = Math.min(r.enquiryLenders6m, 1);
        }
        return r;
    }

    private static Tradeline line(String accountType, String lender, Decimal sanctioned, Decimal outstanding, Integer opened, Integer dpd, String status) {
        Tradeline t = new Tradeline();
        t.accountType = accountType;
        t.lender = lender;
        t.sanctioned = sanctioned;
        t.outstanding = outstanding;
        t.openedMonthsAgo = opened;
        t.maxDpd24 = dpd;
        t.status = status;
        return t;
    }

    // ------------------------------------------------------------------ rules
    public static Assessment assess(Report r) {
        Assessment a = new Assessment();
        Decimal decline = BandhuConfig.get().Decline_Cibil__c == null ? 650 : BandhuConfig.get().Decline_Cibil__c;
        if (r.noHit) {
            a.reviews.add('No credit history: verify income through Account Aggregator, or a secured card against an FD');
        } else {
            if (r.score < decline) {
                a.knockouts.add('CIBIL ' + r.score + ' below ' + decline.intValue());
            }
            if (r.maxDpd24 > 90) {
                a.knockouts.add('A loan more than 90 days overdue in the last 24 months');
            }
            if (r.writtenOff) {
                a.reviews.add('Write-off on record');
            }
            if (r.settled) {
                a.reviews.add('Settled account on record');
            }
            if (r.enquiries6m >= 6) {
                a.reviews.add(r.enquiries6m + ' credit enquiries in 6 months across ' + r.enquiryLenders6m + ' lenders');
            }
            if (r.utilisationPct >= 90) {
                a.reviews.add('Card utilisation ' + r.utilisationPct.intValue() + '%');
            }
        }
        a.result = !a.knockouts.isEmpty() ? 'Fail' : !a.reviews.isEmpty() || (r.score != null && r.score < 700) ? 'Refer' : 'Pass';
        a.summary = r.noHit ? 'No bureau footprint (new to credit)'
            : 'CIBIL ' + r.score + (!a.knockouts.isEmpty() ? ' - ' + String.join(a.knockouts, '; ')
                : !a.reviews.isEmpty() ? ' - review: ' + String.join(a.reviews, '; ')
                : r.score < 700 ? ' - recent delays' : ' - clean record');
        return a;
    }

    // ------------------------------------------------------------------ journey
    /** Soft pull for the journey, reusing an existing customer's cached report (30 days). Saves the cache; not the journey. */
    public static Report softPull(Card_Journey__c j) {
        Report r;
        Contact c;
        if (j.Contact__c != null) {
            c = [SELECT Id, Bandhu_Bureau_Data__c, Bandhu_Bureau_At__c FROM Contact WHERE Id = :j.Contact__c];
            if (c.Bandhu_Bureau_At__c != null && c.Bandhu_Bureau_At__c > Datetime.now().addDays(-CACHE_DAYS) && String.isNotBlank(c.Bandhu_Bureau_Data__c)) {
                r = (Report) JSON.deserialize(c.Bandhu_Bureau_Data__c, Report.class);
                if (r.pan != (j.PAN__c == null ? '' : j.PAN__c.toUpperCase())) {
                    r = null;
                }
            }
        }
        if (r == null) {
            r = pull(j.PAN__c, 'Soft');
            if (c != null) {
                c.Bandhu_Bureau_Data__c = JSON.serialize(r, true);
                c.Bandhu_Bureau_At__c = r.pulledAt;
                update c;
            }
        }
        apply(j, r);
        return r;
    }

    public static void apply(Card_Journey__c j, Report r) {
        j.CIBIL_Score__c = r.score;
        j.Bureau_Data__c = JSON.serialize(r, true);
        j.Bureau_At__c = r.pulledAt;
    }

    public static Report fromJourney(Card_Journey__c j) {
        if (j == null || String.isBlank(j.Bureau_Data__c)) {
            return null;
        }
        try {
            return (Report) JSON.deserialize(j.Bureau_Data__c, Report.class);
        } catch (Exception e) {
            return null;
        }
    }
}
