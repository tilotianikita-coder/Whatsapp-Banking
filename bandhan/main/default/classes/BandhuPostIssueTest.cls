/**
 * Re-approach of declined customers, limit / upgrade offers with consent, scorecard monitoring, and the RM 360 view
 * with a branch-assisted start.
 */
@IsTest
private class BandhuPostIssueTest {
    @IsTest
    static void declinedCustomerIsReapproachedAfterCleanMonths() {
        BandhuTestData.useLogOnly();
        Card_Journey__c j = new Card_Journey__c(Customer_Name__c = 'Ananya Sen', Mobile__c = BandhuTestData.NTB_MOBILE, PAN__c = BandhuTestData.LOW_PAN,
            Monthly_Income__c = 30000, Employment_Type__c = 'Salaried', Date_Of_Birth__c = Date.newInstance(1990, 4, 12), Customer_Type__c = 'New',
            Status__c = 'Completed', Step__c = 'done', Channel__c = 'WhatsApp', Reassess_Status__c = 'Pending', Reassess_On__c = BandhuI18n.today());
        BandhuBureau.apply(j, BandhuBureau.pull(j.PAN__c, 'Soft'));
        j.Bureau_At__c = Datetime.now().addMonths(-7);
        insert j;
        // declined by the underwriter at CIBIL 690 (the bureau check reviews anything under 700)

        System.assertEquals(1, BandhuPostIssue.reassess());
        Card_Journey__c after = BandhuJourneyService.byId(j.Id);
        System.assertEquals('Eligible', after.Reassess_Status__c);
        System.assertEquals(732, after.CIBIL_Score__c, '690 + 7 clean months x 6');
        System.assertEquals('Sparks', after.Recommended_Card__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Bandhu: re-approach%']);
    }

    @IsTest
    static void stillNotEligibleIsCheckedAgainLater() {
        Card_Journey__c j = new Card_Journey__c(PAN__c = BandhuTestData.DECLINE_PAN, Monthly_Income__c = 30000, Date_Of_Birth__c = Date.newInstance(1990, 1, 1),
            Customer_Type__c = 'New', Reassess_Status__c = 'Pending', Reassess_On__c = BandhuI18n.today(), Bureau_At__c = Datetime.now().addMonths(-7));
        insert j;
        System.assertEquals(0, BandhuPostIssue.reassess());
        System.assertEquals(BandhuI18n.today().addDays(90), [SELECT Reassess_On__c FROM Card_Journey__c WHERE Id = :j.Id].Reassess_On__c, 'DPD 90+ stays on file');
    }

    private static BandhuEngine.Result issued() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 2, 3', '4', '2' }, '2.5 lakh', BandhuTestData.GOOD_PAN);
        return BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
    }

    @IsTest
    static void goodBehaviourEarnsALimitOfferThatNeedsConsent() {
        BandhuEngine.Result r = issued();
        Card_Application__c app = [SELECT Id, Credit_Limit__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        update new Card_Application__c(Id = app.Id, Activated_At__c = Datetime.now().addDays(-190), Card_Issued_At__c = Datetime.now().addDays(-200),
            Missed_Payments__c = 0, On_Time_Payments__c = 6, Avg_Utilisation_Pct__c = 75);
        System.assertEquals(1, BandhuPostIssue.limitOffers());
        app = [SELECT Credit_Limit__c, Limit_Offer__c, Limit_Offer_Status__c FROM Card_Application__c WHERE Id = :app.Id];
        System.assertEquals('Offered', app.Limit_Offer_Status__c);
        System.assertEquals(1500000, app.Limit_Offer__c, 'x1.5 capped at the Lumina maximum');
        System.assertEquals(1080000, app.Credit_Limit__c, 'unchanged until the customer consents');
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        System.assertEquals('limit_offer', j.Step__c);
        BandhuEngine.Result a = BandhuEngine.reply(j, 'Yes');
        System.assert(a.message.contains('₹15,00,000'), a.message);
        System.assertEquals(1500000, [SELECT Credit_Limit__c FROM Card_Application__c WHERE Id = :app.Id].Credit_Limit__c);
        System.assertEquals(1, [SELECT COUNT() FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id AND Type__c = 'Limit enhancement']);
    }

    @IsTest
    static void atTheMaximumTheNextCardIsOffered() {
        Card_Application__c a = new Card_Application__c(Card_Product__c = 'Sparks', Credit_Limit__c = 100000, Monthly_Income__c = 50000, Avg_Utilisation_Pct__c = 80);
        BandhuPostIssue.offer(a);
        System.assertEquals('Ignite', a.Upgrade_Offer_Card__c);
        System.assert(a.Limit_Offer__c >= 100000);
    }

    @IsTest
    static void monitoringByBandOncePerQuarter() {
        issued();
        String csv = BandhuPostIssue.monitoringCsv();
        System.assert(csv.startsWith('model,band'), csv);
        System.assert(csv.contains(',A,1,1,'), csv);
        System.assertNotEquals(null, BandhuPostIssue.saveQuarterlyMonitoring());
        System.assertEquals(null, BandhuPostIssue.saveQuarterlyMonitoring(), 'one file a quarter');
    }

    @IsTest
    static void rmSeesThePitchAndStartsABranchApplication() {
        BandhuTestData.useLogOnly();
        Contact c = BandhuTestData.existingCustomer();
        BandhuCustomer360.View v = BandhuCustomer360.get(c.Id);
        System.assert(v.isCustomer);
        System.assertEquals('Deposit', v.tier);
        System.assertNotEquals(null, v.pitchCard, 'pitch: ' + v.notEligibleReason);
        System.assertNotEquals(null, v.bandhanScore);
        System.assert(v.canStart);
        Id journeyId = BandhuCustomer360.startApplication(c.Id);
        Card_Journey__c j = BandhuJourneyService.byId(journeyId);
        System.assertEquals('Branch', j.Channel__c);
        System.assertEquals('consent', j.Step__c);
        // the customer replies on WhatsApp: the branch journey is picked up by the mobile number
        Card_Journey__c onWhatsApp = BandhuJourneyService.resolve(null, null, BandhuTestData.ETB_MOBILE, 'WhatsApp');
        System.assertEquals(journeyId, onWhatsApp.Id);
        BandhuEngine.Result r = BandhuEngine.reply(onWhatsApp, '1');
        System.assertEquals('otp', r.step, r.message);
    }

    @IsTest
    static void newToBankHasNoRelationship() {
        Account a = new Account(Name = 'NTB');
        insert a;
        Contact c = new Contact(LastName = 'Prospect', AccountId = a.Id);
        insert c;
        BandhuCustomer360.View v = BandhuCustomer360.get(c.Id);
        System.assert(!v.isCustomer);
        System.assert(!v.canStart);
    }
}
