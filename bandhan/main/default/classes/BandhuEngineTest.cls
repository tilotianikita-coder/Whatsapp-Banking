@IsTest
private class BandhuEngineTest {
    @IsTest
    static void newToBankTravellerGetsLuminaIssuedStraightThrough() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 2, 3', '4', '2' }, '2.5 lakh', BandhuTestData.GOOD_PAN);
        System.assertEquals('choose', r.step, r.message);
        System.assertEquals('Lumina', r.journey.Recommended_Card__c);
        System.assert(r.message.contains('Your best match: Bandhan Lumina'), r.message);
        System.assertEquals(240000, r.journey.Verified_Income__c, 'Account Aggregator verified 96% of declared');
        System.assertEquals(1080000, r.journey.Credit_Limit__c, '4x + 0.5x (band A) verified income');
        System.assertEquals(4, r.cards.size());
        System.assertNotEquals(null, r.journey.Lead__c, 'a new-to-bank applicant becomes a lead at OTP verification');

        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done' });
        System.assertEquals('review', r.step, r.message);
        System.assert(r.message.contains('Ananya Sen') && r.message.contains('XXXXX1234K'), 'review shows the full name and a masked PAN: ' + r.message);
        r = BandhuTestData.say(r, '1');
        System.assertEquals('done', r.step);
        System.assert(r.message.contains('is approved'), r.message);
        Card_Application__c app = [SELECT Status__c, Recommendation__c, Card_Number_Masked__c, Card_Product__c, Credit_Limit__c,
            (SELECT Result__c FROM Card_Checks__r) FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Card Issued', app.Status__c);
        System.assertEquals('Approve', app.Recommendation__c);
        System.assertEquals('Lumina', app.Card_Product__c);
        System.assert(app.Card_Number_Masked__c.startsWith('5241 XXXX XXXX '), app.Card_Number_Masked__c);
        System.assertEquals(9, app.Card_Checks__r.size());
        System.assertEquals('Qualified', [SELECT Status FROM Lead WHERE Id = :r.journey.Lead__c].Status);
    }

    @IsTest
    static void existingCustomerSkipsWhatIsOnFile() {
        BandhuTestData.useLogOnly();
        BandhuTestData.existingCustomer();
        BandhuEngine.Result r = BandhuEngine.start(BandhuJourneyService.resolve(null, null, BandhuTestData.ETB_MOBILE, 'WhatsApp'));
        System.assert(r.message.startsWith('Welcome back Rohan'), r.message);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1' });
        System.assertEquals('otp', r.step, 'name and mobile are already known: ' + r.message);
        r = BandhuTestData.say(r, BandhuConfig.get().Demo_OTP__c);
        System.assert(r.message.contains('salary account'), r.message);
        System.assertEquals('company', r.step, 'email, DOB, PIN, PAN, employment and income come from the bank: ' + r.message);
        r = BandhuTestData.say(r, 'Tata Steel');
        System.assertEquals('spend', r.step, 'then the needs, in one run');
        r = BandhuTestData.sayAll(r, new List<String>{ '1, 3', '3', '2' });
        System.assertEquals('choose', r.step, 'silent soft pull and no Account Aggregator for an existing customer: ' + r.message);
        System.assertEquals(779, r.journey.CIBIL_Score__c, 'soft pull on the PAN on file');
        System.assertEquals('Deposit', r.journey.ETB_Tier__c);
        System.assertNotEquals(null, [SELECT Bandhu_Bureau_At__c FROM Contact WHERE Id = :r.journey.Contact__c].Bandhu_Bureau_At__c, 'report cached');
        System.assertEquals('Flare', r.journey.Recommended_Card__c);
        System.assertEquals(350000, r.journey.Credit_Limit__c, 'the pre-approved limit');
        r = BandhuTestData.say(r, '1');
        System.assertEquals('review', r.step, 'no Aadhaar or Video KYC for an existing customer: ' + r.message);
        r = BandhuTestData.say(r, '1');
        System.assert(r.message.contains('is approved'), r.message);
        System.assertEquals(null, r.journey.Lead__c, 'existing customers are not leads');
    }

