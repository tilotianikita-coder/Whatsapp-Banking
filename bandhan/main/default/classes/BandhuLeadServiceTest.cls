@IsTest
private class BandhuLeadServiceTest {
    @IsTest
    static void dropOffBecomesAScoredLeadThatTheRmNudges() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.newToBankAtProfile(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 3', '3', '2', '1', '1.5 lakh' });
        System.assertEquals('company', r.step);
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
        System.assert(l.Bandhu_Score_Detail__c.contains('Monthly income ₹1,50,000: 15/20'), l.Bandhu_Score_Detail__c);
        System.assert([SELECT COUNT() FROM Task WHERE WhoId = :l.Id AND Subject LIKE 'Bandhu: card applicant dropped%'] == 1);

        BandhuConsoleController.Insight ins = BandhuConsoleController.getLeadInsight(l.Id);
        System.assert(ins.hasJourney && ins.canNudge, ins.blockedReason);
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
    static void scoringAndScheduling() {
        Card_Journey__c j = new Card_Journey__c(Customer_Name__c = 'A B', Monthly_Income__c = 250000, Spend_Focus__c = 'Travel',
            Fee_Preference__c = 'Best benefits', Bureau_Consent__c = true, CIBIL_Score__c = 780, Recommended_Card__c = 'Lumina',
            Eligible_Cards__c = 'Sparks;Ignite;Flare;Lumina', OTP_Verified__c = true, PAN__c = 'ABCPS1234K');
        BandhuLeadService.Score s = BandhuLeadService.score(j);
        System.assertEquals(100, s.credit, s.detail);
        System.assertEquals('Hot', s.rating());
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
