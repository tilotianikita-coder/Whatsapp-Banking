/**
 * Eligibility maths, parsing, formatting, FAQ matching and journey helpers.
 */
@IsTest
private class LoanSevaUtilsTest {
    private static Existing_Loan__c loan(Decimal emi, Integer onTime, Decimal limitAmount) {
        return LoanSevaTestData.loan(null, 'PL1', 300000, emi, 30, onTime, limitAmount);
    }

    @IsTest
    static void eligibilityAppliesTrackRateFoirAndCaps() {
        // perfect track, salaried, 1L-2L (150000 assumed): EMI headroom = 150000 * 55% - 11800 = 70700
        LoanSevaEligibilityEngine.Result r = LoanSevaEligibilityEngine.evaluate(loan(11800, 12, 500000), '1L-2L', 'Salaried', 300000, null);
        System.assert(r.eligible);
        System.assertEquals(10.99, r.rate);
        System.assertEquals(300000, r.amount);
        System.assertEquals(36, r.tenure, 'Default tenure fits the amount');
        System.assertEquals(LoanSevaEligibilityEngine.emi(300000, 10.99, 36), r.emi);
        System.assertEquals(4500, r.processingFee, '1.5% of 3L');
        System.assertEquals(5, r.emiByTenure.size());
        System.assert(r.foirPct <= 55);
        System.assert(!r.cappedBelowDesired);

        // desired above the pre-approved limit is capped
        r = LoanSevaEligibilityEngine.evaluate(loan(11800, 12, 500000), '2L+', 'Salaried', 900000, 60);
        System.assertEquals(500000, r.amount);
        System.assertEquals(60, r.tenure);
        System.assert(r.cappedBelowDesired);

        // good track: premium and 80% cap; self-employed premium
        r = LoanSevaEligibilityEngine.evaluate(loan(5000, 11, 300000), '2L+', 'Self-employed', null, null);
        System.assertEquals(10.99 + 1.00 + 0.75, r.rate);
        System.assertEquals(225000, r.amount, '80% of 3L rounded down to 25K');

        // FOIR headroom gone
        r = LoanSevaEligibilityEngine.evaluate(loan(50000, 12, 500000), 'Below 50K', 'Salaried', null, null);
        System.assert(!r.eligible);
        System.assert(String.join(r.notes, ' ').contains('No FOIR headroom'));

        // weak track and missing data
        System.assert(!LoanSevaEligibilityEngine.evaluate(loan(5000, 6, 300000), '2L+', 'Salaried', null, null).eligible);
        System.assert(!LoanSevaEligibilityEngine.evaluate(null, '2L+', 'Salaried', null, null).eligible);
        System.assert(!LoanSevaEligibilityEngine.evaluate(loan(5000, 12, 300000), 'unknown', 'Salaried', null, null).eligible);

        // eligible amount below the minimum top-up
        r = LoanSevaEligibilityEngine.evaluate(loan(21000, 12, 500000), 'Below 50K', 'Salaried', null, 12);
        System.assert(!r.eligible);
        System.assertEquals(0, r.amount);
    }

    @IsTest
    static void emiMathsIsConsistent() {
        Decimal e = LoanSevaEligibilityEngine.emi(100000, 12, 12);
        System.assertEquals(8885, e.round(RoundingMode.HALF_UP), 'Standard amortised EMI');
        System.assert(Math.abs(LoanSevaEligibilityEngine.emi(100000, 0, 12) - 100000 / 12.0) < 1, 'Zero rate is principal / months');
        Decimal p = LoanSevaEligibilityEngine.principalFor(e, 12, 12);
        System.assert(Math.abs(p - 100000) < 50, 'principalFor inverts emi: ' + p);
        System.assertEquals(475000, LoanSevaEligibilityEngine.roundDown(499999, 25000));
    }

