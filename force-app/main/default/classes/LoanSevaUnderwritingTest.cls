@IsTest
private class LoanSevaUnderwritingTest {
    private static Loan_Application__c app(String pan, String employment, String company) {
        return new Loan_Application__c(
            Product__c = 'Personal Loan', Application_Type__c = 'New Loan', Status__c = 'Application Submitted',
            Applicant_Name__c = 'Asha Patil', Mobile__c = '9123456780', PAN__c = pan,
            Date_Of_Birth__c = Date.newInstance(1990, 8, 15), Monthly_Income__c = 85000, Existing_EMIs__c = 5000,
            Employment_Type__c = employment, Company_Name__c = company, Offer_Amount__c = 300000, EMI__c = 9900, Tenure_Months__c = 36
        );
    }

    @IsTest
    static void panChecks() {
        System.assertEquals('Pass', LoanSevaUnderwriting.panCheck(app('ABCPP1234K', 'Salaried', 'Infosys')).Result__c);
        System.assertEquals('Fail', LoanSevaUnderwriting.panCheck(app('ABC12', 'Salaried', 'Infosys')).Result__c);
        System.assertEquals('Refer', LoanSevaUnderwriting.panCheck(app('ABCCP1234K', 'Salaried', 'Infosys')).Result__c, 'company PAN');
        Underwriting_Check__c mismatch = LoanSevaUnderwriting.panCheck(app('ABCPS1234K', 'Salaried', 'Infosys'));
        System.assertEquals('Refer', mismatch.Result__c);
        System.assert(mismatch.Details__c.contains('XXXXX1234K'), 'details never hold the full PAN');
    }

    @IsTest
    static void bureauBands() {
        Underwriting_Check__c pass = LoanSevaUnderwriting.bureauCheck(app('ABCPP1234K', 'Salaried', 'Infosys'));
        System.assertEquals('Pass', pass.Result__c);
        System.assertEquals(777, pass.Score__c);
        Underwriting_Check__c refer = LoanSevaUnderwriting.bureauCheck(app('ABCPP1234R', 'Salaried', 'Infosys'));
        System.assertEquals('Refer', refer.Result__c);
        System.assertEquals(695, refer.Score__c);
        Underwriting_Check__c fail = LoanSevaUnderwriting.bureauCheck(app('ABCPP1234Z', 'Salaried', 'Infosys'));
        System.assertEquals('Fail', fail.Result__c);
        System.assert(fail.Details__c.contains('Written-off / settled: Yes'));
    }

    @IsTest
    static void bankAndEmployment() {
        Loan_Application__c a = app('ABCPP1234K', 'Salaried', 'Sunrise Foods');
        System.assertEquals('Pending', LoanSevaUnderwriting.bankStatementCheck(a, new Set<String>()).Result__c);
        Underwriting_Check__c bank = LoanSevaUnderwriting.bankStatementCheck(a, new Set<String>{ 'Bank Statement' });
        System.assertEquals('Pass', bank.Result__c);
        System.assertEquals(83300, bank.Score__c, '98% of declared income');
        System.assertEquals('Refer', LoanSevaUnderwriting.employmentCheck(a, new Set<String>()).Result__c, 'category B without slips');
        System.assertEquals('Pass', LoanSevaUnderwriting.employmentCheck(a, new Set<String>{ 'Salary Slips' }).Result__c);
        System.assertEquals('Pass', LoanSevaUnderwriting.employmentCheck(app('ABCPP1234K', 'Salaried', 'Tata Consultancy Services'), new Set<String>()).Result__c);
        System.assertEquals('Refer', LoanSevaUnderwriting.employmentCheck(app('ABCPP1234K', 'Self-employed', 'Patil Traders'), new Set<String>()).Result__c);
        System.assert(LoanSevaUnderwriting.bankStatementCheck(app('ABCPP1234K', 'Self-employed', 'Patil Traders'), new Set<String>{ 'Bank Statement' })
            .Details__c.contains('business credits'));
    }

