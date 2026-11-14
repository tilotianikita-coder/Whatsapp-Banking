/**
 * Which Bandhan Bank cards an applicant qualifies for, and which one fits them best.
 *
 * Eligibility (per card, thresholds on Bandhu_Card__mdt, all PLACEHOLDERS for the demo):
 *   age 21 - 60 salaried / 21 - 65 self-employed (Bandhu_Config__mdt);
 *   monthly income >= Min_Monthly_Income__c, OR an existing customer whose balances + FDs reach ETB_Min_Balance__c,
 *   OR the bank's pre-approved card (existing customers);
 *   CIBIL >= Min_Cibil__c qualifies, Refer_Cibil__c .. Min_Cibil__c qualifies on refer, below Refer_Cibil__c does not;
 *   below Decline_Cibil__c no card. No score yet (soft check skipped) qualifies on income, to be confirmed on apply.
 * Recommendation: among eligible cards, the highest fit score = the card's weights for what the customer spends on,
 *   their fee preference and monthly spend; ties go to the higher tier. Credit decisions stay with BandhuDecision.
 *   With Account Aggregator data (BandhuCashFlow), what the statements show counts more than what was declared:
 *   each category's card weight x 3 / 2 / 1 for 30% / 15% / 7% of the monthly card-able spend, and the "why" lines quote it.
 * Limit: income x the card's multiple, cut to 75% for FOIR over 40% and to 50% over 50% (existing EMIs, from AA).
 */