    @IsTest
    static void groceryShopperOnALowIncomeGetsSparksWithAnUpgradeHint() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '4 5', '2', '1' }, '32000', BandhuTestData.GOOD_PAN);
        System.assertEquals('Sparks', r.journey.Recommended_Card__c, r.message);
        System.assertEquals('Ignite', r.journey.Upgrade_Card__c);
        System.assert(r.message.contains('you\'d also qualify for *Ignite*'), r.message);
        System.assertEquals(3, r.options.size(), 'no alternative card: apply / compare / specialist');
    }

    @IsTest
    static void lowCreditScoreIsNotEligibleAndOffersASpecialist() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '3', '2' }, '90000', BandhuTestData.DECLINE_PAN);
        System.assertEquals('not_eligible', r.step, r.message);
        System.assert(r.message.contains('credit score below 650') && r.message.contains('Overdraft against your Fixed Deposit'), r.message);
        System.assertEquals(BandhuI18n.today().addDays(180), BandhuJourneyService.byId(r.journey.Id).Reassess_On__c, 're-checked in 6 months');
        r = BandhuTestData.say(r, '1');
        System.assert(r.handoff);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Bandhu: specialist%']);
    }

    @IsTest
    static void anytimeLanguageFaqCompareMenuAndHandoff() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.drive(BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE),
            new Map<String, String>{ 'email' => 'a@example.com', 'dob' => '12/04/1990', 'pincode' => 'Kolkata 700091', 'employment' => '1',
                'income' => '90000', 'pan' => BandhuTestData.GOOD_PAN, 'aa' => '2', 'company' => 'Infosys', 'spend' => '1' });
        System.assertEquals('monthly_spend', r.step, r.message);
        r = BandhuTestData.say(r, 'Hi');
        System.assertEquals('EN', r.journey.Language__c, '"Hi" is a greeting, not Hindi');
        r = BandhuTestData.say(r, 'HI');
        System.assertEquals('HI', r.journey.Language__c);
        System.assertEquals('monthly_spend', r.step, 'the pending question is asked again');
        r = BandhuTestData.say(r, 'EN');
        r = BandhuTestData.say(r, 'What are the fees?');
        System.assert(r.message.contains('Joining fees range'), r.message);
        System.assertEquals('monthly_spend', r.step);
        r = BandhuTestData.say(r, 'compare cards');
        System.assert(r.message.contains('Bandhan Bank credit cards'), r.message);
        r = BandhuTestData.say(r, 'status');
        System.assert(r.message.contains('couldn\'t find an application'), r.message);
        r = BandhuTestData.say(r, 'banana');
        System.assert(!r.success);
        r = BandhuTestData.say(r, 'menu');
        System.assertEquals('menu', r.step);
        r = BandhuTestData.say(r, 'I want to talk to an agent');
        System.assert(r.handoff);
        System.assert(r.journey.Escalated__c);
    }

    @IsTest
    static void consentDeclineAndOtpLockout() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuEngine.start(BandhuJourneyService.resolve(null, null, BandhuTestData.NTB_MOBILE, 'WhatsApp'));
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '2' });
        System.assertEquals('Exited', r.journey.Status__c);
        BandhuEngine.Result k = BandhuEngine.start(BandhuJourneyService.resolve(null, null, '9876500003', 'WhatsApp'));
        k = BandhuTestData.sayAll(k, new List<String>{ '1', '1', 'Test User', '000000', '111111', '222222' });
        System.assert(k.handoff, k.message);
        System.assertEquals('Exited', k.journey.Status__c);
    }

    @IsTest
    static void invalidAnswersAreReAsked() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE);
        System.assertEquals('email', r.step, 'personal details first: ' + r.message);
        r = BandhuTestData.sayAll(r, new List<String>{ 'not an email', 'sen@example.com' });
        System.assertEquals('dob', r.step);
        r = BandhuTestData.sayAll(r, new List<String>{ '31/02/1990' });
        System.assertEquals('dob', r.step);
        r = BandhuTestData.sayAll(r, new List<String>{ '1990-02-28', '7000' });
        System.assertEquals('pincode', r.step);
        r = BandhuTestData.sayAll(r, new List<String>{ '700091', 'NOTAPAN' });
        System.assertEquals('pan', r.step);
        r = BandhuTestData.sayAll(r, new List<String>{ BandhuTestData.GOOD_PAN });
        System.assertEquals('employment', r.step, 'then the income: ' + r.message);
        r = BandhuTestData.say(r, '3');
        System.assertEquals('Business', r.journey.Employment_Type__c);
        r = BandhuTestData.say(r, 'lots');
        System.assertEquals('income', r.step);
        r = BandhuTestData.sayAll(r, new List<String>{ '1.2 lakh', '2' });
        System.assertEquals('company', r.step, 'Account Aggregator skipped, a business owner names the business: ' + r.message);
        r = BandhuTestData.say(r, 'Sen Traders');
        System.assertEquals('spend', r.step, 'the needs in one run');
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '2', '1', '2' });
        System.assertEquals('choose', r.step, r.message);
        System.assertEquals('Kolkata', r.journey.City__c, 'city from the PIN prefix');
        System.assertEquals(null, r.journey.CIBIL_Score__c, 'soft check skipped');
        System.assertEquals(null, r.journey.Verified_Income__c, 'Account Aggregator skipped');
    }

    @IsTest
    static void parsers() {
        System.assertEquals(250000, BandhuI18n.parseAmount('2.5 lakh'));
        System.assertEquals(85000, BandhuI18n.parseAmount('₹85,000'));
        System.assertEquals(85000, BandhuI18n.parseAmount('85k'));
        System.assertEquals(null, BandhuI18n.parseAmount('5'));
        System.assertEquals('9876543210', BandhuI18n.normalizeMobile('+91 98765 43210'));
        System.assertEquals(null, BandhuI18n.normalizeMobile('12345'));
        System.assertEquals('₹1,50,000', BandhuI18n.inr(150000));
        System.assertEquals('₹2.5 lakh', BandhuI18n.inrShort(250000));
        System.assertEquals('HI', BandhuI18n.parseLanguage('हिंदी'));
        System.assertEquals('BN', BandhuI18n.parseLanguage('Bangla'));
        System.assertEquals(2, BandhuEngine.choiceNumber('2️⃣'));
        System.assertEquals(new Set<String>{ 'Travel', 'Dining' }, BandhuEngine.parseFocus('1 and 3'));
        System.assertEquals(new Set<String>{ 'Fuel', 'Groceries' }, BandhuEngine.parseFocus('fuel and groceries'));
        System.assertEquals(Date.newInstance(1990, 8, 15), BandhuEngine.parseDob('15/08/1990'));
        System.assertEquals('XXXXX1234K', BandhuI18n.maskPan('ABCPS1234K'));
    }
}
