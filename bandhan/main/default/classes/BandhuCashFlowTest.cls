/**
 * Account Aggregator parsing, cash-flow analysis and the AA-driven card recommendation.
 * PAN levers: 5th letter T = frequent traveller; digits ending 8 = heavy EMIs; ending 9 = anomalies (BandhuAccountAggregator).
 */
@IsTest
private class BandhuCashFlowTest {
    private static Card_Journey__c journey(String pan, Decimal income, String employment, String focus) {
        return new Card_Journey__c(PAN__c = pan, Monthly_Income__c = income, Employment_Type__c = employment, Spend_Focus__c = focus,
            Customer_Name__c = 'Ananya Sen', Company_Name__c = 'Infosys', Mobile__c = BandhuTestData.NTB_MOBILE);
    }

    @IsTest
    static void parsesBothFipFormatsAndDerivesIncome() {
        Card_Journey__c j = journey(BandhuTestData.GOOD_PAN, 100000, 'Salaried', 'Groceries;Shopping');
        BandhuCashFlow.Analysis a = BandhuAccountAggregator.run(j);
        System.assertEquals(2, a.banks, 'two FIPs in two layouts');
        System.assertEquals(2, a.accounts);
        System.assertEquals(24, a.months);
        System.assert(a.transactions > 400, 'transactions from both accounts: ' + a.transactions);
        System.assertEquals(BandhuProviders.verifiedIncome(100000), a.netMonthlyIncome, 'median of the last 6 salary credits');
        System.assert(a.incomeSource.contains('INFOSYS'), a.incomeSource);
        System.assertEquals('Growing', a.incomeTrend, 'salary rose 8% a year ago');
        System.assert(a.incomeStability >= 90, 'steady salary: ' + a.incomeStability);
        System.assertEquals(12, a.foirPct.intValue(), 'one car loan EMI');
        System.assert(a.topCategories.contains('Groceries') && a.topCategories.contains('Shopping'), a.topCategories);
        System.assert(a.anomalies.isEmpty(), a.anomalies);
        System.assertNotEquals(null, j.AA_Consent_Id__c);
        System.assertEquals(a.netMonthlyIncome, BandhuCashFlow.fromJourney(j).netMonthlyIncome, 'analysis stored on the journey');
        System.assertEquals('Pass', BandhuProviders.income(j).result);
    }

    @IsTest
    static void normalisesDatesAndAmounts() {
        System.assertEquals(Date.newInstance(2026, 3, 7), BandhuCashFlow.toDate('2026-03-07T10:00:00+05:30'));
        System.assertEquals(Date.newInstance(2026, 3, 7), BandhuCashFlow.toDate('07-03-2026'));
        System.assertEquals(Date.newInstance(2026, 3, 7), BandhuCashFlow.toDate('07/03/2026'));
        System.assertEquals(null, BandhuCashFlow.toDate('March'));
        System.assertEquals(125000.5, BandhuCashFlow.toDecimal('1,25,000.50'));
        System.assertEquals(99, BandhuCashFlow.toDecimal(99));
    }

    @IsTest
    static void flagsAnomaliesAndRefers() {
        Card_Journey__c j = journey('ABCPS1239K', 100000, 'Salaried', 'Dining');
        BandhuCashFlow.Analysis a = BandhuAccountAggregator.run(j);
        String all = String.join(a.anomalies, '\n');
        System.assert(all.contains('round-trip transfers with SUMAN ENTERPRISES'), all);
        System.assert(all.contains('Unexplained credit') && all.contains('R K TRADERS'), all);
        System.assert(all.contains('No salary credit in'), all);
        System.assert(a.incomeStability < 90, 'income gaps lower stability: ' + a.incomeStability);
        BandhuProviders.Report r = BandhuProviders.income(j);
        System.assertEquals('Refer', r.result, r.summary);
        System.assert(String.join(r.details, '\n').contains('⚠'), r.details);
    }

    @IsTest
    static void businessSeasonality() {
        BandhuCashFlow.Analysis a = BandhuAccountAggregator.run(journey(BandhuTestData.GOOD_PAN, 120000, 'Self-employed', 'Shopping'));
        System.assert(a.incomeSource.contains('business'), a.incomeSource);
        System.assertNotEquals(null, a.seasonality);
        System.assert(a.seasonality.contains('festive'), a.seasonality);
    }

    @IsTest
    static void heavyEmisCutTheLimit() {
        Card_Journey__c j = journey('ABCPS1238K', 250000, 'Salaried', 'Travel;International');
        j.Date_Of_Birth__c = Date.newInstance(1985, 1, 1);
        j.CIBIL_Score__c = 790;
        BandhuCashFlow.Analysis a = BandhuAccountAggregator.run(j);
        j.Verified_Income__c = a.netMonthlyIncome;
        System.assertEquals(55, a.foirPct.intValue());
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        System.assertEquals('Lumina', out.best.card.DeveloperName);
        System.assertEquals(480000, out.best.creditLimit, '4x income (band ' + out.score.band + ') halved for FOIR over 50%');
        System.assert(String.join(out.best.why, '\n').contains('existing EMIs'), out.best.why);
    }

    /** Said "groceries"; the statements show a traveller: Account Aggregator moves the pick from Ignite to Flare. */
    @IsTest
    static void statementsChangeTheRecommendation() {
        BandhuTestData.useLogOnly();
        List<String> profile = new List<String>{ '1', '1 lakh', 'Infosys', 'ABCPT1234K', '12/04/1990', 'Kolkata 700091', '1' };
        BandhuEngine.Result r = BandhuTestData.newToBankAtProfile(BandhuTestData.NTB_MOBILE, new List<String>{ '4', '2', '2' });
        r = BandhuTestData.sayAll(r, profile);
        r = BandhuTestData.say(r, '2');   // skip Account Aggregator
        System.assertEquals('Ignite', r.journey.Recommended_Card__c, 'declared groceries only: ' + r.message);

        BandhuEngine.Result r2 = BandhuTestData.newToBankAtProfile('9876500003', new List<String>{ '4', '2', '2' });
        r2 = BandhuTestData.sayAll(r2, profile);
        r2 = BandhuTestData.say(r2, '1'); // connect accounts
        System.assertEquals('Flare', r2.journey.Recommended_Card__c, r2.message);
        System.assert(r2.journey.Recommendation_Reason__c.contains('in your statements'), r2.journey.Recommendation_Reason__c);
        System.assert(r2.message.contains('What your statements show'), r2.message);
        System.assertEquals(335000, r2.journey.Credit_Limit__c, '3x + 0.5x (band A) the verified ₹96,000');
    }
}
