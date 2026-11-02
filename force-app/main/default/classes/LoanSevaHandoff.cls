/**
 * Backs the LoanSeva card on the Messaging Session page (loanSevaHandoff): when the bot hands a WhatsApp chat to a
 * live agent, the agent sees who the customer is, their Kotak loan, why they asked for a person, every answer so far
 * (on file from earlier applications, or given today), the offer and the credit check, without asking again.
 */
public with sharing class LoanSevaHandoff {
    private static final Map<String, String> LABELS = new Map<String, String>{
        'dob' => 'Date of birth', 'pan' => 'PAN', 'email' => 'Email', 'pincode' => 'City and PIN', 'employment' => 'Employment',
        'company' => 'Company', 'income' => 'Monthly income', 'obligations' => 'Existing EMIs', 'purpose' => 'Purpose', 'amount' => 'Loan amount'
    };
    private static final String HANDOFF_PREFIX = 'LoanSeva: Human requested - ';

    public class Answer {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String source;
    }

    public class Context {
        @AuraEnabled public Boolean hasJourney = false;
        @AuraEnabled public Boolean existingCustomer = false;
        @AuraEnabled public String customerName;
        @AuraEnabled public String mobile;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id journeyId;
        @AuraEnabled public String journeyName;
        @AuraEnabled public String journeyType;
        @AuraEnabled public String language;
        @AuraEnabled public String stage;
        @AuraEnabled public String currentStep;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public Datetime handedOffAt;
        @AuraEnabled public String loanAccount;
        @AuraEnabled public Decimal loanEmi;
        @AuraEnabled public Decimal loanOutstanding;
        @AuraEnabled public Decimal loanRate;
        @AuraEnabled public String loanTrack;
        @AuraEnabled public Decimal preApproved;
        @AuraEnabled public Integer earlierApplications = 0;
        @AuraEnabled public Integer onFileCount = 0;
        @AuraEnabled public Integer todayCount = 0;
        @AuraEnabled public List<Answer> answers = new List<Answer>();
        @AuraEnabled public Decimal offerAmount;
        @AuraEnabled public Decimal offerRate;
        @AuraEnabled public Decimal offerTenure;
        @AuraEnabled public Decimal offerEmi;
        @AuraEnabled public Boolean offerAccepted = false;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String qualification;
        @AuraEnabled public Decimal cibil;
        @AuraEnabled public Decimal creditScore;
        @AuraEnabled public String questionsAsked;
    }

    @AuraEnabled
    public static Context getContext(Id sessionId) {
        Context ctx = new Context();
        Loan_Journey__c j = journeyFor(sessionId);
        if (j == null) {
            return ctx;
        }
        ctx.hasJourney = true;
        ctx.journeyId = j.Id;
        ctx.journeyName = j.Name;
        ctx.journeyType = String.isBlank(j.Journey_Type__c) ? 'Top-Up' : j.Journey_Type__c;
        ctx.customerName = j.Customer_Name__c;
        ctx.mobile = j.Mobile__c;
        ctx.contactId = j.Contact__c;
        ctx.leadId = j.Lead__c;
        ctx.existingCustomer = j.Contact__c != null && LoanSevaJourneyService.activeLoan(j.Contact__c) != null;
        ctx.language = j.Language__c;
        ctx.stage = j.Stage__c;
        ctx.currentStep = LoanSevaLeadService.stepLabel(j);
        ctx.status = j.Status__c;
        ctx.referenceNumber = j.Reference_Number__c;
        ctx.questionsAsked = j.Questions_Asked__c;
        ctx.qualification = j.Qualification_Status__c;
        ctx.cibil = j.CIBIL_Score__c;
        ctx.creditScore = j.Credit_Score__c;
        ctx.offerAmount = j.Offer_Amount__c;
        ctx.offerRate = j.Offer_Rate__c;
        ctx.offerTenure = j.Offer_Tenure_Months__c;
        ctx.offerEmi = j.Offer_EMI__c;
        ctx.offerAccepted = j.Offer_Accepted__c == true;

        if (j.Contact__c != null) {
            ctx.customerName = j.Contact__r.Name;
            Existing_Loan__c loan = LoanSevaJourneyService.activeLoan(j.Contact__c);
            if (loan != null) {
                ctx.loanAccount = String.isNotBlank(loan.Masked_Account__c) ? loan.Masked_Account__c : loan.Loan_Account_Number__c;
                ctx.loanEmi = loan.Current_EMI__c;
                ctx.loanOutstanding = loan.Outstanding_Principal__c;
                ctx.loanRate = loan.Interest_Rate__c;
                ctx.preApproved = loan.Pre_Approved_Limit__c;
                if (loan.EMIs_Due__c != null) {
                    ctx.loanTrack = (loan.EMIs_Paid_On_Time__c == null ? 0 : loan.EMIs_Paid_On_Time__c.intValue()) + '/' + loan.EMIs_Due__c.intValue() + ' EMIs on time';
                }
            }
            Id appId = j.Loan_Application__c;
            ctx.earlierApplications = [SELECT COUNT() FROM Loan_Application__c WHERE Contact__c = :j.Contact__c AND Submitted_At__c != null AND Id != :appId];
        }

        for (Task t : [
            SELECT Subject, CreatedDate FROM Task
            WHERE WhatId = :j.Id AND Subject LIKE 'LoanSeva: Human requested%'
            ORDER BY CreatedDate DESC LIMIT 1
        ]) {
            String reason = t.Subject.removeStart(HANDOFF_PREFIX);
            // the subject ends with the intent summary in brackets
            Integer cut = reason.lastIndexOf(' (');
            ctx.reason = cut > 0 ? reason.left(cut) : reason;
            ctx.handedOffAt = t.CreatedDate;
        }

        if (LoanSevaJourneyService.isNewLoan(j)) {
            Set<String> onFile = String.isBlank(j.Prefilled_Fields__c) ? new Set<String>() : new Set<String>(j.Prefilled_Fields__c.split(';'));
            for (String field : LoanSevaNewLoan.FIELDS) {
                Answer a = new Answer();
                a.label = LABELS.get(field);
                a.value = valueOf(j, field);
                a.source = a.value == null ? 'Not yet' : onFile.contains(field) ? 'On file' : 'Today';
                if (a.source == 'On file') {
                    ctx.onFileCount++;
                } else if (a.source == 'Today') {
                    ctx.todayCount++;
                }
                ctx.answers.add(a);
            }
        }
        return ctx;
    }

    /** The journey this chat belongs to; for an older chat, the latest journey on the customer's number. */
    @TestVisible
    private static Loan_Journey__c journeyFor(Id sessionId) {
        String sid = String.valueOf(sessionId);
        List<String> ids = new List<String>{ sid, sid.left(15) };
        String fields = LoanSevaJourneyService.journeyFields();
        List<Loan_Journey__c> rows = Database.query(
            'SELECT ' + fields + ' FROM Loan_Journey__c WHERE Messaging_Session_Id__c IN :ids ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        if (!rows.isEmpty()) {
            return rows[0];
        }
        List<MessagingSession> sessions = [SELECT MessagingEndUser.MessagingPlatformKey FROM MessagingSession WHERE Id = :sessionId];
        String mobile = sessions.isEmpty() ? null : LoanSevaJourneyService.normalizeMobile(sessions[0].MessagingEndUser.MessagingPlatformKey);
        if (mobile == null) {
            return null;
        }
        rows = Database.query('SELECT ' + fields + ' FROM Loan_Journey__c WHERE Mobile__c = :mobile ORDER BY LastModifiedDate DESC LIMIT 1');
        return rows.isEmpty() ? null : rows[0];
    }

    private static String valueOf(Loan_Journey__c j, String field) {
        if (!LoanSevaNewLoan.isAnswered(j, field)) {
            return null;
        }
        switch on field {
            when 'dob' {
                return Datetime.newInstance(j.Date_Of_Birth__c, Time.newInstance(12, 0, 0, 0)).format('dd/MM/yyyy');
            }
            when 'pan' {
                return LoanSevaNewLoan.maskPan(j.PAN__c);
            }
            when 'email' {
                return j.Email__c;
            }
            when 'pincode' {
                return ((j.City__c == null ? '' : j.City__c) + ' ' + j.PIN_Code__c).trim();
            }
            when 'employment' {
                return j.Employment_Type__c;
            }
            when 'company' {
                return j.Company_Name__c;
            }
            when 'income' {
                return LoanSevaI18n.inr(j.Monthly_Income__c) + '/month';
            }
            when 'obligations' {
                return LoanSevaI18n.inr(j.Existing_EMIs__c) + '/month';
            }
            when 'purpose' {
                return j.Purpose__c;
            }
            when else {
                return LoanSevaI18n.inr(j.Desired_Amount__c);
            }
        }
    }
}
