/**
 * Existing-customer tiers, relationship score and holds; the full bureau report and its rules.
 */
@IsTest
private class BandhuCustomerTest {
    private static Contact customer(String mobile, List<Bank_Relationship__c> rels) {
        Account a = new Account(Name = 'Bandhu Tier Test');
        insert a;
        Contact c = new Contact(FirstName = 'Rina', LastName = 'Khatun', MobilePhone = mobile, AccountId = a.Id,
            Birthdate = Date.newInstance(1990, 3, 3), MailingCity = 'Howrah', MailingPostalCode = '711101');
        insert c;
        for (Bank_Relationship__c r : rels) {
            r.Contact__c = c.Id;
        }
        insert rels;
        return c;
    }

    @IsTest
    static void tiersAndScore() {
        List<Bank_Relationship__c> mf = new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Relationship_Type__c = 'Microfinance Loan', Outstanding__c = 40000, Monthly_EMI__c = 2200, Max_DPD_12M__c = 0, Vintage_Months__c = 36, PAN__c = BandhuTestData.GOOD_PAN)
        };
        System.assertEquals(BandhuCustomer.MICROFINANCE, BandhuCustomer.build(mf).tier);
        mf.add(new Bank_Relationship__c(Relationship_Type__c = 'Savings Account', Average_Balance__c = 30000, Vintage_Months__c = 24));
        System.assertEquals(BandhuCustomer.DEPOSIT, BandhuCustomer.build(mf).tier);
        mf.add(new Bank_Relationship__c(Relationship_Type__c = 'Home Loan', Outstanding__c = 2500000, Monthly_EMI__c = 24000, Max_DPD_12M__c = 0));
        System.assertEquals(BandhuCustomer.LOAN, BandhuCustomer.build(mf).tier);
        mf.add(new Bank_Relationship__c(Relationship_Type__c = 'Demat', Holding_Value__c = 1200000));
        BandhuCustomer.Insight i = BandhuCustomer.build(mf);
        System.assertEquals(BandhuCustomer.WEALTH, i.tier);
        System.assertEquals(4, i.products);
        System.assert(i.score > 40 && i.score <= 100, i.score + ' ' + i.scoreParts);
        System.assert(String.join(i.lines(), '\n').contains('Demat'), i.lines());
    }

    @IsTest
    static void microfinanceCustomerGetsTheEntryCardOnly() {
        Contact c = customer('9876500011', new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Relationship_Type__c = 'Microfinance Loan', Outstanding__c = 40000, Max_DPD_12M__c = 0, Vintage_Months__c = 36, PAN__c = BandhuTestData.GOOD_PAN)
        });
        Card_Journey__c j = new Card_Journey__c(Contact__c = c.Id, Customer_Type__c = 'Existing', Monthly_Income__c = 90000, CIBIL_Score__c = 790,
            Employment_Type__c = 'Self-employed', Date_Of_Birth__c = Date.newInstance(1990, 3, 3));
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        System.assertEquals(new List<String>{ 'Sparks' }, out.eligibleNames());
        System.assert(String.join(out.options[1].reasons, ';').contains('microfinance'), out.options[1].reasons);
    }

    @IsTest
    static void dormantAccountHoldsTheJourney() {
        BandhuTestData.useLogOnly();
        customer('9876500012', new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Relationship_Type__c = 'Savings Account', Account_Number__c = '50100099998888', Account_Status__c = 'Dormant',
                Average_Balance__c = 2000, Vintage_Months__c = 70, PAN__c = BandhuTestData.GOOD_PAN)
        });
        BandhuEngine.Result r = BandhuEngine.start(BandhuJourneyService.resolve(null, null, '9876500012', 'WhatsApp'));
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1', BandhuConfig.get().Demo_OTP__c });
        System.assertEquals('hold', r.step, r.message);
        System.assert(r.message.contains('reactivation'), r.message);
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        System.assert(j.Hold_Reason__c.contains('dormant'), j.Hold_Reason__c);
        System.assertEquals(null, j.CIBIL_Score__c, 'no bureau pull while on hold');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Bandhu: card journey on hold%']);
        r = BandhuTestData.say(r, 'hello?');
        System.assertEquals('hold', r.step);
    }

    @IsTest
    static void amlFlagIsNotDisclosed() {
        BandhuCustomer.Insight i = BandhuCustomer.build(new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Relationship_Type__c = 'Savings Account', AML_Flag__c = true, KYC_Status__c = 'Re-KYC due')
        });
        System.assertEquals('AML', i.blockerKind, 'AML outranks KYC');
        System.assertNotEquals(null, BandhuI18n.msg('Hold_Review', 'EN'));
        System.assert(!BandhuI18n.msg('Hold_Review', 'EN').containsIgnoreCase('AML'));
    }

    @IsTest
    static void bureauRules() {
        BandhuBureau.Report clean = BandhuBureau.pull(BandhuTestData.GOOD_PAN, 'Soft');
        System.assertEquals('Pass', BandhuBureau.assess(clean).result, BandhuBureau.assess(clean).summary);
        System.assert(clean.accounts.size() >= 3 && clean.utilisationPct < 30, clean.lines());

        BandhuBureau.Report writeOff = BandhuBureau.pull(BandhuTestData.DECLINE_PAN, 'Soft');
        System.assert(writeOff.writtenOff && writeOff.maxDpd24 > 90);
        System.assertEquals('Fail', BandhuBureau.assess(writeOff).result);

        BandhuBureau.Assessment settled = BandhuBureau.assess(BandhuBureau.pull('ABCPS1237K', 'Soft'));
        System.assertEquals('Refer', settled.result);
        System.assert(settled.summary.contains('Settled'), settled.summary);

        BandhuBureau.Assessment velocity = BandhuBureau.assess(BandhuBureau.pull('ABCPS1236K', 'Soft'));
        System.assert(velocity.summary.contains('8 credit enquiries'), velocity.summary);

        BandhuBureau.Report noHit = BandhuBureau.pull('ABCPS1235K', 'Soft');
        System.assert(noHit.noHit);
        System.assertEquals(null, noHit.score);
        System.assertEquals('Refer', BandhuBureau.assess(noHit).result);

        System.assert(BandhuBureau.assess(BandhuBureau.pull('ABCPS1233K', 'Soft')).summary.contains('utilisation 92%'));
    }

    @IsTest
    static void settledAccountMakesEveryCardAManualReview() {
        Card_Journey__c j = new Card_Journey__c(PAN__c = 'ABCPS1237K', Monthly_Income__c = 100000, Employment_Type__c = 'Salaried',
            Date_Of_Birth__c = Date.newInstance(1990, 1, 1), Customer_Type__c = 'New');
        BandhuBureau.apply(j, BandhuBureau.pull(j.PAN__c, 'Soft'));
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        System.assertNotEquals(null, out.best);
        System.assert(out.best.refer, 'eligible on manual review only');
        System.assert(out.best.referNote.contains('Settled'), out.best.referNote);
    }

    @IsTest
    static void cachedReportIsReused() {
        Contact c = customer('9876500013', new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Relationship_Type__c = 'Savings Account', Average_Balance__c = 50000, PAN__c = BandhuTestData.GOOD_PAN)
        });
        Card_Journey__c j = new Card_Journey__c(Contact__c = c.Id, PAN__c = BandhuTestData.GOOD_PAN);
        BandhuBureau.Report first = BandhuBureau.softPull(j);
        Datetime cachedAt = [SELECT Bandhu_Bureau_At__c FROM Contact WHERE Id = :c.Id].Bandhu_Bureau_At__c;
        Card_Journey__c again = new Card_Journey__c(Contact__c = c.Id, PAN__c = BandhuTestData.GOOD_PAN);
        BandhuBureau.Report second = BandhuBureau.softPull(again);
        System.assertEquals(cachedAt, second.pulledAt, 'served from the cache');
        System.assertEquals(first.score, again.CIBIL_Score__c);
    }
}
