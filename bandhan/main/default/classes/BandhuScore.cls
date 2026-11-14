/**
 * Bandhan Score (0 - 1000): Bandhan's own creditworthiness score, distinct from the bureau score.
 * A transparent weighted scorecard (model BSC-1.0) rather than an opaque model, so every decision can be explained to the
 * customer or a regulator: each factor's points are logged on the application (Score_Factors__c) and the check.
 *
 * Factor (max points)            Source
 *   Bureau score (250)           bureau        points = score - 600 (850+ full); no footprint 60
 *   Credit history age (60)      bureau        oldest tradeline, 60 months = full
 *   Active accounts (40)         bureau        1-3 best
 *   Card utilisation (80)        bureau        under 30% best
 *   Enquiries, 6 months (40)     bureau        0-1 best
 *   Repayment, 24 months (60)    bureau        no DPD best
 *   Monthly surplus (80)         AA            surplus / income
 *   Income trend (40)            AA            growing / flat / declining
 *   Obligations, FOIR (80)       AA or bureau  EMIs / income
 *   Cash-flow stability (60)     AA            income stability score
 *   Income level (60)            income
 *   Bandhan relationship (80)    core banking  relationship score (existing customers); new to bank 40
 *   Channel (40)                 journey       branch-assisted 40, digital 25
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

        add(r, 'Bureau score', noHit ? 'no footprint' : cibil == null ? 'not pulled' : String.valueOf(cibil),
            noHit ? 60 : cibil == null ? 100 : clamp(cibil - 600, 0, 250), 250, 'Bureau');
        if (b != null && !noHit) {
            add(r, 'Credit history age', b.oldestMonths + ' months', clamp(b.oldestMonths, 0, 60), 60, 'Bureau');
            add(r, 'Active accounts', String.valueOf(b.activeAccounts),
                b.activeAccounts == 0 ? 10 : b.activeAccounts <= 3 ? 40 : b.activeAccounts <= 5 ? 25 : 10, 40, 'Bureau');
            Decimal u = b.utilisationPct;
            add(r, 'Card utilisation', u.intValue() + '%', u < 30 ? 80 : u < 50 ? 60 : u < 75 ? 35 : u < 90 ? 15 : 0, 80, 'Bureau');
            add(r, 'Enquiries (6 months)', String.valueOf(b.enquiries6m),
                b.enquiries6m <= 1 ? 40 : b.enquiries6m <= 3 ? 25 : b.enquiries6m <= 5 ? 10 : 0, 40, 'Bureau');
            add(r, 'Repayment (24 months)', b.maxDpd24 == 0 ? 'no delays' : 'max DPD ' + b.maxDpd24,
                b.maxDpd24 == 0 ? 60 : b.maxDpd24 <= 30 ? 30 : 0, 60, 'Bureau');
        } else {
            add(r, 'Credit history age', noHit ? 'new to credit' : 'not pulled', noHit ? 0 : 30, 60, 'Bureau');
            add(r, 'Active accounts', noHit ? '0' : 'not pulled', noHit ? 10 : 20, 40, 'Bureau');
            add(r, 'Card utilisation', noHit ? 'no cards' : 'not pulled', 40, 80, 'Bureau');
            add(r, 'Enquiries (6 months)', noHit ? '0' : 'not pulled', 20, 40, 'Bureau');
            add(r, 'Repayment (24 months)', noHit ? 'no history' : 'not pulled', 30, 60, 'Bureau');
        }
        if (cf != null && cf.netMonthlyIncome != null && cf.netMonthlyIncome > 0) {
            Decimal ratio = cf.monthlySurplus / cf.netMonthlyIncome;
            add(r, 'Monthly surplus', BandhuI18n.inr(cf.monthlySurplus) + ' (' + (ratio * 100).intValue() + '%)',
                ratio >= 0.3 ? 80 : ratio >= 0.2 ? 60 : ratio >= 0.1 ? 40 : ratio >= 0 ? 20 : 0, 80, 'Account Aggregator');
            add(r, 'Income trend', cf.incomeTrend, cf.incomeTrend == 'Growing' ? 40 : cf.incomeTrend == 'Flat' ? 25 : 0, 40, 'Account Aggregator');
            Decimal foir = cf.foirPct;
            add(r, 'Obligations (FOIR)', foir.intValue() + '%', foir < 20 ? 80 : foir < 35 ? 60 : foir < 50 ? 30 : 0, 80, 'Account Aggregator');
            add(r, 'Cash-flow stability', cf.incomeStability + '/100', (cf.incomeStability * 60 / 100), 60, 'Account Aggregator');
        } else {
            add(r, 'Monthly surplus', 'no AA data', 40, 80, 'Account Aggregator');
            add(r, 'Income trend', 'no AA data', 20, 40, 'Account Aggregator');
            Decimal foir = b != null && income != null ? b.monthlyEmi / income * 100 : null;
            add(r, 'Obligations (FOIR)', foir == null ? 'unknown' : foir.intValue() + '% (bureau EMIs)',
                foir == null ? 40 : foir < 20 ? 80 : foir < 35 ? 60 : foir < 50 ? 30 : 0, 80, foir == null ? 'Declared' : 'Bureau');
            add(r, 'Cash-flow stability', 'no AA data', 30, 60, 'Account Aggregator');
        }
        add(r, 'Income level', income == null ? 'not shared' : BandhuI18n.inrShort(income) + '/month',
            income == null ? 0 : income >= 200000 ? 60 : income >= 100000 ? 50 : income >= 50000 ? 35 : income >= 25000 ? 20 : 5, 60, p.incomeVerified ? 'Verified' : 'Declared');
        add(r, 'Bandhan relationship', p.existing ? p.relationshipScore + '/100 (' + p.etbTier + ')' : 'new to bank',
            p.existing ? (p.relationshipScore * 80 / 100) : 40, 80, p.existing ? 'Core banking' : 'Journey');
        add(r, 'Channel', p.channel == null ? 'digital' : p.channel, p.channel == 'Branch' ? 40 : 25, 40, 'Journey');
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

    private static Integer clamp(Integer v, Integer lo, Integer hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private static Integer clamp(Decimal v, Integer lo, Integer hi) {
        return clamp(v.intValue(), lo, hi);
    }
}
