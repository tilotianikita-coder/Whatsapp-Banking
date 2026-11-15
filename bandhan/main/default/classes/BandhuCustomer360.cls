/**
 * RM 360 view of an existing customer (Contact page in the Bandhu Cards app): the bank's relationship, the cached bureau
 * report, the latest cash-flow analysis, holds, and the card to pitch before the customer asks: the same eligibility,
 * Bandhan Score and limit model as the digital journey, on what the bank already knows (branch channel).
 */
public with sharing class BandhuCustomer360 {
    public class View {
        @AuraEnabled public String name;
        @AuraEnabled public String mobile;
        @AuraEnabled public Boolean isCustomer = false;
        @AuraEnabled public String tier;
        @AuraEnabled public Integer relationshipScore;
        @AuraEnabled public List<String> relationship = new List<String>();
        @AuraEnabled public String hold;
        @AuraEnabled public String bureau;
        @AuraEnabled public List<String> bureauLines = new List<String>();
        @AuraEnabled public String cashFlow;
        @AuraEnabled public Integer bandhanScore;
        @AuraEnabled public String band;
        @AuraEnabled public List<String> scoreWeakest = new List<String>();
        @AuraEnabled public String pitchCard;
        @AuraEnabled public String pitchName;
        @AuraEnabled public String pitchTier;
        @AuraEnabled public String pitchColor;
        @AuraEnabled public String pitchTagline;
        @AuraEnabled public String pitchLimit;
        @AuraEnabled public List<String> pitchWhy = new List<String>();
        @AuraEnabled public String alternative;
        @AuraEnabled public List<String> eligible = new List<String>();
        @AuraEnabled public String notEligibleReason;
        @AuraEnabled public List<String> history = new List<String>();
        @AuraEnabled public Boolean canStart = false;
    }

    @AuraEnabled
    public static View get(Id contactId) {
        Contact c = [SELECT Id, Name, FirstName, MobilePhone, Birthdate, MailingCity, MailingPostalCode, Bandhu_Bureau_Data__c, Bandhu_Bureau_At__c
                     FROM Contact WHERE Id = :contactId];
        View v = new View();
        v.name = c.Name;
        v.mobile = c.MobilePhone == null ? null : BandhuI18n.maskMobile(BandhuI18n.normalizeMobile(c.MobilePhone));
        BandhuCustomer.Insight i = BandhuCustomer.forContact(c.Id);
        for (Card_Application__c a : [SELECT Name, Card_Product__c, Status__c, Credit_Limit__c, Submitted_At__c FROM Card_Application__c
                                      WHERE Contact__c = :c.Id ORDER BY CreatedDate DESC LIMIT 5]) {
            v.history.add(a.Name + ' · ' + a.Card_Product__c + ' · ' + a.Status__c + (a.Credit_Limit__c == null ? '' : ' · ' + BandhuI18n.inr(a.Credit_Limit__c)));
        }
        if (i == null) {
            return v;
        }
        v.isCustomer = true;
        v.tier = i.tier;
        v.relationshipScore = i.score;
        v.relationship = i.lines();
        v.hold = i.blocker;

        // what the journey would know: the bank's records, the cached bureau report and the latest cash-flow analysis
        Card_Journey__c j = new Card_Journey__c(Contact__c = c.Id, Customer_Type__c = BandhuJourneyService.EXISTING, Channel__c = 'Branch',
            PAN__c = i.pan, Date_Of_Birth__c = c.Birthdate, PIN_Code__c = c.MailingPostalCode, City__c = c.MailingCity,
            Monthly_Income__c = i.salaryCredit, Verified_Income__c = i.salaryCredit, Employment_Type__c = i.salaryCredit != null ? 'Salaried' : null,
            Bureau_Data__c = c.Bandhu_Bureau_Data__c);
        BandhuBureau.Report b = BandhuBureau.fromJourney(j);
        if (b == null && String.isNotBlank(i.pan) && i.blocker == null) {
            b = BandhuBureau.pull(i.pan, 'Soft');   // shown, not stored: the RM view does not create a bureau record
            BandhuBureau.apply(j, b);
        } else if (b != null) {
            j.CIBIL_Score__c = b.score;
        }
        if (b != null) {
            v.bureau = BandhuBureau.assess(b).summary + (c.Bandhu_Bureau_At__c == null ? ' (live soft view)' : ' (cached ' + c.Bandhu_Bureau_At__c.format('dd/MM/yyyy', BandhuI18n.TIMEZONE) + ')');
            v.bureauLines = b.lines();
        }
        for (Card_Journey__c last : [SELECT AA_Insights__c, Monthly_Income__c, Spend_Focus__c FROM Card_Journey__c WHERE Contact__c = :c.Id
                                     AND AA_Consent_Id__c != null ORDER BY CreatedDate DESC LIMIT 1]) {
            j.AA_Insights__c = last.AA_Insights__c;
            j.Spend_Focus__c = last.Spend_Focus__c;
            BandhuCashFlow.Analysis cf = BandhuCashFlow.fromJourney(j);
            v.cashFlow = cf == null ? null : 'Income ' + BandhuI18n.inr(cf.netMonthlyIncome) + '/month · stability ' + cf.incomeStability
                + '/100 · FOIR ' + cf.foirPct.intValue() + '% · top spends ' + cf.topSpendText();
        }
        BandhuEligibility.Outcome o = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        v.bandhanScore = o.score.score;
        v.band = o.score.band;
        v.scoreWeakest = o.score.weakest(3);
        v.eligible = o.eligibleNames();
        BandhuEligibility.Option pick = o.best != null ? o.best : o.secured;
        if (pick != null && i.blocker == null) {
            v.pitchCard = pick.card.DeveloperName + (String.isBlank(pick.card.Tier_Label__c) ? '' : ' (' + pick.card.Tier_Label__c + ')');
            v.pitchTagline = pick.card.Tagline__c;
            v.pitchName = pick.card.DeveloperName;
            v.pitchTier = pick.card.Tier_Label__c;
            v.pitchColor = pick.card.Color__c;
            v.pitchLimit = pick.fdAmount != null ? BandhuI18n.inr(pick.creditLimit) + ' against an FD of ' + BandhuI18n.inr(pick.fdAmount)
                : (pick.limitLow != null && pick.limitLow < pick.creditLimit ? BandhuI18n.inr(pick.limitLow) + ' - ' : '') + BandhuI18n.inr(pick.creditLimit);
            v.pitchWhy = pick.why;
            v.alternative = o.alternative == null ? null : o.alternative.card.DeveloperName;
        } else {
            v.notEligibleReason = i.blocker != null ? 'On hold: ' + i.blocker : o.blockedReason;
        }
        v.canStart = i.blocker == null && pick != null && c.MobilePhone != null;
        return v;
    }

    /** Start a branch-assisted application: the customer gets the pitch on WhatsApp and continues there. */
    @AuraEnabled
    public static Id startApplication(Id contactId) {
        try {
            Contact c = [SELECT Id, Name, FirstName, MobilePhone FROM Contact WHERE Id = :contactId];
            if (c.MobilePhone == null) {
                throw new BandhuException('No mobile number on the customer.');
            }
            BandhuEngine.Result r = BandhuEngine.startBranch(c, UserInfo.getFirstName());
            BandhuWhatsAppSender.enqueue(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(r.journey.Id, r.message, null) });
            return r.journey.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
