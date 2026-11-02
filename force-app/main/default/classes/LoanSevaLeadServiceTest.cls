@IsTest
private class LoanSevaLeadServiceTest {
    private static final String MOBILE = '9123456781';
    private static Loan_Journey__c j;
    private static LoanSevaEngine.Result last;

    private static LoanSevaEngine.Result say(String text) {
        last = LoanSevaEngine.reply(j, text);
        j = last.journey;
        return last;
    }

    /** Mumbai served by the running user, Ladakh not served, everything else to the central desk. */
    private static void useRegions() {
        LoanSevaServiceability.regions = new List<LoanSeva_Region__mdt>{
            new LoanSeva_Region__mdt(MasterLabel = 'Mumbai MMR', PIN_Prefixes__c = '400, 401', Serviceable__c = true, RM_Username__c = UserInfo.getUserName()),
            new LoanSeva_Region__mdt(MasterLabel = 'Not serviceable', PIN_Prefixes__c = '194,744', Serviceable__c = false),
            new LoanSeva_Region__mdt(MasterLabel = 'Rest of India', PIN_Prefixes__c = '*', Serviceable__c = true)
        };
    }

    /** A new-to-bank application that goes quiet at "Existing EMIs" (7 of 10 details) and is picked up by the job. */
    private static void dropAfterIncome(String pinAnswer) {
        dropAfterIncome(pinAnswer, 'abcpp1234k', '1', '85k');
    }

    private static void dropAfterIncome(String pinAnswer, String pan, String consent, String income) {
        LoanSevaTestData.useLogOnly();
        useRegions();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        say('1');
        say('Asha Patil ' + MOBILE);
        say(LoanSevaConfig.get().Demo_OTP__c);
        for (String answer : new List<String>{ '15/08/1990', pan, consent, 'asha.patil@example.com', pinAnswer, '1', 'Infosys', income }) {
            say(answer);
        }
        System.assertEquals('obligations', LoanSevaEngine.awaiting(j));
        update new Loan_Journey__c(Id = j.Id, Last_Activity__c = Datetime.now().addMinutes(-60));
        LoanSevaDropOffJob.run();
        j = LoanSevaJourneyService.byId(j.Id);
    }

