@IsTest
private class LoanSevaQualificationTest {
    private static final String PAN = 'ABCPP1234K';

    /** A new-loan journey with consent and the first seven answers, as if typed on WhatsApp. */
    private static Loan_Journey__c newLoanJourney(String pan, String consent) {
        Loan_Journey__c j = new Loan_Journey__c(
            Mobile__c = '9123456782', Customer_Name__c = 'Asha Patil', Status__c = 'Active', OTP_Verified__c = true,
            Journey_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Date_Of_Birth__c = Date.newInstance(1990, 8, 15), PAN__c = pan,
            Email__c = 'asha.patil@example.com', PIN_Code__c = '411001', Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys',
            Monthly_Income__c = 85000, Existing_EMIs__c = 10000, Bureau_Consent__c = consent, Bureau_Consent_At__c = Datetime.now()
        );
        insert j;
        return LoanSevaJourneyService.byId(j.Id);
    }

    @IsTest
    static void gatesRunInOrderAndScoreTheCredit() {
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        LoanSevaQualification.Outcome o = LoanSevaQualification.run(j.Id, true);
        System.assertEquals(LoanSevaQualification.QUALIFIED, o.status);
        System.assertEquals('Qualified', o.stageGate());
        List<Qualification_Check__c> checks = [
            SELECT Gate__c, Result__c, PAN__c, Request_Id__c, Sort_Order__c FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id ORDER BY Sort_Order__c
        ];
        System.assertEquals(LoanSevaQualification.GATES.size(), checks.size());
        for (Integer i = 0; i < checks.size(); i++) {
            System.assertEquals(LoanSevaQualification.GATES[i], checks[i].Gate__c);
        }
        System.assertEquals(PAN, checks[3].PAN__c, 'the bureau row is keyed on the PAN for the cache');
        System.assert(checks[3].Request_Id__c.startsWith('CIBI-'), checks[3].Request_Id__c);

        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(777, j.CIBIL_Score__c);
        // CIBIL 34/40 + FOIR 11.8% 25/25 + employment 15/15 + fraud 10/10 = 84/90
        System.assertEquals(93, j.Credit_Score__c, o.credit.detail());
        System.assert(j.Indicative_Eligibility__c > 0);
        System.assertEquals('High', o.credit.confidence());
        System.assert(LoanSevaJourneyService.rmDescription(j).contains('Qualification: Qualified'), LoanSevaJourneyService.rmDescription(j));
    }

