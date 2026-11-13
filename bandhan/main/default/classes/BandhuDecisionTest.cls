@IsTest
private class BandhuDecisionTest {
    private static BandhuEngine.Result toReview(String pan, String income, List<String> needs, String pick) {
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, needs, income, pan);
        return BandhuTestData.sayAll(r, new List<String>{ pick, 'ananya@example.com', '1234', BandhuConfig.get().Demo_OTP__c, 'Done' });
    }

    @IsTest
    static void referBandGoesToTheUnderwriterWhoApproves() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = toReview(BandhuTestData.REFER_PAN, '90000', new List<String>{ '1', '3', '2' }, '1');
        System.assertEquals('Flare', r.journey.Chosen_Card__c, r.message);
        r = BandhuTestData.say(r, '1');
        System.assert(r.message.contains('quick review'), r.message);
        Card_Application__c app = [SELECT Id, Status__c, Recommendation__c, Recommendation_Reasons__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Under Review', app.Status__c);
        System.assertEquals('Refer', app.Recommendation__c);
        System.assert(app.Recommendation_Reasons__c.contains('Card Policy'), app.Recommendation_Reasons__c);

        Test.startTest();
        BandhuConsoleController.Review rev = BandhuConsoleController.decide(app.Id, 'Approved', null);
        Test.stopTest();
        System.assertEquals('Card Issued', rev.application.Status__c);
        System.assertNotEquals(null, rev.application.Card_Number_Masked__c);
        System.assert(rev.decided);
        try {
            BandhuDecision.decide(app.Id, 'Declined', 'late change');
            System.assert(false, 'decided applications cannot be decided again');
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('already decided'));
        }
    }

    @IsTest
    static void fraudFailsAndOffersNoBetterCard() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = toReview(BandhuTestData.FRAUD_PAN, '50000', new List<String>{ '4', '2', '1' }, '1');
        r = BandhuTestData.say(r, '1');
        Card_Application__c app = [SELECT Status__c, Recommendation__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Declined', app.Status__c);
        System.assertEquals('Decline', app.Recommendation__c);
        System.assert(r.message.contains('unable to approve'), r.message);
    }

    @IsTest
    static void declineAgainstAnApprovalNeedsNotes() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = toReview(BandhuTestData.GOOD_PAN, '90000', new List<String>{ '1', '3', '2' }, '1');
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        j.KYC_Status__c = 'Aadhaar verified';   // Video KYC not done -> Pending -> Refer
        update j;
        r = BandhuTestData.say(r, '1');
        Card_Application__c app = [SELECT Id, Status__c, Recommendation__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Refer', app.Recommendation__c, 'Video KYC pending refers');
        update new Card_Application__c(Id = app.Id, Recommendation__c = 'Approve');
        try {
            BandhuConsoleController.decide(app.Id, 'Declined', '');
            System.assert(false, 'notes are required against the recommendation');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        BandhuConsoleController.Review rev = BandhuConsoleController.decide(app.Id, 'Declined', 'Customer withdrew');
        System.assertEquals('Declined', rev.application.Status__c);
    }

    @IsTest
    static void lowerCardOfferedAfterADecline() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = toReview(BandhuTestData.GOOD_PAN, '90000', new List<String>{ '1', '3', '2' }, '1');
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        j.Chosen_Card__c = 'Lumina';   // above the applicant's income: policy fails
        update j;
        r = BandhuTestData.say(r, '1');
        System.assertEquals('declined_alt', r.step, r.message);
        System.assertEquals('Flare', r.journey.Alternative_Card__c);
        r = BandhuTestData.say(r, '1');
        System.assertEquals('review', r.step);
        System.assertEquals('Flare', r.journey.Chosen_Card__c);
    }

    @IsTest
    static void providersAreDeterministic() {
        System.assertEquals(630, BandhuProviders.cibil('ABCPS1234Z'));
        System.assertEquals(690, BandhuProviders.cibil('ABCPS1234Y'));
        System.assertEquals(730, BandhuProviders.cibil('ABCPS1234R'));
        System.assertEquals(779, BandhuProviders.cibil('ABCPS1234K'));
        System.assertEquals('Refer', BandhuProviders.panCheck('ABCCS1234K', 'x').result, 'not an individual PAN');
        System.assertEquals('Fail', BandhuProviders.panCheck('BAD', 'x').result);
        System.assertEquals(96000, BandhuProviders.verifiedIncome(100000));
    }
}
