/**
 * Bandhan Score, the limit model, "applied for X, qualify for Y" and the no-history case.
 */
@IsTest
private class BandhuScoreTest {
    private static BandhuEligibility.Profile profile(String pan, Decimal income) {
        BandhuEligibility.Profile p = new BandhuEligibility.Profile();
        p.age = 34;
        p.employment = 'Salaried';
        p.income = income;
        p.bureau = BandhuBureau.pull(pan, 'Soft');
        p.cibil = p.bureau.score;
        p.spendBand = 2;
        return p;
    }

    @IsTest
    static void scoreIsTheSumOfLoggedFactors() {
        BandhuScore.Result r = BandhuScore.compute(profile(BandhuTestData.GOOD_PAN, 150000));
        Integer sum = 0;
        Integer max = 0;
        for (BandhuScore.Factor f : r.factors) {
            sum += f.points;
            max += f.maxPoints;
            System.assert(f.points >= 0 && f.points <= f.maxPoints, f.name);
        }
        System.assertEquals(1000, max, 'the scorecard is out of 1000');
        System.assertEquals(sum, r.score);
        System.assertEquals(14, r.factors.size());
        System.assert(r.lines()[0].startsWith('Bandhan Score ' + r.score), r.lines());
    }

    @IsTest
    static void weakCreditScoresLowerAndCutsTheMultiple() {
        BandhuScore.Result good = BandhuScore.compute(profile(BandhuTestData.GOOD_PAN, 150000));
        BandhuScore.Result weak = BandhuScore.compute(profile(BandhuTestData.LOW_PAN, 150000));
        System.assert(good.score > weak.score + 100, good.score + ' vs ' + weak.score);
        System.assert(weak.weakest(2).size() == 2, weak.weakest(2));
        System.assert(good.multipleAdjustment() >= weak.multipleAdjustment());
    }

    @IsTest
    static void branchChannelAndRelationshipLiftTheScoreAndLimit() {
        BandhuEligibility.Profile digital = profile(BandhuTestData.GOOD_PAN, 100000);
        BandhuEligibility.Profile branch = profile(BandhuTestData.GOOD_PAN, 100000);
        branch.channel = 'Branch';
        branch.existing = true;
        branch.etbTier = 'Deposit';
        branch.relationshipScore = 80;
        System.assert(BandhuScore.compute(branch).score > BandhuScore.compute(digital).score);
        Decimal dl = BandhuEligibility.evaluate(digital).best.creditLimit;
        Decimal bl = BandhuEligibility.evaluate(branch).best.creditLimit;
        System.assert(bl >= dl, 'relationship uplift: ' + bl + ' vs ' + dl);
    }

    @IsTest
    static void multipleIsCappedPerCard() {
        Bandhu_Card__mdt sparks = BandhuConfig.card('Sparks');
        System.assertEquals(60000, BandhuEligibility.limitFor(sparks, 20000, null, 5), 'capped at 3x for the entry card');
        System.assertEquals(25000, BandhuEligibility.limitFor(sparks, 20000, 60, 0), 'FOIR over 50% halves, floored at the card minimum');
    }

    @IsTest
    static void noFootprintAndNoStatementsGetsNoCardUntilStatementsAreShared() {
        BandhuEligibility.Profile p = profile('ABCPS1235K', 60000);
        System.assert(p.bureau.noHit);
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(p);
        System.assertEquals(null, out.best);
        System.assert(out.blockedReason.containsIgnoreCase('no credit history'), out.blockedReason);
        System.assertEquals(null, out.secured, 'no secured card in the range');
        p.cashFlow = new BandhuCashFlow.Analysis();
        System.assertNotEquals(null, BandhuEligibility.evaluate(p).best, 'with bank statements an unsecured card is possible');
    }

    @IsTest
    static void appliedForPlatinumQualifiesForGold() {
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(profile(BandhuTestData.GOOD_PAN, 100000));
        BandhuEligibility.Explanation e = BandhuEligibility.explain(out, 'Lumina');
        System.assertEquals('Platinum', e.applied.Tier_Label__c);
        System.assert(e.missed[0].contains('Monthly income below'), e.missed);
        System.assertEquals(3, e.alternative.card.Tier__c, 'the closest tier below: ' + e.alternative.card.DeveloperName);
        System.assert(String.join(e.gets, '\n').contains('Limit'), e.gets);
    }

    @IsTest
    static void journeyExplainsTheAppliedCardAndAppliesForTheAlternative() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '2', '2' }, '1 lakh', BandhuTestData.GOOD_PAN);
        System.assertEquals('choose', r.step, r.message);
        System.assertNotEquals(null, r.journey.Bandhan_Score__c);
        r = BandhuTestData.say(r, 'I want Lumina');
        System.assertEquals('applied_alt', r.step, r.message);
        System.assert(r.message.contains('Lumina (Platinum)') && r.message.contains('Monthly income below'), r.message);
        System.assertEquals('Lumina', r.journey.Applied_Card__c);
        String alt = r.journey.Alternative_Card__c;
        r = BandhuTestData.say(r, '1');
        System.assertEquals(alt, r.journey.Chosen_Card__c);
        System.assertEquals('email', r.step, r.message);
    }

    @IsTest
    static void everyDecisionLogsTheScoreFactors() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 3', '3', '2' }, '1 lakh', BandhuTestData.REFER_PAN);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', 'ananya@example.com', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Card_Application__c app = [SELECT Recommendation__c, Bandhan_Score__c, Score_Band__c, Score_Factors__c, Model_Version__c,
            (SELECT Check__c, Result__c, Details__c FROM Card_Checks__r) FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertNotEquals(null, app.Bandhan_Score__c);
        System.assertNotEquals(null, app.Score_Factors__c, 'factor log for audit');
        System.assert(app.Model_Version__c.startsWith('BSC'));
        Map<String, Card_Check__c> checks = new Map<String, Card_Check__c>();
        for (Card_Check__c c : app.Card_Checks__r) {
            checks.put(c.Check__c, c);
        }
        System.assertEquals(9, checks.size());
        System.assert(checks.get('Bandhan Score').Details__c.contains('Bureau score'), checks.get('Bandhan Score').Details__c);
    }
}
