/**
 * Backs the LoanSeva Lead card (loanSevaLeadInsight): the qualification stage gates, the intent, credit and combined
 * scores, serviceability, where the customer stopped, and the RM's "Nudge on WhatsApp" button.
 */
public with sharing class LoanSevaLeadInsight {
    /** One stage gate: its latest check, and its SLDS path class (complete, lost, current or not reached). */
    public class Gate {
        @AuraEnabled public String gate;
        @AuraEnabled public String check;
        @AuraEnabled public String provider;
        @AuraEnabled public String result;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Boolean knockout = false;
        @AuraEnabled public Datetime runAt;
        @AuraEnabled public String pathClass;
        @AuraEnabled public String resultClass;
    }

    public class Insight {
        @AuraEnabled public Boolean hasJourney = false;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal intentScore;
        @AuraEnabled public Decimal creditScore;
        @AuraEnabled public String creditConfidence;
        @AuraEnabled public List<String> creditLines = new List<String>();
        @AuraEnabled public Decimal cibil;
        @AuraEnabled public Decimal eligibility;
        @AuraEnabled public String consent;
        @AuraEnabled public String qualification;
        @AuraEnabled public String qualificationGate;
        @AuraEnabled public String stageGate;
        @AuraEnabled public String knockoutReason;
        @AuraEnabled public List<Gate> gates = new List<Gate>();
        @AuraEnabled public String rating;
        @AuraEnabled public List<String> scoreLines = new List<String>();
        @AuraEnabled public String region;
        @AuraEnabled public Boolean serviceable;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public Id journeyId;
        @AuraEnabled public String journeyName;
        @AuraEnabled public String journeyStatus;
        @AuraEnabled public String currentStep;
        @AuraEnabled public Integer detailsDone;
        @AuraEnabled public Integer detailsTotal;
        @AuraEnabled public Datetime droppedAt;
        @AuraEnabled public Datetime lastNudged;
        @AuraEnabled public Datetime resumedAt;
        @AuraEnabled public String preview;
        @AuraEnabled public Boolean canNudge = false;
        @AuraEnabled public String blockedReason;
    }

    @AuraEnabled
    public static Insight getInsight(Id leadId) {
        Lead l = [
            SELECT Id, Status, Rating, IsConverted, Owner.Name, LoanSeva_Journey__c, LoanSeva_Score__c, LoanSeva_Score_Detail__c,
                LoanSeva_Region__c, LoanSeva_Serviceable__c, LoanSeva_Last_Nudged__c, LoanSeva_Resumed_At__c, LoanSeva_Credit_Score__c,
                LoanSeva_Combined_Score__c, LoanSeva_CIBIL_Score__c, LoanSeva_Eligibility__c, LoanSeva_Stage_Gate__c, LoanSeva_Bureau_Consent__c
            FROM Lead WHERE Id = :leadId
        ];
        Insight i = new Insight();
        i.score = l.LoanSeva_Combined_Score__c != null ? l.LoanSeva_Combined_Score__c : l.LoanSeva_Score__c;
        i.intentScore = l.LoanSeva_Score__c;
        i.creditScore = l.LoanSeva_Credit_Score__c;
        i.cibil = l.LoanSeva_CIBIL_Score__c;
        i.eligibility = l.LoanSeva_Eligibility__c;
        i.consent = l.LoanSeva_Bureau_Consent__c;
        i.stageGate = l.LoanSeva_Stage_Gate__c;
        i.rating = l.Rating;
        i.region = l.LoanSeva_Region__c;
        i.serviceable = l.LoanSeva_Serviceable__c;
        i.ownerName = l.Owner.Name;
        i.leadStatus = l.Status;
        i.lastNudged = l.LoanSeva_Last_Nudged__c;
        i.resumedAt = l.LoanSeva_Resumed_At__c;
        if (String.isNotBlank(l.LoanSeva_Score_Detail__c)) {
            i.scoreLines = l.LoanSeva_Score_Detail__c.split('\n');
        }
        if (l.LoanSeva_Journey__c == null) {
            i.blockedReason = 'No LoanSeva WhatsApp journey on this lead.';
            return i;
        }
        Loan_Journey__c j = LoanSevaJourneyService.byId(l.LoanSeva_Journey__c);
        i.hasJourney = true;
        i.journeyId = j.Id;
        i.journeyName = j.Name;
        i.journeyStatus = j.Status__c;
        i.currentStep = LoanSevaLeadService.stepLabel(j);
        i.detailsDone = LoanSevaLeadScoring.answeredSteps(j);
        i.detailsTotal = LoanSevaNewLoan.FIELDS.size();
        i.droppedAt = j.Dropped_At__c;
        i.preview = LoanSevaLeadService.nudgeText(j, UserInfo.getFirstName());
        i.qualification = j.Qualification_Status__c;
        i.knockoutReason = j.Knockout_Reason__c;
        i.qualificationGate = j.Qualification_Gate__c;
        addGates(i, j);
        if (l.IsConverted) {
            i.blockedReason = 'Already converted to a customer.';
        } else if (!l.LoanSeva_Serviceable__c) {
            i.blockedReason = 'PIN code outside the serviceable regions: no RM nudge.';
        } else if (j.Qualification_Status__c == LoanSevaQualification.KNOCKED_OUT) {
            i.blockedReason = 'Knocked out at ' + j.Qualification_Gate__c + ': ' + j.Knockout_Reason__c + '. No RM nudge.';
        } else if (j.Status__c == LoanSevaJourneyService.STATUS_COMPLETED || j.Status__c == LoanSevaJourneyService.STATUS_EXITED) {
            i.blockedReason = 'Journey ' + j.Status__c.toLowerCase() + '.';
        } else {
            i.canNudge = true;
        }
        return i;
    }

    /** The journey's latest checks as stage gates, in gate order; a gate not run yet shows as Pending. */
    private static void addGates(Insight i, Loan_Journey__c j) {
        List<Qualification_Check__c> checks = [
            SELECT Gate__c, Check__c, Provider__c, Result__c, Summary__c, Score__c, Knockout__c, Run_At__c
            FROM Qualification_Check__c WHERE Loan_Journey__c = :j.Id ORDER BY Sort_Order__c
        ];
        if (checks.isEmpty()) {
            return;
        }
        LoanSevaQualification.Credit credit = LoanSevaQualification.credit(checks);
        i.creditLines = credit.lines;
        i.creditConfidence = credit.available == 0 ? null : credit.confidence();
        Map<String, Qualification_Check__c> byGate = new Map<String, Qualification_Check__c>();
        for (Qualification_Check__c c : checks) {
            byGate.put(c.Gate__c, c);
        }
        Boolean current = false;
        for (String name : LoanSevaQualification.GATES) {
            Qualification_Check__c c = byGate.get(name);
            if (c == null) {
                continue;
            }
            Gate g = new Gate();
            g.gate = name;
            g.check = c.Check__c;
            g.provider = c.Provider__c;
            g.result = c.Result__c;
            g.summary = c.Summary__c;
            g.score = c.Score__c;
            g.knockout = c.Knockout__c;
            g.runAt = c.Run_At__c;
            if (c.Result__c == 'Pass' || c.Result__c == 'Refer') {
                g.pathClass = 'slds-path__item slds-is-complete';
            } else if (c.Result__c == 'Fail') {
                // the knock-out is the selected step, shown as lost (SLDS styles lost only on the current step)
                g.pathClass = c.Knockout__c ? 'slds-path__item slds-is-current slds-is-active slds-is-lost' : 'slds-path__item slds-is-complete';
            } else if (!current && j.Qualification_Status__c != LoanSevaQualification.KNOCKED_OUT) {
                g.pathClass = 'slds-path__item slds-is-current slds-is-active';
                current = true;
            } else {
                g.pathClass = 'slds-path__item slds-is-incomplete';
            }
            g.resultClass = c.Result__c == 'Pass' ? 'slds-badge slds-theme_success'
                : c.Result__c == 'Fail' ? 'slds-badge slds-theme_error'
                : c.Result__c == 'Refer' ? 'slds-badge slds-theme_warning' : 'slds-badge';
            i.gates.add(g);
        }
    }

    @AuraEnabled
    public static String nudge(Id leadId) {
        try {
            return LoanSevaLeadService.nudge(leadId);
        } catch (LoanSevaException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