    @IsTest
    static void dropOffBecomesAScoredLeadForTheRegionRmWhoNudgesAndTheJourneyResumes() {
        dropAfterIncome('Mumbai 400001');
        System.assertEquals(LoanSevaJourneyService.STATUS_DROPPED, j.Status__c);
        System.assertEquals('Existing EMIs (7/10 details)', j.Drop_Point__c);
        System.assertEquals(null, j.Next_Nudge_At__c, 'The RM nudges a prospect, not the automatic re-engagement');
        System.assertNotEquals(null, j.Lead__c);

        Lead l = [
            SELECT FirstName, LastName, MobilePhone, Email, PostalCode, City, LeadSource, Status, Rating, OwnerId, LoanSeva_Score__c,
                LoanSeva_Score_Detail__c, LoanSeva_Region__c, LoanSeva_Serviceable__c, LoanSeva_Drop_Point__c, LoanSeva_Journey__c,
                LoanSeva_Credit_Score__c, LoanSeva_Combined_Score__c, LoanSeva_CIBIL_Score__c, LoanSeva_Eligibility__c,
                LoanSeva_Stage_Gate__c, LoanSeva_Bureau_Consent__c
            FROM Lead WHERE Id = :j.Lead__c
        ];
        System.assertEquals('Asha', l.FirstName);
        System.assertEquals('Patil', l.LastName);
        System.assertEquals(MOBILE, l.MobilePhone);
        System.assertEquals('400001', l.PostalCode);
        System.assertEquals(LoanSevaLeadService.SOURCE, l.LeadSource);
        System.assertEquals('New', l.Status);
        // income 85K 18 + salaried 10 + age 5 + depth (verified 5, 7 details 14) = 52
        System.assertEquals(52, l.LoanSeva_Score__c, l.LoanSeva_Score_Detail__c);
        // credit: CIBIL 777 34/40 + FOIR 0% 25/25 + Infosys verified 15/15 + Hunter clear 10/10 = 84/90 -> 93
        System.assertEquals(777, l.LoanSeva_CIBIL_Score__c);
        System.assertEquals(93, l.LoanSeva_Credit_Score__c);
        System.assertEquals(73, l.LoanSeva_Combined_Score__c, 'average of intent and credit');
        System.assertEquals('Hot', l.Rating);
        System.assertEquals('Qualified', l.LoanSeva_Stage_Gate__c);
        System.assertEquals('Given', l.LoanSeva_Bureau_Consent__c);
        System.assert(l.LoanSeva_Eligibility__c > 0, 'indicative eligibility from the declared income');
        System.assertEquals(LoanSevaQualification.QUALIFIED, j.Qualification_Status__c);
        System.assertEquals(93, j.Credit_Score__c);
        System.assertEquals(6, [SELECT COUNT() FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id AND Lead__c = :l.Id], 'one check per gate, on the Lead');
        System.assert(l.LoanSeva_Score_Detail__c.contains('Monthly income ₹85,000: 18/25'), l.LoanSeva_Score_Detail__c);
        System.assertEquals('Mumbai MMR', l.LoanSeva_Region__c);
        System.assert(l.LoanSeva_Serviceable__c);
        System.assertEquals(UserInfo.getUserId(), l.OwnerId, 'Owned by the region RM');
        System.assertEquals('Existing EMIs', l.LoanSeva_Drop_Point__c);
        System.assertEquals(j.Id, l.LoanSeva_Journey__c);

        Task t = [SELECT Subject, Description, OwnerId, WhoId, WhatId, Priority FROM Task WHERE WhoId = :l.Id];
        System.assert(t.Subject.contains('Hot lead 73/100 (Mumbai MMR) dropped at Existing EMIs'), t.Subject);
        System.assert(t.Description.contains('Stage gate: Qualified'), t.Description);
        System.assert(t.Description.contains('Intent score: 52/100'), t.Description);
        System.assert(t.Description.contains('Credit score: 93/100'), t.Description);
        System.assert(t.Description.contains('Combined: 73/100 (Hot)'), t.Description);
        System.assertEquals('High', t.Priority);
        System.assertEquals(UserInfo.getUserId(), t.OwnerId);

        // the job runs again: no duplicate lead or task, no automatic nudge
        LoanSevaDropOffJob.run();
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE MobilePhone = :MOBILE]);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id]);
        System.assertEquals(0, LoanSevaJourneyService.byId(j.Id).Nudges_Sent__c);

        LoanSevaLeadInsight.Insight insight = LoanSevaLeadInsight.getInsight(l.Id);
        System.assert(insight.canNudge, insight.blockedReason);
        System.assertEquals('Existing EMIs', insight.currentStep);
        System.assertEquals(7, insight.detailsDone);
        System.assert(insight.preview.startsWith('Hi Asha 👋'), insight.preview);
        System.assert(insight.preview.contains('7 of 10 details'), insight.preview);
        System.assertEquals(7, insight.scoreLines.size(), 'Six parameters and the total');
        System.assertEquals(73, insight.score);
        System.assertEquals(52, insight.intentScore);
        System.assertEquals(93, insight.creditScore);
        System.assertEquals(6, insight.gates.size());
        System.assertEquals(LoanSevaQualification.GATE_SERVICEABILITY, insight.gates[0].gate);
        for (LoanSevaLeadInsight.Gate g : insight.gates) {
            System.assertEquals('slds-path__item slds-is-complete', g.pathClass, g.gate + ': ' + g.summary);
        }
        System.assert(insight.preview.contains('indicative, subject to verification'), insight.preview);
        System.assert(insight.preview.indexOf('indicative') < insight.preview.indexOf('Continue'), 'the amount comes before the call to action');

        Test.startTest();
        String sent = LoanSevaLeadInsight.nudge(l.Id);
        Test.stopTest();
        j = LoanSevaJourneyService.byId(j.Id);
        System.assert(j.Last_Send_Status__c.startsWith('LogOnly') && j.Last_Send_Status__c.contains('Asha'), j.Last_Send_Status__c);
        System.assertEquals(1, j.Nudges_Sent__c);
        l = [SELECT Status, LoanSeva_Last_Nudged__c, LoanSeva_Resumed_At__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Working', l.Status);
        System.assertNotEquals(null, l.LoanSeva_Last_Nudged__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id AND IsClosed = FALSE], 'The drop-off task is done');
        System.assert([SELECT Description FROM Task WHERE WhoId = :l.Id AND Subject LIKE '%WhatsApp nudge sent'].Description.endsWith(sent), 'The nudge is logged');

        // the customer replies Continue: same step, nothing re-entered
        say('Continue');
        System.assertEquals(LoanSevaJourneyService.STATUS_ACTIVE, j.Status__c);
        System.assert(last.message.startsWith(LoanSevaI18n.msg('NL_Welcome_Back', 'EN', new Map<String, Object>{ 'name' => ' Asha' })), last.message);
        System.assert(last.message.contains(LoanSevaNewLoan.question(j, 'obligations')), last.message);
        System.assertNotEquals(null, [SELECT LoanSeva_Resumed_At__c FROM Lead WHERE Id = :l.Id].LoanSeva_Resumed_At__c);
        say('0');
        System.assertEquals('purpose', LoanSevaEngine.awaiting(j));
        System.assertEquals('Infosys', j.Company_Name__c, 'Answers from before the drop are kept');
    }

    @IsTest
    static void startJourneyAfterTheDropAlsoPicksUp() {
        dropAfterIncome('400001');
        LoanSevaEngine.Result r = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE, true));
        System.assertEquals(j.Id, r.journey.Id);
        System.assert(r.message.contains(LoanSevaNewLoan.question(r.journey, 'obligations')), r.message);
        System.assertEquals(false, r.journey.Menu_Pending__c);
    }

    @IsTest
    static void nonServiceablePinIsUnqualifiedWithNoTaskOrNudge() {
        dropAfterIncome('194101');
        Lead l = [SELECT Status, LoanSeva_Serviceable__c, LoanSeva_Region__c FROM Lead WHERE Id = :j.Lead__c];
        System.assertEquals('Unqualified', l.Status);
        System.assert(!l.LoanSeva_Serviceable__c);
        System.assertEquals('Not serviceable', l.LoanSeva_Region__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id AND IsClosed = FALSE], 'no RM call');
        Task logged = [SELECT Subject, Status FROM Task WHERE WhoId = :l.Id];
        System.assert(logged.Subject.contains('PIN code 194101 is outside the serviceable regions'), logged.Subject);
        System.assert(!LoanSevaLeadInsight.getInsight(l.Id).canNudge);
        try {
            LoanSevaLeadInsight.nudge(l.Id);
            System.assert(false, 'A non-serviceable lead is not nudged');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    private static Lead qualifiedLead() {
        return [
            SELECT Status, Rating, LoanSeva_Stage_Gate__c, LoanSeva_Credit_Score__c, LoanSeva_Combined_Score__c, LoanSeva_CIBIL_Score__c,
                LoanSeva_Eligibility__c, LoanSeva_Bureau_Consent__c
            FROM Lead WHERE Id = :j.Lead__c
        ];
    }

    private static void assertKnockedOut(String gate, String reason) {
        Lead l = qualifiedLead();
        System.assertEquals(LoanSevaQualification.KNOCKED_OUT, j.Qualification_Status__c);
        System.assertEquals(gate, j.Qualification_Gate__c);
        System.assert(j.Knockout_Reason__c.contains(reason), j.Knockout_Reason__c);
        System.assertEquals('Unqualified', l.Status);
        System.assertEquals('Cold', l.Rating, 'a knocked-out lead is Cold whatever its intent');
        System.assertEquals('Knocked out at ' + gate, l.LoanSeva_Stage_Gate__c);
        System.assertEquals(null, l.LoanSeva_Eligibility__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id AND IsClosed = FALSE], 'no RM call for a knocked-out lead');
        Task logged = [SELECT Subject, Priority FROM Task WHERE WhoId = :l.Id];
        System.assert(logged.Subject.contains('Knocked out at ' + gate), logged.Subject);
        System.assertEquals('Low', logged.Priority);
        LoanSevaLeadInsight.Insight insight = LoanSevaLeadInsight.getInsight(l.Id);
        System.assert(!insight.canNudge);
        System.assert(insight.blockedReason.startsWith('Knocked out at ' + gate), insight.blockedReason);
        Boolean afterKnockout = false;
        for (LoanSevaLeadInsight.Gate g : insight.gates) {
            if (afterKnockout && g.result != 'Pending') {
                System.assertEquals('Skipped', g.result, g.gate + ' is not called after the knock-out');
                System.assert(g.summary.startsWith('Not run'), g.summary);
            }
            if (g.gate == gate) {
                System.assertEquals('slds-path__item slds-is-current slds-is-active slds-is-lost', g.pathClass);
                afterKnockout = true;
            }
        }
        try {
            LoanSevaLeadInsight.nudge(l.Id);
            System.assert(false, 'A knocked-out lead is not nudged');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void bureauWriteOffKnocksTheLeadOut() {
        dropAfterIncome('400001', 'ABCPP1234Z', '1', '85k');
        assertKnockedOut(LoanSevaQualification.GATE_BUREAU, 'CIBIL');
        System.assertEquals(630, qualifiedLead().LoanSeva_CIBIL_Score__c);
    }

    @IsTest
    static void hunterNegativeListKnocksOutBeforeTheBureauIsPulled() {
        dropAfterIncome('400001', 'ABCPP1234X', '1', '85k');
        assertKnockedOut(LoanSevaQualification.GATE_FRAUD, 'negative list');
        System.assertEquals(null, qualifiedLead().LoanSeva_CIBIL_Score__c, 'no bureau enquiry once fraud knocks the lead out');
    }

    @IsTest
    static void incomeBelowPolicyKnocksTheLeadOut() {
        dropAfterIncome('400001', 'ABCPP1234K', '1', '20000');
        assertKnockedOut(LoanSevaQualification.GATE_INCOME, 'below the minimum');
    }

    @IsTest
    static void skippedConsentWaitsAtConsentWithoutABureauPull() {
        dropAfterIncome('400001', 'ABCPP1234K', 'Skip for now', '85k');
        Lead l = qualifiedLead();
        System.assertEquals('Skipped', l.LoanSeva_Bureau_Consent__c);
        System.assertEquals('Waiting at Consent', l.LoanSeva_Stage_Gate__c);
        System.assertEquals(null, l.LoanSeva_CIBIL_Score__c);
        System.assertEquals('New', l.Status, 'skipping is not a knock-out');
        // no CIBIL: FOIR needs declared EMIs, so only employment 15/15 and fraud 10/10 count
        System.assertEquals(100, l.LoanSeva_Credit_Score__c);
        System.assertEquals(52, l.LoanSeva_Combined_Score__c, 'Low confidence (25 points of data): the rating stays on intent');
        System.assertEquals('Warm', l.Rating);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :j.Lead__c], 'the RM still calls');
        System.assertEquals('Skipped', [SELECT Result__c FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id AND Gate__c = :LoanSevaQualification.GATE_BUREAU].Result__c);
    }

    @IsTest
    static void registrationLeadIsReusedAndRescored() {
        Lead existing = new Lead(LastName = 'Patil', Company = 'Individual', MobilePhone = MOBILE, LeadSource = 'Other');
        insert existing;
        dropAfterIncome('Pune 411001');
        System.assertEquals(existing.Id, j.Lead__c);
        Lead l = [SELECT LeadSource, LoanSeva_Region__c, LoanSeva_Score__c FROM Lead WHERE Id = :existing.Id];
        System.assertEquals(LoanSevaLeadService.SOURCE, l.LeadSource);
        System.assertEquals('Rest of India', l.LoanSeva_Region__c);
        System.assertEquals(52, l.LoanSeva_Score__c);
    }

    @IsTest
    static void scoring() {
        Loan_Journey__c hot = new Loan_Journey__c(
            Monthly_Income__c = 150000, Existing_EMIs__c = 10000, Employment_Type__c = 'Salaried', Desired_Amount__c = 300000,
            Date_Of_Birth__c = LoanSevaI18n.todayIst().addYears(-35), OTP_Verified__c = true, PAN__c = 'ABCPP1234K',
            Email__c = 'a@b.com', PIN_Code__c = '400001', Company_Name__c = 'Infosys', Purpose__c = 'Travel', Offer_Amount__c = 300000
        );
        LoanSevaLeadScoring.Score s = LoanSevaLeadScoring.score(hot);
        System.assertEquals(100, s.points, s.detail());
        System.assertEquals('Hot', s.rating);

        hot.Existing_EMIs__c = 60000; // 40% FOIR
        hot.Employment_Type__c = 'Self-employed';
        hot.Desired_Amount__c = 5000000;
        s = LoanSevaLeadScoring.score(hot);
        System.assertEquals(100 - 12 - 4 - 6, s.points, s.detail());

        s = LoanSevaLeadScoring.score(new Loan_Journey__c());
        System.assertEquals(0, s.points);
        System.assertEquals('Cold', s.rating);
        System.assert(s.detail().contains('Monthly income not shared: 0/25'), s.detail());
    }

    @IsTest
    static void serviceabilityUsesTheLongestPrefix() {
        useRegions();
        LoanSevaServiceability.regions.add(new LoanSeva_Region__mdt(MasterLabel = 'Thane', PIN_Prefixes__c = '4006', Serviceable__c = true));
        System.assertEquals('Mumbai MMR', LoanSevaServiceability.forPin('401203').name);
        System.assertEquals('Thane', LoanSevaServiceability.forPin('400601').name);
        System.assertEquals(UserInfo.getUserId(), LoanSevaServiceability.forPin('400001').rmId);
        System.assertEquals('Rest of India', LoanSevaServiceability.forPin('560001').name);
        System.assert(!LoanSevaServiceability.forPin('744101').serviceable);
        LoanSevaServiceability.Region none = LoanSevaServiceability.forPin(null);
        System.assert(none.serviceable && none.rmId == null, 'No PIN yet: default RM');
        LoanSevaServiceability.regions = new List<LoanSeva_Region__mdt>();
        System.assert(!LoanSevaServiceability.forPin('400001').serviceable, 'No region at all: not serviceable');
    }

    @IsTest
    static void submittedProspectConvertsIntoTheContact() {
        Account a = new Account(Name = 'LoanSeva Test Customers');
        insert a;
        Contact c = new Contact(LastName = 'Patil', AccountId = a.Id, MobilePhone = MOBILE);
        insert c;
        Lead l = new Lead(LastName = 'Patil', Company = 'Individual', MobilePhone = MOBILE);
        insert l;
        Loan_Journey__c x = new Loan_Journey__c(Mobile__c = MOBILE, Status__c = 'Active', Lead__c = l.Id, Contact__c = c.Id);
        insert x;
        Test.startTest();
        LoanSevaLeadService.convert(x);
        Test.stopTest();
        l = [SELECT IsConverted, ConvertedContactId, Status FROM Lead WHERE Id = :l.Id];
        System.assert(l.IsConverted || l.Status == 'Qualified', 'Converted, or Qualified where conversion is not allowed');
        if (l.IsConverted) {
            System.assertEquals(c.Id, l.ConvertedContactId);
        }
    }
}
