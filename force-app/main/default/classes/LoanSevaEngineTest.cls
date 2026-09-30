@IsTest
private class LoanSevaEngineTest {
    @TestSetup
    static void setup() {
        LoanSevaTestData.createCustomers();
    }

    @IsTest
    static void happyPathCreatesApplicationTaskEventAndFeedback() {
        Test.startTest();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        System.assertEquals('menu', LoanSevaEngine.awaiting(j));

        LoanSevaEngine.Result r = LoanSevaEngine.answerFaq(j, 'What can I use the loan for?');
        System.assert(r.success, 'FAQ should match');
        System.assert(LoanSevaJourneyService.byId(j.Id).Questions_Asked__c.contains('What can I use the loan for?'));

        r = LoanSevaEngine.verifyCustomer(r.journey, null, null);
        System.assertEquals('identity', LoanSevaEngine.awaiting(r.journey), 'Empty inputs ask for name and mobile');

        r = LoanSevaEngine.verifyCustomer(r.journey, 'Priya Sharma', LoanSevaTestData.PRIYA_MOBILE);
        System.assert(r.message.contains('XXXXXX0001'), 'OTP message shows the masked mobile: ' + r.message);
        System.assertEquals('otp', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.verifyOtp(r.journey, '123456');
        System.assert(r.journey.OTP_Verified__c);
        System.assert(r.message.contains('XXXX'), 'Snapshot uses the masked account number');
        System.assert(!r.message.contains('PL00099990001'), 'Full account number is never shown');
        System.assertEquals('loan_confirm', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.confirmLoan(r.journey, true);
        System.assertEquals('employment', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.personalise(r.journey, '1');
        System.assertEquals('Salaried', r.journey.Employment_Type__c);
        System.assertEquals('company', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.personalise(r.journey, 'Infosys');
        r = LoanSevaEngine.personalise(r.journey, '3');
        System.assertEquals('1L-2L', r.journey.Income_Bucket__c);
        r = LoanSevaEngine.personalise(r.journey, 'home renovation');
        System.assertEquals('Home renovation', r.journey.Purpose__c);
        System.assertEquals('amount', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.personalise(r.journey, '4');
        System.assertEquals(500000, r.journey.Desired_Amount__c, 'Option 4 = 100% of the 5L limit');

        // offer is shown right after the last answer
        System.assertEquals('Offer', r.journey.Stage__c);
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        System.assertNotEquals(null, r.journey.Offer_Amount__c);
        System.assertEquals(10.99, r.journey.Offer_Rate__c, 'Perfect track, salaried = base rate');

        r = LoanSevaEngine.offer(r.journey, null, '48 months');
        System.assertEquals(48, r.journey.Offer_Tenure_Months__c);
        Decimal emi48 = r.journey.Offer_EMI__c;
        System.assertEquals(LoanSevaEligibilityEngine.emi(r.journey.Offer_Amount__c, 10.99, 48), emi48);

        r = LoanSevaEngine.acceptOffer(r.journey);
        System.assert(Pattern.matches('KMB-PLTU-\\d{6}-\\d{4}', r.journey.Reference_Number__c), r.journey.Reference_Number__c);
        System.assert(r.message.contains(r.journey.Reference_Number__c));
        System.assertEquals('callback', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.scheduleCallback(r.journey, '2', null);
        Datetime expected = LoanSevaI18n.istDateTime(LoanSevaI18n.todayIst().addDays(1), 11, 0);
        System.assertEquals(expected, r.journey.Callback_DateTime__c, 'Option 2 = tomorrow 11:00 IST');
        System.assertEquals('feedback_csat', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.feedback(r.journey, '5');
        System.assertEquals('feedback_resolution', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.feedback(r.journey, '1');
        r = LoanSevaEngine.feedback(r.journey, 'Super quick!');
        Test.stopTest();

        Loan_Journey__c fin = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('Completed', fin.Status__c);
        System.assertEquals('done', LoanSevaEngine.awaiting(fin));
        System.assert(fin.Intent_Summary__c.startsWith('Priya — ₹'), fin.Intent_Summary__c);
        System.assert(fin.Intent_Summary__c.contains('home renovation'));
        System.assert(fin.Intent_Summary__c.contains('Salaried @ Infosys'));

        Loan_Application__c app = [SELECT Status__c, Reference_Number__c, Offer_Amount__c, FOIR__c, Callback_DateTime__c FROM Loan_Application__c WHERE Id = :fin.Loan_Application__c];
        System.assertEquals('Callback Scheduled', app.Status__c);
        System.assertEquals(fin.Reference_Number__c, app.Reference_Number__c);
        System.assert(app.FOIR__c > 0 && app.FOIR__c <= 55, 'FOIR within policy: ' + app.FOIR__c);

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :app.Id], 'RM task on the application');
        Event ev = [SELECT StartDateTime, EndDateTime, WhoId FROM Event WHERE WhatId = :app.Id];
        System.assertEquals(expected, ev.StartDateTime);
        System.assertEquals(fin.Contact__c, ev.WhoId);

        Journey_Feedback__c fb = [SELECT CSAT__c, Resolution__c, Comment__c FROM Journey_Feedback__c WHERE Loan_Journey__c = :j.Id];
        System.assertEquals(5, fb.CSAT__c);
        System.assertEquals('Yes, fully', fb.Resolution__c);
        System.assertEquals('Super quick!', fb.Comment__c);

        // once complete, further feedback replies just repeat the sign-off
        System.assert(LoanSevaEngine.feedback(fin, 'hello').message.contains(fin.Reference_Number__c));
    }

    @IsTest
    static void otpLocksAfterMaxAttemptsAndCreatesRmTask() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        j = LoanSevaEngine.verifyCustomer(j, 'Priya', LoanSevaTestData.PRIYA_MOBILE).journey;

        Test.startTest();
        LoanSevaEngine.Result r = LoanSevaEngine.verifyOtp(j, '111111');
        System.assert(!r.success);
        System.assert(r.message.contains('2'), 'Tells the customer attempts left: ' + r.message);
        r = LoanSevaEngine.verifyOtp(r.journey, '222222');
        r = LoanSevaEngine.verifyOtp(r.journey, '333333');
        Test.stopTest();

        System.assertEquals(LoanSevaJourneyService.STATUS_EXITED, r.journey.Status__c);
        System.assertEquals('handoff', LoanSevaEngine.awaiting(r.journey));
        System.assert(r.journey.Drop_Point__c.contains('OTP failed'));
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :j.Id AND Subject LIKE '%OTP failed%']);
        // locked journeys cannot retry
        System.assertEquals(LoanSevaI18n.msg('OTP_Locked', 'EN'), LoanSevaEngine.verifyOtp(r.journey, '123456').message);
        System.assertEquals(LoanSevaI18n.msg('OTP_Locked', 'EN'), LoanSevaEngine.verifyCustomer(r.journey, 'Priya', LoanSevaTestData.PRIYA_MOBILE).message);
    }

    @IsTest
    static void verifyRejectsUnknownMobileAndWrongName() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney('9123400000');
        LoanSevaEngine.Result r = LoanSevaEngine.verifyCustomer(j, 'Someone Else', '9123400000');
        System.assert(!r.success);
        System.assertEquals(LoanSevaI18n.msg('Verify_Not_Found', 'EN', new Map<String, Object>{ 'mobile' => '+91 XXXXXX0000' }), r.message);

        r = LoanSevaEngine.verifyCustomer(r.journey, 'Anita Kulkarni', LoanSevaTestData.PRIYA_MOBILE);
        System.assert(!r.success);
        System.assertEquals(LoanSevaI18n.msg('Verify_Name_Mismatch', 'EN'), r.message);
        System.assertEquals(null, r.journey.Existing_Loan__c, 'Loan is linked only after a name match');

        // OTP before identity asks for identity
        System.assertEquals(LoanSevaI18n.msg('Verify_Prompt', 'EN'), LoanSevaEngine.verifyOtp(r.journey, '123456').message);
    }

    @IsTest
    static void disputedSnapshotHandsOff() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        j = LoanSevaEngine.verifyCustomer(j, 'Priya Sharma', LoanSevaTestData.PRIYA_MOBILE).journey;
        j = LoanSevaEngine.verifyOtp(j, '123456').journey;
        // a repeated OTP call re-shows the snapshot
        System.assert(LoanSevaEngine.verifyOtp(j, 'anything').message.contains('XXXX'));

        LoanSevaEngine.Result r = LoanSevaEngine.confirmLoan(j, false);
        System.assert(r.handoff);
        System.assert(!r.journey.Loan_Confirmed__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :j.Id AND Subject LIKE '%disputes%']);
    }

