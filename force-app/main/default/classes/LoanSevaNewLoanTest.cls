@IsTest
private class LoanSevaNewLoanTest {
    private static final String MOBILE = '9123456780';
    private static Loan_Journey__c j;
    private static LoanSevaEngine.Result last;

    private static LoanSevaEngine.Result say(String text) {
        last = LoanSevaEngine.reply(j, text);
        j = last.journey;
        return last;
    }

    private static String otp() {
        return LoanSevaConfig.get().Demo_OTP__c;
    }

    private static void startUnknownCustomer() {
        LoanSevaTestData.useLogOnly();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
    }

    /** Verified new-loan journey with all 10 answers given and the offer on screen. */
    private static void throughOffer(String employmentChoice, String company) {
        startUnknownCustomer();
        say('1');
        say('Asha Patil ' + MOBILE);
        say('1');
        say(otp());
        for (String answer : new List<String>{ '15/08/1990', 'abcpp1234k', 'asha.patil@example.com', 'Pune 411001',
                employmentChoice, company, '85k', '0', '1', '3 lakh' }) {
            say(answer);
        }
    }

    private static Id addFile(Id linkedTo, String title) {
        ContentVersion v = new ContentVersion(Title = title, PathOnClient = title + '.jpg', VersionData = Blob.valueOf('img'), FirstPublishLocationId = linkedTo);
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    @IsTest
    static void notFoundOffersApplicationAndRunsFullJourney() {
        startUnknownCustomer();
        say('1');
        System.assertEquals('identity', LoanSevaEngine.awaiting(j));
        say('Asha Patil ' + MOBILE);
        System.assertEquals(LoanSevaI18n.msg('Verify_Not_Found', 'EN', new Map<String, Object>{ 'mobile' => '+91 XXXXXX6780' }), last.message);
        System.assertEquals('apply_offer', LoanSevaEngine.awaiting(j));
        System.assert(LoanSevaEngine.pendingPrompt(j, false).startsWith(LoanSevaI18n.msg('NL_Apply_Reprompt', 'EN').left(30)));

        say('1');
        System.assert(LoanSevaJourneyService.isNewLoan(j));
        System.assertEquals('otp', LoanSevaEngine.awaiting(j), 'name and mobile were already given');
        System.assert(last.message.startsWith(LoanSevaI18n.msg('NL_Intro', 'EN')));
        say(otp());
        System.assert(last.message.contains('*1/10* — '), last.message);
        System.assertEquals('dob', LoanSevaEngine.awaiting(j));

        for (String answer : new List<String>{ '15/08/1990', 'my PAN is abcpp1234k', 'Asha.Patil@Example.com', 'Pune 411 001',
                '1', 'Infosys Ltd', '85,000', 'none', '1', '3 lakh' }) {
            say(answer);
            System.assert(last.success, answer + ' -> ' + last.message);
        }
        System.assertEquals(Date.newInstance(1990, 8, 15), j.Date_Of_Birth__c);
        System.assertEquals('ABCPP1234K', j.PAN__c);
        System.assertEquals('asha.patil@example.com', j.Email__c);
        System.assertEquals('411001', j.PIN_Code__c);
        System.assertEquals('Pune', j.City__c);
        System.assertEquals(85000, j.Monthly_Income__c);
        System.assertEquals('50K-1L', j.Income_Bucket__c);
        System.assertEquals(0, j.Existing_EMIs__c);
        System.assertEquals(300000, j.Offer_Amount__c);
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(j));
        System.assert(last.message.contains('*indicative*'), last.message);
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        System.assertEquals(cfg.Base_Rate__c + cfg.New_Loan_Rate_Premium__c, j.Offer_Rate__c);

        Test.startTest();
        say('1');
        System.assertEquals('doc_pan', LoanSevaEngine.awaiting(j));
        System.assert(last.message.contains(LoanSevaI18n.msg('NL_Doc_Pan', 'EN')));
        System.assertEquals(null, j.Reference_Number__c, 'reference is assigned at submit');

        say('Done');
        System.assertEquals(false, last.success, 'no file yet');
        System.assertEquals(LoanSevaI18n.msg('NL_Doc_Not_Received', 'EN'), last.message);
        addFile(j.Id, 'pan_front');
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('doc_bank', LoanSevaEngine.awaiting(j), 'a file sent without a caption is picked up as it arrives');
        say('Done');
        System.assertEquals(false, last.success, 'the PAN file is not counted again');
        say('Skip');
        System.assertEquals('Bank Statement', j.Docs_Skipped__c);
        System.assertEquals('doc_salary', LoanSevaEngine.awaiting(j), 'salaried applicants are asked for salary slips');
        addFile(j.Id, 'slips');
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('consent', LoanSevaEngine.awaiting(j));
        String review = LoanSevaEngine.pendingPrompt(j, false);
        System.assert(review.contains('XXXXX1234K'), review);
        System.assert(!review.contains('ABCPP1234K'), 'full PAN is never echoed');
        System.assert(review.contains('⏳ later'), 'bank statement is shown as pending');

        say('1');
        Test.stopTest();

        System.assert(last.message.startsWith(LoanSevaI18n.msg('NL_Submitted', 'EN').left(20)), last.message);
        System.assertEquals('feedback_csat', LoanSevaEngine.awaiting(j));
        System.assert(j.Reference_Number__c.startsWith(cfg.New_Loan_Reference_Prefix__c + '-'), j.Reference_Number__c);
        Contact c = [SELECT FirstName, LastName, Email, Birthdate, MobilePhone FROM Contact WHERE Id = :j.Contact__c];
        System.assertEquals('Asha', c.FirstName);
        System.assertEquals('Patil', c.LastName);
        System.assertEquals('asha.patil@example.com', c.Email);

        Loan_Application__c app = [
            SELECT Status__c, Application_Type__c, Product__c, PAN__c, Bureau_Consent__c, Reference_Number__c, Underwriting_Status__c,
                Recommendation__c, CIBIL_Score__c, Underwriting_Summary__c, (SELECT Document_Type__c FROM Loan_Documents__r),
                (SELECT Check__c, Result__c FROM Underwriting_Checks__r ORDER BY Sort_Order__c)
            FROM Loan_Application__c WHERE Id = :j.Loan_Application__c
        ];
        System.assertEquals('New Loan', app.Application_Type__c);
        System.assertEquals('Personal Loan', app.Product__c);
        System.assertEquals('ABCPP1234K', app.PAN__c);
        System.assert(app.Bureau_Consent__c);
        System.assertEquals(j.Reference_Number__c, app.Reference_Number__c);
        System.assertEquals(2, app.Loan_Documents__r.size());
        System.assertEquals(2, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :app.Id]);
        System.assertEquals('Completed', app.Underwriting_Status__c, app.Underwriting_Summary__c);
        System.assertEquals('Under Review', app.Status__c);
        System.assertEquals(6, app.Underwriting_Checks__r.size());
        System.assertEquals('Pending', app.Underwriting_Checks__r[2].Result__c, 'bank statement was skipped');
        System.assertEquals('Refer', app.Recommendation__c);
        System.assertEquals(777, app.CIBIL_Score__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :app.Id AND Subject LIKE '%New loan application%']);
        System.assert(LoanSevaJourneyService.intentSummary(j).contains('new personal loan'));

        say('5');
        System.assertEquals('feedback_resolution', LoanSevaEngine.awaiting(j));
    }

    @IsTest
    static void invalidAnswersAreReAsked() {
        startUnknownCustomer();
        say('4');
        System.assert(LoanSevaJourneyService.isNewLoan(j), 'menu option 4 starts an application');
        System.assertEquals('identity', LoanSevaEngine.awaiting(j));
        say('123');
        System.assertEquals(false, last.success);
        System.assertEquals(LoanSevaI18n.msg('NL_Verify_Prompt', 'EN'), last.message);
        say('Asha Patil ' + MOBILE);
        say(otp());
        Map<String, String> bad = new Map<String, String>{ 'dob' => '31/02/1990', 'pan' => 'ABC123', 'email' => 'rm at kotak', 'pincode' => 'Pune' };
        for (String field : new List<String>{ 'dob', 'pan', 'email', 'pincode' }) {
            say(bad.get(field));
            System.assertEquals(false, last.success, field);
            System.assert(last.message.startsWith(LoanSevaI18n.msg('NL_Invalid', 'EN')), last.message);
            System.assertEquals(field, LoanSevaEngine.awaiting(j));
            say(new Map<String, String>{ 'dob' => '1990-08-15', 'pan' => 'ABCPP1234K', 'email' => 'rm@kotak.example', 'pincode' => '560001' }.get(field));
            System.assert(last.success, field + ' -> ' + last.message);
        }
        System.assertEquals(false, j.Escalated__c, 'an email starting rm@ is data, not a request for an RM');
        System.assertEquals('Bengaluru', j.City__c, 'city from the PIN prefix');
        say('3');
        System.assertEquals(false, last.success);
        System.assert(last.message.startsWith(LoanSevaI18n.msg('Personalise_Invalid', 'EN')), 'option lists keep their own message');
    }

    @IsTest
    static void selfEmployedSkipsSalarySlipsAndCanEscalateAtReview() {
        throughOffer('2', 'Patil Traders');
        say('1');
        say('skip');
        say('skip');
        System.assertEquals('consent', LoanSevaEngine.awaiting(j), 'no salary slips for self-employed');
        System.assert(!last.message.contains('Salary slips'));
        say('2');
        System.assert(last.handoff);
        System.assert(j.Escalated__c);
    }

    @IsTest
    static void existingContactWithoutOfferAndMenuChoices() {
        LoanSevaTestData.useLogOnly();
        Contact c = new Contact(FirstName = 'Meera', LastName = 'Joshi', MobilePhone = MOBILE);
        insert c;
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        say('1');
        say('Meera Joshi ' + MOBILE);
        System.assert(last.message.startsWith('Thanks Meera!'), last.message);
        System.assertEquals('apply_offer', LoanSevaEngine.awaiting(j));
        say('2');
        System.assertEquals(LoanSevaI18n.msg('Verify_Prompt', 'EN'), last.message);
        System.assertEquals('identity', LoanSevaEngine.awaiting(j));
        say('Meera Joshi ' + MOBILE);
        say('3');
        System.assert(last.handoff, 'option 3 is a specialist');

        update new Loan_Journey__c(Id = j.Id, Status__c = 'Completed');
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        System.assertEquals(c.Id, j.Contact__c);
        say('I want to apply for a new personal loan');
        System.assert(LoanSevaJourneyService.isNewLoan(j), 'typed request from the menu');
        System.assertEquals('identity', LoanSevaEngine.awaiting(j));
    }

    @IsTest
    static void preApprovedCustomersCanApplyForNewLoan() {
        LoanSevaTestData.useLogOnly();
        Id priyaId = LoanSevaTestData.createCustomers()[0].Id;
        LoanSevaEngine.Result welcome = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, LoanSevaTestData.PRIYA_MOBILE));
        j = welcome.journey;
        System.assert(welcome.message.contains('pre-qualified'), welcome.message);
        System.assert(welcome.message.contains('4️⃣ Apply for a new Personal Loan'), welcome.message);

        say('how is this different from a new loan');
        System.assert(!LoanSevaJourneyService.isNewLoan(j), 'a comparison is an FAQ, not an application');
        say('4');
        System.assert(LoanSevaJourneyService.isNewLoan(j), 'option 4 from the personalised welcome');
        System.assertEquals(priyaId, j.Contact__c);
        if (LoanSevaEngine.awaiting(j) == 'identity') {
            say('Priya Sharma ' + LoanSevaTestData.PRIYA_MOBILE);
        }
        System.assertEquals('otp', LoanSevaEngine.awaiting(j));
        say(otp());
        System.assertEquals('dob', LoanSevaEngine.awaiting(j), 'straight to the new-loan questions, no Top-Up loan confirmation');
        System.assertEquals(null, j.Existing_Loan__c);
    }

    @IsTest
    static void typedApplyRequestFromPreApprovedCustomer() {
        LoanSevaTestData.useLogOnly();
        LoanSevaTestData.createCustomers();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, LoanSevaTestData.PRIYA_MOBILE)).journey;
        say('I want to apply for a new loan');
        System.assert(LoanSevaJourneyService.isNewLoan(j));
    }

    @IsTest
    static void lowIncomeIsReferred() {
        startUnknownCustomer();
        say('4');
        say('Asha Patil ' + MOBILE);
        say(otp());
        for (String answer : new List<String>{ '15/08/1990', 'ABCPP1234K', 'a@b.co', '411001', '1', 'Infosys', '30000', '25000', '2', '1 lakh' }) {
            say(answer);
        }
        System.assert(last.handoff, last.message);
        System.assertEquals(LoanSevaI18n.msg('NL_Refer', 'EN', new Map<String, Object>{ 'name' => 'Asha' }), last.message);
        System.assertEquals(LoanSevaI18n.msg('Refer_Reprompt', 'EN'), LoanSevaEngine.pendingPrompt(j, false));
    }

    /** Known customer (Contact on the mobile) starting a new loan from the menu, through the OTP. */
    private static void returningCustomerVerified() {
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        say('4');
        System.assert(LoanSevaJourneyService.isNewLoan(j));
        say('Meera Joshi ' + MOBILE);
        System.assertEquals('otp', LoanSevaEngine.awaiting(j));
        say(otp());
    }

    @IsTest
    static void returningCustomerIsAskedOnlyWhatIsNotOnFile() {
        LoanSevaTestData.useLogOnly();
        Contact c = new Contact(FirstName = 'Meera', LastName = 'Joshi', MobilePhone = MOBILE, Email = 'meera@example.com');
        insert c;
        insert LoanSevaTestData.loan(c.Id, 'PL00099990009', 100000, 5000, 12, 10, null);
        insert new Loan_Application__c(Contact__c = c.Id, Product__c = 'Personal Loan', Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN,
            Submitted_At__c = Datetime.now().addDays(-30), Date_Of_Birth__c = Date.newInstance(1988, 3, 12), PAN__c = 'ABCPJ1234M',
            City__c = 'Pune', PIN_Code__c = '411001', Monthly_Income__c = 120000);
        insert new Loan_Journey__c(Contact__c = c.Id, Status__c = 'Completed', Journey_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN,
            Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys');

        returningCustomerVerified();
        String m = last.message;
        System.assert(m.startsWith(LoanSevaI18n.msg('NL_Prefilled', 'EN').left(15)), m);
        System.assert(m.contains('Welcome back'), m);
        System.assert(m.contains('XXXXX1234M') && !m.contains('ABCPJ1234M'), 'PAN on file is masked: ' + m);
        System.assert(m.contains('meera@example.com'), 'email from the customer record');
        System.assert(m.contains('Pune 411001'), 'address from the earlier application');
        System.assert(m.contains('Salaried @ Infosys'), 'employer from the earlier journey');
        System.assert(m.contains(LoanSevaI18n.inr(5000)), 'EMIs from the active Kotak loan');
        System.assert(m.contains('questions left: *2*'), m);
        System.assert(m.contains('*1/2* — '), 'only purpose and amount are asked: ' + m);
        System.assertEquals('purpose', LoanSevaEngine.awaiting(j));
        System.assertEquals('dob;pan;email;pincode;employment;company;income;obligations', j.Prefilled_Fields__c);
        System.assertEquals(120000, j.Monthly_Income__c);
        System.assertEquals('1L-2L', j.Income_Bucket__c);
        System.assertEquals(5000, j.Existing_EMIs__c);

        say('1');
        System.assert(last.message.startsWith('*2/2* — '), last.message);
        say('3 lakh');
        System.assertEquals('offer_decision', LoanSevaEngine.awaiting(j), last.message);
        say('1');
        say('skip');
        say('skip');
        say('skip');
        System.assertEquals('consent', LoanSevaEngine.awaiting(j));
        Test.startTest();
        say('1');
        Test.stopTest();

        System.assertEquals(c.Id, j.Contact__c, 'no duplicate customer');
        Contact after = [SELECT Email, Birthdate, MailingCity, MailingPostalCode FROM Contact WHERE Id = :c.Id];
        System.assertEquals('meera@example.com', after.Email);
        System.assertEquals(Date.newInstance(1988, 3, 12), after.Birthdate, 'blanks on the customer record are completed');
        System.assertEquals('411001', after.MailingPostalCode);
        System.assertEquals('Pune', after.MailingCity);
        System.assertEquals('ABCPJ1234M', [SELECT PAN__c FROM Loan_Application__c WHERE Id = :j.Loan_Application__c].PAN__c);
    }

    @IsTest
    static void changeReAsksEverythingOnFile() {
        LoanSevaTestData.useLogOnly();
        insert new Contact(FirstName = 'Meera', LastName = 'Joshi', MobilePhone = MOBILE, Email = 'meera@example.com',
            Birthdate = Date.newInstance(1988, 3, 12), MailingPostalCode = '400060', MailingCity = 'Mumbai');
        returningCustomerVerified();
        System.assert(last.message.contains('12/03/1988') && last.message.contains('Mumbai 400060'), last.message);
        System.assert(last.message.contains('*1/7* — '), 'DOB, email and PIN are on file: ' + last.message);
        System.assertEquals('pan', LoanSevaEngine.awaiting(j));

        say('Change');
        System.assert(last.message.startsWith(LoanSevaI18n.msg('NL_Change', 'EN')), last.message);
        System.assert(last.message.contains('*1/10* — '), last.message);
        System.assertEquals('dob', LoanSevaEngine.awaiting(j));
        System.assertEquals(null, j.Prefilled_Fields__c);
        System.assertEquals(null, j.Email__c);
        System.assertEquals(null, j.City__c);
        say('Change');
        System.assertEquals(false, last.success, 'nothing left to change, so it is read as an answer');
        System.assertEquals('dob', LoanSevaEngine.awaiting(j));
    }

    @IsTest
    static void verifiedTopUpCustomerSkipsSecondOtp() {
        LoanSevaTestData.useLogOnly();
        LoanSevaTestData.createCustomers();
        j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        j.Purpose__c = 'Home Renovation';
        LoanSevaEngine.Result r = LoanSevaNewLoan.start(j);
        j = r.journey;
        System.assert(r.message.startsWith(LoanSevaI18n.msg('NL_Intro', 'EN')), r.message);
        System.assert(!r.message.contains(otp()), 'no second OTP');
        System.assert(r.message.contains(LoanSevaI18n.inr(11800)), 'EMI of the Kotak loan: ' + r.message);
        System.assertEquals('dob', LoanSevaEngine.awaiting(j));
        System.assertEquals('obligations', j.Prefilled_Fields__c);
        System.assertEquals(null, j.Purpose__c, 'the loan need is asked afresh');
    }

    @IsTest
    static void hindiQuestionsAreRenumbered() {
        Loan_Journey__c h = new Loan_Journey__c(Language__c = 'HI', Journey_Type__c = 'New Loan');
        String q = LoanSevaNewLoan.question(h, 'employment');
        System.assert(q.startsWith('*5/10* — '), q);
        System.assert(!q.contains('1/5'), q);
        System.assert(LoanSevaNewLoan.question(h, 'amount').startsWith('*10/10* — '));
        h.Monthly_Income__c = 40000;
        System.assertEquals(800000, LoanSevaNewLoan.maxAmount(h));
    }

    @IsTest
    static void parsers() {
        System.assertEquals(Date.newInstance(1990, 8, 15), LoanSevaNewLoan.parseDob('15 Aug 1990'));
        System.assertEquals(Date.newInstance(1990, 8, 5), LoanSevaNewLoan.parseDob('5-8-1990'));
        System.assertEquals(Date.newInstance(1988, 12, 1), LoanSevaNewLoan.parseDob('1988-12-01'));
        System.assertEquals(null, LoanSevaNewLoan.parseDob('30/02/1990'));
        System.assertEquals(null, LoanSevaNewLoan.parseDob('sometime'));
        System.assertEquals(35, LoanSevaNewLoan.ageOn(Date.newInstance(1990, 10, 2), Date.newInstance(2026, 10, 1)));
        System.assertEquals(36, LoanSevaNewLoan.ageOn(Date.newInstance(1990, 10, 1), Date.newInstance(2026, 10, 1)));
        System.assertEquals('ABCPE1234F', LoanSevaNewLoan.parsePan('ABCPE 1234 F'));
        System.assertEquals(null, LoanSevaNewLoan.parsePan('ABCPE12345'));
        System.assertEquals('XXXXX1234F', LoanSevaNewLoan.maskPan('ABCPE1234F'));
        Loan_Journey__c x = new Loan_Journey__c(Journey_Type__c = 'New Loan');
        System.assert(LoanSevaNewLoan.applyAnswer(x, 'obligations', '12,500'));
        System.assertEquals(12500, x.Existing_EMIs__c);
        System.assert(LoanSevaNewLoan.applyAnswer(x, 'obligations', '800'));
        System.assertEquals(800, x.Existing_EMIs__c);
        System.assert(!LoanSevaNewLoan.applyAnswer(x, 'obligations', 'some'));
        System.assert(!LoanSevaNewLoan.applyAnswer(x, 'amount', '10000'), 'below the new-loan minimum');
        System.assert(!LoanSevaNewLoan.applyAnswer(x, 'dob', '01/01/2015'), 'under 18');
        System.assert(!LoanSevaNewLoan.applyAnswer(x, 'unknown', 'x'));
    }

    @IsTest
    static void eligibilityForNewLoans() {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        LoanSevaEligibilityEngine.Result low = LoanSevaEligibilityEngine.evaluateNew(cfg.New_Loan_Min_Income__c - 1, 0, 'Salaried', 200000, null);
        System.assert(!low.eligible);
        System.assert(!LoanSevaEligibilityEngine.evaluateNew(null, 0, 'Salaried', 200000, null).eligible);
        System.assert(!LoanSevaEligibilityEngine.evaluateNew(50000, 40000, 'Salaried', 200000, null).eligible, 'no FOIR headroom');
        LoanSevaEligibilityEngine.Result se = LoanSevaEligibilityEngine.evaluateNew(100000, 0, 'Self-employed', 50000000, 60);
        System.assert(se.eligible);
        System.assertEquals(cfg.Base_Rate__c + cfg.New_Loan_Rate_Premium__c + cfg.Self_Employed_Premium__c, se.rate);
        System.assert(se.amount <= Math.min(cfg.New_Loan_Max_Amount__c, 100000 * cfg.New_Loan_Income_Multiple__c));
        System.assert(se.cappedBelowDesired);
    }

    @IsTest
    static void captionlessFileIsRecordedAndNextPromptSent() {
        throughOffer('1', 'Infosys');
        say('1');
        System.assertEquals('doc_pan', LoanSevaEngine.awaiting(j));
        Test.startTest();
        Id fileId = addFile(j.Id, 'pan');
        Test.stopTest();
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('doc_bank', LoanSevaEngine.awaiting(j));
        Loan_Document__c d = [SELECT Document_Type__c, Content_Document_Id__c FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c];
        System.assertEquals('PAN Card', d.Document_Type__c);
        System.assertEquals(fileId, d.Content_Document_Id__c);
        System.assert(j.Last_Send_Status__c.contains(LoanSevaI18n.msg('NL_Doc_Received', 'EN', new Map<String, Object>{ 'count' => 1 })), j.Last_Send_Status__c);
        System.assert(j.Last_Send_Status__c.contains('Document 2/3'), 'the next prompt goes out proactively');

        LoanSevaInboundFiles.process([SELECT LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE ContentDocumentId = :fileId AND LinkedEntityId = :j.Id]);
        System.assertEquals('doc_bank', LoanSevaEngine.awaiting(LoanSevaJourneyService.byId(j.Id)), 'a file already recorded does not advance again');
        addFile(j.Loan_Application__c, 'rm_upload');
        System.assertEquals(1, [SELECT COUNT() FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c], 'files on other records are ignored');
    }

    @IsTest
    static void fileForADroppedJourneyIsRecordedAndReactivatesIt() {
        throughOffer('1', 'Infosys');
        say('1');
        update new Loan_Journey__c(Id = j.Id, Status__c = LoanSevaJourneyService.STATUS_DROPPED, Dropped_At__c = Datetime.now());
        Test.startTest();
        Id fileId = addFile(j.Id, 'pan');
        Test.stopTest();
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('doc_bank', LoanSevaEngine.awaiting(j), 'the customer was idle while finding the photo');
        System.assertEquals(LoanSevaJourneyService.STATUS_ACTIVE, j.Status__c);
        System.assertEquals(fileId, [SELECT Content_Document_Id__c FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c].Content_Document_Id__c);
    }

    @IsTest
    static void fileOnANewSessionReachesTheJourney() {
        List<MessagingChannel> channels = [SELECT Id FROM MessagingChannel WHERE DeveloperName = :LoanSevaConfig.get().WhatsApp_Channel__c];
        if (channels.isEmpty()) {
            return; // no WhatsApp channel in this org; the session-only path is covered above
        }
        throughOffer('1', 'Infosys');
        say('1');
        MessagingEndUser eu = new MessagingEndUser(Name = 'Asha Patil', MessagingChannelId = channels[0].Id, MessagingPlatformKey = '91' + MOBILE,
            MessageType = 'Custom', MessagingConsentStatus = 'ExplicitlyOptedIn');
        insert eu;
        MessagingSession returning = new MessagingSession(MessagingChannelId = channels[0].Id, MessagingEndUserId = eu.Id, Status = 'Ended');
        insert returning;
        // The journey still points at the session the customer started on, which has since ended.
        update new Loan_Journey__c(Id = j.Id, Messaging_Session_Id__c = '0MwgL00000F73wbSAB', Messaging_End_User_Id__c = eu.Id);

        Test.startTest();
        Id fileId = addFile(returning.Id, 'pan_on_new_session');
        Test.stopTest();
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('doc_bank', LoanSevaEngine.awaiting(j), 'the session id on the journey is stale but the end user matches');
        System.assertEquals(fileId, [SELECT Content_Document_Id__c FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c].Content_Document_Id__c);
    }

    @IsTest
    static void filesOnTheSessionAreCollectedOnce() {
        Loan_Application__c app = new Loan_Application__c(Product__c = 'Personal Loan');
        insert app;
        Loan_Journey__c jj = new Loan_Journey__c(Mobile__c = MOBILE, Status__c = 'Active', Stage__c = 'Documents', Loan_Application__c = app.Id);
        insert jj;
        addFile(jj.Id, 'statement');
        System.assertEquals(1, LoanSevaDocumentService.collect(jj, 'Bank Statement'));
        System.assertEquals(0, LoanSevaDocumentService.collect(jj, 'Bank Statement'), 'already recorded');
        Loan_Document__c d = [SELECT Document_Type__c, File_Name__c, Source__c FROM Loan_Document__c WHERE Loan_Application__c = :app.Id];
        System.assertEquals('statement.jpg', d.File_Name__c);
        System.assertEquals(0, LoanSevaDocumentService.collect(new Loan_Journey__c(), 'PAN Card'));
    }

    @IsTest
    static void reengagementUsesNewLoanCopy() {
        Loan_Journey__c x = new Loan_Journey__c(Journey_Type__c = 'New Loan', Language__c = 'EN', Customer_Name__c = 'asha patil');
        System.assertEquals(LoanSevaI18n.msg('NL_Reengage_1', 'EN', new Map<String, Object>{ 'name' => 'Asha', 'purpose' => '' }), LoanSevaDropOffJob.reengageText(x, 1));
        System.assert(LoanSevaDropOffJob.reengageText(x, 2).contains('still waiting'));
    }
}
