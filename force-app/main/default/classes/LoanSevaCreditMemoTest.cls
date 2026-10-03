@IsTest
private class LoanSevaCreditMemoTest {
    private static Loan_Application__c underwritten(String pan, String employment, String company, Decimal existingEmis, List<String> docTypes) {
        Loan_Application__c app = new Loan_Application__c(
            Product__c = 'Personal Loan', Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Status__c = 'Application Submitted',
            Applicant_Name__c = 'Asha Patil', Mobile__c = '9123456780', Email__c = 'asha@example.com', PAN__c = pan,
            Date_Of_Birth__c = Date.newInstance(1990, 8, 15), Monthly_Income__c = 85000, Existing_EMIs__c = existingEmis,
            Employment_Type__c = employment, Company_Name__c = company, Offer_Amount__c = 300000, Rate__c = 11.49,
            EMI__c = 9900, Tenure_Months__c = 36, Reference_Number__c = 'KMB-PL-261003-0001'
        );
        insert app;
        List<Loan_Document__c> docs = new List<Loan_Document__c>();
        for (String t : docTypes) {
            docs.add(new Loan_Document__c(Loan_Application__c = app.Id, Document_Type__c = t));
        }
        insert docs;
        LoanSevaUnderwriting.run(app.Id);
        return app;
    }

    private static Map<String, Object> report(Id appId, String check) {
        Underwriting_Check__c c = [SELECT Report_Data__c FROM Underwriting_Check__c WHERE Loan_Application__c = :appId AND Check__c = :check];
        return (Map<String, Object>) JSON.deserializeUntyped(c.Report_Data__c);
    }

    private static List<Object> table(Map<String, Object> report, String title) {
        for (Object t : (List<Object>) report.get('tables')) {
            Map<String, Object> m = (Map<String, Object>) t;
            if (m.get('title') == title) {
                return (List<Object>) m.get('rows');
            }
        }
        return null;
    }

    @IsTest
    static void cleanFileReadsAsApprove() {
        Loan_Application__c app = underwritten('ABCPP1234K', 'Salaried', 'Infosys', 5000, new List<String>{ 'PAN Card', 'Bank Statement' });
        LoanSevaCreditMemo.Memo m = LoanSevaDecisionService.getScorecard(app.Id).memo;
        System.assertEquals('Approve', m.recommendation);
        System.assert(m.headline.startsWith('Approve - clean file, all 6 checks passed'), m.headline);
        System.assertEquals(6, m.strengths.size(), m.strengths);
        System.assert(m.risks.isEmpty(), m.risks);
        System.assert(m.narrative.contains('₹3,00,000'), m.narrative);
        System.assert(!m.approveIsDeviation);
        System.assert(m.rejectIsDeviation, 'rejecting a clean file needs a reason');

        Map<String, Object> bureau = report(app.Id, 'Credit Bureau');
        System.assert(table(bureau, 'Accounts').size() >= 3, 'active loans, a card and closed accounts');
        List<Object> enquiries = table(bureau, 'Enquiries');
        System.assert(JSON.serialize(enquiries[0]).contains('This application'), enquiries);
        System.assertEquals(6, table(report(app.Id, 'Bank Statement Analysis'), 'Monthly summary').size());
        System.assertEquals(6, table(report(app.Id, 'Employment Verification'), 'PF contributions').size());
        System.assertEquals(5, table(report(app.Id, 'Policy & FOIR'), 'Policy grid').size());
        System.assertEquals(4, table(report(app.Id, 'Dedupe & Fraud'), 'Watchlist screening').size());
        LoanSevaUnderwriting.run(app.Id);
        System.assertEquals(JSON.serialize(table(bureau, 'Accounts')), JSON.serialize(table(report(app.Id, 'Credit Bureau'), 'Accounts')), 'a re-run shows the same accounts');
    }

    @IsTest
    static void openItemsBecomeConditions() {
        Loan_Application__c app = underwritten('ABCPP1234R', 'Salaried', 'Sunrise Foods', 5000, new List<String>());
        LoanSevaCreditMemo.Memo m = LoanSevaCreditMemo.build(
            [SELECT Applicant_Name__c, Recommendation__c, Offer_Amount__c, Tenure_Months__c, EMI__c, Employment_Type__c, Company_Name__c, CIBIL_Score__c,
                Monthly_Income__c, Existing_EMIs__c FROM Loan_Application__c WHERE Id = :app.Id],
            [SELECT Check__c, Result__c, Score__c, Summary__c FROM Underwriting_Check__c WHERE Loan_Application__c = :app.Id]
        );
        System.assertEquals('Refer', m.recommendation);
        System.assert(m.headline.startsWith('Refer - 3 items to clear'), m.headline);
        System.assert(String.join(m.risks, '|').contains('CIBIL 695'), m.risks);
        String conditions = String.join(m.conditions, '|');
        System.assert(conditions.contains('bank statement'), conditions);
        System.assert(conditions.contains('salary slips'), conditions);
        System.assert(conditions.contains('delay'), conditions);
        System.assert(m.approveIsDeviation);
        System.assert(!m.rejectIsDeviation);

        List<Object> accounts = table(report(app.Id, 'Credit Bureau'), 'Accounts');
        System.assert(JSON.serialize(accounts).contains('30 in '), 'the 30-day delay shows on the card');
        Map<String, Object> bank = report(app.Id, 'Bank Statement Analysis');
        System.assertEquals(null, table(bank, 'Monthly summary'), 'no statement, no analysis');
    }