    @IsTest
    static void policyChecks() {
        System.assertEquals('Pass', LoanSevaUnderwriting.policyCheck(app('ABCPP1234K', 'Salaried', 'Infosys')).Result__c);
        Loan_Application__c old = app('ABCPP1234K', 'Salaried', 'Infosys');
        old.Date_Of_Birth__c = LoanSevaI18n.todayIst().addYears(-58);
        Underwriting_Check__c aged = LoanSevaUnderwriting.policyCheck(old);
        System.assertEquals('Fail', aged.Result__c);
        System.assert(aged.Summary__c.contains('maturity'), aged.Summary__c);
        Loan_Application__c young = app('ABCPP1234K', 'Salaried', 'Infosys');
        young.Date_Of_Birth__c = LoanSevaI18n.todayIst().addYears(-19);
        System.assertEquals('Fail', LoanSevaUnderwriting.policyCheck(young).Result__c);
        Loan_Application__c stretched = app('ABCPP1234K', 'Salaried', 'Infosys');
        stretched.Existing_EMIs__c = 40000;
        System.assertEquals('Refer', LoanSevaUnderwriting.policyCheck(stretched).Result__c, 'FOIR above the maximum');
    }

    @IsTest
    static void runRecommendsAndDedupes() {
        Loan_Application__c first = app('ABCPP1234K', 'Salaried', 'Infosys');
        insert first;
        insert new List<Loan_Document__c>{
            new Loan_Document__c(Loan_Application__c = first.Id, Document_Type__c = 'Bank Statement'),
            new Loan_Document__c(Loan_Application__c = first.Id, Document_Type__c = 'PAN Card')
        };
        Test.startTest();
        LoanSevaUnderwriting.start(first.Id);
        Test.stopTest();
        first = [SELECT Recommendation__c, Status__c, Underwriting_Status__c, CIBIL_Score__c, Underwriting_Summary__c,
                 (SELECT Request_Id__c FROM Underwriting_Checks__r ORDER BY Sort_Order__c) FROM Loan_Application__c WHERE Id = :first.Id];
        System.assertEquals('Approve', first.Recommendation__c, first.Underwriting_Summary__c);
        System.assertEquals('Under Review', first.Status__c);
        System.assertEquals(777, first.CIBIL_Score__c);
        System.assertEquals(6, first.Underwriting_Checks__r.size());
        System.assert(first.Underwriting_Checks__r[0].Request_Id__c.startsWith('NSDL-'));

        Loan_Application__c second = app('ABCPP1234K', 'Salaried', 'Infosys');
        second.Mobile__c = '9000011111';
        second.PAN__c = 'ABCPP1234Z';
        insert second;
        LoanSevaUnderwriting.run(second.Id);
        System.assertEquals('Decline', [SELECT Recommendation__c FROM Loan_Application__c WHERE Id = :second.Id].Recommendation__c);
        second.PAN__c = 'ABCPP1234K';
        update second;
        System.assertEquals('Refer', LoanSevaUnderwriting.dedupeCheck(second).Result__c, 'same PAN, different mobile');
        LoanSevaUnderwriting.run(second.Id);
        System.assertEquals(6, [SELECT COUNT() FROM Underwriting_Check__c WHERE Loan_Application__c = :second.Id], 're-run replaces earlier checks');
    }

    @IsTest
    static void incompleteApplicationIsDeclined() {
        Loan_Application__c a = app('ABCPP1234K', 'Salaried', 'Infosys');
        a.Applicant_Name__c = null;
        a.Monthly_Income__c = null;
        a.Date_Of_Birth__c = null;
        a.Employment_Type__c = null;
        insert a;
        LoanSevaUnderwriting.run(a.Id);
        a = [SELECT Underwriting_Status__c, Recommendation__c FROM Loan_Application__c WHERE Id = :a.Id];
        System.assertEquals('Completed', a.Underwriting_Status__c);
        System.assertEquals('Decline', a.Recommendation__c, 'no date of birth fails policy');
    }
}
