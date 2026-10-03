@IsTest
private class LoanSevaDecisionServiceTest {
    private static Loan_Application__c submitted(String pan, String mobile, String language) {
        LoanSevaTestData.useLogOnly();
        Contact c = new Contact(FirstName = 'Asha', LastName = 'Patil', MobilePhone = mobile);
        insert c;
        Loan_Journey__c j = new Loan_Journey__c(Mobile__c = mobile, Customer_Name__c = 'Asha Patil', Language__c = language,
            Journey_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Status__c = 'Active', Contact__c = c.Id);
        insert j;
        Loan_Application__c app = new Loan_Application__c(
            Product__c = 'Personal Loan', Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Status__c = 'Application Submitted',
            Loan_Journey__c = j.Id, Contact__c = c.Id, Applicant_Name__c = 'Asha Patil', Mobile__c = mobile, PAN__c = pan,
            Date_Of_Birth__c = Date.newInstance(1990, 8, 15), Monthly_Income__c = 85000, Existing_EMIs__c = 0,
            Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys', Offer_Amount__c = 300000, Rate__c = 11.49,
            Tenure_Months__c = 36, EMI__c = 9890, Reference_Number__c = 'KMB-PL-261001-0042'
        );
        insert app;
        insert new Loan_Document__c(Loan_Application__c = app.Id, Document_Type__c = 'Bank Statement');
        LoanSevaUnderwriting.run(app.Id);
        return app;
    }

    private static String lastSend(Id applicationId) {
        return [SELECT Loan_Journey__r.Last_Send_Status__c FROM Loan_Application__c WHERE Id = :applicationId].Loan_Journey__r.Last_Send_Status__c;
    }

    @IsTest
    static void approveCreatesLanAndSendsMaskedLan() {
        Loan_Application__c app = submitted('ABCPP1234K', '9123456780', 'EN');
        LoanSevaDecisionService.Scorecard before = LoanSevaDecisionService.getScorecard(app.Id);
        System.assert(before.canDecide);
        System.assertEquals(6, before.checks.size());
        System.assertEquals(1, before.documents.size());
        System.assertEquals('XXXXX1234K', before.maskedPan);
        System.assertEquals('Approve', before.application.Recommendation__c);

        Test.startTest();
        LoanSevaDecisionService.Scorecard after = LoanSevaDecisionService.approve(app.Id, 'Clean file');
        Test.stopTest();

        System.assert(!after.canDecide);
        Loan_Application__c saved = [SELECT Name, Status__c, Decision__c, Decision_By__c, Decision_At__c, Decision_Notes__c, Loan_Account__c FROM Loan_Application__c WHERE Id = :app.Id];
        System.assertEquals('Approved', saved.Status__c);
        System.assertEquals('Approved', saved.Decision__c);
        System.assertEquals(UserInfo.getUserId(), saved.Decision_By__c);
        System.assertNotEquals(null, saved.Decision_At__c);
        System.assertEquals('Clean file', saved.Decision_Notes__c);

        Existing_Loan__c loan = [SELECT Loan_Account_Number__c, Masked_Account__c, Status__c, Contact__c, Outstanding_Principal__c,
                                 Current_EMI__c, Interest_Rate__c, Tenure_Remaining_Months__c FROM Existing_Loan__c WHERE Id = :saved.Loan_Account__c];
        String expectedLan = LoanSevaConfig.get().Lan_Prefix__c + Datetime.now().format('yyMMdd', LoanSevaI18n.TIMEZONE)
            + saved.Name.replaceAll('[^0-9]', '').leftPad(8, '0');
        System.assertEquals(expectedLan, loan.Loan_Account_Number__c);
        System.assertEquals('Sanctioned', loan.Status__c);
        System.assertEquals(app.Contact__c, loan.Contact__c);
        System.assertEquals(300000, loan.Outstanding_Principal__c);
        System.assertEquals(9890, loan.Current_EMI__c);
        System.assertEquals(11.49, loan.Interest_Rate__c);
        System.assertEquals(36, loan.Tenure_Remaining_Months__c);
        System.assertEquals(loan.Masked_Account__c, after.maskedLan);

        String sent = lastSend(app.Id);
        System.assert(sent.startsWith('LogOnly'), sent);
        System.assert(sent.contains('Congratulations Asha'), sent);
        System.assert(!sent.contains(loan.Loan_Account_Number__c), 'the full LAN is never sent to the customer');
    }

    @IsTest
    static void approvedMessageShowsTermsAndMaskedLan() {
        Loan_Application__c app = new Loan_Application__c(Decision__c = 'Approved', Offer_Amount__c = 300000, Rate__c = 11.49,
            Tenure_Months__c = 36, EMI__c = 9890, Reference_Number__c = 'KMB-PL-261001-0042');
        String text = LoanSevaDecisionService.message(app, new Loan_Journey__c(Customer_Name__c = 'asha patil', Language__c = 'HI'),
            new Existing_Loan__c(Loan_Account_Number__c = 'PL26100100000042'));
        System.assert(text.startsWith('🎉 बधाई हो Asha'), text);
        System.assert(text.contains('11.49'), text);
        System.assert(text.contains('36'), text);
        System.assert(text.contains('KMB-PL-261001-0042'), text);
    }