    @IsTest
    static void gatesRePromptUntilPrerequisitesAreMet() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        String verifyPrompt = LoanSevaI18n.msg('Verify_Prompt', 'EN');
        System.assertEquals(verifyPrompt, LoanSevaEngine.confirmLoan(j, true).message);
        System.assertEquals(verifyPrompt, LoanSevaEngine.personalise(j, '1').message);
        System.assertEquals(verifyPrompt, LoanSevaEngine.offer(j, null, null).message);
        System.assertEquals(verifyPrompt, LoanSevaEngine.acceptOffer(j).message);
        System.assertEquals(verifyPrompt, LoanSevaEngine.scheduleCallback(j, '1', null).message);

        j = LoanSevaEngine.verifyCustomer(j, 'Priya', LoanSevaTestData.PRIYA_MOBILE).journey;
        System.assertEquals(LoanSevaI18n.msg('OTP_Reprompt', 'EN'), LoanSevaEngine.pendingPrompt(j, false));
        j = LoanSevaEngine.verifyOtp(j, '123456').journey;
        System.assertEquals(LoanSevaI18n.msg('Loan_Confirm_Reprompt', 'EN'), LoanSevaEngine.pendingPrompt(j, false));

        // answering a personalisation question implies the snapshot was accepted
        LoanSevaEngine.Result r = LoanSevaEngine.personalise(j, 'salaried');
        System.assert(r.journey.Loan_Confirmed__c);
        System.assertEquals('Salaried', r.journey.Employment_Type__c);
        System.assertEquals(LoanSevaI18n.msg('Q_Company', 'EN'), r.message);
    }

    @IsTest
    static void invalidAnswersAreReAsked() {
        Loan_Journey__c j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        LoanSevaEngine.Result r = LoanSevaEngine.personalise(j, 'banana');
        System.assert(!r.success);
        System.assert(r.message.contains(LoanSevaI18n.msg('Q_Employment', 'EN')));
        System.assertEquals(null, r.journey.Employment_Type__c);

        r = LoanSevaEngine.personalise(r.journey, '2');
        System.assertEquals('Self-employed', r.journey.Employment_Type__c);
        System.assertEquals(LoanSevaI18n.msg('Q_Business', 'EN'), r.message, 'Self-employed get the business question');
        r = LoanSevaEngine.personalise(r.journey, 'x');
        System.assert(!r.success, 'One-letter company is rejected');
        r = LoanSevaEngine.personalise(r.journey, 'Sharma Traders');
        r = LoanSevaEngine.personalise(r.journey, '₹1,20,000');
        System.assertEquals('1L-2L', r.journey.Income_Bucket__c, 'Typed income maps to a bucket');
        r = LoanSevaEngine.personalise(r.journey, 'something else');
        System.assert(!r.success);
        r = LoanSevaEngine.personalise(r.journey, 'my daughter\'s wedding');
        System.assertEquals('Wedding', r.journey.Purpose__c);
        r = LoanSevaEngine.personalise(r.journey, '10000');
        System.assert(!r.success, 'Below minimum top-up');
        r = LoanSevaEngine.personalise(r.journey, '2 lakh');
        System.assertEquals(200000, r.journey.Desired_Amount__c);
        System.assertEquals(11.74, r.journey.Offer_Rate__c, 'Self-employed premium applied');
        // extra personalise calls after completion just re-show the offer
        System.assertEquals('Offer', LoanSevaEngine.personalise(r.journey, 'hi').journey.Stage__c);
    }

    @IsTest
    static void weakRepaymentTrackIsReferredToRm() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.VIKRAM_MOBILE, 'Vikram Rao');
        System.assert(r.handoff);
        System.assert(!r.success);
        System.assertEquals(null, r.journey.Offer_Amount__c);
        System.assertEquals('Referred to RM', [SELECT Status__c FROM Loan_Application__c WHERE Loan_Journey__c = :r.journey.Id].Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :r.journey.Id AND Subject LIKE '%Refer%']);
        System.assertEquals(LoanSevaI18n.msg('Refer_Reprompt', 'EN'), LoanSevaEngine.pendingPrompt(r.journey, false));
        System.assertEquals(LoanSevaI18n.msg('Refer_Reprompt', 'EN'), LoanSevaEngine.acceptOffer(r.journey).message, 'No offer to accept');
        r = LoanSevaEngine.reply(r.journey, '1');
        System.assert(!r.journey.Offer_Accepted__c, 'A referred journey cannot accept an offer');
    }

    @IsTest
    static void goodTrackOfferIsCappedAndEditable() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.RAHUL_MOBILE, 'Rahul Deshmukh');
        System.assertEquals(11.99, r.journey.Offer_Rate__c, 'Good-track premium applied');
        System.assert(r.journey.Offer_Amount__c <= 300000 * LoanSevaEligibilityEngine.GOOD_TRACK_CAP);
        System.assert(r.message.contains(LoanSevaI18n.msg('Offer_Capped', 'EN', new Map<String, Object>{ 'max' => LoanSevaI18n.inr(r.journey.Offer_Amount__c) })));

        r = LoanSevaEngine.offer(r.journey, '1 lakh', null);
        System.assertEquals(100000, r.journey.Offer_Amount__c);
        r = LoanSevaEngine.offer(r.journey, null, '2 years');
        System.assertEquals(24, r.journey.Offer_Tenure_Months__c);
        r = LoanSevaEngine.offer(r.journey, '75k', null);
        System.assertEquals(75000, r.journey.Offer_Amount__c);
        System.assertEquals(24, r.journey.Offer_Tenure_Months__c, 'Changing only the amount keeps the tenure');
        System.assertEquals(1, [SELECT COUNT() FROM Loan_Application__c WHERE Loan_Journey__c = :r.journey.Id], 'Edits update one application');
    }

    @IsTest
    static void callbackAcceptsTypedTimesAndRejectsPast() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.acceptOffer(r.journey);
        String ref = r.journey.Reference_Number__c;
        System.assertEquals(ref, LoanSevaEngine.acceptOffer(r.journey).journey.Reference_Number__c, 'Accepting twice keeps the reference');
        System.assert(LoanSevaEngine.pendingPrompt(r.journey, false).contains('2️⃣'), 'Re-prompt lists the slots');

        LoanSevaEngine.Result bad = LoanSevaEngine.scheduleCallback(r.journey, 'whenever', null);
        System.assert(!bad.success);
        bad = LoanSevaEngine.scheduleCallback(bad.journey, null, '2001-01-01T10:00:00Z');
        System.assert(!bad.success, 'Past times are rejected');

        Test.startTest();
        LoanSevaEngine.Result ok = LoanSevaEngine.scheduleCallback(bad.journey, 'tomorrow 4pm', null);
        Test.stopTest();
        System.assert(ok.success);
        System.assertEquals(LoanSevaI18n.istDateTime(LoanSevaI18n.todayIst().addDays(1), 16, 0), ok.journey.Callback_DateTime__c);
        System.assert(ok.message.contains(ref));
    }

    @IsTest
    static void callbackAcceptsAsapAndIsoPreference() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.acceptOffer(r.journey);
        LoanSevaEngine.Result ok = LoanSevaEngine.scheduleCallback(r.journey, 'as soon as possible', null);
        System.assert(ok.success);
        System.assert(ok.journey.Callback_DateTime__c > Datetime.now());
        Integer hour = LoanSevaI18n.istHour(ok.journey.Callback_DateTime__c);
        System.assert(hour >= 9 && hour <= 19, 'ASAP slot is in business hours: ' + hour);

        String iso = Datetime.now().addDays(3).format('yyyy-MM-dd', LoanSevaI18n.TIMEZONE) + 'T15:30';
        Loan_Journey__c j2 = LoanSevaTestData.personalisedJourney(LoanSevaTestData.RAHUL_MOBILE, 'Rahul').journey;
        j2 = LoanSevaEngine.acceptOffer(j2).journey;
        LoanSevaEngine.Result byIso = LoanSevaEngine.scheduleCallback(j2, null, iso);
        System.assertEquals(15, LoanSevaI18n.istHour(byIso.journey.Callback_DateTime__c), 'Naive ISO values are IST wall-clock');
    }

    @IsTest
    static void feedbackValidatesAnswersAndSkipsComment() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.acceptOffer(r.journey);
        Loan_Journey__c j = r.journey;
        j.Feedback_Step__c = null;
        r = LoanSevaEngine.feedback(j, null);
        System.assertEquals('Feedback', r.journey.Stage__c, 'Feedback can start without a callback');
        System.assert(!LoanSevaEngine.feedback(r.journey, '9').success, 'CSAT must be 1-5');
        r = LoanSevaEngine.feedback(r.journey, '4 😊');
        System.assert(!LoanSevaEngine.feedback(r.journey, 'hmm').success);
        r = LoanSevaEngine.feedback(r.journey, 'mostly');
        System.assertEquals(3, r.journey.Feedback_Step__c);
        r = LoanSevaEngine.feedback(r.journey, 'Skip');
        Journey_Feedback__c fb = [SELECT CSAT__c, Resolution__c, Comment__c FROM Journey_Feedback__c WHERE Loan_Journey__c = :j.Id];
        System.assertEquals(4, fb.CSAT__c);
        System.assertEquals('Mostly', fb.Resolution__c);
        System.assertEquals(null, fb.Comment__c);
        System.assertEquals('Completed', r.journey.Status__c);
    }

    @IsTest
    static void languageSwitchRepeatsPendingQuestion() {
        Loan_Journey__c j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        LoanSevaEngine.Result r = LoanSevaEngine.setLanguage(j, 'हिंदी');
        System.assertEquals('HI', r.journey.Language__c);
        System.assert(r.message.contains(LoanSevaI18n.msg('Q_Employment', 'HI')));
        System.assertNotEquals(LoanSevaI18n.msg('Q_Employment', 'HI'), LoanSevaI18n.msg('Q_Employment', 'EN'), 'Hindi copy exists');
        r = LoanSevaEngine.setLanguage(r.journey, 'marathi');
        System.assertEquals('MR', r.journey.Language__c);
        r = LoanSevaEngine.setLanguage(r.journey, 'klingon');
        System.assertEquals(LoanSevaI18n.msg('Language_Options', 'MR'), r.message);
        System.assertEquals('MR', LoanSevaJourneyService.byId(j.Id).Language__c, 'Language persisted');
        Loan_Journey__c m = LoanSevaTestData.startedJourney(LoanSevaTestData.RAHUL_MOBILE);
        r = LoanSevaEngine.setLanguage(m, 'HI');
        System.assert(r.message.contains('2️⃣'), 'At the menu the menu is repeated, not the name/mobile ask: ' + r.message);
        System.assert(!r.message.contains(LoanSevaI18n.msg('Verify_Prompt', 'HI')));
    }

    @IsTest
    static void faqFallbackAndResumePrompt() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.answerFaq(j, 'zzzz qqqq');
        System.assert(!r.success);
        System.assert(r.message.startsWith(LoanSevaI18n.msg('FAQ_Not_Found', 'EN')), r.message);
        System.assert(r.message.endsWith(LoanSevaI18n.msg('FAQ_Nudge', 'EN')), 'No match still points to the next step');
        r = LoanSevaEngine.answerFaq(r.journey, 'What documents do I need?');
        System.assert(r.message.endsWith(LoanSevaI18n.msg('FAQ_Nudge', 'EN')), 'Unverified customers are nudged to verify');

        Loan_Journey__c v = LoanSevaTestData.verifiedJourney(LoanSevaTestData.RAHUL_MOBILE, 'Rahul Deshmukh');
        r = LoanSevaEngine.answerFaq(v, 'what is the interest rate');
        System.assert(r.message.contains(LoanSevaI18n.msg('Resume_Prompt', 'EN')), 'Verified customers resume where they were');
        System.assert(r.message.contains(LoanSevaI18n.msg('Q_Employment', 'EN')));
    }

    @IsTest
    static void escalationCreatesTaskAndFlagsHandoff() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.escalate(j, null);
        System.assert(r.handoff);
        System.assert(r.journey.Escalated__c);
        Task t = [SELECT Subject, Priority, WhoId FROM Task WHERE WhatId = :j.Id];
        System.assert(t.Subject.contains('Human requested'));
        System.assertEquals('High', t.Priority);
        System.assertEquals(j.Contact__c, t.WhoId);
    }

    @IsTest
    static void replyRoutesEveryStepOnJourneyState() {
        Test.startTest();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, '2');
        System.assert(r.message.contains('Top-Up'), 'Menu 2 asks what they want to know: ' + r.message);
        r = LoanSevaEngine.reply(r.journey, 'What can I use the loan for?');
        System.assert(r.success, 'A clear question is answered from the FAQ');
        r = LoanSevaEngine.reply(r.journey, 'Hi');
        System.assertEquals('menu', LoanSevaEngine.awaiting(r.journey), 'A greeting re-shows the welcome menu');
        r = LoanSevaEngine.reply(r.journey, 'Yes');
        System.assertEquals('identity', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, 'My name is Priya Sharma, mobile +91 ' + LoanSevaTestData.PRIYA_MOBILE);
        System.assertEquals('otp', LoanSevaEngine.awaiting(r.journey), 'Name and mobile are extracted from one message: ' + r.message);
        r = LoanSevaEngine.reply(r.journey, '123456');
        System.assertEquals('loan_confirm', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, 'maybe');
        System.assertEquals('loan_confirm', LoanSevaEngine.awaiting(r.journey), 'An unclear reply re-asks');
        r = LoanSevaEngine.reply(r.journey, 'हाँ, सही है');
        System.assertEquals('employment', LoanSevaEngine.awaiting(r.journey), 'Hindi yes confirms the loan');
        for (String answer : new List<String>{ '1', 'Infosys', '3', '1', '4' }) {
            r = LoanSevaEngine.reply(r.journey, answer);
        }
        System.assertEquals(500000, r.journey.Desired_Amount__c);
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, '2');
        System.assert(r.message.contains('lakh'), 'Change without details asks for amount/tenure: ' + r.message);
        r = LoanSevaEngine.reply(r.journey, '3 lakh for 48 months');
        System.assertEquals(300000, r.journey.Desired_Amount__c, 'A leading 3 is an amount here, not option 3');
        r = LoanSevaEngine.reply(r.journey, '4 lakh for 48 months');
        System.assertEquals(400000, r.journey.Desired_Amount__c);
        System.assertEquals(48, r.journey.Offer_Tenure_Months__c);
        r = LoanSevaEngine.reply(r.journey, '36 months');
        System.assertEquals(36, r.journey.Offer_Tenure_Months__c);
        System.assertEquals(400000, r.journey.Desired_Amount__c, 'A tenure-only change keeps the amount');
        r = LoanSevaEngine.reply(r.journey, '3');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey), 'Option 3 asks for the question');
        r = LoanSevaEngine.reply(r.journey, 'hmm');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, '1');
        System.assertNotEquals(null, r.journey.Reference_Number__c);
        r = LoanSevaEngine.reply(r.journey, '2');
        System.assertNotEquals(null, r.journey.Callback_DateTime__c);
        r = LoanSevaEngine.reply(r.journey, '5');
        r = LoanSevaEngine.reply(r.journey, '1');
        r = LoanSevaEngine.reply(r.journey, 'Skip');
        System.assertEquals('done', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, 'Thanks!');
        System.assert(r.message.contains(r.journey.Reference_Number__c), 'Done: sign-off repeats the reference');
        Test.stopTest();
    }

    @IsTest
    static void replyHandlesNoMenuEscalationAndLockout() {
        Test.startTest();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, '3');
        System.assert(r.handoff, 'Menu 3 hands off to a specialist');
        r = LoanSevaEngine.reply(r.journey, '1');
        r = LoanSevaEngine.reply(r.journey, 'Priya Sharma ' + LoanSevaTestData.PRIYA_MOBILE);
        r = LoanSevaEngine.reply(r.journey, '123456');
        r = LoanSevaEngine.reply(r.journey, 'No, wrong');
        System.assert(r.handoff, 'Disputed snapshot hands off');

        Loan_Journey__c k = LoanSevaTestData.startedJourney(LoanSevaTestData.RAHUL_MOBILE);
        r = LoanSevaEngine.verifyCustomer(k, 'Rahul Deshmukh', LoanSevaTestData.RAHUL_MOBILE);
        for (Integer i = 0; i < 3; i++) {
            r = LoanSevaEngine.reply(r.journey, '000000');
        }
        System.assertEquals('handoff', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, 'hello');
        System.assertEquals(LoanSevaJourneyService.STATUS_EXITED, r.journey.Status__c, 'Locked journeys stay exited');
        Test.stopTest();
    }

    @IsTest
    static void replyEscalatesSpecialistRequestsWithRmTask() {
        Test.startTest();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, 'I want to talk to a human agent');
        System.assert(r.handoff, 'A request for a human hands off');
        r = LoanSevaEngine.reply(r.journey, 'मुझे विशेषज्ञ से बात करनी है');
        System.assert(r.handoff, 'Hindi request for a specialist hands off');

        Loan_Journey__c k = LoanSevaTestData.startedJourney(LoanSevaTestData.RAHUL_MOBILE);
        r = LoanSevaEngine.verifyCustomer(k, 'Rahul Deshmukh', LoanSevaTestData.RAHUL_MOBILE);
        r = LoanSevaEngine.reply(r.journey, 'agent');
        System.assertEquals('otp', LoanSevaEngine.awaiting(r.journey), 'OTP step is never treated as an escalation');
        Test.stopTest();

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :j.Id AND Subject LIKE 'LoanSeva: Human requested%'];
        System.assertEquals(2, tasks.size(), 'Each request logs an RM Task');
        System.assert(tasks[0].Subject.contains('Asked for a specialist'), tasks[0].Subject);
        System.assertEquals(true, [SELECT Escalated__c FROM Loan_Journey__c WHERE Id = :j.Id].Escalated__c);
    }

    @IsTest
    static void askQuestionTreatsNextMessageAsQuestion() {
        Test.startTest();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, '2');
        System.assert(r.journey.Question_Pending__c, 'Menu 2 waits for a question');
        r = LoanSevaEngine.reply(r.journey, 'I would like to know more about PL');
        System.assert(r.success, 'A general question gets the Top-Up overview: ' + r.message);
        System.assert(r.message.contains('Personal Loan Top-Up'), r.message);
        System.assertEquals('menu', LoanSevaEngine.awaiting(r.journey), 'Still at the menu, not restarted into verification');
        System.assert(!r.journey.Question_Pending__c);

        r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.RAHUL_MOBILE, 'Rahul Deshmukh');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, '3');
        r = LoanSevaEngine.reply(r.journey, 'Yes');
        System.assert(!r.journey.Offer_Accepted__c, 'A Yes typed as the question never accepts the offer');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey), 'Yes carries on to the offer: ' + r.message);
        r = LoanSevaEngine.reply(r.journey, '3');
        r = LoanSevaEngine.reply(r.journey, 'tell me more about the fees');
        System.assert(r.success && !r.journey.Offer_Accepted__c, 'The specific FAQ wins over the overview: ' + r.message);
        r = LoanSevaEngine.reply(r.journey, '3');
        r = LoanSevaEngine.reply(r.journey, '1️⃣');
        System.assert(r.journey.Offer_Accepted__c, 'A bare option number still picks that option');
        Test.stopTest();

        String asked = [SELECT Questions_Asked__c FROM Loan_Journey__c WHERE Id = :j.Id].Questions_Asked__c;
        System.assert(asked.contains('know more about PL'), 'The question is logged for the RM: ' + asked);
    }

    @IsTest
    static void askingForMyOfferStartsTheOfferJourney() {
        Test.startTest();
        LoanSevaEngine.Result r = LoanSevaEngine.reply(LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE), 'I want to know my offer');
        System.assertEquals('identity', LoanSevaEngine.awaiting(r.journey), 'Typed offer request at the menu: ' + r.message);

        r = LoanSevaEngine.reply(LoanSevaTestData.startedJourney(LoanSevaTestData.RAHUL_MOBILE), '2');
        r = LoanSevaEngine.reply(r.journey, 'Yes');
        System.assertEquals('identity', LoanSevaEngine.awaiting(r.journey), 'Yes after Ask a question carries on, not FAQ_Not_Found: ' + r.message);

        r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.reply(r.journey, '3');
        r = LoanSevaEngine.reply(r.journey, 'show me my offer');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        System.assert(!r.message.startsWith(LoanSevaI18n.msg('FAQ_Not_Found', 'EN').left(20)), 'The offer is shown again: ' + r.message);
        System.assert(!r.journey.Offer_Accepted__c);
        Test.stopTest();
    }

    @IsTest
    static void greetingAfterCompletedJourneyStartsFresh() {
        Loan_Journey__c done = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        done.Status__c = LoanSevaJourneyService.STATUS_COMPLETED;
        done.Language__c = 'HI';
        update done;
        Test.startTest();
        System.assertEquals(done.Id, LoanSevaJourneyService.resolve(done.Id, null, null).Id, 'Other actions keep the journey');
        Loan_Journey__c fresh = LoanSevaJourneyService.resolve(done.Id, null, LoanSevaTestData.PRIYA_MOBILE, true);
        Test.stopTest();
        System.assertNotEquals(done.Id, fresh.Id, 'Start after completion begins a new journey');
        System.assertEquals('HI', fresh.Language__c, 'The language carries over');
        System.assertEquals('menu', LoanSevaEngine.awaiting(fresh));
    }

    @IsTest
    static void resumedJourneyMenuPicksMenuOptions() {
        Test.startTest();
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.reply(r.journey, '48 months');
        r = LoanSevaEngine.reply(r.journey, '1');
        System.assertEquals('callback', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.start(r.journey);
        System.assert(r.journey.Menu_Pending__c, 'Welcome menu on a resumed journey');
        r = LoanSevaEngine.reply(r.journey, '2');
        System.assertEquals(null, r.journey.Callback_DateTime__c, '2 is the menu question option, not callback slot 2');
        System.assert(r.journey.Question_Pending__c);
        r = LoanSevaEngine.reply(r.journey, 'I want to know more about Top-up');
        System.assert(r.success && r.message.contains('Personal Loan Top-Up'), r.message);

        r = LoanSevaEngine.start(r.journey);
        r = LoanSevaEngine.reply(r.journey, '1');
        System.assert(r.message.contains(LoanSevaI18n.msg('Resume_Prompt', 'EN')), 'Option 1 resumes the pending step: ' + r.message);
        System.assertEquals(null, r.journey.Callback_DateTime__c);

        r = LoanSevaEngine.start(r.journey);
        r = LoanSevaEngine.reply(r.journey, 'Thu 11am');
        System.assertNotEquals(null, r.journey.Callback_DateTime__c, 'A real answer still answers the pending step');
        System.assert(!r.journey.Menu_Pending__c);

        r = LoanSevaEngine.start(r.journey);
        r = LoanSevaEngine.reply(r.journey, '3');
        System.assert(r.handoff, 'Option 3 escalates');
        Test.stopTest();

        Loan_Journey__c o = LoanSevaTestData.personalisedJourney(LoanSevaTestData.RAHUL_MOBILE, 'Rahul Deshmukh').journey;
        r = LoanSevaEngine.reply(o, '48 months');
        r = LoanSevaEngine.start(r.journey);
        r = LoanSevaEngine.reply(r.journey, '1');
        System.assertEquals(48, r.journey.Offer_Tenure_Months__c, 'Option 1 re-shows the offer with the chosen tenure');
        System.assert(!r.journey.Offer_Accepted__c, 'Option 1 on the menu never accepts the offer');
    }

    @IsTest
    static void parsersHandleIndianFormats() {
        System.assertEquals(500000, LoanSevaEngine.parseAmount('5L'));
        System.assertEquals(250000, LoanSevaEngine.parseAmount('2.5 lakhs'));
        System.assertEquals(500000, LoanSevaEngine.parseAmount('₹5,00,000'));
        System.assertEquals(80000, LoanSevaEngine.parseAmount('80k'));
        System.assertEquals(12000000, LoanSevaEngine.parseAmount('1.2 cr'));
        System.assertEquals(300000, LoanSevaEngine.parseAmount('3 लाख'));
        System.assertEquals(null, LoanSevaEngine.parseAmount('5'), 'Bare small numbers are menu choices, not amounts');
        System.assertEquals(null, LoanSevaEngine.parseAmount('none'));

        System.assertEquals(48, LoanSevaEngine.parseTenure('48 months'));
        System.assertEquals(36, LoanSevaEngine.parseTenure('3 years'));
        System.assertEquals(24, LoanSevaEngine.parseTenure('2'));
        System.assertEquals(null, LoanSevaEngine.parseTenure('17 months'), 'Only configured tenures');
        System.assertEquals(null, LoanSevaEngine.parseTenure(''));

        System.assertEquals(2, LoanSevaEngine.choiceNumber('2️⃣'));
        System.assertEquals(3, LoanSevaEngine.choiceNumber('३'));
        System.assertEquals(2, LoanSevaEngine.choiceNumber('2. Mostly'));
        System.assertEquals(1, LoanSevaEngine.choiceNumber('option 1'));
        System.assertEquals(null, LoanSevaEngine.choiceNumber('24 hours'));
        System.assertEquals(null, LoanSevaEngine.choiceNumber(null));

        System.assertEquals('+91 XXXXXX4321', LoanSevaEngine.maskMobile('9876504321'));
        System.assertEquals('1️⃣', LoanSevaEngine.numberEmoji(1));
        System.assertEquals('12', LoanSevaEngine.numberEmoji(12));
        List<Decimal> opts = LoanSevaEngine.amountOptions(500000);
        System.assertEquals(4, opts.size());
        System.assert(opts[0] == 125000 && opts[1] == 250000 && opts[2] == 375000 && opts[3] == 500000, 'Quarter steps up to the limit: ' + opts);
        opts = LoanSevaEngine.amountOptions(40000);
        System.assert(opts.size() == 1 && opts[0] == 40000, 'Tiny limits still get one option: ' + opts);
        System.assert(LoanSevaEngine.namesMatch('priya s', new Contact(FirstName = 'Priya', LastName = 'Sharma')));
        System.assert(!LoanSevaEngine.namesMatch('Anita', new Contact(FirstName = 'Priya', LastName = 'Sharma')));
        System.assertEquals('menu', LoanSevaEngine.awaiting(null));
    }
}
