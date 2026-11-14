@IsTest
private class BandhuLeadServiceTest {
    @IsTest
    static void dropOffBecomesAScoredLeadThatTheRmNudges() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.drive(BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE), new Map<String, String>{
            'employment' => '1', 'income' => '1.5 lakh', 'pan' => BandhuTestData.GOOD_PAN, 'aa' => '2', 'spend' => '1, 3', 'monthly_spend' => '3', 'fee' => '2' });
        System.assertEquals('company', r.step, r.message);
        update new Card_Journey__c(Id = r.journey.Id, Last_Activity__c = Datetime.now().addMinutes(-30));

        Test.startTest();
        BandhuDropOffJob.run();
        Test.stopTest();

        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        System.assertEquals('Dropped', j.Status__c);
        System.assert(j.Drop_Point__c.startsWith('Company'), j.Drop_Point__c);
        Lead l = [SELECT Name, LeadSource, Rating, Bandhu_Intent_Score__c, Bandhu_Credit_Score__c, Bandhu_Drop_Point__c, Bandhu_Score_Detail__c
                  FROM Lead WHERE Id = :j.Lead__c];
        System.assertEquals('Ananya Sen', l.Name);
        System.assertEquals(BandhuLeadService.SOURCE, l.LeadSource);
        System.assertEquals(j.Drop_Point__c, l.Bandhu_Drop_Point__c);
        System.assert(l.Bandhu_Intent_Score__c > 0 && l.Bandhu_Credit_Score__c > 0);
        System.assert(l.Bandhu_Score_Detail__c.contains('Monthly income ₹1,50,000: 20/25'), l.Bandhu_Score_Detail__c);
        // the PIN and bureau aren't shared yet: those gates wait
        Lead gated = [SELECT Status, Bandhu_Stage_Gate__c, Bandhu_Credit_Confidence__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Waiting at Serviceability', gated.Bandhu_Stage_Gate__c);
        System.assertNotEquals('Unqualified', gated.Status);
        System.assertEquals(7, [SELECT COUNT() FROM Bandhu_Lead_Check__c WHERE Lead__c = :l.Id]);
        System.assert([SELECT COUNT() FROM Task WHERE WhoId = :l.Id AND Subject LIKE 'Bandhu: card applicant dropped%'] == 1);

        BandhuConsoleController.Insight ins = BandhuConsoleController.getLeadInsight(l.Id);
        System.assert(ins.hasJourney && ins.canNudge, ins.blockedReason);
        System.assertEquals(7, ins.gates.size());
        System.assertEquals(1, ins.pathIndex);
        String sent = BandhuConsoleController.nudge(l.Id);
        System.assert(sent.contains('Reply *Continue*'), sent);
        System.assertEquals(1, BandhuJourneyService.byId(j.Id).Nudges_Sent__c);

        // the reply resumes the dropped journey at the same question
        BandhuEngine.Result back = BandhuEngine.start(BandhuJourneyService.resolve(null, null, BandhuTestData.NTB_MOBILE, 'WhatsApp'));
        System.assert(back.message.startsWith('Welcome back Ananya'), back.message);
        System.assertEquals('company', back.step);
        System.assertEquals('Active', back.journey.Status__c);
    }

    @IsTest
    static void qualifiedProspectScoresHot() {
        Card_Journey__c j = new Card_Journey__c(Customer_Name__c = 'A B', Monthly_Income__c = 250000, Verified_Income__c = 250000,
            Spend_Focus__c = 'Travel', Monthly_Spend__c = 120000, Fee_Preference__c = 'Best benefits', Consent__c = true, Bureau_Consent__c = true,
            CIBIL_Score__c = 780, Recommended_Card__c = 'Lumina', Eligible_Cards__c = 'Sparks;Ignite;Flare;Lumina', OTP_Verified__c = true,
            PAN__c = BandhuTestData.GOOD_PAN, Employment_Type__c = 'Salaried', Company_Name__c = 'TCS', Date_Of_Birth__c = Date.newInstance(1990, 4, 12),
            PIN_Code__c = '700091', Step__c = 'choose');
        BandhuQualification.Outcome q = BandhuQualification.evaluate(j);
        System.assertEquals(100, q.credit, q.detail());
        System.assertEquals('Hot', q.rating());
        System.assertEquals('Qualified', q.stageGate());
        System.assertEquals('High', q.confidence);
        System.assertEquals('Kolkata', q.region.name);
        System.assert(q.intent >= 80, q.detail());
    }

    @IsTest
    static void knockOuts() {
        // longest prefix wins: 744 (Andaman) is not serviceable, the rest of India is
        System.assert(!BandhuQualification.region('744101').serviceable);
        System.assertEquals('Rest of India', BandhuQualification.region('302001').name);
        System.assertEquals('Rest of West Bengal', BandhuQualification.region('713204').name);

        Card_Journey__c j = new Card_Journey__c(Customer_Name__c = 'A B', Monthly_Income__c = 60000, Consent__c = true, Bureau_Consent__c = true,
            PAN__c = BandhuTestData.DECLINE_PAN, CIBIL_Score__c = 630, PIN_Code__c = '713204', OTP_Verified__c = true);
        BandhuQualification.Outcome q = BandhuQualification.evaluate(j);
        System.assertEquals(BandhuQualification.GATE_BUREAU, q.knockedOutAt);
        System.assertEquals('Cold', q.rating());
        System.assertEquals('Skipped', q.checks[4].Result__c);

        j.PIN_Code__c = '744101';
        System.assertEquals(BandhuQualification.GATE_SERVICEABILITY, BandhuQualification.evaluate(j).knockedOutAt);
        j.PIN_Code__c = '700091';
        j.PAN__c = BandhuTestData.FRAUD_PAN;
        System.assertEquals(BandhuQualification.GATE_FRAUD, BandhuQualification.evaluate(j).knockedOutAt);
        j.PAN__c = BandhuTestData.GOOD_PAN;
        j.CIBIL_Score__c = 779;
        j.Monthly_Income__c = 15000;
        System.assertEquals(BandhuQualification.GATE_INCOME, BandhuQualification.evaluate(j).knockedOutAt);
    }

    @IsTest
    static void knockedOutLeadIsUnqualifiedAndNotNudged() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '3', '2', '1' }, '60000',
            BandhuTestData.DECLINE_PAN);
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        Lead l = [SELECT Status, Rating, Bandhu_Stage_Gate__c FROM Lead WHERE Id = :j.Lead__c];
        System.assertEquals('Unqualified', l.Status);
        System.assertEquals('Cold', l.Rating);
        System.assertEquals('Knocked out at Credit Bureau', l.Bandhu_Stage_Gate__c);
        BandhuConsoleController.Insight ins = BandhuConsoleController.getLeadInsight(l.Id);
        System.assert(!ins.canNudge);
        System.assert(ins.blockedReason.startsWith('Unqualified'), ins.blockedReason);
        try {
            BandhuLeadService.nudge(l.Id);
            System.assert(false);
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('knocked out'));
        }
    }

    @IsTest
    static void scheduling() {
        Test.startTest();
        Id jobId = BandhuDropOffJob.start();
        System.assertNotEquals(null, jobId);
        BandhuDropOffJob.stop();
        Test.stopTest();
    }

    @IsTest
    static void insightWithoutAJourney() {
        Lead l = new Lead(LastName = 'Plain', Company = 'X');
        insert l;
        BandhuConsoleController.Insight i = BandhuConsoleController.getLeadInsight(l.Id);
        System.assert(!i.hasJourney);
        try {
            BandhuConsoleController.nudge(l.Id);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
