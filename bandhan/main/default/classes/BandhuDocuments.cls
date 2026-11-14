/**
 * Document intelligence for income proof: OCR + NLP extraction (MOCK: the figures are simulated from the application;
 * going live, Einstein Document AI / a Prompt Template or an OCR vendor fills extract()) and a real cross-check:
 * PAN on the document vs the application, and the extracted monthly income vs the declared one; more than
 * VARIANCE_THRESHOLD below declared -> Refer for manual review.
 * Demo lever: a file name containing "mismatch" (or PAN digits ending 2) reads 30% lower.
 * The application's Income Verification check is updated with every document.
 */
public with sharing class BandhuDocuments {
    public static final Decimal VARIANCE_THRESHOLD = 15;

    public class Extraction {
        public String docType;
        public String employer;
        public String pan;
        public String period;
        public Decimal monthlyIncome;
        public Decimal grossMonthly;
        public Decimal annualIncome;
        public Decimal tds;
        public Decimal confidence;
    }

    @TestVisible
    private static Extraction extract(String docType, String fileName, Card_Application__c app) {
        Extraction e = new Extraction();
        e.docType = docType;
        Decimal declared = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        String pan = app.PAN__c == null ? '' : app.PAN__c.toUpperCase();
        Boolean low = (fileName != null && fileName.containsIgnoreCase('mismatch')) || (pan.length() >= 9 && pan.substring(5, 9).endsWith('2'));
        Decimal net = (declared * (low ? 0.7 : 0.98) / 100).setScale(0) * 100;
        e.employer = String.isBlank(app.Company_Name__c) ? 'Not legible' : app.Company_Name__c.toUpperCase();
        e.pan = pan;
        e.monthlyIncome = net;
        e.grossMonthly = (net * 1.18 / 100).setScale(0) * 100;
        e.annualIncome = docType == 'ITR' || docType == 'Form 16' ? net * 12 : null;
        e.tds = docType == 'Form 16' ? (net * 12 * 0.08).setScale(0) : null;
        Date last = BandhuI18n.today().toStartOfMonth().addDays(-1);
        e.period = docType == 'Salary slip' ? Datetime.newInstance(last, Time.newInstance(0, 0, 0, 0)).format('MMM yyyy')
            : docType == 'Bank statement' ? 'Last 6 months' : 'FY ' + (last.month() >= 4 ? last.year() - 1 : last.year() - 2) + '-' + String.valueOf(last.month() >= 4 ? last.year() : last.year() - 1).right(2);
        e.confidence = 0.94;
        return e;
    }

    public static Bandhu_Document__c process(Id applicationId, String docType, Id contentDocumentId) {
        Card_Application__c app = [SELECT Id, PAN__c, Monthly_Income__c, Company_Name__c, Verified_Income__c FROM Card_Application__c WHERE Id = :applicationId];
        String fileName;
        if (contentDocumentId != null) {
            for (ContentDocument d : [SELECT Title FROM ContentDocument WHERE Id = :contentDocumentId]) {
                fileName = d.Title;
            }
        }
        Extraction e = extract(docType, fileName, app);
        Decimal declared = app.Monthly_Income__c == null ? 0 : app.Monthly_Income__c;
        Decimal variance = declared == 0 ? 0 : ((declared - e.monthlyIncome) / declared * 100).setScale(1);
        Boolean panOk = String.isNotBlank(app.PAN__c) && e.pan == app.PAN__c.toUpperCase();
        Boolean pass = panOk && variance <= VARIANCE_THRESHOLD;
        Bandhu_Document__c d = new Bandhu_Document__c(
            Card_Application__c = applicationId, Type__c = docType, Content_Document_Id__c = contentDocumentId, File_Name__c = fileName,
            Employer__c = e.employer, PAN_On_Document__c = BandhuI18n.maskPan(e.pan), PAN_Match__c = panOk, Period__c = e.period,
            Extracted_Monthly_Income__c = e.monthlyIncome, Declared_Monthly_Income__c = declared, Variance_Pct__c = variance,
            Result__c = pass ? 'Pass' : 'Refer', Extracted_Data__c = JSON.serialize(e, true),
            Summary__c = (docType + ' ' + e.period + ': ' + BandhuI18n.inr(e.monthlyIncome) + '/month net from ' + e.employer
                + (pass ? ' · matches the declared income' : !panOk ? ' · PAN does not match' : ' · ' + variance + '% below declared ' + BandhuI18n.inr(declared))).abbreviate(255));
        insert d;
        updateIncomeCheck(app);
        return d;
    }

    /** Re-score Income Verification on the application from all its documents. */
    private static void updateIncomeCheck(Card_Application__c app) {
        List<Bandhu_Document__c> docs = [SELECT Result__c, Summary__c, Extracted_Monthly_Income__c FROM Bandhu_Document__c
                                         WHERE Card_Application__c = :app.Id ORDER BY CreatedDate ASC];
        List<Card_Check__c> checks = [SELECT Id, Result__c, Summary__c, Details__c, Provider__c FROM Card_Check__c
                                      WHERE Card_Application__c = :app.Id AND Check__c = 'Income Verification' LIMIT 1];
        if (checks.isEmpty() || docs.isEmpty()) {
            return;
        }
        Card_Check__c c = checks[0];
        Boolean allPass = true;
        List<String> lines = new List<String>();
        Decimal lowest;
        for (Bandhu_Document__c d : docs) {
            allPass &= d.Result__c == 'Pass';
            lines.add((d.Result__c == 'Pass' ? '✓ ' : '⚠ ') + d.Summary__c);
            lowest = lowest == null || d.Extracted_Monthly_Income__c < lowest ? d.Extracted_Monthly_Income__c : lowest;
        }
        String base = c.Details__c == null ? '' : c.Details__c.substringBefore('\nDocuments:');
        c.Details__c = (base + '\nDocuments:\n' + String.join(lines, '\n')).abbreviate(32768);
        if (allPass) {
            c.Result__c = 'Pass';
            c.Provider__c = 'Documents (OCR, mock)';
            c.Summary__c = ('Verified from ' + docs.size() + ' document(s): ' + BandhuI18n.inr(lowest) + '/month').abbreviate(255);
            app.Verified_Income__c = lowest;
            update app;
        } else {
            c.Result__c = 'Refer';
            c.Summary__c = ('Documents disagree with the declared income: ' + lines[lines.size() - 1].removeStart('⚠ ')).abbreviate(255);
        }
        update c;
    }

    @AuraEnabled
    public static Bandhu_Document__c upload(Id applicationId, String docType, Id contentDocumentId) {
        try {
            return process(applicationId, docType, contentDocumentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Bandhu_Document__c> documents(Id applicationId) {
        return [SELECT Id, Name, Type__c, File_Name__c, Period__c, Employer__c, Extracted_Monthly_Income__c, Variance_Pct__c, PAN_Match__c,
                Result__c, Summary__c FROM Bandhu_Document__c WHERE Card_Application__c = :applicationId ORDER BY CreatedDate DESC];
    }
}
