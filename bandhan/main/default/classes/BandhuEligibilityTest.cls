@IsTest
private class BandhuEligibilityTest {
    private static BandhuEligibility.Profile profile(Decimal income, Integer cibil, Set<String> focus, String fee) {
        BandhuEligibility.Profile p = new BandhuEligibility.Profile();
        p.age = 34;
        p.employment = 'Salaried';
        p.income = income;
        p.cibil = cibil;
        p.focus = focus;
        p.feePreference = fee;
        p.spendBand = 2;
        return p;
    }

    @IsTest
    static void incomeDecidesTheTiers() {
        System.assertEquals(new List<String>{ 'Sparks' }, BandhuEligibility.evaluate(profile(30000, 780, new Set<String>(), null)).eligibleNames());
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite' }, BandhuEligibility.evaluate(profile(50000, 780, new Set<String>(), null)).eligibleNames());
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite', 'Flare' }, BandhuEligibility.evaluate(profile(100000, 780, new Set<String>(), null)).eligibleNames());
        System.assertEquals(4, BandhuEligibility.evaluate(profile(250000, 780, new Set<String>(), null)).eligibleNames().size(), 'all four cards');
        BandhuEligibility.Outcome none = BandhuEligibility.evaluate(profile(20000, 780, new Set<String>(), null));
        System.assertEquals(null, none.best);
        System.assert(none.blockedReason.contains('monthly income below'), none.blockedReason);
        System.assertEquals(null, none.secured, 'Bandhan has no secured card in the range');
    }

    @IsTest
    static void creditScoreBandsReferAndDecline() {
        // Fair (650-699): every card on review; Lumina needs Good or better even for review
        BandhuEligibility.Outcome fair = BandhuEligibility.evaluate(profile(250000, 680, new Set<String>{ 'International' }, BandhuEligibility.BEST_BENEFITS));
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite', 'Flare' }, fair.eligibleNames(), 'Fair 680: Lumina is out');
        for (BandhuEligibility.Option opt : fair.options) {
            if (opt.eligible) {
                System.assert(opt.refer, opt.card.DeveloperName + ' refers for a Fair score');
            }
        }
        // Good (700-749): Sparks, Ignite and Flare straight through, Lumina on review; Excellent (750+): everything
        BandhuEligibility.Outcome good = BandhuEligibility.evaluate(profile(250000, 730, new Set<String>{ 'International' }, BandhuEligibility.BEST_BENEFITS));
        for (BandhuEligibility.Option opt : good.options) {
            System.assert(opt.eligible, opt.card.DeveloperName);
            System.assertEquals(opt.card.DeveloperName == 'Lumina', opt.refer, opt.card.DeveloperName + ' at Good 730');
        }
        for (BandhuEligibility.Option opt : BandhuEligibility.evaluate(profile(250000, 760, new Set<String>(), null)).options) {
            System.assert(opt.eligible && !opt.refer, opt.card.DeveloperName + ' at Excellent 760');
        }
        System.assertEquals('Good', BandhuBureau.band(730));
        System.assertEquals('Excellent', BandhuBureau.band(750));
        System.assertEquals('Fair', BandhuBureau.band(690));
        System.assertEquals('Poor', BandhuBureau.band(640));
        System.assertEquals(null, BandhuEligibility.evaluate(profile(250000, 640, new Set<String>(), null)).best, 'below 650: no card');
        System.assertEquals(4, BandhuEligibility.evaluate(profile(250000, null, new Set<String>(), null)).eligibleNames().size(), 'no score yet: on income');
    }

    @IsTest
    static void needsDecideTheBestFit() {
        System.assertEquals('Ignite', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Groceries' }, BandhuEligibility.BEST_BENEFITS)).best.card.DeveloperName);
        System.assertEquals('Sparks', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Groceries' }, BandhuEligibility.LOWEST_FEE)).best.card.DeveloperName, 'lowest fee wins for an everyday spender');
        System.assertEquals('Lumina', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'International', 'Dining' }, BandhuEligibility.BEST_BENEFITS)).best.card.DeveloperName);
        System.assertEquals('Sparks', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Shopping' }, BandhuEligibility.LOWEST_FEE)).best.card.DeveloperName);
        BandhuEligibility.Outcome o = BandhuEligibility.evaluate(profile(100000, 780, new Set<String>{ 'Travel' }, BandhuEligibility.BEST_BENEFITS));
        System.assertEquals('Flare', o.best.card.DeveloperName, 'a traveller gets the travel card');
        System.assertEquals('B', o.score.band, o.score.lines());
        System.assertEquals(300000, o.best.creditLimit, '3x income at band B');
        System.assertEquals(240000, o.best.limitLow, 'range from 80%');
        System.assertNotEquals(null, o.alternative);
        System.assertEquals('Lumina', o.upgrade.card.DeveloperName, 'income is the only gap to Lumina');
    }

    @IsTest
    static void ageAndRelationshipRoutes() {
        BandhuEligibility.Profile young = profile(250000, 780, new Set<String>(), null);
        young.age = 19;
        System.assert(BandhuEligibility.evaluate(young).blockedReason.contains('age under 21'));
        BandhuEligibility.Profile senior = profile(250000, 780, new Set<String>(), null);
        senior.age = 63;
        System.assert(BandhuEligibility.evaluate(senior).blockedReason.contains('age over 60'));
        senior.employment = 'Self-employed';
        System.assertEquals(null, BandhuEligibility.evaluate(senior).blockedReason, 'self-employed up to 65');
        BandhuEligibility.Profile wealthy = profile(90000, 780, new Set<String>(), null);
        wealthy.existing = true;
        wealthy.relationshipValue = 1500000;
        System.assert(BandhuEligibility.evaluate(wealthy).eligibleNames().contains('Lumina'), 'relationship route to Lumina');
        BandhuEligibility.Profile preApproved = profile(30000, 780, new Set<String>(), null);
        preApproved.existing = true;
        preApproved.preApprovedCard = 'Ignite';
        preApproved.preApprovedLimit = 120000;
        BandhuEligibility.Outcome o = BandhuEligibility.evaluate(preApproved);
        System.assert(o.eligibleNames().contains('Ignite'), 'pre-approved card despite the income');
    }
}
