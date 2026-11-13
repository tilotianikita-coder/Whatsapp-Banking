/**
 * Lead management for new-to-bank card applicants: a Lead per prospect (from OTP verification on), scored on intent
 * and credit, with RM tasks and a one-click WhatsApp nudge that resumes the journey where it stopped.
 *
 * Intent (0-100): details shared (5 each, max 50) + income band (up to 20) + needs answered (10) + soft-check consent (10)
 *                 + reached a recommendation (10).
 * Credit (0-100): CIBIL band (up to 50; 20 while not pulled) + best eligible card tier (10 each, max 40) + no fraud flag (10).
 */
public inherited sharing class BandhuLeadService {
    public static final String SOURCE = 'Bandhu Card Journey';
    private static final Map<String, String> STEP_LABELS = new Map<String, String>{
        'menu' => 'Welcome menu', 'consent' => 'Consent', 'name' => 'Name', 'mobile' => 'Mobile', 'otp' => 'OTP',
        'spend' => 'Spend categories', 'monthly_spend' => 'Monthly spend', 'fee' => 'Fee preference', 'employment' => 'Employment',
        'income' => 'Income', 'company' => 'Company', 'pan' => 'PAN', 'dob' => 'Date of birth', 'pincode' => 'PIN code',
        'bureau' => 'Credit check consent', 'aa' => 'Account Aggregator', 'choose' => 'Card recommendation', 'email' => 'Email',
        'aadhaar' => 'Aadhaar eKYC', 'aadhaar_otp' => 'Aadhaar OTP', 'vkyc' => 'Video KYC', 'review' => 'Review and submit',
        'not_eligible' => 'Not eligible', 'declined_alt' => 'Declined (alternative offered)', 'done' => 'Done'
    };

    public static String stepLabel(Card_Journey__c j) {
        String l = STEP_LABELS.get(j.Step__c);
        return l == null ? j.Step__c : l;
    }

    public class Score {
        public Integer intent = 0;
        public Integer credit = 0;
        public List<String> detail = new List<String>();

        public Integer combined() {
            return Math.round((intent + credit) / 2.0);
        }

        public String rating() {
            return combined() >= 70 ? 'Hot' : combined() >= 50 ? 'Warm' : 'Cold';
        }
    }

    public static Score score(Card_Journey__c j) {
        Score s = new Score();
        Integer done = BandhuJourneyService.fieldsDone(j);
        Integer pts = Math.min(50, done * 5);
        s.intent += pts;
        s.detail.add('Details shared ' + done + '/10: ' + pts + '/50');
        Decimal income = j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c;
        pts = income == null ? 0 : income >= 200000 ? 20 : income >= 75000 ? 15 : income >= 40000 ? 10 : income >= 25000 ? 5 : 0;
        s.intent += pts;
        s.detail.add('Monthly income ' + (income == null ? 'not shared' : BandhuI18n.inr(income)) + ': ' + pts + '/20');
        pts = String.isNotBlank(j.Spend_Focus__c) && String.isNotBlank(j.Fee_Preference__c) ? 10 : 0;
        s.intent += pts;
        s.detail.add('Needs ' + (String.isBlank(j.Spend_Focus__c) ? 'not shared' : j.Spend_Focus__c.replace(';', ', ')) + ': ' + pts + '/10');
        pts = j.Bureau_Consent__c ? 10 : 0;
        s.intent += pts;
        s.detail.add('Soft credit check ' + (j.Bureau_Consent__c ? 'consented' : 'not yet') + ': ' + pts + '/10');
        pts = j.Recommended_Card__c != null ? 10 : 0;
        s.intent += pts;
        s.detail.add('Recommendation ' + (j.Recommended_Card__c == null ? 'not reached' : j.Recommended_Card__c) + ': ' + pts + '/10');

        Integer cibil = j.CIBIL_Score__c == null ? null : j.CIBIL_Score__c.intValue();
        pts = cibil == null ? 20 : cibil >= 760 ? 50 : cibil >= 720 ? 40 : cibil >= 700 ? 30 : cibil >= 650 ? 15 : 0;
        s.credit += pts;
        s.detail.add('CIBIL ' + (cibil == null ? 'not pulled yet' : String.valueOf(cibil)) + ': ' + pts + '/50');
        Integer tier = 0;
        if (String.isNotBlank(j.Eligible_Cards__c)) {
            for (String c : j.Eligible_Cards__c.split(';')) {
                Bandhu_Card__mdt card = BandhuConfig.card(c);
                tier = card == null ? tier : Math.max(tier, card.Tier__c.intValue());
            }
        }
        pts = tier * 10;
        s.credit += pts;
        s.detail.add('Best eligible card ' + (tier == 0 ? 'none yet' : j.Eligible_Cards__c.substringAfterLast(';')) + ': ' + pts + '/40');
        Boolean flagged = String.isNotBlank(j.PAN__c) && j.PAN__c.right(1) == 'X';
        pts = flagged ? 0 : 10;
        s.credit += pts;
        s.detail.add('Fraud & dedupe ' + (flagged ? 'flagged' : 'clear') + ': ' + pts + '/10');
        return s;
    }

    /** The prospect's Lead (new-to-bank only), created or refreshed with the latest score. */
    public static Id upsertLead(Card_Journey__c j) {
        if (j.Contact__c != null || j.Customer_Type__c == BandhuJourneyService.EXISTING || j.Mobile__c == null) {
            return null;
        }
        Lead l;
        if (j.Lead__c != null) {
            l = new Lead(Id = j.Lead__c);
        } else {
            List<String> variants = BandhuI18n.mobileVariants(j.Mobile__c);
            for (Lead existing : [SELECT Id FROM Lead WHERE MobilePhone IN :variants AND IsConverted = false ORDER BY CreatedDate DESC LIMIT 1]) {
                l = existing;
            }
        }
        Boolean isNew = l == null;
        if (isNew) {
            l = new Lead(Company = 'Individual', LeadSource = SOURCE, Status = 'New');
            Id owner = rmId();
            if (owner != null) {
                l.OwnerId = owner;
            }
        }
        String name = String.isBlank(j.Customer_Name__c) ? 'Prospect ' + j.Mobile__c.right(4) : j.Customer_Name__c;
        l.FirstName = name.contains(' ') ? name.substringBeforeLast(' ') : null;
        l.LastName = name.contains(' ') ? name.substringAfterLast(' ') : name;
        l.MobilePhone = j.Mobile__c;
        l.Email = j.Email__c;
        l.City = j.City__c;
        l.PostalCode = j.PIN_Code__c;
        l.Bandhu_Journey__c = j.Id;
        applyScore(l, j);
        if (isNew) {
            Database.DMLOptions dml = new Database.DMLOptions();
            dml.DuplicateRuleHeader.allowSave = true;
            Database.insert(l, dml);
        } else {
            update l;
        }
        j.Lead__c = l.Id;
        return l.Id;
    }

    private static void applyScore(Lead l, Card_Journey__c j) {
        Score s = score(j);
        l.Bandhu_Intent_Score__c = s.intent;
        l.Bandhu_Credit_Score__c = s.credit;
        l.Bandhu_Combined_Score__c = s.combined();
        l.Rating = s.rating();
        l.Bandhu_CIBIL__c = j.CIBIL_Score__c;
        l.Bandhu_Recommended_Card__c = j.Recommended_Card__c;
        l.Bandhu_Eligible_Cards__c = j.Eligible_Cards__c;
        l.Bandhu_Drop_Point__c = j.Status__c == BandhuJourneyService.STATUS_DROPPED ? j.Drop_Point__c : stepLabel(j);
        l.Bandhu_Score_Detail__c = String.join(s.detail, '\n');
    }

    /** RM task about this journey (WhoId = the prospect's Lead when there is one). */
    public static void rmTask(Card_Journey__c j, String subject, String body) {
        Task t = new Task(Subject = subject.abbreviate(255), Description = body, Priority = 'High', Status = 'Not Started',
            ActivityDate = BandhuI18n.today(), WhatId = j.Id);
        if (j.Lead__c != null) {
            t.WhoId = j.Lead__c;
            t.WhatId = null;
        }
        Id owner = rmId();
        if (owner != null) {
            t.OwnerId = owner;
        }
        if (j.Id == null && j.Lead__c == null) {
            return;
        }
        insert t;
    }

    /** Submitted and approved: the prospect is now a customer. */
    public static void convert(Card_Journey__c j) {
        if (j.Lead__c != null) {
            Database.update(new Lead(Id = j.Lead__c, Status = 'Qualified', Bandhu_Drop_Point__c = 'Card issued'), false);
        }
    }

    /** RM nudge from the Lead page: a WhatsApp message that resumes the journey. */
    public static String nudge(Id leadId) {
        Lead l = [SELECT Id, Bandhu_Journey__c, Owner.Name, Bandhu_Last_Nudged__c FROM Lead WHERE Id = :leadId];
        if (l.Bandhu_Journey__c == null) {
            throw new BandhuException('This lead has no Bandhu card journey to resume.');
        }
        Card_Journey__c j = BandhuJourneyService.byId(l.Bandhu_Journey__c);
        String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
        String body = BandhuI18n.msg('Nudge_RM', j.Language__c, new Map<String, Object>{
            'name' => first, 'rm' => l.Owner.Name, 'done' => BandhuJourneyService.fieldsDone(j) });
        j.Nudges_Sent__c = (j.Nudges_Sent__c == null ? 0 : j.Nudges_Sent__c) + 1;
        j.Last_Nudged__c = Datetime.now();
        update j;
        update new Lead(Id = l.Id, Bandhu_Last_Nudged__c = Datetime.now(), Status = 'Working');
        BandhuWhatsAppSender.enqueue(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(j.Id, body, null) });
        return body;
    }

    /** Idle journeys become drop-offs: the Lead is re-scored with the drop point and the RM gets a call task. */
    public static void captureDropOffs(List<Card_Journey__c> journeys) {
        for (Card_Journey__c j : journeys) {
            if (j.Customer_Type__c != BandhuJourneyService.EXISTING && j.Mobile__c != null) {
                upsertLead(j);
            }
            rmTask(j, 'Bandhu: card applicant dropped at ' + stepLabel(j) + ' - ' + BandhuEngine.label(j),
                'Dropped at ' + j.Drop_Point__c + '. ' + (j.Recommended_Card__c == null ? '' : 'Recommended: ' + j.Recommended_Card__c + '. ')
                + 'Nudge on WhatsApp from the Lead page, or call.');
        }
    }

    private static Id rmId() {
        String username = BandhuConfig.get().RM_Username__c;
        if (String.isBlank(username)) {
            return null;
        }
        for (User u : [SELECT Id FROM User WHERE Username = :username AND IsActive = TRUE LIMIT 1]) {
            return u.Id;
        }
        return null;
    }
}