    @IsTest
    static void noConsentLeavesTheBureauPendingAndStartDoesNothing() {
        Loan_Journey__c j = newLoanJourney(PAN, null);
        Test.startTest();
        LoanSevaQualification.start(j);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id], 'nothing runs before the consent question');

        LoanSevaQualification.Outcome o = LoanSevaQualification.evaluate(j, false);
        System.assertEquals(LoanSevaQualification.IN_PROGRESS, o.status);
        System.assertEquals('Waiting at Consent', o.stageGate());
        System.assertEquals(null, o.cibil);
    }

    @IsTest
    static void startRunsInTheBackgroundOnceConsentIsGiven() {
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        Test.startTest();
        LoanSevaQualification.start(j);
        Test.stopTest();
        System.assertEquals(LoanSevaQualification.QUALIFIED, LoanSevaJourneyService.byId(j.Id).Qualification_Status__c);
    }

    @IsTest
    static void foirAbovePolicyKnocksOut() {
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        j.Existing_EMIs__c = 60000;
        LoanSevaQualification.Outcome o = LoanSevaQualification.evaluate(j, false);
        System.assert(o.knockedOut());
        System.assertEquals(LoanSevaQualification.GATE_INCOME, o.gate);
        System.assert(o.knockout.contains('above'), o.knockout);
        System.assertEquals(null, o.eligibility);
    }

    @IsTest
    static void outsideTheServiceableRegionsIsAKnockOut() {
        LoanSevaServiceability.regions = new List<LoanSeva_Region__mdt>{
            new LoanSeva_Region__mdt(MasterLabel = 'Not serviceable', PIN_Prefixes__c = '194', Serviceable__c = false),
            new LoanSeva_Region__mdt(MasterLabel = 'Rest of India', PIN_Prefixes__c = '*', Serviceable__c = true)
        };
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        j.PIN_Code__c = '194101';
        LoanSevaQualification.Outcome o = LoanSevaQualification.evaluate(j, false);
        System.assertEquals('Knocked out at ' + LoanSevaQualification.GATE_SERVICEABILITY, o.stageGate());
        System.assertEquals(null, o.cibil, 'the bureau is not pulled for a PIN Kotak cannot serve');
    }

    @IsTest
    static void underwritingReusesTheJourneySoftPull() {
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        LoanSevaQualification.run(j.Id, true);
        Qualification_Check__c pulled = [
            SELECT Request_Id__c, Run_At__c FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id AND Gate__c = :LoanSevaQualification.GATE_BUREAU
        ];
        System.assertEquals(pulled.Request_Id__c, LoanSevaQualification.cachedBureau(PAN.toLowerCase()).Request_Id__c);

        Loan_Application__c app = new Loan_Application__c(
            Applicant_Name__c = 'Asha Patil', Mobile__c = '9123456782', PAN__c = PAN, Date_Of_Birth__c = Date.newInstance(1990, 8, 15),
            Monthly_Income__c = 85000, Existing_EMIs__c = 10000, Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys', Offer_Amount__c = 300000
        );
        insert app;
        LoanSevaUnderwriting.run(app.Id);
        Underwriting_Check__c bureau = [SELECT Request_Id__c, Details__c FROM Underwriting_Check__c WHERE Loan_Application__c = :app.Id AND Check__c = 'Credit Bureau'];
        System.assertEquals(pulled.Request_Id__c, bureau.Request_Id__c, 'one enquiry: the journey pull is reused');
        System.assert(bureau.Details__c.startsWith('Soft pull reused from the WhatsApp journey'), bureau.Details__c);

        // a second journey for the same PAN reuses it too
        Loan_Journey__c again = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        LoanSevaQualification.Outcome o = LoanSevaQualification.evaluate(again, true);
        System.assertEquals(pulled.Request_Id__c, o.checks[3].Request_Id__c);
    }

    @IsTest
    static void noCacheWhenCacheDaysIsZero() {
        LoanSevaProviders.configs = new Map<String, LoanSeva_Provider__mdt>{
            LoanSevaProviders.CIBIL => new LoanSeva_Provider__mdt(Apex_Class__c = 'LoanSevaProviders.MockCibil', Cache_Days__c = 0)
        };
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        LoanSevaQualification.run(j.Id, true);
        System.assertEquals(null, LoanSevaQualification.cachedBureau(PAN));
    }

    @IsTest
    static void calloutProvidersWaitForTheBackgroundJob() {
        LoanSevaProviders.configs = new Map<String, LoanSeva_Provider__mdt>{
            LoanSevaProviders.HUNTER => new LoanSeva_Provider__mdt(Apex_Class__c = 'LoanSevaProviders.MockHunter', Callout__c = true)
        };
        Loan_Journey__c j = newLoanJourney(PAN, LoanSevaQualification.CONSENT_GIVEN);
        LoanSevaQualification.Outcome inline = LoanSevaQualification.evaluate(j, false);
        System.assertEquals('Pending', inline.checks[2].Result__c);
        System.assert(inline.checks[2].Summary__c.startsWith('Queued'), inline.checks[2].Summary__c);
        System.assertEquals('Pass', LoanSevaQualification.evaluate(j, true).checks[2].Result__c);
        System.assert(LoanSevaProviders.makesCallouts(LoanSevaProviders.HUNTER));
    }

    @IsTest
    static void providerClassComesFromMetadata() {
        System.assert(LoanSevaProviders.bureau() instanceof LoanSevaProviders.MockCibil);
        LoanSevaProviders.configs = new Map<String, LoanSeva_Provider__mdt>{
            LoanSevaProviders.PERFIOS => new LoanSeva_Provider__mdt(Apex_Class__c = 'NoSuchPerfiosClass')
        };
        System.assert(LoanSevaProviders.fraud() instanceof LoanSevaProviders.MockHunter, 'no record: the mock');
        try {
            LoanSevaProviders.bankStatements();
            System.assert(false, 'an unknown class is reported');
        } catch (LoanSevaException e) {
            System.assert(e.getMessage().contains('NoSuchPerfiosClass'), e.getMessage());
        }
    }

    @IsTest
    static void topUpQualifiesOnConsentFraudAndBureau() {
        LoanSevaTestData.createCustomers();
        Loan_Journey__c j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        System.assertEquals(LoanSevaQualification.CONSENT_GIVEN, j.Bureau_Consent__c);
        LoanSevaQualification.Outcome o = LoanSevaQualification.run(j.Id, true);
        System.assertEquals(4, o.checks.size(), 'serviceability, consent, fraud and bureau only');
        System.assertEquals(LoanSevaQualification.QUALIFIED, o.status, o.stageGate());
        System.assertNotEquals(null, LoanSevaJourneyService.byId(j.Id).CIBIL_Score__c);
    }

    @IsTest
    static void creditScoreHasNoValueWithoutData() {
        LoanSevaQualification.Credit c = LoanSevaQualification.credit(new List<Qualification_Check__c>());
        System.assertEquals(null, c.score());
        System.assertEquals('Low', c.confidence());
        System.assert(c.detail().contains('no data yet'));
    }
}
