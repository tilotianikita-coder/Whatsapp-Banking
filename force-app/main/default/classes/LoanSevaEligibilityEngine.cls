/**
 * Explainable PL Top-Up eligibility rules (demo):
 *  1. Repayment track: fewer than Min_On_Time_EMIs__c on-time EMIs (of last 12) -> refer to RM.
 *     12/12 -> base rate, full pre-approved cap. Otherwise -> Good_Track_Premium__c and GOOD_TRACK_CAP of the cap.
 *  2. Rate: Base_Rate__c + track premium + Self_Employed_Premium__c (if self-employed).
 *  3. FOIR: (existing EMI + new EMI) must stay within Max_FOIR_Pct__c of assumed monthly income.
 *  4. Amount: min(desired, pre-approved cap, FOIR headroom), rounded down to Amount_Rounding__c.
 *     If no tenure is requested, the shortest tenure that fits the desired amount is chosen.
 */
public with sharing class LoanSevaEligibilityEngine {
    public static final Decimal GOOD_TRACK_CAP = 0.8;

    public class Result {
        public Boolean eligible = false;
        public Decimal maxEligible = 0;
        public Decimal amount = 0;
        public Decimal rate = 0;
        public Integer tenure;
        public Decimal emi = 0;
        public Decimal processingFee = 0;
        public Decimal foirPct = 0;
        public Boolean cappedBelowDesired = false;
        public Map<Integer, Decimal> emiByTenure = new Map<Integer, Decimal>();
        public List<String> notes = new List<String>();
    }

    public static Result evaluate(
        Existing_Loan__c loan,
        String incomeBucket,
        String employmentType,
        Decimal desiredAmount,
        Integer requestedTenure
    ) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Result r = new Result();

        Decimal income = LoanSevaConfig.incomeValues().get(incomeBucket);
        if (loan == null || income == null) {
            r.notes.add('Missing existing loan or income bucket');
            return r;
        }
        Decimal currentEmi = loan.Current_EMI__c == null ? 0 : loan.Current_EMI__c;
        Decimal onTime = loan.EMIs_Paid_On_Time__c == null ? 0 : loan.EMIs_Paid_On_Time__c;
        Decimal due = (loan.EMIs_Due__c == null || loan.EMIs_Due__c == 0) ? 12 : loan.EMIs_Due__c;

        // Rule 1 - repayment track
        if (onTime < cfg.Min_On_Time_EMIs__c) {
            r.notes.add('Repayment track ' + onTime + '/' + due + ' below minimum ' + cfg.Min_On_Time_EMIs__c + ' - refer to RM');
            return r;
        }
        Boolean perfectTrack = onTime >= due;
        Decimal cap = loan.Pre_Approved_Limit__c * (perfectTrack ? 1 : GOOD_TRACK_CAP);

        // Rule 2 - rate
        r.rate = cfg.Base_Rate__c;
        if (!perfectTrack) {
            r.rate += cfg.Good_Track_Premium__c;
        }
        if (employmentType == 'Self-employed') {
            r.rate += cfg.Self_Employed_Premium__c;
        }
        r.notes.add('Track ' + onTime + '/' + due + (perfectTrack ? ' (perfect)' : ' (good)') + '; rate ' + r.rate + '% p.a.');

        // Rule 3 - FOIR headroom
        Decimal emiHeadroom = income * cfg.Max_FOIR_Pct__c / 100 - currentEmi;
        r.notes.add('Assumed income ' + income + '; max FOIR ' + cfg.Max_FOIR_Pct__c + '%; existing EMI ' + currentEmi + '; EMI headroom ' + emiHeadroom.setScale(0));
        if (emiHeadroom <= 0) {
            r.notes.add('No FOIR headroom - refer to RM');
            return r;
        }
        return price(r, cap, emiHeadroom, currentEmi, income, desiredAmount, requestedTenure, cfg.Min_Topup_Amount__c, 'FOIR after top-up');
    }

    /**
     * New Personal Loan (no existing Kotak loan, no pre-approved limit):
     *  1. Declared income below New_Loan_Min_Income__c -> refer to RM.
     *  2. Rate: Base_Rate__c + New_Loan_Rate_Premium__c + Self_Employed_Premium__c (if self-employed).
     *  3. Cap: min(New_Loan_Max_Amount__c, income x New_Loan_Income_Multiple__c).
     *  4. FOIR and amount as for Top-Up, with the declared EMIs as the existing obligations.
     */
    public static Result evaluateNew(
        Decimal monthlyIncome,
        Decimal existingEmis,
        String employmentType,
        Decimal desiredAmount,
        Integer requestedTenure
    ) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Result r = new Result();
        if (monthlyIncome == null || monthlyIncome <= 0) {
            r.notes.add('Missing declared income');
            return r;
        }
        Decimal obligations = existingEmis == null ? 0 : existingEmis;
        if (monthlyIncome < cfg.New_Loan_Min_Income__c) {
            r.notes.add('Declared income ' + monthlyIncome + ' below minimum ' + cfg.New_Loan_Min_Income__c + ' - refer to RM');
            return r;
        }
        r.rate = cfg.Base_Rate__c + cfg.New_Loan_Rate_Premium__c;
        if (employmentType == 'Self-employed') {
            r.rate += cfg.Self_Employed_Premium__c;
        }
        Decimal cap = Math.min(cfg.New_Loan_Max_Amount__c, monthlyIncome * cfg.New_Loan_Income_Multiple__c);
        r.notes.add('New loan; rate ' + r.rate + '% p.a.; cap ' + cap.setScale(0) + ' (' + cfg.New_Loan_Income_Multiple__c + 'x income, max ' + cfg.New_Loan_Max_Amount__c + ')');
        Decimal emiHeadroom = monthlyIncome * cfg.Max_FOIR_Pct__c / 100 - obligations;
        r.notes.add('Declared income ' + monthlyIncome + '; max FOIR ' + cfg.Max_FOIR_Pct__c + '%; existing EMIs ' + obligations + '; EMI headroom ' + emiHeadroom.setScale(0));
        if (emiHeadroom <= 0) {
            r.notes.add('No FOIR headroom - refer to RM');
            return r;
        }
        return price(r, cap, emiHeadroom, obligations, monthlyIncome, desiredAmount, requestedTenure, cfg.New_Loan_Min_Amount__c, 'FOIR with new loan');
    }

    /** Shared tail: picks the tenure and amount within the cap and EMI headroom, then prices the EMI and fee. */
    private static Result price(
        Result r, Decimal cap, Decimal emiHeadroom, Decimal currentEmi, Decimal income,
        Decimal desiredAmount, Integer requestedTenure, Decimal minAmount, String foirLabel
    ) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        List<Integer> tenures = LoanSevaConfig.tenureOptions();
        Integer maxTenure = tenures[tenures.size() - 1];
        Decimal rounding = LoanSevaConfig.rounding();
        r.maxEligible = roundDown(Math.min(cap, principalFor(emiHeadroom, r.rate, maxTenure)), rounding);
        Decimal wanted = (desiredAmount == null || desiredAmount <= 0) ? r.maxEligible : desiredAmount;

        // Tenure choice
        if (requestedTenure != null && tenures.contains(requestedTenure)) {
            r.tenure = requestedTenure;
        } else {
            r.tenure = maxTenure;
            Integer defaultTenure = Integer.valueOf(cfg.Default_Tenure__c);
            for (Integer t : tenures) {
                if (t >= defaultTenure && principalFor(emiHeadroom, r.rate, t) >= Math.min(wanted, r.maxEligible)) {
                    r.tenure = t;
                    break;
                }
            }
        }

        // Rule 4 - amount
        Decimal fitsAtTenure = roundDown(Math.min(cap, principalFor(emiHeadroom, r.rate, r.tenure)), rounding);
        r.amount = roundDown(Math.min(wanted, fitsAtTenure), rounding);
        r.cappedBelowDesired = r.amount < wanted;
        if (r.amount < minAmount) {
            r.notes.add('Eligible amount ' + r.amount + ' below minimum ' + minAmount + ' - refer to RM');
            r.amount = 0;
            return r;
        }

        r.eligible = true;
        r.emi = emi(r.amount, r.rate, r.tenure);
        r.processingFee = Math.max(cfg.Processing_Fee_Min__c, (r.amount * cfg.Processing_Fee_Pct__c / 100).setScale(0, RoundingMode.HALF_UP));
        r.foirPct = ((currentEmi + r.emi) / income * 100).setScale(1, RoundingMode.HALF_UP);
        for (Integer t : tenures) {
            r.emiByTenure.put(t, emi(r.amount, r.rate, t));
        }
        r.notes.add('Offer ' + r.amount + ' @ ' + r.rate + '% for ' + r.tenure + 'm, EMI ' + r.emi + ', ' + foirLabel + ' ' + r.foirPct + '%');
        return r;
    }

    /** Standard reducing-balance EMI: P * r * (1+r)^n / ((1+r)^n - 1), rounded to the rupee. */
    public static Decimal emi(Decimal principal, Decimal annualRatePct, Integer months) {
        if (principal == null || principal <= 0 || months == null || months <= 0) {
            return 0;
        }
        if (annualRatePct == null || annualRatePct == 0) {
            return (principal / months).setScale(0, RoundingMode.HALF_UP);
        }
        Double r = annualRatePct.doubleValue() / 12 / 100;
        Double factor = Math.pow(1 + r, months);
        return Decimal.valueOf(principal.doubleValue() * r * factor / (factor - 1)).setScale(0, RoundingMode.HALF_UP);
    }

    /** Inverse of emi(): the principal a given EMI can service. */
    public static Decimal principalFor(Decimal emiAmount, Decimal annualRatePct, Integer months) {
        if (emiAmount == null || emiAmount <= 0) {
            return 0;
        }
        Double r = annualRatePct.doubleValue() / 12 / 100;
        Double factor = Math.pow(1 + r, months);
        return Decimal.valueOf(emiAmount.doubleValue() * (factor - 1) / (r * factor));
    }

    public static Decimal roundDown(Decimal amount, Decimal step) {
        return (amount / step).round(System.RoundingMode.DOWN) * step;
    }
}
