/**
 * Consent log, hard-enquiry declaration, MITC, OTP activation, cooling-off cancellation, consent withdrawal and the
 * 30-day activation rule.
 */
@IsTest
private class BandhuComplianceTest {
    private static BandhuEngine.Result issued() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 2, 3', '4', '2' }, '2.5 lakh', BandhuTestData.GOOD_PAN);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', 'ananya@example.com', '1234', BandhuConfig.get().Demo_OTP__c, 'Done' });
        System.assertEquals('review', r.step, r.message);
        System.assert(r.message.contains('hard credit enquiry'), 'declared before submitting: ' + r.message);
        return BandhuTestData.say(r, '1');
    }

    @IsTest
    static void everyConsentAndDisclosureIsLogged() {
        BandhuEngine.Result r = issued();
        System.assert(r.message.contains('is approved') && r.message.contains('MITC') && r.message.contains('Activate'), r.message);
        Set<String> types = new Set<String>();
        for (Bandhu_Consent__c c : [SELECT Type__c, Retain_Until__c, Expires_On__c, Purpose__c FROM Bandhu_Consent__c WHERE Card_Journey__c = :r.journey.Id]) {
            types.add(c.Type__c);
            System.assert(c.Retain_Until__c > BandhuI18n.today().addYears(4), 'cardholder retention: ' + c.Type__c);
            if (c.Type__c == 'Account Aggregator') {
                System.assertEquals(BandhuI18n.today().addDays(30), c.Expires_On__c, 'time-bound');
                System.assert(c.Purpose__c.startsWith('Credit underwriting'), c.Purpose__c);
            }
        }
        System.assert(types.containsAll(new Set<String>{ 'DPDP data processing', 'Soft credit check', 'Account Aggregator', 'Hard credit enquiry', 'MITC delivered' }), types);
        Card_Application__c app = [SELECT MITC_Sent_At__c, Activation_Due__c, Cooling_Off_Until__c, Hard_Enquiry_At__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertNotEquals(null, app.MITC_Sent_At__c);
        System.assertNotEquals(null, app.Hard_Enquiry_At__c);
        System.assertEquals(BandhuI18n.today().addDays(30), app.Activation_Due__c);
        System.assertEquals(BandhuI18n.today().addDays(7), app.Cooling_Off_Until__c);
    }

    @IsTest
    static void activationNeedsTheOtp() {
        BandhuEngine.Result r = issued();
        r = BandhuTestData.say(r, 'Activate');
        System.assertEquals('activate_otp', r.step, r.message);
        r = BandhuTestData.say(r, '000000');
        System.assertEquals('activate_otp', r.step, 'wrong OTP');
        r = BandhuTestData.say(r, BandhuConfig.get().Demo_OTP__c);
        System.assert(r.message.contains('is active'), r.message);
        System.assert(r.message.contains('reward points a month') && r.message.contains('Lumina'), 'rewards tip from the statements: ' + r.message);
        System.assertNotEquals(null, [SELECT Activated_At__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id].Activated_At__c);
        System.assertEquals(1, [SELECT COUNT() FROM Bandhu_Consent__c WHERE Card_Journey__c = :r.journey.Id AND Type__c = 'Card activation']);
    }

    @IsTest
    static void cancelInTheCoolingOffPeriod() {
        BandhuEngine.Result r = issued();
        r = BandhuTestData.say(r, 'cancel card');
        System.assertEquals('cancel_confirm', r.step, r.message);
        r = BandhuTestData.say(r, '1');
        System.assertEquals('Cancelled', [SELECT Status__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id].Status__c);
        r = BandhuTestData.say(r, 'activate');
        System.assert(r.message.contains('don\'t see an issued card'), r.message);
    }

    @IsTest
    static void unactivatedCardsCloseAfter30Days() {
        BandhuEngine.Result r = issued();
        Card_Application__c app = [SELECT Id FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        update new Card_Application__c(Id = app.Id, Activation_Due__c = BandhuI18n.today().addDays(-1));
        System.assertEquals(1, BandhuCompliance.closeUnactivated());
        System.assertEquals('Cancelled', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
    }

    @IsTest
    static void withdrawingConsentStopsTheJourney() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE);
        r = BandhuTestData.say(r, 'I want to withdraw my consent');
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        System.assertEquals('Exited', j.Status__c);
        System.assertEquals(false, j.Consent__c);
        System.assertEquals(0, [SELECT COUNT() FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id AND Type__c = 'DPDP data processing' AND Status__c = 'Active']);
        System.assertEquals(1, [SELECT COUNT() FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id AND Type__c = 'Consent withdrawn']);
    }
}
