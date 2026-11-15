/**
 * Data for the Bandhu Lightning components: the underwriter's Card Application review (bandhuApplicationReview),
 * the Lead insight with the WhatsApp nudge (bandhuLeadInsight) and the specialist handoff panel (bandhuHandoff).
 */
public with sharing class BandhuConsoleController {
    public class Check {
        @AuraEnabled public String name;
        @AuraEnabled public String provider;
        @AuraEnabled public String result;
        @AuraEnabled public String summary;
        @AuraEnabled public String details;
        @AuraEnabled public Decimal score;
    }

    public class Review {
        @AuraEnabled public Card_Application__c application;
        @AuraEnabled public List<Check> checks = new List<Check>();
        @AuraEnabled public BandhuEngine.CardView card;
        @AuraEnabled public String needs;
        @AuraEnabled public String why;
        @AuraEnabled public String eligible;
        @AuraEnabled public Boolean decided;
        @AuraEnabled public Boolean approveIsDeviation;
        @AuraEnabled public Boolean declineIsDeviation;
        @AuraEnabled public CashFlowView cashFlow;
        @AuraEnabled public ScoreView score;
    }

    /** The Account Aggregator analysis as the underwriter sees it. */
    public class CashFlowView {
        @AuraEnabled public String consentId;
        @AuraEnabled public String purpose;
        @AuraEnabled public String period;
        @AuraEnabled public Integer months;
        @AuraEnabled public Integer banks;
        @AuraEnabled public Integer accounts;
        @AuraEnabled public Integer transactions;
        @AuraEnabled public String netIncome;
        @AuraEnabled public String declaredIncome;
        @AuraEnabled public String incomeSource;
        @AuraEnabled public Integer stability;
        @AuraEnabled public String trend;
        @AuraEnabled public String growth;
        @AuraEnabled public String emi;
        @AuraEnabled public Integer foir;
        @AuraEnabled public String outflow;
        @AuraEnabled public String surplus;
        @AuraEnabled public String avgBalance;
        @AuraEnabled public String cardSpend;
        @AuraEnabled public List<SpendRow> spend = new List<SpendRow>();
        @AuraEnabled public List<SpendRow> outflowParts = new List<SpendRow>();
        @AuraEnabled public String declaredSpend;
        @AuraEnabled public String spendGapFlag;
        @AuraEnabled public List<String> lifestyle = new List<String>();
        @AuraEnabled public String seasonality;
        @AuraEnabled public List<String> anomalies = new List<String>();
    }

    public class SpendRow {
        @AuraEnabled public String category;
        @AuraEnabled public String amount;
        @AuraEnabled public Integer pct;
        @AuraEnabled public Boolean highlight = false;
    }

    /** The Bandhan Score and each factor's contribution (the audit log on the application). */
    public class ScoreView {
        @AuraEnabled public Integer score;
        @AuraEnabled public String band;
        @AuraEnabled public String model;
        @AuraEnabled public List<FactorRow> factors = new List<FactorRow>();
    }

    public class FactorRow {
        @AuraEnabled public String name;
        @AuraEnabled public String value;
        @AuraEnabled public String source;
        @AuraEnabled public Integer points;
        @AuraEnabled public Integer maxPoints;
        @AuraEnabled public Integer pct;
    }

    @AuraEnabled
    public static Review getReview(Id applicationId) {
        Review r = new Review();
        r.application = [
            SELECT Id, Name, Applicant_Name__c, Mobile__c, PAN__c, Date_Of_Birth__c, Email__c, City__c, PIN_Code__c, Employment_Type__c,
                Company_Name__c, Monthly_Income__c, Verified_Income__c, Customer_Type__c, CIBIL_Score__c, Eligible_Cards__c, Card_Product__c,
                Credit_Limit__c, Channel__c, Recommendation__c, Recommendation_Reasons__c, Fit_Summary__c, Status__c, Decision__c,
                Decision_Notes__c, Decision_By__r.Name, Decision_At__c, Submitted_At__c, Reference_Number__c, Card_Number_Masked__c,
                Card_Issued_At__c, Card_Journey__c, Card_Journey__r.Spend_Focus__c, Card_Journey__r.Monthly_Spend__c,
                Card_Journey__r.Fee_Preference__c, Card_Journey__r.Recommended_Card__c, Bandhan_Score__c, Score_Band__c, Score_Factors__c, Model_Version__c, Limit_Range__c, FD_Amount__c
            FROM Card_Application__c WHERE Id = :applicationId
        ];
        r.application.PAN__c = BandhuI18n.maskPan(r.application.PAN__c);
        for (Card_Check__c c : [
            SELECT Check__c, Provider__c, Result__c, Summary__c, Details__c, Score__c FROM Card_Check__c
            WHERE Card_Application__c = :applicationId ORDER BY Sort_Order__c
        ]) {
            Check ch = new Check();
            ch.name = c.Check__c;
            ch.provider = c.Provider__c;
            ch.result = c.Result__c;
            ch.summary = c.Summary__c;
            ch.details = c.Details__c;
            ch.score = c.Score__c;
            r.checks.add(ch);
        }
        Bandhu_Card__mdt card = BandhuConfig.card(r.application.Card_Product__c);
        if (card != null) {
            BandhuEngine.CardView v = new BandhuEngine.CardView();
            v.name = card.DeveloperName;
            v.tagline = card.Tagline__c;
            v.color = card.Color__c;
            v.joiningFee = card.Joining_Fee__c == null ? 0 : card.Joining_Fee__c.intValue();
            v.rewards = card.Rewards__c;
            v.lounge = card.Lounge__c;
            v.welcome = card.Welcome__c;
            v.creditLimit = BandhuI18n.inr(r.application.Credit_Limit__c);
            v.tierLabel = card.Tier_Label__c;
            v.secured = card.Secured__c == true;
            r.card = v;
        }
        journeySummary(r);
        r.cashFlow = cashFlowView(r.application);
        r.score = scoreView(r.application);
        r.decided = r.application.Status__c == 'Card Issued' || r.application.Status__c == 'Declined';
        r.approveIsDeviation = r.application.Recommendation__c == BandhuDecision.DECLINE;
        r.declineIsDeviation = r.application.Recommendation__c == BandhuDecision.APPROVE;
        return r;
    }

    private static CashFlowView cashFlowView(Card_Application__c app) {
        if (app.Card_Journey__c == null) {
            return null;
        }
        Card_Journey__c jr = BandhuJourneyService.byId(app.Card_Journey__c);
        BandhuCashFlow.Analysis a = BandhuCashFlow.fromJourney(jr);
        if (a == null) {
            return null;
        }
        CashFlowView v = new CashFlowView();
        v.consentId = a.consentId;
        v.purpose = a.purpose;
        v.period = BandhuI18n.formatDate(a.fromDate) + ' - ' + BandhuI18n.formatDate(a.toDate);
        v.months = a.months;
        v.banks = a.banks;
        v.accounts = a.accounts;
        v.transactions = a.transactions;
        v.netIncome = BandhuI18n.inr(a.netMonthlyIncome);
        v.declaredIncome = a.declaredIncome == null ? null : BandhuI18n.inr(a.declaredIncome);
        v.incomeSource = a.incomeSource;
        v.stability = a.incomeStability;
        v.trend = a.incomeTrend;
        v.growth = (a.incomeGrowthPct >= 0 ? '+' : '') + a.incomeGrowthPct + '% year on year';
        v.emi = BandhuI18n.inr(a.monthlyObligations);
        v.foir = a.foirPct == null ? 0 : a.foirPct.intValue();
        v.outflow = BandhuI18n.inr(a.avgMonthlyOutflow);
        v.surplus = BandhuI18n.inr(a.monthlySurplus);
        v.avgBalance = a.avgBalance == null ? null : BandhuI18n.inr(a.avgBalance);
        v.cardSpend = BandhuI18n.inr(a.monthlyCardSpend);
        List<String> cats = new List<String>(a.spend.keySet());
        cats.sort();
        // largest first
        for (Integer i = 0; i < cats.size(); i++) {
            for (Integer k = i + 1; k < cats.size(); k++) {
                if (a.spend.get(cats[k]) > a.spend.get(cats[i])) {
                    String t = cats[i];
                    cats[i] = cats[k];
                    cats[k] = t;
                }
            }
        }
        for (String c : cats) {
            SpendRow row = new SpendRow();
            row.category = c == 'International' ? 'Travel abroad' : c;
            row.amount = BandhuI18n.inr(a.spend.get(c));
            row.pct = a.monthlyCardSpend == 0 ? 0 : (a.spend.get(c) / a.monthlyCardSpend * 100).intValue();
            v.spend.add(row);
        }
        // the outflow, card-able spend first (it is the part a card can take), then the rest largest first
        Decimal total = 0;
        for (Decimal d : a.outflowBy.values()) {
            total += d;
        }
        List<String> order = new List<String>{ 'Card-able spend', 'Rent', 'EMIs', 'Investments', 'Cash', 'Bills', 'Other transfers' };
        for (String g : order) {
            Decimal amt = g == 'Card-able spend' ? a.monthlyCardSpend : a.outflowBy.get(g);   // one figure everywhere
            if (amt == null || amt <= 0) {
                continue;
            }
            SpendRow row = new SpendRow();
            row.category = g;
            row.amount = BandhuI18n.inr(amt);
            row.pct = total == 0 ? 0 : (amt / total * 100).round(System.RoundingMode.HALF_UP).intValue();
            row.highlight = g == 'Card-able spend';
            v.outflowParts.add(row);
        }
        // what the customer said they would spend on the card vs what the statements show today
        if (jr.Monthly_Spend__c != null) {
            v.declaredSpend = BandhuI18n.inr(jr.Monthly_Spend__c);
            if (jr.Monthly_Spend__c > a.monthlyCardSpend * 2 && jr.Monthly_Spend__c - a.monthlyCardSpend > 20000) {
                v.spendGapFlag = 'Declared card spend ' + BandhuI18n.inr(jr.Monthly_Spend__c) + ' a month is ' + (a.monthlyCardSpend == 0 ? 'far'
                    : (jr.Monthly_Spend__c / a.monthlyCardSpend).setScale(1) + 'x') + ' the ' + BandhuI18n.inr(a.monthlyCardSpend)
                    + ' card-able spend in the statements: check the limit is not sized on the declared figure';
            }
        }
        v.lifestyle = a.lifestyle;
        v.seasonality = a.seasonality;
        v.anomalies = a.anomalies;
        return v;
    }

    private static ScoreView scoreView(Card_Application__c app) {
        if (String.isBlank(app.Score_Factors__c)) {
            return null;
        }
        BandhuScore.Result res;
        try {
            res = (BandhuScore.Result) JSON.deserialize(app.Score_Factors__c, BandhuScore.Result.class);
        } catch (Exception e) {
            return null;
        }
        ScoreView v = new ScoreView();
        v.score = res.score;
        v.band = res.band;
        v.model = res.model;
        for (BandhuScore.Factor f : res.factors) {
            FactorRow row = new FactorRow();
            row.name = f.name;
            row.value = f.value;
            row.source = f.source;
            row.points = f.points;
            row.maxPoints = f.maxPoints;
            row.pct = f.maxPoints == 0 ? 0 : f.points * 100 / f.maxPoints;
            v.factors.add(row);
        }
        return v;
    }

    private static void journeySummary(Review r) {
        Card_Journey__c j = r.application.Card_Journey__r;
        if (j == null) {
            return;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(j.Spend_Focus__c)) {
            parts.add('Spends on ' + j.Spend_Focus__c.replace(';', ', ').toLowerCase());
        }
        if (j.Monthly_Spend__c != null) {
            parts.add('about ' + BandhuI18n.inrShort(j.Monthly_Spend__c) + ' a month');
        }
        if (String.isNotBlank(j.Fee_Preference__c)) {
            parts.add('prefers ' + j.Fee_Preference__c.toLowerCase());
        }
        r.needs = String.join(parts, ' · ');
        r.why = r.application.Fit_Summary__c;
        r.eligible = String.isBlank(r.application.Eligible_Cards__c) ? 'None' : r.application.Eligible_Cards__c.replace(';', ', ');
    }

    @AuraEnabled
    public static Review decide(Id applicationId, String decision, String notes) {
        try {
            BandhuDecision.decide(applicationId, decision, notes);
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
        return getReview(applicationId);
    }

    // ------------------------------------------------------------------ Lead insight
    public class Insight {
        @AuraEnabled public Boolean hasJourney = false;
        @AuraEnabled public String customerName;
        @AuraEnabled public String mobile;
        @AuraEnabled public String channel;
        @AuraEnabled public String step;
        @AuraEnabled public String status;
        @AuraEnabled public String dropPoint;
        @AuraEnabled public Integer detailsDone;
        @AuraEnabled public Decimal intent;
        @AuraEnabled public Decimal credit;
        @AuraEnabled public Decimal combined;
        @AuraEnabled public String rating;
        @AuraEnabled public Decimal cibil;
        @AuraEnabled public String recommended;
        @AuraEnabled public String eligible;
        @AuraEnabled public String needs;
        @AuraEnabled public String income;
        @AuraEnabled public String creditLimit;
        @AuraEnabled public List<String> scoreLines = new List<String>();
        @AuraEnabled public Boolean canNudge = false;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public Datetime lastNudged;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String stageGate;
        @AuraEnabled public String region;
        @AuraEnabled public String confidence;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public List<Gate> gates = new List<Gate>();
        @AuraEnabled public List<String> path = new List<String>();
        @AuraEnabled public Integer pathIndex;
        @AuraEnabled public String cardTier;
        @AuraEnabled public String cardColor;
        @AuraEnabled public String cardTagline;
        @AuraEnabled public Decimal bandhanScore;
        @AuraEnabled public String cashFlow;
        @AuraEnabled public String customerType;
        @AuraEnabled public String language;
    }

    public class Gate {
        @AuraEnabled public String gate;
        @AuraEnabled public String provider;
        @AuraEnabled public String result;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal points;
        @AuraEnabled public Decimal maxPoints;
        @AuraEnabled public Boolean knockout;
    }

    /** The prospect's journey milestones, for the path on the Lead page. */
    // the journey's stages in the order they are asked (income source and Account Aggregator come before the needs)
    private static final List<String> PATH = new List<String>{ 'Verified & details', 'Income & statements', 'Needs', 'Credit check', 'Recommendation', 'KYC', 'Submitted' };

    /** The stage the customer is in now (6 = submitted, shown as done). */
    private static Integer pathIndex(Card_Journey__c j) {
        if (j.Status__c == BandhuJourneyService.STATUS_COMPLETED || j.Card_Application__c != null) {
            return 6;
        }
        Map<String, Integer> byStep = new Map<String, Integer>{ 'menu' => 0, 'consent' => 0, 'name' => 0, 'mobile' => 0, 'otp' => 0, 'hold' => 0,
            'email' => 0, 'dob' => 0, 'pincode' => 0, 'pan' => 0,
            'employment' => 1, 'income' => 1, 'aa' => 1, 'company' => 1,
            'spend' => 2, 'monthly_spend' => 2, 'fee' => 2,
            'bureau' => 3,
            'choose' => 4, 'not_eligible' => 4, 'applied_alt' => 4, 'secured_offer' => 4, 'after_compare' => 4,
            'aadhaar' => 5, 'aadhaar_otp' => 5, 'vkyc' => 5, 'review' => 5 };
        Integer idx = byStep.get(j.Step__c);
        return idx == null ? 0 : idx;
    }

    @AuraEnabled
    public static Insight getLeadInsight(Id leadId) {
        Insight i = new Insight();
        Lead l = [
            SELECT Id, Name, MobilePhone, Rating, Status, IsConverted, Bandhu_Journey__c, Bandhu_Intent_Score__c, Bandhu_Credit_Score__c,
                Bandhu_Combined_Score__c, Bandhu_CIBIL__c, Bandhu_Recommended_Card__c, Bandhu_Eligible_Cards__c, Bandhu_Drop_Point__c,
                Bandhu_Score_Detail__c, Bandhu_Last_Nudged__c, Bandhu_Stage_Gate__c, Bandhu_Region__c, Bandhu_Credit_Confidence__c
            FROM Lead WHERE Id = :leadId
        ];
        i.customerName = l.Name;
        i.intent = l.Bandhu_Intent_Score__c;
        i.credit = l.Bandhu_Credit_Score__c;
        i.combined = l.Bandhu_Combined_Score__c;
        i.rating = l.Rating;
        i.cibil = l.Bandhu_CIBIL__c;
        i.recommended = l.Bandhu_Recommended_Card__c;
        i.eligible = String.isBlank(l.Bandhu_Eligible_Cards__c) ? null : l.Bandhu_Eligible_Cards__c.replace(';', ', ');
        i.dropPoint = l.Bandhu_Drop_Point__c;
        i.lastNudged = l.Bandhu_Last_Nudged__c;
        i.scoreLines = String.isBlank(l.Bandhu_Score_Detail__c) ? new List<String>() : l.Bandhu_Score_Detail__c.split('\n');
        i.stageGate = l.Bandhu_Stage_Gate__c;
        i.region = l.Bandhu_Region__c;
        i.confidence = l.Bandhu_Credit_Confidence__c;
        i.leadStatus = l.Status;
        Boolean knocked = false;
        for (Bandhu_Lead_Check__c c : [
            SELECT Gate__c, Provider__c, Result__c, Summary__c, Points__c, Max_Points__c, Knockout__c
            FROM Bandhu_Lead_Check__c WHERE Lead__c = :leadId ORDER BY Sort_Order__c
        ]) {
            Gate g = new Gate();
            g.gate = c.Gate__c;
            g.provider = c.Provider__c;
            g.result = c.Result__c;
            g.summary = c.Summary__c;
            g.points = c.Points__c;
            g.maxPoints = c.Max_Points__c;
            g.knockout = c.Knockout__c;
            knocked = knocked || c.Knockout__c;
            i.gates.add(g);
        }
        i.path = PATH;
        if (l.Bandhu_Journey__c == null) {
            i.blockedReason = 'No Bandhu card journey on this lead.';
            return i;
        }
        Card_Journey__c j = BandhuJourneyService.byId(l.Bandhu_Journey__c);
        i.hasJourney = true;
        i.mobile = BandhuI18n.maskMobile(j.Mobile__c);
        i.channel = j.Channel__c;
        i.step = BandhuLeadService.stepLabel(j);
        i.status = j.Status__c;
        i.detailsDone = BandhuJourneyService.fieldsDone(j);
        i.needs = String.isBlank(j.Spend_Focus__c) ? null : j.Spend_Focus__c.replace(';', ', ');
        Decimal income = j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c;
        i.income = income == null ? null : BandhuI18n.inr(income) + (j.Verified_Income__c != null ? ' (verified)' : ' (declared)');
        i.creditLimit = j.Credit_Limit__c == null ? null : BandhuI18n.inr(j.Credit_Limit__c);
        i.applicationId = j.Card_Application__c;
        Bandhu_Card__mdt rc = String.isBlank(i.recommended) ? null : BandhuConfig.card(i.recommended);
        if (rc != null) {
            i.cardTier = rc.Tier_Label__c;
            i.cardColor = rc.Color__c;
            i.cardTagline = rc.Tagline__c;
        }
        i.bandhanScore = j.Bandhan_Score__c;
        i.customerType = j.Customer_Type__c == BandhuJourneyService.EXISTING ? 'Existing customer' : 'New to bank';
        i.language = j.Language__c == 'HI' ? 'Hindi' : j.Language__c == 'BN' ? 'Bengali' : 'English';
        BandhuCashFlow.Analysis cf = BandhuCashFlow.fromJourney(j);
        if (cf != null) {
            i.cashFlow = BandhuI18n.inr(cf.netMonthlyIncome) + '/month · stability ' + cf.incomeStability + '/100 (' + cf.incomeTrend.toLowerCase()
                + ') · EMIs ' + cf.foirPct.intValue() + '% · ' + cf.customerSpendText('EN') + (cf.anomalies.isEmpty() ? '' : ' · ⚠ ' + cf.anomalies.size() + ' flag(s)');
        }
        i.pathIndex = pathIndex(j);
        if (knocked) {
            i.blockedReason = 'Unqualified: ' + l.Bandhu_Stage_Gate__c.toLowerCase() + ' - no nudge.';
        } else if (l.IsConverted || j.Status__c == BandhuJourneyService.STATUS_COMPLETED) {
            i.blockedReason = 'Application completed - no nudge needed.';
        } else if (j.Mobile__c == null) {
            i.blockedReason = 'No mobile number yet.';
        } else {
            i.canNudge = true;
        }
        return i;
    }

    @AuraEnabled
    public static String nudge(Id leadId) {
        try {
            return BandhuLeadService.nudge(leadId);
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ------------------------------------------------------------------ handoff panel
    public class Handoff {
        @AuraEnabled public Boolean hasJourney = false;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerType;
        @AuraEnabled public String mobile;
        @AuraEnabled public String language;
        @AuraEnabled public String step;
        @AuraEnabled public String reason;
        @AuraEnabled public List<String> answers = new List<String>();
        @AuraEnabled public String recommendation;
        @AuraEnabled public String applicationStatus;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id contactId;
    }

    @AuraEnabled
    public static Handoff getHandoff(Id sessionId) {
        Handoff h = new Handoff();
        List<Card_Journey__c> js = [SELECT Id FROM Card_Journey__c WHERE Messaging_Session_Id__c = :sessionId ORDER BY LastModifiedDate DESC LIMIT 1];
        if (js.isEmpty()) {
            String mobile = BandhuJourneyService.sessionMobile(sessionId);
            if (mobile != null) {
                js = [SELECT Id FROM Card_Journey__c WHERE Mobile__c = :mobile ORDER BY LastModifiedDate DESC LIMIT 1];
            }
        }
        if (js.isEmpty()) {
            return h;
        }
        Card_Journey__c j = BandhuJourneyService.byId(js[0].Id);
        h.hasJourney = true;
        h.customerName = String.isBlank(j.Customer_Name__c) ? 'Not shared yet' : j.Customer_Name__c;
        h.customerType = j.Customer_Type__c == BandhuJourneyService.EXISTING ? 'Existing Bandhan Bank customer' : 'New to bank';
        h.mobile = BandhuI18n.maskMobile(j.Mobile__c);
        h.language = j.Language__c == 'HI' ? 'Hindi' : j.Language__c == 'BN' ? 'Bengali' : 'English';
        h.step = BandhuLeadService.stepLabel(j);
        h.leadId = j.Lead__c;
        h.contactId = j.Contact__c;
        h.applicationId = j.Card_Application__c;
        for (Task t : [SELECT Description FROM Task WHERE (WhatId = :j.Id OR WhoId = :j.Lead__c) AND Subject LIKE 'Bandhu: specialist%' ORDER BY CreatedDate DESC LIMIT 1]) {
            h.reason = t.Description;
        }
        add(h, 'Needs', j.Spend_Focus__c == null ? null : j.Spend_Focus__c.replace(';', ', '));
        add(h, 'Monthly spend', j.Monthly_Spend__c == null ? null : BandhuI18n.inrShort(j.Monthly_Spend__c));
        add(h, 'Fee preference', j.Fee_Preference__c);
        add(h, 'Employment', j.Employment_Type__c == null ? null : j.Employment_Type__c + (j.Company_Name__c == null ? '' : ' @ ' + j.Company_Name__c));
        Decimal income = j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c;
        add(h, 'Income', income == null ? null : BandhuI18n.inr(income) + (j.Verified_Income__c != null ? ' (verified)' : ' (declared)'));
        BandhuCashFlow.Analysis cf = BandhuCashFlow.fromJourney(j);
        if (cf != null) {
            add(h, 'Cash flow (AA)', 'stability ' + cf.incomeStability + '/100, ' + cf.incomeTrend.toLowerCase() + ' · EMIs ' + cf.foirPct.intValue()
                + '% of income · top spends ' + cf.topSpendText() + (cf.anomalies.isEmpty() ? '' : ' · ⚠ ' + cf.anomalies.size() + ' flag(s)'));
        }
        add(h, 'PAN', j.PAN__c == null ? null : BandhuI18n.maskPan(j.PAN__c));
        add(h, 'City', j.City__c == null ? null : j.City__c + ' ' + j.PIN_Code__c);
        add(h, 'CIBIL (soft)', j.CIBIL_Score__c == null ? null : String.valueOf(j.CIBIL_Score__c.intValue()));
        add(h, 'Eligible cards', j.Eligible_Cards__c == null ? null : j.Eligible_Cards__c.replace(';', ', '));
        add(h, 'KYC', j.KYC_Status__c);
        h.recommendation = j.Recommended_Card__c == null ? null : j.Recommended_Card__c + (j.Credit_Limit__c == null ? '' : ' · indicative limit ' + BandhuI18n.inr(j.Credit_Limit__c));
        if (j.Card_Application__c != null) {
            h.applicationStatus = [SELECT Status__c FROM Card_Application__c WHERE Id = :j.Card_Application__c].Status__c;
        }
        return h;
    }

    private static void add(Handoff h, String label, String value) {
        if (String.isNotBlank(value)) {
            h.answers.add(label + ': ' + value);
        }
    }
}
