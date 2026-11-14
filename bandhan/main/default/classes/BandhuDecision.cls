/**
 * Submits a card application, runs the checks and routes it (explainable, assist-only):
 *   any Fail -> Decline (with the best lower card the applicant still qualifies for);
 *   any Refer or Pending -> Refer to the card underwriting team;
 *   all Pass -> Approve straight through and issue the virtual card.
 * The underwriter approves or declines referred applications from the Card Application page (decide()).
 */
public inherited sharing class BandhuDecision {
    public static final String APPROVE = 'Approve';
    public static final String REFER = 'Refer';
    public static final String DECLINE = 'Decline';

    public class Outcome {
        public Card_Application__c application;
        public String recommendation;
        public String alternativeCard;
        public List<Card_Check__c> checks = new List<Card_Check__c>();
    }

    public static Outcome submit(Card_Journey__c j) {
        Bandhu_Config__mdt cfg = BandhuConfig.get();
        Card_Application__c app = j.Card_Application__c == null ? new Card_Application__c() : new Card_Application__c(Id = j.Card_Application__c);
        app.Card_Journey__c = j.Id;
        app.Contact__c = j.Contact__c;
        app.Lead__c = j.Lead__c;
        app.Applicant_Name__c = j.Customer_Name__c;
        for (String f : new List<String>{ 'Mobile__c', 'PAN__c', 'Date_Of_Birth__c', 'Email__c', 'PIN_Code__c', 'City__c', 'Employment_Type__c',
                'Company_Name__c', 'Monthly_Income__c', 'Verified_Income__c', 'Customer_Type__c', 'Eligible_Cards__c', 'Channel__c' }) {
            app.put(f, j.get(f));
        }
        app.Card_Product__c = j.Chosen_Card__c;
        app.Fit_Summary__c = j.Recommendation_Reason__c;
        app.Submitted_At__c = Datetime.now();
        app.Status__c = 'Submitted';
        upsert app;
        if (String.isBlank(j.Reference_Number__c)) {
            Card_Application__c withName = [SELECT Name FROM Card_Application__c WHERE Id = :app.Id];
            j.Reference_Number__c = (String.isBlank(cfg.Reference_Prefix__c) ? 'BBL-CC' : cfg.Reference_Prefix__c) + '-'
                + Datetime.now().format('yyMMdd', BandhuI18n.TIMEZONE) + '-' + withName.Name.right(6);
        }
        app.Reference_Number__c = j.Reference_Number__c;
        j.Card_Application__c = app.Id;

        Outcome o = new Outcome();
        o.application = app;
        delete [SELECT Id FROM Card_Check__c WHERE Card_Application__c = :app.Id];
        BandhuBureau.Report hard = BandhuBureau.pull(j.PAN__c, 'Hard');
        BandhuBureau.apply(j, hard);
        BandhuProviders.Report bureau = BandhuProviders.bureauReport(hard);
        app.CIBIL_Score__c = bureau.score;
        List<BandhuProviders.Report> reports = new List<BandhuProviders.Report>{
            BandhuProviders.panCheck(j.PAN__c, j.Customer_Name__c),
            BandhuProviders.aadhaar(null, j.Customer_Type__c == BandhuJourneyService.EXISTING),
            bureau,
            BandhuProviders.income(j),
            BandhuProviders.videoKyc(j),
            BandhuProviders.fraud(j.PAN__c, j.Mobile__c, app.Id),
            BandhuProviders.dueDiligence(j)
        };
        List<String> names = new List<String>{ 'PAN Verification', 'Aadhaar eKYC', 'Credit Bureau', 'Income Verification', 'Video KYC', 'Dedupe & Fraud', 'Customer Due Diligence' };
        for (Integer i = 0; i < reports.size(); i++) {
            o.checks.add(check(app.Id, names[i], reports[i], i + 1));
        }

        // card policy: re-run eligibility with the hard bureau score and the verified income
        BandhuEligibility.Outcome elig = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        BandhuEligibility.Option chosen;
        for (BandhuEligibility.Option opt : elig.options) {
            if (opt.card.DeveloperName == j.Chosen_Card__c) {
                chosen = opt;
            }
        }
        BandhuProviders.Report policy = new BandhuProviders.Report();
        policy.provider = 'Bandhan card policy';
        if (chosen != null && chosen.eligible && !chosen.refer) {
            policy.result = 'Pass';
            policy.summary = j.Chosen_Card__c + ': income, age and score within policy';
            app.Credit_Limit__c = chosen.creditLimit;
        } else if (chosen != null && chosen.eligible) {
            policy.result = 'Refer';
            policy.summary = j.Chosen_Card__c + ': ' + (chosen.referNote != null ? chosen.referNote : 'CIBIL ' + bureau.score + ' in the refer band');
            app.Credit_Limit__c = chosen.creditLimit;
        } else {
            policy.result = 'Fail';
            policy.summary = j.Chosen_Card__c + ': ' + (chosen == null || chosen.reasons.isEmpty() ? (elig.blockedReason == null ? 'not eligible' : elig.blockedReason) : String.join(chosen.reasons, '; '));
        }
        policy.details.add('Eligible cards: ' + (elig.eligibleNames().isEmpty() ? 'none' : String.join(elig.eligibleNames(), ', ')));
        o.checks.add(check(app.Id, 'Card Policy', policy, 8));
        insert o.checks;

        Boolean anyFail = false;
        Boolean anyRefer = false;
        List<String> reasons = new List<String>();
        for (Card_Check__c c : o.checks) {
            if (c.Result__c == 'Fail') {
                anyFail = true;
                reasons.add('✕ ' + c.Check__c + ': ' + c.Summary__c);
            } else if (c.Result__c == 'Refer' || c.Result__c == 'Pending') {
                anyRefer = true;
                reasons.add('⚠ ' + c.Check__c + ': ' + c.Summary__c);
            }
        }
        o.recommendation = anyFail ? DECLINE : anyRefer ? REFER : APPROVE;
        if (reasons.isEmpty()) {
            reasons.add('✓ All checks passed: straight-through approval');
        }
        app.Recommendation__c = o.recommendation;
        app.Recommendation_Reasons__c = String.join(reasons, '\n');
        app.Eligible_Cards__c = String.join(elig.eligibleNames(), ';');
        j.Eligible_Cards__c = app.Eligible_Cards__c;
        if (o.recommendation == APPROVE) {
            app.Status__c = 'Card Issued';
            app.Decision__c = 'Approved';
            app.Decision_At__c = Datetime.now();
            app.Card_Number_Masked__c = BandhuProviders.issueCard(app);
            app.Card_Issued_At__c = Datetime.now();
            j.Stage__c = 'Issued';
            j.Status__c = BandhuJourneyService.STATUS_COMPLETED;
        } else if (o.recommendation == REFER) {
            app.Status__c = 'Under Review';
            BandhuJourneyService.advance(j, 'Decision');
        } else {
            app.Status__c = 'Declined';
            app.Decision__c = 'Declined';
            app.Decision_At__c = Datetime.now();
            BandhuJourneyService.advance(j, 'Decision');
            for (BandhuEligibility.Option opt : elig.options) {
                if (opt.eligible && opt.card.DeveloperName != j.Chosen_Card__c && (o.alternativeCard == null
                        || opt.card.Tier__c > BandhuConfig.card(o.alternativeCard).Tier__c)) {
                    o.alternativeCard = opt.card.DeveloperName;
                }
            }
        }
        update app;
        o.application = app;
        return o;
    }

    private static Card_Check__c check(Id appId, String name, BandhuProviders.Report r, Integer sortOrder) {
        return new Card_Check__c(
            Card_Application__c = appId, Check__c = name, Provider__c = r.provider, Result__c = r.result, Score__c = r.score,
            Summary__c = r.summary == null ? null : r.summary.abbreviate(255), Details__c = String.join(r.details, '\n'),
            Report_Data__c = r.data == null ? null : r.data.abbreviate(131072),
            Sort_Order__c = sortOrder, Run_At__c = Datetime.now()
        );
    }

    /**
     * Underwriter decision on the Card Application page. Going against the recommendation needs notes.
     * Approving issues the virtual card; either way the customer is told on WhatsApp.
     */
    public static Card_Application__c decide(Id appId, String decision, String notes) {
        Card_Application__c app = [
            SELECT Id, Name, Status__c, Recommendation__c, Card_Product__c, Credit_Limit__c, Card_Journey__c, Reference_Number__c,
                Applicant_Name__c, Monthly_Income__c, Card_Number_Masked__c
            FROM Card_Application__c WHERE Id = :appId
        ];
        if (app.Status__c == 'Card Issued' || app.Status__c == 'Declined') {
            throw new BandhuException('This application is already decided (' + app.Status__c + ').');
        }
        Boolean isApproved = decision == 'Approved';
        Boolean deviation = (isApproved && app.Recommendation__c == DECLINE) || (!isApproved && app.Recommendation__c == APPROVE);
        if (deviation && String.isBlank(notes)) {
            throw new BandhuException('Please add notes: this decision goes against the ' + app.Recommendation__c + ' recommendation.');
        }
        app.Decision__c = isApproved ? 'Approved' : 'Declined';
        app.Decision_Notes__c = notes;
        app.Decision_By__c = UserInfo.getUserId();
        app.Decision_At__c = Datetime.now();
        if (isApproved) {
            if (app.Credit_Limit__c == null) {
                Bandhu_Card__mdt c = BandhuConfig.card(app.Card_Product__c);
                app.Credit_Limit__c = c == null ? null : BandhuEligibility.limitFor(c, app.Monthly_Income__c);
            }
            app.Card_Number_Masked__c = BandhuProviders.issueCard(app);
            app.Card_Issued_At__c = Datetime.now();
            app.Status__c = 'Card Issued';
        } else {
            app.Status__c = 'Declined';
        }
        update app;
        if (app.Card_Journey__c != null) {
            Card_Journey__c j = BandhuJourneyService.byId(app.Card_Journey__c);
            j.Status__c = BandhuJourneyService.STATUS_COMPLETED;
            j.Stage__c = isApproved ? 'Issued' : j.Stage__c;
            j.Step__c = 'done';
            update j;
            String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
            String body = BandhuI18n.msg(isApproved ? 'Decision_Approved_RM' : 'Decision_Declined_RM', j.Language__c, new Map<String, Object>{
                'name' => first, 'card' => app.Card_Product__c, 'masked' => app.Card_Number_Masked__c,
                'limit' => BandhuI18n.inr(app.Credit_Limit__c), 'ref' => app.Reference_Number__c, 'link' => activationLink()
            });
            BandhuWhatsAppSender.enqueue(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(j.Id, body, null) });
        }
        return app;
    }

    public static String activationLink() {
        String base = BandhuConfig.get().Site_Url__c;
        return String.isBlank(base) ? 'bandhan.bank.in/activate' : base.removeEnd('/') + '?view=card';
    }
}