public inherited sharing class BandhuEligibility {
    public static final List<String> FOCUS = new List<String>{ 'Travel', 'International', 'Dining', 'Groceries', 'Shopping', 'Fuel' };
    public static final String LOWEST_FEE = 'Lowest fee';
    public static final String BEST_BENEFITS = 'Best benefits';

    public class Profile {
        public Integer age;
        public String employment;
        public Decimal income;
        public Integer cibil;
        public Boolean existing = false;
        public Decimal relationshipValue = 0;
        public String preApprovedCard;
        public Decimal preApprovedLimit;
        public Set<String> focus = new Set<String>();
        public Integer spendBand;           // 1 under 15K, 2 15-50K, 3 50K-1L, 4 over 1L
        public String feePreference;
        public BandhuCashFlow.Analysis cashFlow;   // Account Aggregator analysis, when shared
        public BandhuBureau.Report bureau;         // soft-pull report, when pulled
        public String etbTier;                     // existing customers: BandhuCustomer tier
        public Integer internalDpd = 0;            // worst DPD on a Bandhan loan in 12 months
    }

    public class Option {
        public Bandhu_Card__mdt card;
        public Boolean eligible = false;
        public Boolean refer = false;
        public Boolean incomeShort = false;  // fails only on income: an "upgrade" hint is possible
        public List<String> reasons = new List<String>();
        public Decimal fit = 0;
        public Decimal creditLimit;
        public List<String> why = new List<String>();
        public String limitNote;
        public String referNote;
    }

    public class Outcome {
        public List<Option> options = new List<Option>();
        public Option best;
        public Option alternative;
        public Option upgrade;
        public String blockedReason;

        public List<String> eligibleNames() {
            List<String> names = new List<String>();
            for (Option o : options) {
                if (o.eligible) {
                    names.add(o.card.DeveloperName);
                }
            }
            return names;
        }
    }

    public static Outcome evaluate(Profile p) {
        Bandhu_Config__mdt cfg = BandhuConfig.get();
        Outcome out = new Outcome();
        String common = commonBlock(p, cfg);
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            Option o = new Option();
            o.card = c;
            if (common != null) {
                o.reasons.add(common);
            } else {
                Boolean preApproved = p.existing && p.preApprovedCard == c.DeveloperName;
                Boolean relationship = p.existing && nz(c.ETB_Min_Balance__c) > 0 && nz(p.relationshipValue) >= c.ETB_Min_Balance__c;
                Boolean incomeOk = p.income != null && p.income >= nz(c.Min_Monthly_Income__c);
                if (!incomeOk && !preApproved && !relationship) {
                    o.reasons.add('Monthly income below ' + BandhuI18n.inr(c.Min_Monthly_Income__c));
                    o.incomeShort = true;
                }
                if (p.existing && p.etbTier != null && String.isNotBlank(c.ETB_Tiers__c) && !c.ETB_Tiers__c.split(';').contains(p.etbTier)) {
                    o.reasons.add('Not offered to ' + p.etbTier.toLowerCase() + ' customers');
                    o.incomeShort = false;
                }
                if (p.cibil != null) {
                    if (p.cibil < nz(c.Refer_Cibil__c)) {
                        o.reasons.add('CIBIL ' + p.cibil + ' below ' + c.Refer_Cibil__c.intValue());
                        o.incomeShort = false;
                    } else if (p.cibil < nz(c.Min_Cibil__c)) {
                        o.refer = true;
                    }
                }
                o.eligible = o.reasons.isEmpty();
                String review = reviewNote(p);
                if (o.eligible && review != null) {
                    o.refer = true;
                    o.referNote = review;
                }
                if (o.eligible) {
                    if (preApproved && p.preApprovedLimit != null) {
                        o.creditLimit = p.preApprovedLimit;
                    } else {
                        o.creditLimit = limitFor(c, p.income, p.cashFlow == null ? null : p.cashFlow.foirPct);
                        if (p.cashFlow != null && nz(p.cashFlow.foirPct) > 40) {
                            o.limitNote = '⚖ Limit set for your existing EMIs (' + p.cashFlow.foirPct.intValue() + '% of income)';
                        }
                    }
                }
            }
            scoreFit(o, p);
            out.options.add(o);
        }
        if (common != null) {
            out.blockedReason = common;
            return out;
        }
        for (Option o : out.options) {
            if (o.eligible && (out.best == null || o.fit > out.best.fit || (o.fit == out.best.fit && o.card.Tier__c > out.best.card.Tier__c))) {
                out.best = o;
            }
        }
        for (Option o : out.options) {
            if (o.eligible && o != out.best && (out.alternative == null || o.fit > out.alternative.fit
                    || (o.fit == out.alternative.fit && o.card.Tier__c > out.alternative.card.Tier__c))) {
                out.alternative = o;
            }
        }
        if (out.best != null) {
            for (Option o : out.options) {
                if (o.incomeShort && o.card.Tier__c > out.best.card.Tier__c && out.upgrade == null) {
                    out.upgrade = o;
                }
            }
        } else {
            out.blockedReason = lowestReason(out.options);
        }
        return out;
    }

    /** Age and the hard CIBIL floor apply to every card. */
    private static String commonBlock(Profile p, Bandhu_Config__mdt cfg) {
        if (p.age != null) {
            Decimal maxAge = p.employment == 'Self-employed' ? cfg.Max_Age_Self_Employed__c : cfg.Max_Age_Salaried__c;
            if (p.age < nz(cfg.Min_Age__c)) {
                return 'age under ' + cfg.Min_Age__c.intValue();
            }
            if (maxAge != null && p.age > maxAge) {
                return 'age over ' + maxAge.intValue();
            }
        }
        if (p.cibil != null && cfg.Decline_Cibil__c != null && p.cibil < cfg.Decline_Cibil__c) {
            return 'credit score below ' + cfg.Decline_Cibil__c.intValue();
        }
        if (p.bureau != null && p.bureau.maxDpd24 > 90) {
            return 'a loan more than 90 days overdue in the last 24 months';
        }
        return null;
    }

    /** Eligible, but only on manual review: bureau flags and the bank's own repayment track. */
    private static String reviewNote(Profile p) {
        List<String> notes = new List<String>();
        if (p.bureau != null) {
            notes.addAll(BandhuBureau.assess(p.bureau).reviews);
        }
        if (p.etbTier == BandhuCustomer.MICROFINANCE && p.internalDpd > 0) {
            notes.add('microfinance repayment delays (DPD ' + p.internalDpd + ')');
        } else if (p.internalDpd > 30) {
            notes.add('DPD ' + p.internalDpd + ' on a Bandhan loan');
        }
        return notes.isEmpty() ? null : 'manual review: ' + String.join(notes, '; ');
    }

    private static String lowestReason(List<Option> options) {
        for (Option o : options) {
            if (!o.reasons.isEmpty()) {
                return o.reasons[0].toLowerCase();
            }
        }
        return 'eligibility criteria not met';
    }

    /** Monthly income x the card's multiple, kept within the card's range and rounded down to ₹5,000. */
    public static Decimal limitFor(Bandhu_Card__mdt c, Decimal income) {
        return limitFor(c, income, null);
    }

    /** ... cut for a high obligation-to-income ratio (FOIR, %): over 40% -> 75%, over 50% -> 50%. */
    public static Decimal limitFor(Bandhu_Card__mdt c, Decimal income, Decimal foirPct) {
        Decimal factor = foirPct == null || foirPct <= 40 ? 1 : foirPct <= 50 ? 0.75 : 0.5;
        Decimal raw = income == null ? nz(c.Limit_Min__c) : income * nz(c.Limit_Multiple__c) * factor;
        raw = Math.max(nz(c.Limit_Min__c), Math.min(c.Limit_Max__c == null ? raw : c.Limit_Max__c, raw));
        return Math.floor(raw / 5000) * 5000;
    }

    private static void scoreFit(Option o, Profile p) {
        Bandhu_Card__mdt c = o.card;
        Map<String, Decimal> weight = new Map<String, Decimal>{
            'Travel' => c.Fit_Travel__c, 'International' => c.Fit_International__c, 'Dining' => c.Fit_Dining__c,
            'Groceries' => c.Fit_Groceries__c, 'Shopping' => c.Fit_Shopping__c, 'Fuel' => c.Fit_Fuel__c
        };
        Map<String, String> benefit = new Map<String, String>{
            'Travel' => String.isNotBlank(c.Accelerated__c) && c.Accelerated__c.containsIgnoreCase('travel') ? c.Accelerated__c : c.Lounge__c,
            'International' => String.isNotBlank(c.Accelerated__c) && c.Accelerated__c.containsIgnoreCase('international') ? c.Accelerated__c : c.Lounge__c,
            'Dining' => firstNonBlank(c.Dining__c, c.Movies__c),
            'Groceries' => firstNonBlank(c.Accelerated__c, c.Rewards__c),
            'Shopping' => firstNonBlank(c.Accelerated__c, c.Rewards__c),
            'Fuel' => c.Fuel__c
        };
        if (p.cashFlow != null && nz(p.cashFlow.monthlyCardSpend) > 0) {
            // what the statements show: the bigger the share of spend, the more the card's strength in it counts
            for (String f : FOCUS) {
                Decimal share = p.cashFlow.share(f);
                Integer mult = share >= 0.3 ? 3 : share >= 0.15 ? 2 : share >= 0.07 ? 1 : 0;
                Decimal w = nz(weight.get(f));
                o.fit += w * mult;
                if (mult >= 2 && w >= 3 && String.isNotBlank(benefit.get(f)) && o.why.size() < 3) {
                    o.why.add('✅ ' + f + ': ' + BandhuI18n.inrShort(p.cashFlow.spend.get(f)) + '/month in your statements · ' + benefit.get(f));
                }
            }
        }
        for (String f : FOCUS) {
            if (p.focus.contains(f)) {
                Decimal w = nz(weight.get(f));
                o.fit += w;
                String line = '✅ ' + f + ': ' + benefit.get(f);
                if (w >= 3 && String.isNotBlank(benefit.get(f)) && o.why.size() < 3 && !String.join(o.why, '|').contains(benefit.get(f))) {
                    o.why.add(line);
                }
            }
        }
        if (p.feePreference == LOWEST_FEE) {
            o.fit += nz(c.Fit_Low_Fee__c) * 2;
            if (nz(c.Fit_Low_Fee__c) >= 3) {
                o.why.add('✅ Low fee: ₹' + nz(c.Joining_Fee__c).intValue() + ' · ' + c.Fee_Waiver__c);
            }
        } else if (p.feePreference == BEST_BENEFITS) {
            o.fit += nz(c.Tier__c) * 2;
        }
        Integer band = p.spendBand;
        if (band == null && p.cashFlow != null && p.cashFlow.monthlyCardSpend > 0) {
            Decimal s = p.cashFlow.monthlyCardSpend;
            band = s < 15000 ? 1 : s < 50000 ? 2 : s <= 100000 ? 3 : 4;
        }
        if (band != null) {
            // high monthly spend favours milestone-rich cards; low spend favours low fees
            o.fit += band >= 3 ? nz(c.Fit_High_Spend__c) * (band - 2) : nz(c.Fit_Low_Fee__c) * (3 - band) / 2;
            if (band >= 3 && String.isNotBlank(c.Milestone__c) && o.why.size() < 3) {
                o.why.add('✅ Milestone: ' + c.Milestone__c);
            }
        }
        if (o.why.isEmpty()) {
            o.why.add('✅ ' + c.Rewards__c + (String.isNotBlank(c.Accelerated__c) ? ' · ' + c.Accelerated__c : ''));
        }
        if (o.limitNote != null) {
            o.why.add(o.limitNote);
        }
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }
}
