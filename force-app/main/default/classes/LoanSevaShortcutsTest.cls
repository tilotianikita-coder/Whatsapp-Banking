@IsTest
private class LoanSevaShortcutsTest {
    private static final String NEW_MOBILE = '9123456780';

    @TestSetup
    static void setup() {
        LoanSevaTestData.createCustomers();
    }

    @IsTest
    static void emiCalculatorAtTheMenu() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, 'EMI 3 lakh 24 months');
        Decimal rate = LoanSevaConfig.get().Base_Rate__c;
        Decimal emi = LoanSevaEligibilityEngine.emi(300000, rate, 24);
        System.assert(r.message.startsWith('🧮'), r.message);
        System.assert(r.message.contains('👉 *24 months · ' + LoanSevaI18n.inr(emi) + '/month*'), r.message);
        System.assert(r.message.contains('Total interest: ' + LoanSevaI18n.inr(emi * 24 - 300000)), r.message);
        System.assert(r.message.endsWith(LoanSevaI18n.msg('FAQ_Nudge', 'EN')), r.message);
        System.assertEquals('menu', LoanSevaEngine.awaiting(r.journey), 'the calculator does not move the journey on');
    }

    @IsTest
    static void emiCalculatorMidJourneyReturnsToTheQuestion() {
        Loan_Journey__c j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        System.assertEquals('employment', LoanSevaEngine.awaiting(j));

        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, 'what would the EMI be for 48 months on 5 lakh');
        System.assert(r.message.contains('*₹5,00,000*'), 'the tenure is not read as the amount: ' + r.message);
        System.assert(r.message.contains('👉 *48 months'), r.message);
        System.assert(r.message.contains(LoanSevaI18n.msg('Resume_Prompt', 'EN')), r.message);
        System.assert(r.message.endsWith(LoanSevaEngine.withProgress(LoanSevaI18n.msg('Q_Employment', 'EN'))), r.message);
        System.assertEquals('employment', LoanSevaEngine.awaiting(r.journey));

        // the agent may route it as a question instead
        r = LoanSevaEngine.answerFaq(r.journey, 'What is the EMI for 2 lakh?');
        System.assert(r.message.contains('*₹2,00,000*'), r.message);
        System.assertEquals('employment', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.reply(r.journey, '1');
        System.assertEquals('Salaried', r.journey.Employment_Type__c, 'the next reply still answers the question');
    }

    @IsTest
    static void emiWithoutAnAmountAndOnTheOfferAreNotShortcuts() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(r.journey));
        r = LoanSevaEngine.reply(r.journey, 'EMI for 3 lakh');
        System.assert(!r.message.contains('🧮'), 'on the offer an amount re-prices it: ' + r.message);
        System.assertEquals(300000, r.journey.Offer_Amount__c);

        System.assertEquals(null, LoanSevaShortcuts.handle(LoanSevaTestData.startedJourney(LoanSevaTestData.RAHUL_MOBILE), 'what is an EMI'));
    }

    @IsTest
    static void statusWithNoApplication() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(NEW_MOBILE);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, 'Status');
        System.assert(r.message.startsWith(LoanSevaI18n.msg('Status_None', 'EN')), r.message);
    }

    @IsTest
    static void topUpStatusAfterTheCallbackIsBooked() {
        LoanSevaEngine.Result r = LoanSevaTestData.personalisedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        r = LoanSevaEngine.acceptOffer(r.journey);
        r = LoanSevaEngine.scheduleCallback(r.journey, '1', null);
        System.assertEquals('feedback_csat', LoanSevaEngine.awaiting(r.journey));

        r = LoanSevaEngine.reply(r.journey, 'where is my application?');
        System.assert(r.message.contains('```' + r.journey.Reference_Number__c + '```'), r.message);
        System.assert(r.message.contains('✅ Offer ready\n✅ Offer accepted\n✅ Specialist call · '), r.message);
        System.assert(r.message.contains('🔄 Disbursal'), r.message);
        System.assert(r.message.endsWith(LoanSevaI18n.msg('FB_Q1', 'EN')), 'then the rating question again: ' + r.message);
        System.assertEquals('feedback_csat', LoanSevaEngine.awaiting(r.journey));
    }

    @IsTest
    static void newLoanStatusThroughToApproval() {
        Loan_Journey__c j = LoanSevaTestData.startedJourney(NEW_MOBILE);
        Loan_Application__c app = new Loan_Application__c(
            Loan_Journey__c = j.Id, Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Product__c = 'Personal Loan',
            Status__c = 'Under Review', Underwriting_Status__c = 'Completed', Submitted_At__c = Datetime.now(),
            Reference_Number__c = 'KMB-PL-261005-0042', Offer_Amount__c = 300000
        );
        insert app;
        insert new List<Loan_Document__c>{
            new Loan_Document__c(Loan_Application__c = app.Id, Document_Type__c = 'PAN Card', Status__c = 'Verified'),
            new Loan_Document__c(Loan_Application__c = app.Id, Document_Type__c = 'Bank Statement', Status__c = 'Received')
        };

        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, 'status');
        System.assert(r.message.contains('```KMB-PL-261005-0042```'), r.message);
        System.assert(r.message.contains('✅ Application submitted\n🔄 Documents (2 received, 1 verified)\n✅ Credit & KYC checks\n🔄 Credit officer review\n⚪ Decision'), r.message);
        System.assert(r.message.contains(LoanSevaI18n.msg('Status_In_Review', 'EN')), r.message);

        Existing_Loan__c loan = LoanSevaTestData.loan([SELECT Id FROM Contact LIMIT 1].Id, 'PL26100500000042', 300000, 9800, 36, 0, 0);
        insert loan;
        update new Loan_Application__c(Id = app.Id, Decision__c = LoanSevaDecisionService.APPROVED, Status__c = 'Approved', Loan_Account__c = loan.Id);
        j = LoanSevaEngine.setLanguage(r.journey, 'HI').journey;
        r = LoanSevaEngine.reply(j, 'स्टेटस');
        System.assert(r.message.startsWith('📋 *आवेदन की स्थिति*'), r.message);
        System.assert(r.message.contains('✅ निर्णय'), r.message);
        System.assert(r.message.contains('XXXX XXXX 0042'), 'masked loan account only: ' + r.message);
        System.assert(!r.message.contains('PL26100500000042'), r.message);
    }

    @IsTest
    static void progressBar() {
        System.assertEquals('*2/5* ▰▰▱▱▱ — Which company?', LoanSevaEngine.withProgress('*2/5* — Which company?'));
        System.assertEquals('No counter', LoanSevaEngine.withProgress('No counter'));
    }
}
