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
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite', 'Voyage' }, BandhuEligibility.evaluate(profile(50000, 780, new Set<String>(), null)).eligibleNames());
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite', 'Flare', 'Voyage' }, BandhuEligibility.evaluate(profile(100000, 780, new Set<String>(), null)).eligibleNames());
        System.assertEquals(5, BandhuEligibility.evaluate(profile(250000, 780, new Set<String>(), null)).eligibleNames().size(), 'all unsecured cards');
        BandhuEligibility.Outcome none = BandhuEligibility.evaluate(profile(20000, 780, new Set<String>(), null));
        System.assertEquals(null, none.best);
        System.assert(none.blockedReason.contains('monthly income below'), none.blockedReason);
        System.assertEquals('Shield', none.secured.card.DeveloperName, 'no unsecured card: the FD-backed card');
        System.assertEquals(30000, none.secured.fdAmount, 'FD sized for a 25,000 limit at 90%, rounded up to 5,000');
        System.assertEquals(27000, none.secured.creditLimit);
    }

    @IsTest
    static void creditScoreBandsReferAndDecline() {
        BandhuEligibility.Outcome o = BandhuEligibility.evaluate(profile(250000, 730, new Set<String>{ 'International' }, BandhuEligibility.BEST_BENEFITS));
        System.assertEquals(new List<String>{ 'Sparks', 'Ignite', 'Flare', 'Voyage' }, o.eligibleNames(), 'CIBIL 730 is below Lumina\'s refer band');
        for (BandhuEligibility.Option opt : o.options) {
            if (opt.card.DeveloperName == 'Flare') {
                System.assert(opt.refer, 'Flare refers between 720 and 740');
            }
        }
        System.assertEquals(null, BandhuEligibility.evaluate(profile(250000, 640, new Set<String>(), null)).best, 'below 650: no card');
        System.assertEquals(5, BandhuEligibility.evaluate(profile(250000, null, new Set<String>(), null)).eligibleNames().size(), 'no score yet: on income');
    }

    @IsTest
    static void needsDecideTheBestFit() {
        System.assertEquals('Ignite', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Groceries' }, BandhuEligibility.BEST_BENEFITS)).best.card.DeveloperName);
        System.assertEquals('Sparks', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Groceries' }, BandhuEligibility.LOWEST_FEE)).best.card.DeveloperName, 'lowest fee wins for an everyday spender');
        System.assertEquals('Lumina', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'International', 'Dining' }, BandhuEligibility.BEST_BENEFITS)).best.card.DeveloperName);
        System.assertEquals('Sparks', BandhuEligibility.evaluate(profile(250000, 780, new Set<String>{ 'Shopping' }, BandhuEligibility.LOWEST_FEE)).best.card.DeveloperName);
        BandhuEligibility.Outcome o = BandhuEligibility.evaluate(profile(100000, 780, new Set<String>{ 'Travel' }, BandhuEligibility.BEST_BENEFITS));
        System.assertEquals('Voyage', o.best.card.DeveloperName, 'a pure traveller gets the co-branded travel card');
        System.assertEquals('B', o.score.band, o.score.lines());
        System.assertEquals(250000, o.best.creditLimit, '2.5x income at band B');
        System.assertEquals(200000, o.best.limitLow, 'range from 80%');
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
