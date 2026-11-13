/**
 * Lead management for new-to-bank card applicants: a Lead per prospect (from OTP verification on), scored on intent
 * and credit, with RM tasks and a one-click WhatsApp nudge that resumes the journey where it stopped.
 *
 * Scoring and stage gates come from BandhuQualification: a knocked-out lead (not serviceable, fraud, CIBIL below the
 * decline line, no card) is Unqualified and Cold, gets no RM task or nudge. The owner is the region's RM (else Config RM).
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
        BandhuQualification.Outcome q = BandhuQualification.evaluate(j);
        if (isNew) {
            l = new Lead(Company = 'Individual', LeadSource = SOURCE, Status = 'New');
        }
        Id owner = rmId(q.region.rmUsername);
        if (owner != null && (isNew || q.region.rmUsername != null)) {
            l.OwnerId = owner;
        }
        String name = String.isBlank(j.Customer_Name__c) ? 'Prospect ' + j.Mobile__c.right(4) : j.Customer_Name__c;
        l.FirstName = name.contains(' ') ? name.substringBeforeLast(' ') : null;
        l.LastName = name.contains(' ') ? name.substringAfterLast(' ') : name;
        l.MobilePhone = j.Mobile__c;
        l.Email = j.Email__c;
        l.City = j.City__c;
        l.PostalCode = j.PIN_Code__c;
        l.Bandhu_Journey__c = j.Id;
        applyScore(l, j, q);
        if (q.knockedOut()) {
            l.Status = 'Unqualified';
        }
        if (isNew) {
            Database.DMLOptions dml = new Database.DMLOptions();
            dml.DuplicateRuleHeader.allowSave = true;
            Database.insert(l, dml);
        } else {
            update l;
        }
        j.Lead__c = l.Id;
        saveChecks(l.Id, j, q);
        return l.Id;
    }

    /** Replaces the lead's stage-gate records with this run. */
    private static void saveChecks(Id leadId, Card_Journey__c j, BandhuQualification.Outcome q) {
        delete [SELECT Id FROM Bandhu_Lead_Check__c WHERE Lead__c = :leadId];
        for (Bandhu_Lead_Check__c c : q.checks) {
            c.Lead__c = leadId;
            c.Card_Journey__c = j.Id;
        }
        insert q.checks;
    }

    public static Boolean knockedOut(Id leadId) {
        return leadId != null && [SELECT COUNT() FROM Bandhu_Lead_Check__c WHERE Lead__c = :leadId AND Knockout__c = true] > 0;
    }

    private static void applyScore(Lead l, Card_Journey__c j, BandhuQualification.Outcome q) {
        l.Bandhu_Intent_Score__c = q.intent;
        l.Bandhu_Credit_Score__c = q.credit;
        l.Bandhu_Combined_Score__c = q.combined();
        l.Rating = q.rating();
        l.Bandhu_Stage_Gate__c = q.stageGate();
        l.Bandhu_Region__c = q.region.name;
        l.Bandhu_Serviceable__c = q.region.serviceable;
        l.Bandhu_Credit_Confidence__c = q.confidence;
        l.Bandhu_CIBIL__c = j.CIBIL_Score__c;
        l.Bandhu_Recommended_Card__c = j.Recommended_Card__c;
        l.Bandhu_Eligible_Cards__c = j.Eligible_Cards__c;
        l.Bandhu_Drop_Point__c = j.Status__c == BandhuJourneyService.STATUS_DROPPED ? j.Drop_Point__c : stepLabel(j);
        l.Bandhu_Score_Detail__c = (q.knockedOut() ? 'Knocked out at ' + q.knockedOutAt + ': ' + q.knockoutReason + '\n' : '') + q.detail();
    }

    /** RM task about this journey (WhoId = the prospect's Lead when there is one). */
    public static void rmTask(Card_Journey__c j, String subject, String body) {
        Task t = new Task(Subject = subject.abbreviate(255), Description = body, Priority = 'High', Status = 'Not Started',
            ActivityDate = BandhuI18n.today(), WhatId = j.Id);
        if (j.Lead__c != null) {
            t.WhoId = j.Lead__c;
            t.WhatId = null;
        }
        Id owner = rmId(null);
        if (j.Lead__c != null) {
            for (Lead l : [SELECT OwnerId FROM Lead WHERE Id = :j.Lead__c AND Owner.Type = 'User']) {
                owner = l.OwnerId;
            }
        }
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
        if (knockedOut(l.Id)) {
            throw new BandhuException('This lead is knocked out at a stage gate (see the Qualification gates), so it is not nudged.');
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
            if (knockedOut(j.Lead__c)) {
                continue;
            }
            rmTask(j, 'Bandhu: card applicant dropped at ' + stepLabel(j) + ' - ' + BandhuEngine.label(j),
                'Dropped at ' + j.Drop_Point__c + '. ' + (j.Recommended_Card__c == null ? '' : 'Recommended: ' + j.Recommended_Card__c + '. ')
                + 'Nudge on WhatsApp from the Lead page, or call.');
        }
    }

    private static Id rmId(String regionUsername) {
        String username = String.isNotBlank(regionUsername) ? regionUsername : BandhuConfig.get().RM_Username__c;
        if (String.isBlank(username)) {
            return null;
        }
        for (User u : [SELECT Id FROM User WHERE Username = :username AND IsActive = TRUE LIMIT 1]) {
            return u.Id;
        }
        return null;
    }
}
