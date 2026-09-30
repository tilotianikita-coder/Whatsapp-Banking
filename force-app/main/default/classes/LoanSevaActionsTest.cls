/**
 * Drives the full journey through the invocable actions exactly as the agent does,
 * checking the `awaiting` routing output after every step.
 */
@IsTest
private class LoanSevaActionsTest {
    @TestSetup
    static void setup() {
        LoanSevaTestData.createCustomers();
    }

    @IsTest
    static void fullJourneyThroughActions() {
        Test.startTest();
        LoanSevaStartAction.Request start = new LoanSevaStartAction.Request();
        start.mobile = LoanSevaTestData.PRIYA_MOBILE;
        LoanSevaActionResult r = LoanSevaStartAction.run(new List<LoanSevaStartAction.Request>{ start })[0];
        System.assert(r.success);
        System.assert(r.message.contains('Priya'), 'Personalised welcome: ' + r.message);
        System.assertEquals('menu', r.awaiting);
        String jid = r.journeyId;

        LoanSevaFaqAction.Request faq = new LoanSevaFaqAction.Request();
        faq.journeyId = jid;
        faq.question = 'How fast is disbursal?';
        r = LoanSevaFaqAction.run(new List<LoanSevaFaqAction.Request>{ faq })[0];
        System.assert(r.success);
        System.assertEquals(jid, r.journeyId);

        LoanSevaLanguageAction.Request lang = new LoanSevaLanguageAction.Request();
        lang.journeyId = jid;
        lang.language = 'MR';
        r = LoanSevaLanguageAction.run(new List<LoanSevaLanguageAction.Request>{ lang })[0];
        System.assertEquals('MR', r.language);
        lang.language = 'EN';
        r = LoanSevaLanguageAction.run(new List<LoanSevaLanguageAction.Request>{ lang })[0];
        System.assertEquals('EN', r.language);

        LoanSevaVerifyAction.Request verify = new LoanSevaVerifyAction.Request();
        verify.journeyId = jid;
        r = LoanSevaVerifyAction.run(new List<LoanSevaVerifyAction.Request>{ verify })[0];
        System.assertEquals('identity', r.awaiting);
        verify.customerName = 'Priya Sharma';
        verify.registeredMobile = '+91 ' + LoanSevaTestData.PRIYA_MOBILE;
        r = LoanSevaVerifyAction.run(new List<LoanSevaVerifyAction.Request>{ verify })[0];
        System.assertEquals('otp', r.awaiting);
        System.assertEquals(false, r.verified);

        LoanSevaOtpAction.Request otp = new LoanSevaOtpAction.Request();
        otp.journeyId = jid;
        otp.otp = '123 456';
        r = LoanSevaOtpAction.run(new List<LoanSevaOtpAction.Request>{ otp })[0];
        System.assertEquals(true, r.verified);
        System.assertEquals('loan_confirm', r.awaiting);

        LoanSevaConfirmLoanAction.Request confirm = new LoanSevaConfirmLoanAction.Request();
        confirm.journeyId = jid;
        confirm.confirmed = true;
        r = LoanSevaConfirmLoanAction.run(new List<LoanSevaConfirmLoanAction.Request>{ confirm })[0];
        System.assertEquals('employment', r.awaiting);

        List<String> expectedNext = new List<String>{ 'company', 'income', 'purpose', 'amount', 'offer_decision' };
        List<String> answers = new List<String>{ 'Salaried', 'TCS', '2', 'Education', '2' };
        for (Integer i = 0; i < answers.size(); i++) {
            LoanSevaPersonaliseAction.Request p = new LoanSevaPersonaliseAction.Request();
            p.journeyId = jid;
            p.answer = answers[i];
            r = LoanSevaPersonaliseAction.run(new List<LoanSevaPersonaliseAction.Request>{ p })[0];
            System.assertEquals(expectedNext[i], r.awaiting, 'After answer ' + answers[i]);
        }
        System.assertEquals('Offer', r.stage);

        LoanSevaOfferAction.Request offer = new LoanSevaOfferAction.Request();
        offer.journeyId = jid;
        offer.tenure = '60 months';
        r = LoanSevaOfferAction.run(new List<LoanSevaOfferAction.Request>{ offer })[0];
        System.assert(r.message.contains('60'), r.message);
        System.assertEquals('offer_decision', r.awaiting);

        LoanSevaAcceptOfferAction.Request accept = new LoanSevaAcceptOfferAction.Request();
        accept.journeyId = jid;
        r = LoanSevaAcceptOfferAction.run(new List<LoanSevaAcceptOfferAction.Request>{ accept })[0];
        System.assert(r.referenceNumber.startsWith('KMB-PLTU-'));
        System.assertEquals('callback', r.awaiting);

        LoanSevaCallbackAction.Request cb = new LoanSevaCallbackAction.Request();
        cb.journeyId = jid;
        cb.preference = '3';
        r = LoanSevaCallbackAction.run(new List<LoanSevaCallbackAction.Request>{ cb })[0];
        System.assertEquals('feedback_csat', r.awaiting);

        for (String a : new List<String>{ '5', '1', 'Great' }) {
            LoanSevaFeedbackAction.Request fb = new LoanSevaFeedbackAction.Request();
            fb.journeyId = jid;
            fb.answer = a;
            r = LoanSevaFeedbackAction.run(new List<LoanSevaFeedbackAction.Request>{ fb })[0];
        }
        System.assertEquals('done', r.awaiting);
        System.assertEquals('Completed', r.status);

        LoanSevaEscalateAction.Request esc = new LoanSevaEscalateAction.Request();
        esc.journeyId = jid;
        esc.reason = 'Wants to discuss tenure';
        r = LoanSevaEscalateAction.run(new List<LoanSevaEscalateAction.Request>{ esc })[0];
        Test.stopTest();

        System.assert(r.handoff);
        System.assertEquals(1, [SELECT COUNT() FROM Loan_Journey__c], 'Every action worked on the same journey');
        Loan_Journey__c j = [SELECT Company_Name__c, Purpose__c, Offer_Tenure_Months__c, Escalated__c FROM Loan_Journey__c];
        System.assertEquals('TCS', j.Company_Name__c);
        System.assertEquals('Education', j.Purpose__c);
        System.assertEquals(60, j.Offer_Tenure_Months__c);
        System.assert(j.Escalated__c);
    }

