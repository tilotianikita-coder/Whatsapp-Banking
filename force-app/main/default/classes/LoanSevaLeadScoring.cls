/**
 * Scores a new-to-bank prospect who dropped off, out of 100, from what the journey captured so far.
 *
 *   Monthly income            25   1L+ 25 | 50K+ 18 | at least New_Loan_Min_Income 10
 *   Repayment capacity (FOIR) 15   existing EMIs / income: under 20% 15 | under 40% 8 | within Max_FOIR_Pct 3
 *   Employment                10   Salaried 10 | Self-employed 6
 *   Ask vs eligibility        10   amount within income x New_Loan_Income_Multiple (capped at the max) 10 | above it 4
 *   Age                        5   Min_Age to Max_Age_At_Maturity
 *   Journey depth             35   mobile verified 5 | 2 per application detail (10) | offer seen 10
 *
 * This is the intent score: unknown answers score 0, so depth and quality both count. The Lead Rating comes from it
 * combined with the credit score (LoanSevaQualification): 70+ Hot, 40-69 Warm, below 40 Cold.
 */
public with sharing class LoanSevaLeadScoring {
    public static final Integer HOT = 70;
    public static final Integer WARM = 40;

    public class Score {
        public Integer points = 0;
        public String rating;
        public List<String> lines = new List<String>();

        public String detail() {
            return String.join(lines, '\n') + '\nIntent score: ' + points + '/100';
        }
    }

    public static Score score(Loan_Journey__c j) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Score s = new Score();
        Decimal income = monthlyIncome(j);

        Integer pts = 0;
        if (income != null) {
            pts = income >= 100000 ? 25 : income >= 50000 ? 18 : income >= nz(cfg.New_Loan_Min_Income__c, 25000) ? 10 : 0;
        }
        add(s, 'Monthly income ' + (income == null ? 'not shared' : LoanSevaI18n.inr(income)), pts, 25);

        pts = 0;
        String foirText = 'not shared';
        if (income != null && income > 0 && j.Existing_EMIs__c != null) {
            Decimal foir = (j.Existing_EMIs__c * 100 / income).setScale(0);
            foirText = foir + '% of income';
            pts = foir < 20 ? 15 : foir < 40 ? 8 : foir <= nz(cfg.Max_FOIR_Pct__c, 55) ? 3 : 0;
        }
        add(s, 'Existing EMIs ' + foirText, pts, 15);

        pts = j.Employment_Type__c == 'Salaried' ? 10 : j.Employment_Type__c == 'Self-employed' ? 6 : 0;
        add(s, 'Employment ' + (String.isBlank(j.Employment_Type__c) ? 'not shared' : j.Employment_Type__c), pts, 10);

        pts = 0;
        String askText = 'not shared';
        if (j.Desired_Amount__c != null) {
            askText = LoanSevaI18n.inr(j.Desired_Amount__c);
            Decimal cap = nz(cfg.New_Loan_Max_Amount__c, 2500000);
            if (income != null) {
                cap = Math.min(cap, income * nz(cfg.New_Loan_Income_Multiple__c, 20));
            }
            pts = j.Desired_Amount__c <= cap ? 10 : 4;
            askText += pts == 10 ? ' (within eligibility)' : ' (above eligibility)';
        }
        add(s, 'Amount asked ' + askText, pts, 10);

        Integer age = age(j.Date_Of_Birth__c);
        pts = age != null && age >= nz(cfg.Min_Age__c, 21) && age <= nz(cfg.Max_Age_At_Maturity__c, 60) ? 5 : 0;
        add(s, 'Age ' + (age == null ? 'not shared' : String.valueOf(age)), pts, 5);

        Integer answered = answeredSteps(j);
        pts = (j.OTP_Verified__c == true ? 5 : 0) + 2 * answered + (j.Offer_Amount__c != null ? 10 : 0);
        add(s, 'Journey depth: ' + (j.OTP_Verified__c == true ? 'mobile verified, ' : 'mobile not verified, ') + answered + '/'
            + LoanSevaNewLoan.FIELDS.size() + ' details' + (j.Offer_Amount__c != null ? ', offer seen' : ''), pts, 35);

        s.rating = rating(s.points);
        return s;
    }

    public static String rating(Integer points) {
        return points >= HOT ? 'Hot' : points >= WARM ? 'Warm' : 'Cold';
    }

    /** Application details answered so far (date of birth ... amount). */
    public static Integer answeredSteps(Loan_Journey__c j) {
        Integer n = 0;
        for (String field : LoanSevaNewLoan.FIELDS) {
            if (LoanSevaNewLoan.isAnswered(j, field)) {
                n++;
            }
        }
        return n;
    }

    private static Decimal monthlyIncome(Loan_Journey__c j) {
        if (j.Monthly_Income__c != null) {
            return j.Monthly_Income__c;
        }
        return String.isBlank(j.Income_Bucket__c) ? null : LoanSevaConfig.incomeValues().get(j.Income_Bucket__c);
    }

    private static Integer age(Date dob) {
        if (dob == null) {
            return null;
        }
        Date today = LoanSevaI18n.todayIst();
        Integer years = today.year() - dob.year();
        return Date.newInstance(today.year(), dob.month(), dob.day()) > today ? years - 1 : years;
    }

    private static void add(Score s, String label, Integer pts, Integer max) {
        s.points += pts;
        s.lines.add(label + ': ' + pts + '/' + max);
    }

    private static Decimal nz(Decimal value, Decimal fallback) {
        return value == null ? fallback : value;
    }
}
