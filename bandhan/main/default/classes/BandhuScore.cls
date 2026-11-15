/**
 * Bandhan Score (0 - 1000): Bandhan's own creditworthiness score, distinct from the bureau score.
 * A transparent weighted scorecard (model BSC-1.0) rather than an opaque model, so every decision can be explained to the
 * customer or a regulator: each factor's points are logged on the application (Score_Factors__c) and the check.
 *
 * Three groups, out of 600 + 250 + 150 = 1000:
 * Credit bureau (600)
 *   Bureau score (280)           by CIBIL band: Poor (<650) 0-110, Fair (650-699) 110-220, Good (700-749) 220-280, Excellent (750+) 280; no footprint 70
 *   Credit history age (70)      oldest tradeline, 60 months = full
 *   Active accounts (40)         1-3 best
 *   Card utilisation (90)        under 30% best
 *   Enquiries, 6 months (50)     0-1 best
 *   Repayment, 24 months (70)    no DPD best
 * Bank statements, Account Aggregator (250)
 *   Monthly surplus (80)         surplus / income
 *   Income trend (40)            growing / flat / declining
 *   Obligations, FOIR (80)       EMIs / income (bureau EMIs when there are no statements)
 *   Cash-flow stability (50)     income stability score
 * Income, relationship and channel (150)
 *   Income level (50)            monthly income
 *   Bandhan relationship (50)    relationship score (existing customers); new to bank 25
 *   Channel (20)                 branch-assisted 20, digital 12
 *   Verified income (30)         AA / salary credits
 * Missing data scores about half the factor (neutral), so a thin profile is not penalised as a bad one.
 * Bands: A 700+ (limit +0.5x), B 550-699, C 400-549 (limit -0.5x), D under 400 (manual review).
 */