    @IsTest
    static void rejectSendsDeclineWithoutCreatingLoan() {
        Loan_Application__c app = submitted('ABCPP1234Z', '9123456781', 'EN');
        System.assertEquals('Decline', LoanSevaDecisionService.getScorecard(app.Id).application.Recommendation__c);
        Test.startTest();
        LoanSevaDecisionService.reject(app.Id, 'Write-off on bureau');
        Test.stopTest();
        Loan_Application__c saved = [SELECT Status__c, Decision__c, Loan_Account__c FROM Loan_Application__c WHERE Id = :app.Id];
        System.assertEquals('Rejected', saved.Status__c);
        System.assertEquals('Rejected', saved.Decision__c);
        System.assertEquals(null, saved.Loan_Account__c);
        System.assertEquals(0, [SELECT COUNT() FROM Existing_Loan__c]);
        String sent = lastSend(app.Id);
        System.assert(sent.contains('unable to approve'), sent);
        System.assert(!sent.contains('Write-off'), 'internal notes never reach the customer');
    }

    @IsTest
    static void decisionsAreGuarded() {
        Loan_Application__c app = submitted('ABCPP1234K', '9123456782', 'EN');
        LoanSevaDecisionService.approve(app.Id, null);
        for (String attempt : new List<String>{ 'approve', 'reject', 'rerun' }) {
            try {
                if (attempt == 'approve') {
                    LoanSevaDecisionService.approve(app.Id, null);
                } else if (attempt == 'reject') {
                    LoanSevaDecisionService.reject(app.Id, null);
                } else {
                    LoanSevaDecisionService.rerunUnderwriting(app.Id);
                }
                System.assert(false, attempt + ' after a decision should fail');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage());
            }
        }
        System.assertEquals(1, [SELECT COUNT() FROM Existing_Loan__c], 'only one LAN per application');

        Loan_Application__c pending = new Loan_Application__c(Product__c = 'Personal Loan', Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN,
            Status__c = 'Application Submitted', Underwriting_Status__c = 'In Progress', Offer_Amount__c = 100000);
        insert pending;
        try {
            LoanSevaDecisionService.approve(pending.Id, null);
            System.assert(false, 'approval waits for underwriting');
        } catch (AuraHandledException e) {
            System.assertEquals('Application Submitted', [SELECT Status__c FROM Loan_Application__c WHERE Id = :pending.Id].Status__c);
        }
        try {
            LoanSevaDecisionService.decide(new List<Id>{ pending.Id }, 'Maybe', null);
            System.assert(false, 'unknown decision');
        } catch (LoanSevaException e) {
            System.assert(e.getMessage().contains('Maybe'));
        }
    }

    @IsTest
    static void decisionsAgainstTheRecommendationNeedNotes() {
        Loan_Application__c refer = submitted('ABCPP1234R', '9123456784', 'EN');
        LoanSevaDecisionService.Scorecard s = LoanSevaDecisionService.getScorecard(refer.Id);
        System.assertEquals('Refer', s.memo.recommendation);
        System.assert(s.memo.approveIsDeviation);
        try {
            LoanSevaDecisionService.approve(refer.Id, '  ');
            System.assert(false, 'approving a Refer without notes should fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('recommends Refer'), e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Existing_Loan__c], 'no LAN without a reason');
        LoanSevaDecisionService.approve(refer.Id, 'Delay explained - card payment missed while travelling');
        System.assertEquals('Approved', [SELECT Decision__c FROM Loan_Application__c WHERE Id = :refer.Id].Decision__c);
    }

    @IsTest
    static void rejectingACleanFileNeedsNotes() {
        Loan_Application__c clean = submitted('ABCPP1234K', '9123456785', 'EN');
        try {
            LoanSevaDecisionService.reject(clean.Id, null);
            System.assert(false, 'rejecting a clean file without notes should fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('recommends Approve'), e.getMessage());
        }
        System.assertEquals(null, [SELECT Decision__c FROM Loan_Application__c WHERE Id = :clean.Id].Decision__c);
    }

    @IsTest
    static void referredApplicationStaysOpen() {
        Loan_Application__c app = submitted('ABCPP1234K', '9123456786', 'EN');
        update new Loan_Application__c(Id = app.Id, Decision__c = LoanSevaDecisionService.REFERRED, Status__c = 'Under Review',
            Decision_Notes__c = 'More details and documents required');
        System.assert(LoanSevaDecisionService.getScorecard(app.Id).canDecide, 'a referral is not final');
        System.assertEquals(6, LoanSevaDecisionService.rerunUnderwriting(app.Id).checks.size());
        LoanSevaDecisionService.approve(app.Id, 'Documents received');
        System.assertEquals('Approved', [SELECT Decision__c FROM Loan_Application__c WHERE Id = :app.Id].Decision__c);
    }

    @IsTest
    static void rerunRefreshesChecksAndTopUpIsNotDecidable() {
        Loan_Application__c app = submitted('ABCPP1234K', '9123456783', 'EN');
        insert new Loan_Document__c(Loan_Application__c = app.Id, Document_Type__c = 'PAN Card');
        LoanSevaDecisionService.Scorecard s = LoanSevaDecisionService.rerunUnderwriting(app.Id);
        System.assertEquals(6, s.checks.size());
        System.assertEquals(2, s.documents.size());

        Loan_Application__c topUp = new Loan_Application__c(Product__c = 'Personal Loan', Application_Type__c = 'Top-Up', Status__c = 'Under Review');
        insert topUp;
        System.assert(!LoanSevaDecisionService.getScorecard(topUp.Id).canDecide, 'top-ups are booked through the existing loan flow');
    }
}