    @IsTest
    static void hardStopsReadAsDecline() {
        Loan_Application__c app = underwritten('ABCPP1234Z', 'Self-employed', 'Patil Traders', 40000, new List<String>{ 'Bank Statement' });
        LoanSevaCreditMemo.Memo m = LoanSevaDecisionService.getScorecard(app.Id).memo;
        System.assertEquals('Decline', m.recommendation);
        System.assert(m.headline.startsWith('Decline - 1 hard stop (Credit Bureau)'), m.headline);
        String risks = String.join(m.risks, '|');
        System.assert(risks.contains('written-off'), risks);
        System.assert(risks.contains('FOIR'), risks);
        System.assert(String.join(m.conditions, '|').contains('ITR'), m.conditions);
        System.assert(m.approveGuidance.contains('deviation'), m.approveGuidance);

        System.assert(JSON.serialize(table(report(app.Id, 'Credit Bureau'), 'Accounts')).contains('Written-off'));
        System.assertEquals(6, table(report(app.Id, 'Employment Verification'), 'GST filings').size(), 'self-employed get GST, not EPFO');
        System.assert(JSON.serialize(report(app.Id, 'Bank Statement Analysis')).contains('Business credits'));
    }

    @IsTest
    static void fraudAndKycFlags() {
        Loan_Application__c first = underwritten('ABCPS1234K', 'Salaried', 'Infosys', 0, new List<String>{ 'Bank Statement' });
        Loan_Application__c second = new Loan_Application__c(Product__c = 'Personal Loan', Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN,
            Applicant_Name__c = 'Ravi Kumar', Mobile__c = '9000011111', Email__c = 'ravi@mailinator.com', PAN__c = 'ABCPS1234K',
            Monthly_Income__c = 85000, Employment_Type__c = 'Salaried', Company_Name__c = 'Infosys', Date_Of_Birth__c = Date.newInstance(1990, 1, 1));
        insert second;
        Underwriting_Check__c fraud = LoanSevaUnderwriting.dedupeCheck(second);
        System.assertEquals('Refer', fraud.Result__c);
        System.assertEquals(2, fraud.Score__c, 'PAN reuse and a disposable email');
        System.assert(fraud.Report_Data__c.contains('mailinator.com'));

        LoanSevaCreditMemo.Memo m = LoanSevaDecisionService.getScorecard(first.Id).memo;
        System.assert(String.join(m.conditions, '|').contains('DigiLocker'), 'PAN name mismatch');
        Underwriting_Check__c company = LoanSevaUnderwriting.panCheck(new Loan_Application__c(PAN__c = 'ABCCP1234K', Applicant_Name__c = 'Asha Patil'));
        System.assert(company.Report_Data__c.contains('Non-individual'));
        System.assert(LoanSevaUnderwriting.panCheck(new Loan_Application__c(PAN__c = 'BAD')).Report_Data__c.contains('Invalid PAN'));
    }

    @IsTest
    static void foirReferSuggestsAffordableEmi() {
        Loan_Application__c app = underwritten('ABCPP1234K', 'Salaried', 'Infosys', 40000, new List<String>{ 'Bank Statement' });
        LoanSevaCreditMemo.Memo m = LoanSevaDecisionService.getScorecard(app.Id).memo;
        System.assertEquals('Refer', m.recommendation);
        Decimal affordable = (85000 * LoanSevaConfig.get().Max_FOIR_Pct__c / 100 - 40000).setScale(0);
        System.assert(String.join(m.conditions, '|').contains(LoanSevaI18n.inr(affordable)), m.conditions);
    }

    @IsTest
    static void notRunYet() {
        LoanSevaCreditMemo.Memo m = LoanSevaCreditMemo.build(new Loan_Application__c(), new List<Underwriting_Check__c>());
        System.assertEquals('Underwriting has not run yet', m.headline);
        System.assert(!m.approveIsDeviation);
        System.assert(!LoanSevaCreditMemo.isDeviation(null, LoanSevaDecisionService.APPROVED));
    }
}