public inherited sharing class BandhuScore {
    public static final String MODEL_VERSION = 'BSC-1.0 (Bandhan scorecard)';

    public class Factor {
        public String name;
        public String value;
        public Integer points;
        public Integer maxPoints;
        public String source;
    }

    public class Result {
        public Integer score = 0;
        public String band;
        public String model = MODEL_VERSION;
        public List<Factor> factors = new List<Factor>();

        public Decimal multipleAdjustment() {
            return band == 'A' ? 0.5 : band == 'C' ? -0.5 : 0;
        }

        public List<String> lines() {
            List<String> l = new List<String>{ 'Bandhan Score ' + score + '/1000 · band ' + band + ' · ' + model };
            for (Factor f : factors) {
                l.add('• ' + f.name + ': ' + f.value + ' -> ' + f.points + '/' + f.maxPoints + ' (' + f.source + ')');
            }
            return l;
        }

        /** The factors that pulled the score down most (for "why" explanations). */
        public List<String> weakest(Integer n) {
            List<Factor> sorted = factors.clone();
            for (Integer i = 0; i < sorted.size(); i++) {
                for (Integer k = i + 1; k < sorted.size(); k++) {
                    if (sorted[k].maxPoints - sorted[k].points > sorted[i].maxPoints - sorted[i].points) {
                        Factor t = sorted[i];
                        sorted[i] = sorted[k];
                        sorted[k] = t;
                    }
                }
            }
            List<String> out = new List<String>();
            for (Integer i = 0; i < Math.min(n, sorted.size()); i++) {
                if (sorted[i].points < sorted[i].maxPoints) {
                    out.add(sorted[i].name + ' (' + sorted[i].value + ')');
                }
            }
            return out;
        }
    }

    public static Result compute(BandhuEligibility.Profile p) {
        Result r = new Result();
        BandhuBureau.Report b = p.bureau;
        BandhuCashFlow.Analysis cf = p.cashFlow;
        Integer cibil = p.cibil != null ? p.cibil : b != null ? b.score : null;
        Boolean noHit = b != null && b.noHit;
        Decimal income = p.income == null || p.income == 0 ? null : p.income;

        // ---- credit bureau (600)
        add(r, 'Bureau score', noHit ? 'no footprint' : cibil == null ? 'not pulled' : cibil + ' · ' + BandhuBureau.band(cibil),
            noHit ? 70 : cibil == null ? 110 : bureauPoints(cibil), 280, 'Bureau');
        if (b != null && !noHit) {
            add(r, 'Credit history age', b.oldestMonths + ' months', clamp(b.oldestMonths * 70 / 60, 0, 70), 70, 'Bureau');
            add(r, 'Active accounts', String.valueOf(b.activeAccounts),
                b.activeAccounts == 0 ? 10 : b.activeAccounts <= 3 ? 40 : b.activeAccounts <= 5 ? 25 : 10, 40, 'Bureau');
            Decimal u = b.utilisationPct;
            add(r, 'Card utilisation', u.intValue() + '%', u < 30 ? 90 : u < 50 ? 70 : u < 75 ? 40 : u < 90 ? 20 : 0, 90, 'Bureau');
            add(r, 'Enquiries (6 months)', String.valueOf(b.enquiries6m),
                b.enquiries6m <= 1 ? 50 : b.enquiries6m <= 3 ? 30 : b.enquiries6m <= 5 ? 12 : 0, 50, 'Bureau');
            add(r, 'Repayment (24 months)', b.maxDpd24 == 0 ? 'no delays' : 'max DPD ' + b.maxDpd24,
                b.maxDpd24 == 0 ? 70 : b.maxDpd24 <= 30 ? 35 : 0, 70, 'Bureau');
        } else {
            add(r, 'Credit history age', noHit ? 'new to credit' : 'not pulled', noHit ? 0 : 35, 70, 'Bureau');
            add(r, 'Active accounts', noHit ? '0' : 'not pulled', noHit ? 10 : 20, 40, 'Bureau');
            add(r, 'Card utilisation', noHit ? 'no cards' : 'not pulled', 45, 90, 'Bureau');
            add(r, 'Enquiries (6 months)', noHit ? '0' : 'not pulled', 25, 50, 'Bureau');
            add(r, 'Repayment (24 months)', noHit ? 'no history' : 'not pulled', 35, 70, 'Bureau');
        }
        // ---- bank statements, Account Aggregator (250)
        if (cf != null && cf.netMonthlyIncome != null && cf.netMonthlyIncome > 0) {
            Decimal ratio = cf.monthlySurplus / cf.netMonthlyIncome;
            add(r, 'Monthly surplus', BandhuI18n.inr(cf.monthlySurplus) + ' (' + (ratio * 100).intValue() + '%)',
                ratio >= 0.3 ? 80 : ratio >= 0.2 ? 60 : ratio >= 0.1 ? 40 : ratio >= 0 ? 20 : 0, 80, 'Account Aggregator');
            add(r, 'Income trend', cf.incomeTrend, cf.incomeTrend == 'Growing' ? 40 : cf.incomeTrend == 'Flat' ? 25 : 0, 40, 'Account Aggregator');
            Decimal foir = cf.foirPct;
            add(r, 'Obligations (FOIR)', foir.intValue() + '%', foir < 20 ? 80 : foir < 35 ? 60 : foir < 50 ? 30 : 0, 80, 'Account Aggregator');
            add(r, 'Cash-flow stability', cf.incomeStability + '/100', (cf.incomeStability * 50 / 100), 50, 'Account Aggregator');
        } else {
            add(r, 'Monthly surplus', 'no AA data', 40, 80, 'Account Aggregator');
            add(r, 'Income trend', 'no AA data', 20, 40, 'Account Aggregator');
            Decimal foir = b != null && income != null ? b.monthlyEmi / income * 100 : null;
            add(r, 'Obligations (FOIR)', foir == null ? 'unknown' : foir.intValue() + '% (bureau EMIs)',
                foir == null ? 40 : foir < 20 ? 80 : foir < 35 ? 60 : foir < 50 ? 30 : 0, 80, foir == null ? 'Declared' : 'Bureau');
            add(r, 'Cash-flow stability', 'no AA data', 25, 50, 'Account Aggregator');
        }
        // ---- income, relationship and channel (150)
        add(r, 'Income level', income == null ? 'not shared' : BandhuI18n.inrShort(income) + '/month',
            income == null ? 0 : income >= 200000 ? 50 : income >= 100000 ? 42 : income >= 50000 ? 30 : income >= 25000 ? 17 : 5, 50, p.incomeVerified ? 'Verified' : 'Declared');
        add(r, 'Bandhan relationship', p.existing ? p.relationshipScore + '/100 (' + p.etbTier + ')' : 'new to bank',
            p.existing ? (p.relationshipScore * 50 / 100) : 25, 50, p.existing ? 'Core banking' : 'Journey');
        add(r, 'Channel', p.channel == null ? 'digital' : p.channel, p.channel == 'Branch' ? 20 : 12, 20, 'Journey');
        add(r, 'Verified income', p.incomeVerified ? 'yes' : 'self-declared', p.incomeVerified ? 30 : 0, 30, p.incomeVerified ? 'AA / salary credits' : 'Declared');

        r.band = r.score >= 700 ? 'A' : r.score >= 550 ? 'B' : r.score >= 400 ? 'C' : 'D';
        return r;
    }

    private static void add(Result r, String name, String value, Integer points, Integer maxPoints, String source) {
        Factor f = new Factor();
        f.name = name;
        f.value = value;
        f.points = clamp(points, 0, maxPoints);
        f.maxPoints = maxPoints;
        f.source = source;
        r.factors.add(f);
        r.score += f.points;
    }

    /** A good score should cost little and a weak one a lot: linear between these steps. */
    @TestVisible
    private static Integer bureauPoints(Integer cibil) {
        List<Integer> at = new List<Integer>{ 550, 600, 650, 700, 750 };
        List<Integer> pts = new List<Integer>{ 0, 40, 110, 220, 280 };
        if (cibil <= at[0]) {
            return 0;
        }
        if (cibil >= 750) {
            return 280;   // Excellent: full points
        }
        for (Integer i = 1; i < at.size(); i++) {
            if (cibil <= at[i]) {
                return pts[i - 1] + (pts[i] - pts[i - 1]) * (cibil - at[i - 1]) / (at[i] - at[i - 1]);
            }
        }
        return 280;
    }

    private static Integer clamp(Integer v, Integer lo, Integer hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private static Integer clamp(Decimal v, Integer lo, Integer hi) {
        return clamp(v.intValue(), lo, hi);
    }
}
