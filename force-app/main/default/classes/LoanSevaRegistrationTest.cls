@IsTest
private class LoanSevaRegistrationTest {
    @TestSetup
    static void setup() {
        LoanSevaTestData.createCustomers();
    }

    private static LoanSevaRegistrationService.Registration reg(String mobile, String name, String lang, Boolean consent) {
        LoanSevaRegistrationService.Registration r = new LoanSevaRegistrationService.Registration();
        r.mobile = mobile;
        r.name = name;
        r.language = lang;
        r.source = 'Link';
        r.consent = consent;
        return r;
    }

    @IsTest
    static void registerMatchesCustomersCapturesProspectsAndNudges() {
        Test.startTest();
        Map<String, Loan_Journey__c> journeys = LoanSevaRegistrationService.register(new List<LoanSevaRegistrationService.Registration>{
            reg('+91 98765 00001', 'Priya S', 'HI', true),
            reg('9812300000', 'Arjun Mehta', 'MR', true),
            reg('12345', 'Bad Number', 'EN', true),
            reg('9812399999', 'No Consent', 'EN', false)
        });
        Test.stopTest();

        System.assertEquals(2, journeys.size(), 'Invalid mobiles and missing consent are skipped');
        Loan_Journey__c priya = [SELECT Stage__c, Status__c, Source__c, Language__c, Contact__c, Lead__c, Existing_Loan__c, Last_Send_Status__c, Nudge_Sent_At__c FROM Loan_Journey__c WHERE Mobile__c = :LoanSevaTestData.PRIYA_MOBILE];
        System.assertEquals('Nudge', priya.Stage__c);
        System.assertEquals('Link', priya.Source__c);
        System.assertEquals('HI', priya.Language__c);
        System.assertNotEquals(null, priya.Contact__c);
        System.assertEquals(null, priya.Lead__c);
        System.assertEquals(null, priya.Existing_Loan__c, 'Loan links only after verification');
        System.assertNotEquals(null, priya.Nudge_Sent_At__c);
        System.assert(priya.Last_Send_Status__c.startsWith('LogOnly'), 'Nudge recorded: ' + priya.Last_Send_Status__c);
        System.assert(priya.Last_Send_Status__c.contains('₹5L'), 'Personalised with the pre-approved limit');

        Loan_Journey__c arjun = [SELECT Contact__c, Lead__c, Language__c, Last_Send_Status__c FROM Loan_Journey__c WHERE Mobile__c = '9812300000'];
        System.assertEquals(null, arjun.Contact__c);
        Lead l = [SELECT LastName, MobilePhone, Company FROM Lead WHERE Id = :arjun.Lead__c];
        System.assertEquals('Arjun Mehta', l.LastName);
        System.assertEquals('Individual', l.Company);
        System.assertEquals('MR', arjun.Language__c);
        System.assert(arjun.Last_Send_Status__c.contains(LoanSevaI18n.msg('Nudge_Generic', 'MR').abbreviate(40).removeEnd('...')));
    }

    @IsTest
    static void reRegisteringReusesTheOpenJourney() {
        LoanSevaRegistrationService.register(new List<LoanSevaRegistrationService.Registration>{ reg('9812300000', null, 'EN', true) });
        LoanSevaRegistrationService.register(new List<LoanSevaRegistrationService.Registration>{ reg('9812300000', null, 'EN', true) });
        System.assertEquals(1, [SELECT COUNT() FROM Loan_Journey__c WHERE Mobile__c = '9812300000']);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE MobilePhone = '9812300000']);
        System.assertEquals('WhatsApp 0000', [SELECT LastName FROM Lead WHERE MobilePhone = '9812300000'].LastName);
        System.assert(LoanSevaRegistrationService.register(new List<LoanSevaRegistrationService.Registration>()).isEmpty());
    }

    @IsTest
    static void platformEventHandsOffToSubscriber() {
        Test.startTest();
        LoanSevaRegistrationService.publish(reg('9876500002', ' Rahul ', 'EN', true));
        Test.getEventBus().deliver();
        Test.stopTest();
        Loan_Journey__c j = [SELECT Contact__c, Customer_Name__c, Consent_WhatsApp__c FROM Loan_Journey__c WHERE Mobile__c = :LoanSevaTestData.RAHUL_MOBILE];
        System.assertNotEquals(null, j.Contact__c, 'Matched a +91-formatted contact phone');
        System.assertEquals('Rahul Deshmukh', j.Customer_Name__c);
        System.assert(j.Consent_WhatsApp__c);
    }

    @IsTest
    static void controllerValidatesAndSubmits() {
        PageReference page = Page.LoanSevaRegister;
        page.getParameters().put('src', 'link');
        Test.setCurrentPage(page);
        LoanSevaRegisterController c = new LoanSevaRegisterController();
        System.assertEquals('Link', c.source);
        System.assertEquals(3, c.getLanguageOptions().size());

        c.submit();
        System.assertEquals('Please enter your full name.', c.errorMessage);
        c.fullName = 'Priya Sharma';
        c.mobile = '12345';
        c.submit();
        System.assertEquals('Please enter a valid 10-digit Indian mobile number.', c.errorMessage);
        c.mobile = '98765 00001';
        c.submit();
        System.assert(c.errorMessage.contains('agree'), 'Consent is mandatory');
        System.assert(!c.submitted);

        c.consent = true;
        c.language = 'HI';
        Test.startTest();
        c.submit();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(null, c.errorMessage);
        System.assert(c.submitted);
        System.assertEquals('+91 XXXXXX0001', c.maskedMobile);
        System.assertEquals('HI', [SELECT Language__c FROM Loan_Journey__c WHERE Mobile__c = :LoanSevaTestData.PRIYA_MOBILE].Language__c);
    }

    @IsTest
    static void qrIsTheDefaultSource() {
        Test.setCurrentPage(Page.LoanSevaRegister);
        System.assertEquals('QR', new LoanSevaRegisterController().source);
    }
}