    @IsTest
    static void dateParserUnderstandsCommonReplies() {
        Date today = LoanSevaI18n.todayIst();
        System.assertEquals(LoanSevaI18n.istDateTime(today.addDays(1), 16, 0), LoanSevaDateParser.parse('tomorrow 4pm'));
        System.assertEquals(LoanSevaI18n.istDateTime(today.addDays(2), 11, 30), LoanSevaDateParser.parse('day after tomorrow 11:30 am'));
        System.assertEquals(LoanSevaI18n.istDateTime(today.addDays(1), 15, 0), LoanSevaDateParser.parse('कल 3:00'), 'Hindi "tomorrow", 3:00 means afternoon');
        System.assertEquals(LoanSevaI18n.istDateTime(today, 23, 0), LoanSevaDateParser.parse('today 11 pm'));
        System.assertEquals(LoanSevaI18n.istDateTime(today.addDays(1), 0, 0).date(), LoanSevaDateParser.parse('tomorrow 12 am').addMinutes(330).dateGmt());

        Datetime byMonth = LoanSevaDateParser.parse('15 dec 10am');
        System.assertEquals(12, byMonth.addMinutes(330).monthGmt());
        System.assertEquals(15, byMonth.addMinutes(330).dayGmt());
        Datetime bySlash = LoanSevaDateParser.parse('15/12 10:00');
        System.assertEquals(byMonth, bySlash);

        Datetime weekday = LoanSevaDateParser.parse('Thu 11:00');
        System.assertEquals('Thu', weekday.format('EEE', LoanSevaI18n.TIMEZONE));
        System.assertEquals(11, LoanSevaI18n.istHour(weekday));

        System.assert(LoanSevaDateParser.parse('9am') > Datetime.now(), 'A bare time is never in the past');
        System.assertEquals(null, LoanSevaDateParser.parse('sometime next week'));
        System.assertEquals(null, LoanSevaDateParser.parse('13pm'));
        System.assertEquals(null, LoanSevaDateParser.parse('25:00'));
        System.assertEquals(null, LoanSevaDateParser.parse(''));
    }

    @IsTest
    static void i18nFormatsIndianStyle() {
        System.assertEquals('₹5,00,000', LoanSevaI18n.inr(500000));
        System.assertEquals('₹1,23,45,678', LoanSevaI18n.inr(12345678));
        System.assertEquals('₹999', LoanSevaI18n.inr(999));
        System.assertEquals('-₹1,500', LoanSevaI18n.inr(-1500));
        System.assertEquals('', LoanSevaI18n.inr(null));
        System.assertEquals('₹5L', LoanSevaI18n.inrShort(500000));
        System.assertEquals('₹2.5L', LoanSevaI18n.inrShort(250000));
        System.assertEquals('₹1.2Cr', LoanSevaI18n.inrShort(12000000));
        System.assertEquals('₹75,000', LoanSevaI18n.inrShort(75000));
        System.assertEquals('', LoanSevaI18n.inrShort(null));

        System.assertEquals('HI', LoanSevaI18n.parseLanguage('Hindi'));
        System.assertEquals('MR', LoanSevaI18n.parseLanguage('मराठी'));
        System.assertEquals('EN', LoanSevaI18n.parseLanguage('en'));
        System.assertEquals(null, LoanSevaI18n.parseLanguage('tamil'));
        System.assertEquals(null, LoanSevaI18n.parseLanguage(null));

        System.assertEquals('hindi', LoanSevaI18n.pick('english', 'hindi', 'marathi', 'HI'));
        System.assertEquals('marathi', LoanSevaI18n.pick('english', 'hindi', 'marathi', 'MR'));
        System.assertEquals('english', LoanSevaI18n.pick('english', '', 'marathi', 'HI'), 'Falls back to English');
        System.assertEquals('Hi Priya, ', LoanSevaI18n.mergeTokens('Hi {name}, {missing}', new Map<String, Object>{ 'name' => 'Priya', 'missing' => null }));
        System.assertEquals('', LoanSevaI18n.formatDateTime(null));
        System.assertEquals(LoanSevaI18n.istDateTime(Date.newInstance(2026, 1, 1), 10, 0), Datetime.newInstanceGmt(2026, 1, 1, 4, 30, 0));

        // every message key has all three languages
        for (LoanSeva_Message__mdt m : [SELECT DeveloperName, English__c, Hindi__c, Marathi__c FROM LoanSeva_Message__mdt]) {
            System.assert(String.isNotBlank(m.English__c) && String.isNotBlank(m.Hindi__c) && String.isNotBlank(m.Marathi__c), m.DeveloperName + ' is missing a language');
        }
        try {
            LoanSevaI18n.msg('No_Such_Key', 'EN');
            System.assert(false, 'Expected a missing-key error');
        } catch (LoanSevaException e) {
            System.assert(e.getMessage().contains('No_Such_Key'));
        }
    }