    @IsTest
    static void unknownJourneyIdStartsFreshAndErrorsDegradeGracefully() {
        LoanSevaStartAction.Request start = new LoanSevaStartAction.Request();
        start.journeyId = 'not-an-id';
        start.sessionId = '';
        LoanSevaActionResult r = LoanSevaStartAction.run(new List<LoanSevaStartAction.Request>{ start })[0];
        System.assert(r.success);
        System.assertEquals('menu', r.awaiting);
        System.assertEquals(LoanSevaI18n.msg('Welcome_Generic', 'EN', new Map<String, Object>{ 'name' => '', 'limit' => '' }), r.message);

        LoanSevaActionResult err = LoanSevaActionResult.error(new LoanSevaException('boom'), r.journeyId);
        System.assertEquals(false, err.success);
        System.assert(err.handoff);
        System.assertEquals(r.journeyId, err.journeyId);
        System.assert(err.message.contains('Agent'), 'Error copy offers a specialist');
        System.assert(!err.message.contains('boom'), 'Raw errors are never shown to customers');
    }

    @IsTest
    static void everyActionFailsGracefully() {
        LoanSevaJourneyService.forcedError = new LoanSevaException('database unavailable');
        String jid = 'a00000000000000';
        List<LoanSevaActionResult> rs = new List<LoanSevaActionResult>();
        LoanSevaStartAction.Request a = new LoanSevaStartAction.Request(); a.journeyId = jid;
        rs.addAll(LoanSevaStartAction.run(new List<LoanSevaStartAction.Request>{ a }));
        LoanSevaFaqAction.Request b = new LoanSevaFaqAction.Request(); b.journeyId = jid;
        rs.addAll(LoanSevaFaqAction.run(new List<LoanSevaFaqAction.Request>{ b }));
        LoanSevaLanguageAction.Request c = new LoanSevaLanguageAction.Request(); c.journeyId = jid;
        rs.addAll(LoanSevaLanguageAction.run(new List<LoanSevaLanguageAction.Request>{ c }));
        LoanSevaVerifyAction.Request d = new LoanSevaVerifyAction.Request(); d.journeyId = jid;
        rs.addAll(LoanSevaVerifyAction.run(new List<LoanSevaVerifyAction.Request>{ d }));
        LoanSevaOtpAction.Request e = new LoanSevaOtpAction.Request(); e.journeyId = jid;
        rs.addAll(LoanSevaOtpAction.run(new List<LoanSevaOtpAction.Request>{ e }));
        LoanSevaConfirmLoanAction.Request f = new LoanSevaConfirmLoanAction.Request(); f.journeyId = jid;
        rs.addAll(LoanSevaConfirmLoanAction.run(new List<LoanSevaConfirmLoanAction.Request>{ f }));
        LoanSevaPersonaliseAction.Request g = new LoanSevaPersonaliseAction.Request(); g.journeyId = jid;
        rs.addAll(LoanSevaPersonaliseAction.run(new List<LoanSevaPersonaliseAction.Request>{ g }));
        LoanSevaOfferAction.Request h = new LoanSevaOfferAction.Request(); h.journeyId = jid;
        rs.addAll(LoanSevaOfferAction.run(new List<LoanSevaOfferAction.Request>{ h }));
        LoanSevaAcceptOfferAction.Request i = new LoanSevaAcceptOfferAction.Request(); i.journeyId = jid;
        rs.addAll(LoanSevaAcceptOfferAction.run(new List<LoanSevaAcceptOfferAction.Request>{ i }));
        LoanSevaCallbackAction.Request k = new LoanSevaCallbackAction.Request(); k.journeyId = jid;
        rs.addAll(LoanSevaCallbackAction.run(new List<LoanSevaCallbackAction.Request>{ k }));
        LoanSevaFeedbackAction.Request l = new LoanSevaFeedbackAction.Request(); l.journeyId = jid;
        rs.addAll(LoanSevaFeedbackAction.run(new List<LoanSevaFeedbackAction.Request>{ l }));
        LoanSevaEscalateAction.Request m = new LoanSevaEscalateAction.Request(); m.journeyId = jid;
        rs.addAll(LoanSevaEscalateAction.run(new List<LoanSevaEscalateAction.Request>{ m }));

        System.assertEquals(12, rs.size());
        for (LoanSevaActionResult r : rs) {
            System.assertEquals(false, r.success);
            System.assert(r.handoff, 'Failures hand off to a human');
            System.assertEquals(jid, r.journeyId, 'Journey id is preserved for the next turn');
        }
        System.assertEquals(0, [SELECT COUNT() FROM Loan_Journey__c], 'Nothing is written on failure');
    }
}
