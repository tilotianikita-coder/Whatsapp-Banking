/**
 * Fraud / velocity / address signals, AIS and GST income cross-checks, and document reading with the income cross-check.
 */
@IsTest
private class BandhuRiskTest {
    @IsTest
    static void addressMustMatchThePin() {
        System.assertEquals(null, BandhuRisk.addressMismatch('Kolkata', '700091'));
        System.assertEquals(null, BandhuRisk.addressMismatch('Salt Lake, Kolkata', '700091'));
        System.assert(BandhuRisk.addressMismatch('Mumbai', '700091').contains('is in Kolkata'));
        System.assertEquals(null, BandhuRisk.addressMismatch('Anywhere', '999999'), 'unknown PIN: no opinion');
    }

    @IsTest
    static void velocityAndAddressRefer() {
        List<Card_Journey__c> js = new List<Card_Journey__c>();
        for (Integer i = 0; i < 3; i++) {
            js.add(new Card_Journey__c(PAN__c = BandhuTestData.GOOD_PAN, Mobile__c = '98765000' + (20 + i), City__c = 'Mumbai', PIN_Code__c = '700091'));
        }
        insert js;
        BandhuProviders.Report r = BandhuRisk.fraud(js[0], null);
        System.assertEquals('Refer', r.result, r.summary);
        System.assert(r.summary.contains('3 applications from this PAN / mobile in 24 hours'), r.summary);
        System.assert(r.summary.contains('is in Kolkata'), r.summary);
        Card_Journey__c fraudster = new Card_Journey__c(PAN__c = BandhuTestData.FRAUD_PAN);
        System.assertEquals('Fail', BandhuRisk.fraud(fraudster, null).result);
    }

    @IsTest
    static void creditHungryAcrossLenders() {
        Card_Journey__c j = new Card_Journey__c(PAN__c = 'ABCPS1236K', City__c = 'Kolkata', PIN_Code__c = '700091');
        BandhuBureau.apply(j, BandhuBureau.pull(j.PAN__c, 'Soft'));
        System.assert(BandhuRisk.fraud(j, null).summary.contains('5 lenders'));
    }

    @IsTest
    static void aisAndGstCrossChecks() {
        BandhuRisk.IncomeCheck ok = BandhuRisk.ais(BandhuTestData.GOOD_PAN, 100000, 'Salaried');
        System.assert(!ok.flagged, ok.lines);
        BandhuRisk.IncomeCheck weak = BandhuRisk.ais('ABCPS1232K', 100000, 'Salaried');
        System.assert(weak.flagged && weak.variancePct == 45, weak.lines);
        BandhuRisk.IncomeCheck gst = BandhuRisk.gst('ABCPS1232K', '700091', 100000);
        System.assert(gst.flagged, gst.lines);
        System.assert(gst.lines[0].startsWith('GSTIN 19ABCPS1232K1Z'), gst.lines[0]);
        System.assert(!BandhuRisk.gst(BandhuTestData.GOOD_PAN, '700091', 100000).flagged);

        Card_Journey__c j = new Card_Journey__c(PAN__c = 'ABCPS1232K', Monthly_Income__c = 100000, Verified_Income__c = 98000,
            Employment_Type__c = 'Business', PIN_Code__c = '700091');
        System.assertEquals(2, BandhuRisk.incomeChecks(j).size(), 'AIS and GST for a business owner');
        BandhuProviders.Report income = BandhuProviders.income(j);
        System.assertEquals('Refer', income.result, income.summary);
    }

    private static Card_Application__c declaredIncomeApplication() {
        BandhuTestData.useLogOnly();
        Map<String, String> a = BandhuTestData.answers(new List<String>{ '4', '2', '1' }, '60000', BandhuTestData.GOOD_PAN);
        a.put('aa', '2');   // no Account Aggregator: income stays self-declared
        BandhuEngine.Result r = BandhuTestData.drive(BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE), a);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', 'ananya@example.com', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        return [SELECT Id, Recommendation__c, (SELECT Result__c FROM Card_Checks__r WHERE Check__c = 'Income Verification')
                FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
    }

    private static Id file(String title) {
        ContentVersion v = new ContentVersion(Title = title, PathOnClient = title + '.pdf', VersionData = Blob.valueOf('%PDF-1.4 demo'));
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    @IsTest
    static void salarySlipVerifiesTheDeclaredIncome() {
        Card_Application__c app = declaredIncomeApplication();
        System.assertEquals('Refer', app.Card_Checks__r[0].Result__c, 'self-declared income');
        Bandhu_Document__c d = BandhuDocuments.upload(app.Id, 'Salary slip', file('Salary slip Oct'));
        System.assertEquals('Pass', d.Result__c, d.Summary__c);
        System.assert(d.PAN_Match__c);
        System.assertEquals('Pass', [SELECT Result__c FROM Card_Check__c WHERE Card_Application__c = :app.Id AND Check__c = 'Income Verification'].Result__c);
        System.assertEquals(58800, [SELECT Verified_Income__c FROM Card_Application__c WHERE Id = :app.Id].Verified_Income__c);
        System.assertEquals(1, BandhuDocuments.documents(app.Id).size());
    }

    @IsTest
    static void discrepancyBeyondTheThresholdRefers() {
        Card_Application__c app = declaredIncomeApplication();
        Bandhu_Document__c d = BandhuDocuments.upload(app.Id, 'Form 16', file('Form16 mismatch'));
        System.assertEquals('Refer', d.Result__c);
        System.assertEquals(30, d.Variance_Pct__c);
        Card_Check__c c = [SELECT Result__c, Details__c FROM Card_Check__c WHERE Card_Application__c = :app.Id AND Check__c = 'Income Verification'];
        System.assertEquals('Refer', c.Result__c);
        System.assert(c.Details__c.contains('Documents:'), c.Details__c);
    }
}