    @IsTest
    static void faqMatcherIsGroundedInApprovedContent() {
        System.assertEquals('Interest_Rate', LoanSevaFaqMatcher.bestMatch('What is the interest rate?').DeveloperName);
        System.assertEquals('Vs_New_Loan', LoanSevaFaqMatcher.bestMatch('how is this different from a new loan').DeveloperName);
        System.assertEquals('Documents', LoanSevaFaqMatcher.bestMatch('which documents are needed').DeveloperName);
        System.assertEquals(null, LoanSevaFaqMatcher.bestMatch('because'), 'Word-start matching avoids false hits');
        System.assertEquals(null, LoanSevaFaqMatcher.bestMatch(''));
        System.assertEquals(null, LoanSevaFaqMatcher.bestMatch('tell me more about PL'), 'The overview is opt-in');
        System.assertEquals('About_Top_Up', LoanSevaFaqMatcher.bestMatch('tell me more about PL', true).DeveloperName);
        System.assertEquals('Interest_Rate', LoanSevaFaqMatcher.bestMatch('tell me more about the interest rate', true).DeveloperName, 'Specific FAQs win');

        LoanSeva_FAQ__mdt rate = LoanSevaFaqMatcher.bestMatch('interest rate');
        String answer = LoanSevaFaqMatcher.render(rate, 'EN');
        System.assert(answer.contains(LoanSevaConfig.get().Rate_Display__c), 'Rate comes from config: ' + answer);
        System.assert(!answer.contains('{'), 'All tokens merged');
        System.assertEquals(9, LoanSevaFaqMatcher.all().size(), '8 specific FAQs plus the Top-Up overview');
        for (LoanSeva_FAQ__mdt f : LoanSevaFaqMatcher.all()) {
            System.assert(String.isNotBlank(LoanSevaFaqMatcher.render(f, 'HI')));
        }
    }

    @IsTest
    static void configAndJourneyHelpers() {
        System.assertEquals(new List<Integer>{ 12, 24, 36, 48, 60 }, LoanSevaConfig.tenureOptions());
        System.assertEquals(3, LoanSevaConfig.maxOtpAttempts());
        System.assertEquals(150000, LoanSevaConfig.incomeValues().get('1L-2L'));
        System.assertEquals(25000, LoanSevaConfig.rounding());

        System.assertEquals('9876543210', LoanSevaJourneyService.normalizeMobile('+91 98765-43210'));
        System.assertEquals(null, LoanSevaJourneyService.normalizeMobile('12345'));
        System.assert(LoanSevaJourneyService.isValidIndianMobile('09876543210'));
        System.assert(LoanSevaJourneyService.isValidIndianMobile('919876543210'));
        System.assert(!LoanSevaJourneyService.isValidIndianMobile('5876543210'), 'Indian mobiles start with 6-9');
        System.assert(!LoanSevaJourneyService.isId('hello'));
        System.assert(!LoanSevaJourneyService.isId(null));

        Loan_Journey__c j = new Loan_Journey__c(Mobile__c = '9876543210', Stage__c = 'Offer', Status__c = 'Dropped', Drop_Point__c = 'Offer (5/5 fields)',
            Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys', Income_Bucket__c = '1L-2L', Purpose__c = 'Travel', Desired_Amount__c = 250000);
        System.assertEquals(5, LoanSevaJourneyService.fieldsCompleted(j));
        System.assertEquals('Customer 9876543210 — ₹2.5L top-up for travel, Salaried @ Infosys, income 1L-2L, dropped at Offer (5/5 fields)', LoanSevaJourneyService.intentSummary(j));
        LoanSevaJourneyService.advance(j, 'Verify');
        System.assertEquals('Offer', j.Stage__c, 'Stages never move backwards');
        System.assertEquals('Active', j.Status__c, 'Activity re-activates a dropped journey');
        System.assertEquals(UserInfo.getUserId(), LoanSevaJourneyService.rmOwnerId(j));

        Lead l = new Lead(LastName = 'Prospect', Company = 'Individual', MobilePhone = '9876543210');
        insert l;
        j.Lead__c = l.Id;
        insert j;
        Task t = LoanSevaJourneyService.buildRmTask(LoanSevaJourneyService.byId(j.Id), 'Follow up', 'details', null);
        insert t;
        System.assertEquals(l.Id, t.WhoId);
        System.assertEquals(null, t.WhatId, 'Lead tasks cannot also carry a WhatId');
        System.assert(t.Description.contains(j.Id), 'Journey is referenced in the description instead');
    }
}
