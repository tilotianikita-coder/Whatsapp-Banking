/**
 * RM decision on a new-loan application. Approve creates the loan account (LAN) as a Sanctioned Existing_Loan__c
 * and tells the customer on WhatsApp with the masked LAN only; Reject records the decision and sends a polite
 * decline. Backs the loanSevaScorecard component on the Loan Application record page.
 */
public with sharing class LoanSevaDecisionService {
    public static final String APPROVED = 'Approved';
    public static final String REJECTED = 'Rejected';
    /** Sent back for more details or documents; the application stays open for a final decision. */
    public static final String REFERRED = 'Referred';
    private static final Set<String> DECIDABLE = new Set<String>{ 'Application Submitted', 'Under Review' };

    public class Scorecard {
        @AuraEnabled public Loan_Application__c application;
        @AuraEnabled public List<Underwriting_Check__c> checks;
        @AuraEnabled public List<Loan_Document__c> documents;
        @AuraEnabled public String maskedPan;
        @AuraEnabled public String maskedLan;
        @AuraEnabled public Boolean canDecide;
        @AuraEnabled public LoanSevaCreditMemo.Memo memo;
    }

    @AuraEnabled
    public static Scorecard getScorecard(Id applicationId) {
        Loan_Application__c app = load(applicationId);
        Scorecard s = new Scorecard();
        s.application = app;
        s.checks = app.Underwriting_Checks__r;
        s.documents = app.Loan_Documents__r;
        s.maskedPan = String.isBlank(app.PAN__c) ? null : LoanSevaNewLoan.maskPan(app.PAN__c);
        s.maskedLan = app.Loan_Account__r?.Masked_Account__c;
        s.canDecide = canDecide(app);
        s.memo = LoanSevaCreditMemo.build(app, app.Underwriting_Checks__r);
        return s;
    }

    @AuraEnabled
    public static Scorecard approve(Id applicationId, String notes) {
        try {
            decide(new List<Id>{ applicationId }, APPROVED, notes);
        } catch (LoanSevaException e) {
            throw auraError(e.getMessage());
        }
        return getScorecard(applicationId);
    }

    @AuraEnabled
    public static Scorecard reject(Id applicationId, String notes) {
        try {
            decide(new List<Id>{ applicationId }, REJECTED, notes);
        } catch (LoanSevaException e) {
            throw auraError(e.getMessage());
        }
        return getScorecard(applicationId);
    }

    @AuraEnabled
    public static Scorecard rerunUnderwriting(Id applicationId) {
        Loan_Application__c app = load(applicationId);
        if (!canDecide(app)) {
            throw auraError('Underwriting can only be re-run before the decision.');
        }
        LoanSevaUnderwriting.run(applicationId);
        return getScorecard(applicationId);
    }

    /** Bulk-safe decision: one LAN per approved application, one WhatsApp message per customer. */
    public static void decide(List<Id> applicationIds, String decision, String notes) {
        if (decision != APPROVED && decision != REJECTED) {
            throw new LoanSevaException('Unknown decision: ' + decision);
        }
        List<Loan_Application__c> apps = [
            SELECT Id, Name, Status__c, Decision__c, Application_Type__c, Contact__c, Applicant_Name__c, Offer_Amount__c,
                Rate__c, Tenure_Months__c, EMI__c, Reference_Number__c, Loan_Journey__c, Loan_Account__c, Underwriting_Status__c, Recommendation__c
            FROM Loan_Application__c WHERE Id IN :applicationIds
        ];
        for (Loan_Application__c app : apps) {
            if (!canDecide(app)) {
                throw new LoanSevaException('Application ' + app.Reference_Number__c + ' is not awaiting a decision.');
            }
            if (decision == APPROVED && (app.Offer_Amount__c == null || app.Underwriting_Status__c != 'Completed')) {
                throw new LoanSevaException('Approve after underwriting has completed and an amount is set.');
            }
            if (String.isBlank(notes) && LoanSevaCreditMemo.isDeviation(app.Recommendation__c, decision)) {
                throw new LoanSevaException('The system recommends ' + app.Recommendation__c + ' - add a note explaining this decision.');
            }
        }

        Map<Id, Existing_Loan__c> loans = new Map<Id, Existing_Loan__c>();
        if (decision == APPROVED) {
            for (Loan_Application__c app : apps) {
                loans.put(app.Id, newLoan(app));
            }
            insert loans.values();
        }
        Datetime now = Datetime.now();
        for (Loan_Application__c app : apps) {
            app.Decision__c = decision;
            app.Decision_By__c = UserInfo.getUserId();
            app.Decision_At__c = now;
            app.Decision_Notes__c = String.isBlank(notes) ? null : notes.abbreviate(4000);
            app.Status__c = decision;
            if (loans.containsKey(app.Id)) {
                app.Loan_Account__c = loans.get(app.Id).Id;
            }
        }
        update apps;
        notifyCustomers(apps, loans);
    }

    private static Boolean canDecide(Loan_Application__c app) {
        return app.Application_Type__c == LoanSevaJourneyService.TYPE_NEW_LOAN && (app.Decision__c == null || app.Decision__c == REFERRED) && DECIDABLE.contains(app.Status__c);
    }

    /** PL + yyMMdd (IST) + 8-digit application sequence, e.g. PL26100100000042. */
    @TestVisible
    private static String lan(String sequence) {
        String seq = sequence == null ? '0' : sequence.replaceAll('[^0-9]', '');
        return LoanSevaConfig.get().Lan_Prefix__c + Datetime.now().format('yyMMdd', LoanSevaI18n.TIMEZONE) + seq.leftPad(8, '0').right(8);
    }

    private static Existing_Loan__c newLoan(Loan_Application__c app) {
        Integer tenure = app.Tenure_Months__c == null ? 0 : app.Tenure_Months__c.intValue();
        String lanNumber = lan(app.Name);
        return new Existing_Loan__c(
            Name = 'Personal Loan ' + lanNumber,
            Loan_Account_Number__c = lanNumber,
            Contact__c = app.Contact__c,
            Product__c = 'Personal Loan',
            Status__c = 'Sanctioned',
            Outstanding_Principal__c = app.Offer_Amount__c,
            Interest_Rate__c = app.Rate__c,
            Current_EMI__c = app.EMI__c,
            Tenure_Remaining_Months__c = tenure,
            EMIs_Due__c = tenure,
            EMIs_Paid_On_Time__c = 0,
            Pre_Approved_Limit__c = 0
        );
    }

    private static void notifyCustomers(List<Loan_Application__c> apps, Map<Id, Existing_Loan__c> loans) {
        Set<Id> journeyIds = new Set<Id>();
        for (Loan_Application__c app : apps) {
            if (app.Loan_Journey__c != null) {
                journeyIds.add(app.Loan_Journey__c);
            }
        }
        if (journeyIds.isEmpty()) {
            return;
        }
        Map<Id, Loan_Journey__c> journeys = new Map<Id, Loan_Journey__c>([
            SELECT Id, Customer_Name__c, Language__c, Contact__r.FirstName FROM Loan_Journey__c WHERE Id IN :journeyIds
        ]);
        Map<Id, Existing_Loan__c> masked = new Map<Id, Existing_Loan__c>([SELECT Masked_Account__c FROM Existing_Loan__c WHERE Id IN :loans.values()]);
        String definition = LoanSevaConfig.get().Reengage_Definition__c;
        List<LoanSevaWhatsAppSender.Outbound> outbound = new List<LoanSevaWhatsAppSender.Outbound>();
        for (Loan_Application__c app : apps) {
            Loan_Journey__c j = journeys.get(app.Loan_Journey__c);
            if (j != null) {
                outbound.add(new LoanSevaWhatsAppSender.Outbound(j.Id, message(app, j, masked.get(app.Loan_Account__c)), definition));
            }
        }
        LoanSevaWhatsAppSender.enqueue(outbound);
    }

    @TestVisible
    private static String message(Loan_Application__c app, Loan_Journey__c j, Existing_Loan__c loan) {
        Map<String, Object> tokens = new Map<String, Object>{ 'name' => LoanSevaJourneyService.firstName(j), 'ref' => app.Reference_Number__c };
        if (app.Decision__c == REJECTED) {
            return LoanSevaI18n.msg('NL_Rejected', j.Language__c, tokens);
        }
        tokens.putAll(new Map<String, Object>{
            'amount' => LoanSevaI18n.inr(app.Offer_Amount__c),
            'rate' => app.Rate__c,
            'tenure' => app.Tenure_Months__c == null ? null : app.Tenure_Months__c.intValue(),
            'emi' => LoanSevaI18n.inr(app.EMI__c),
            'lan' => loan.Masked_Account__c
        });
        return LoanSevaI18n.msg('NL_Approved', j.Language__c, tokens);
    }

    private static Loan_Application__c load(Id applicationId) {
        return [
            SELECT Id, Name, CreatedDate, Status__c, Application_Type__c, Applicant_Name__c, Mobile__c, Email__c, City__c, PIN_Code__c, PAN__c,
                Date_Of_Birth__c, Employment_Type__c, Company_Name__c, Monthly_Income__c, Existing_EMIs__c, Purpose__c,
                Offer_Amount__c, Rate__c, Tenure_Months__c, EMI__c, Reference_Number__c, CIBIL_Score__c, Recommendation__c,
                Underwriting_Status__c, Underwriting_Summary__c, Decision__c, Decision_At__c, Decision_By__r.Name, Decision_Notes__c,
                Loan_Account__c, Loan_Account__r.Masked_Account__c, Loan_Account__r.Loan_Account_Number__c, Loan_Account__r.Status__c, Bureau_Consent__c, Loan_Journey__c,
                (SELECT Id, Check__c, Provider__c, Result__c, Score__c, Summary__c, Details__c, Report_Data__c, Request_Id__c, Run_At__c
                 FROM Underwriting_Checks__r ORDER BY Sort_Order__c),
                (SELECT Id, Document_Type__c, File_Name__c, Status__c, Received_At__c, Content_Document_Id__c
                 FROM Loan_Documents__r ORDER BY Received_At__c)
            FROM Loan_Application__c WHERE Id = :applicationId
        ];
    }

    /** AuraHandledException hides its message from Apex callers unless it is set explicitly. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
