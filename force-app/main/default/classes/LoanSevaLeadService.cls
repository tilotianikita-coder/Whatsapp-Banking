/**
 * New-to-bank drop-off -> Lead -> intent and credit scores -> qualification gates -> RM -> WhatsApp nudge -> resume.
 *
 *  1. captureDropOffs (drop-off job): a prospect with no Contact who goes quiet becomes (or updates) a Lead, with the
 *     intent score (LoanSevaLeadScoring), the qualification gates and credit score (LoanSevaQualification: serviceability,
 *     consent, Hunter, CIBIL soft pull, income and FOIR, employment) and the two combined into the Rating. Leads are owned
 *     by the region's RM, who gets a call task; a knocked-out lead (not serviceable, fraud, CIBIL, FOIR) is Unqualified
 *     with a completed activity saying why, and no call task. The automatic re-engagement nudges are off for these
 *     journeys: the RM nudges.
 *  2. nudge (RM, from the Lead page): sends a WhatsApp message saying the application is saved, marks the Lead Working.
 *  3. markResumed (customer replies Continue): the journey picks up at the same step; the Lead records when.
 *  4. convert (application submitted): the Lead converts into the new customer's Contact.
 *
 * Without sharing: the agent user updates Leads owned by RMs.
 */
public without sharing class LoanSevaLeadService {
    public static final String SOURCE = 'LoanSeva WhatsApp';
    public static final String STATUS_NEW = 'New';
    public static final String STATUS_WORKING = 'Working';
    public static final String STATUS_UNQUALIFIED = 'Unqualified';

    private static final Map<String, String> STEP_LABELS = new Map<String, String>{
        'menu' => 'Welcome menu', 'identity' => 'Name and mobile', 'otp' => 'OTP', 'dob' => 'Date of birth', 'pan' => 'PAN',
        'email' => 'Email', 'pincode' => 'PIN code', 'employment' => 'Employment type', 'company' => 'Company',
        'income' => 'Monthly income', 'obligations' => 'Existing EMIs', 'purpose' => 'Purpose', 'amount' => 'Loan amount',
        'offer_decision' => 'Offer', 'doc_pan' => 'Documents', 'doc_bank' => 'Documents', 'doc_salary' => 'Documents',
        'consent' => 'Review and consent', 'bureau_consent' => 'Credit check consent'
    };

    /** The step a journey is waiting on, in RM words ("Monthly income"). */
    public static String stepLabel(Loan_Journey__c j) {
        String state = LoanSevaEngine.awaiting(j);
        return STEP_LABELS.containsKey(state) ? STEP_LABELS.get(state) : state;
    }

    /** Drop-off job, for journeys without a Contact. Upserts the Leads and links them; returns the RM tasks to insert. */
    public static List<Task> captureDropOffs(List<Loan_Journey__c> journeys) {
        List<Task> tasks = new List<Task>();
        if (journeys.isEmpty()) {
            return tasks;
        }
        Set<Id> leadIds = new Set<Id>();
        Set<String> mobiles = new Set<String>();
        for (Loan_Journey__c j : journeys) {
            if (j.Lead__c != null) {
                leadIds.add(j.Lead__c);
            }
            if (String.isNotBlank(j.Mobile__c)) {
                mobiles.add(j.Mobile__c);
            }
        }
        Map<Id, Lead> byId = new Map<Id, Lead>();
        Map<String, Lead> byMobile = new Map<String, Lead>();
        for (Lead l : [
            SELECT Id, FirstName, LastName, MobilePhone, Company, LeadSource, Status
            FROM Lead
            WHERE (Id IN :leadIds OR MobilePhone IN :mobiles) AND IsConverted = FALSE
            ORDER BY CreatedDate ASC
        ]) {
            byId.put(l.Id, l);
            if (!byMobile.containsKey(l.MobilePhone)) {
                byMobile.put(l.MobilePhone, l);
            }
        }

        List<Lead> leads = new List<Lead>();
        List<LoanSevaLeadScoring.Score> scores = new List<LoanSevaLeadScoring.Score>();
        List<LoanSevaServiceability.Region> regions = new List<LoanSevaServiceability.Region>();
        List<LoanSevaQualification.Outcome> outcomes = new List<LoanSevaQualification.Outcome>();
        for (Loan_Journey__c j : journeys) {
            Lead l = j.Lead__c != null && byId.containsKey(j.Lead__c) ? byId.get(j.Lead__c) : byMobile.get(j.Mobile__c);
            if (l == null) {
                l = new Lead(Company = 'Individual', LeadSource = SOURCE);
                if (String.isNotBlank(j.Mobile__c)) {
                    byMobile.put(j.Mobile__c, l);
                }
            }
            LoanSevaLeadScoring.Score score = LoanSevaLeadScoring.score(j);
            LoanSevaServiceability.Region region = LoanSevaServiceability.forPin(j.PIN_Code__c);
            // no callouts here: providers that call out use their earlier result from the in-journey run
            LoanSevaQualification.Outcome outcome = LoanSevaQualification.evaluate(j, false);
            fill(l, j, score, region, outcome);
            if (!leads.contains(l)) {
                leads.add(l);
            }
            scores.add(score);
            regions.add(region);
            outcomes.add(outcome);
        }
        upsert leads;

        for (Integer i = 0; i < journeys.size(); i++) {
            Loan_Journey__c j = journeys[i];
            Lead l = j.Lead__c != null && byId.containsKey(j.Lead__c) ? byId.get(j.Lead__c) : byMobile.get(j.Mobile__c);
            j.Lead__c = l.Id;
            LoanSevaQualification.apply(j, outcomes[i]);
            // the RM nudges these prospects; no automatic re-engagement
            j.Next_Nudge_At__c = null;
            if (regions[i].serviceable && !outcomes[i].knockedOut() && j.RM_Followup_Created__c != true) {
                tasks.add(rmTask(j, l, scores[i], regions[i], outcomes[i]));
                j.RM_Followup_Created__c = true;
            } else if (j.RM_Followup_Created__c != true) {
                // no call for the RM, but the Lead's activity records why
                tasks.add(closedTask(j, l, scores[i], regions[i], outcomes[i]));
                j.RM_Followup_Created__c = true;
            }
        }
        LoanSevaQualification.save(journeys, outcomes);
        return tasks;
    }

    private static void fill(Lead l, Loan_Journey__c j, LoanSevaLeadScoring.Score score, LoanSevaServiceability.Region region,
            LoanSevaQualification.Outcome outcome) {
        if (String.isNotBlank(j.Customer_Name__c)) {
            List<String> parts = j.Customer_Name__c.normalizeSpace().split(' ');
            l.LastName = parts.remove(parts.size() - 1);
            l.FirstName = parts.isEmpty() ? null : String.join(parts, ' ');
        } else if (String.isBlank(l.LastName)) {
            l.LastName = 'WhatsApp prospect ' + (j.Mobile__c == null ? '' : j.Mobile__c.right(4));
        }
        l.MobilePhone = j.Mobile__c;
        if (String.isNotBlank(j.Email__c) && j.Email__c.contains('@')) {
            l.Email = j.Email__c;
        }
        if (String.isNotBlank(j.PIN_Code__c)) {
            l.PostalCode = j.PIN_Code__c;
        }
        if (String.isNotBlank(j.City__c)) {
            l.City = j.City__c;
        }
        if (String.isBlank(l.Company)) {
            l.Company = 'Individual';
        }
        if (String.isBlank(l.LeadSource) || l.LeadSource == 'Other') {
            l.LeadSource = SOURCE;
        }
        LoanSevaQualification.fillLead(l, j, outcome, score);
        l.LoanSeva_Region__c = region.name.abbreviate(80);
        l.LoanSeva_Serviceable__c = region.serviceable;
        l.LoanSeva_Drop_Point__c = stepLabel(j).abbreviate(255);
        l.LoanSeva_Journey__c = j.Id;
        l.Description = LoanSevaJourneyService.rmDescription(j).abbreviate(32000);
        if (!region.serviceable || outcome.knockedOut()) {
            l.Status = STATUS_UNQUALIFIED;
        } else if (String.isBlank(l.Status) || l.Status == STATUS_UNQUALIFIED) {
            l.Status = STATUS_NEW;
        }
        l.OwnerId = region.rmId != null ? region.rmId : LoanSevaJourneyService.rmOwnerId(j);
    }

    private static Task rmTask(Loan_Journey__c j, Lead l, LoanSevaLeadScoring.Score score, LoanSevaServiceability.Region region,
            LoanSevaQualification.Outcome outcome) {
        Task t = LoanSevaJourneyService.buildRmTask(
            j,
            l.Rating + ' lead ' + l.LoanSeva_Combined_Score__c + '/100 (' + region.name + ') dropped at ' + stepLabel(j) + ': nudge on WhatsApp',
            'New-to-bank prospect went quiet at ' + stepLabel(j) + '. Open the Lead and use "Nudge on WhatsApp": the journey '
                + 'picks up from the same step.\n\nStage gate: ' + outcome.stageGate()
                + (outcome.eligibility == null ? '' : '\nIndicative eligibility: up to ' + LoanSevaI18n.inr(outcome.eligibility) + ' (subject to verification)')
                + '\n\nIntent\n' + score.detail() + '\n\nCredit\n' + outcome.credit.detail()
                + '\n\nCombined: ' + l.LoanSeva_Combined_Score__c + '/100 (' + l.Rating + ')\n\n' + LoanSevaJourneyService.rmDescription(j),
            null
        );
        t.OwnerId = l.OwnerId;
        t.Priority = l.Rating == 'Hot' ? 'High' : l.Rating == 'Warm' ? 'Normal' : 'Low';
        return t;
    }

    /** A completed activity on an Unqualified lead: not serviceable or knocked out, so no RM call. */
    private static Task closedTask(Loan_Journey__c j, Lead l, LoanSevaLeadScoring.Score score, LoanSevaServiceability.Region region,
            LoanSevaQualification.Outcome outcome) {
        String why = !region.serviceable
            ? 'PIN code ' + j.PIN_Code__c + ' is outside the serviceable regions'
            : 'Knocked out at ' + outcome.gate + ': ' + outcome.knockout;
        Task t = LoanSevaJourneyService.buildRmTask(
            j,
            'Unqualified lead ' + l.LoanSeva_Combined_Score__c + '/100 dropped at ' + stepLabel(j) + ': ' + why,
            'New-to-bank prospect went quiet at ' + stepLabel(j) + '. ' + why + ', so there is no RM call or WhatsApp nudge.\n\n'
                + 'Stage gate: ' + outcome.stageGate() + '\n\nIntent\n' + score.detail() + '\n\nCredit\n' + outcome.credit.detail()
                + '\n\nCombined: ' + l.LoanSeva_Combined_Score__c + '/100 (' + l.Rating + ')\n\n' + LoanSevaJourneyService.rmDescription(j),
            null
        );
        t.OwnerId = l.OwnerId;
        t.Status = 'Completed';
        t.Priority = 'Low';
        t.Type = 'Other';
        return t;
    }

    // ------------------------------------------------------------------ RM nudge
    /** The WhatsApp message the RM's nudge sends, in the customer's language. */
    public static String nudgeText(Loan_Journey__c j, String rmName) {
        Integer done = LoanSevaLeadScoring.answeredSteps(j);
        String key = done > 0 || j.OTP_Verified__c == true ? 'NL_RM_Nudge' : 'NL_RM_Nudge_Start';
        String name = LoanSevaJourneyService.firstName(j);
        String body = LoanSevaI18n.msg(key, j.Language__c, new Map<String, Object>{
            'name' => String.isBlank(name) ? '' : ' ' + name,
            'rm' => String.isBlank(rmName) ? 'Kotak' : rmName,
            'done' => done,
            'total' => LoanSevaNewLoan.FIELDS.size()
        });
        // the indicative amount sharpens the nudge, always worded as subject to verification; it goes before the call to action
        Integer cut = body.lastIndexOf('\n\n');
        if (j.Indicative_Eligibility__c != null && j.Indicative_Eligibility__c > 0 && j.Qualification_Status__c != LoanSevaQualification.KNOCKED_OUT && cut > 0) {
            body = body.left(cut) + '\n\n' + LoanSevaI18n.msg('NL_RM_Nudge_Eligible', j.Language__c, new Map<String, Object>{
                'amount' => LoanSevaI18n.inr(j.Indicative_Eligibility__c)
            }) + body.substring(cut);
        }
        return body;
    }

    /** Sends the RM's WhatsApp nudge for the Lead's journey. Returns the text sent. */
    public static String nudge(Id leadId) {
        Lead l = [
            SELECT Id, Status, LoanSeva_Journey__c, LoanSeva_Serviceable__c, IsConverted
            FROM Lead WHERE Id = :leadId
        ];
        if (l.LoanSeva_Journey__c == null) {
            throw new LoanSevaException('This lead has no LoanSeva WhatsApp journey to pick up.');
        }
        if (l.IsConverted) {
            throw new LoanSevaException('This lead is already a customer.');
        }
        if (!l.LoanSeva_Serviceable__c) {
            throw new LoanSevaException('The customer\'s PIN code is outside the serviceable regions.');
        }
        Loan_Journey__c j = LoanSevaJourneyService.byId(l.LoanSeva_Journey__c);
        if (j.Qualification_Status__c == LoanSevaQualification.KNOCKED_OUT) {
            throw new LoanSevaException('The lead was knocked out at ' + j.Qualification_Gate__c + ': ' + j.Knockout_Reason__c);
        }
        if (j.Status__c == LoanSevaJourneyService.STATUS_COMPLETED || j.Status__c == LoanSevaJourneyService.STATUS_EXITED) {
            throw new LoanSevaException('The journey is already ' + j.Status__c.toLowerCase() + '.');
        }
        if (String.isBlank(j.Mobile__c)) {
            throw new LoanSevaException('The journey has no WhatsApp number.');
        }
        String body = nudgeText(j, UserInfo.getFirstName());
        Datetime now = Datetime.now();

        j.Nudges_Sent__c = (j.Nudges_Sent__c == null ? 0 : j.Nudges_Sent__c) + 1;
        update new Loan_Journey__c(Id = j.Id, Nudges_Sent__c = j.Nudges_Sent__c);
        l.Status = STATUS_WORKING;
        l.LoanSeva_Last_Nudged__c = now;
        update l;

        List<Task> open = [SELECT Id FROM Task WHERE WhoId = :leadId AND IsClosed = FALSE AND Subject LIKE 'LoanSeva:%'];
        for (Task t : open) {
            t.Status = 'Completed';
        }
        Task sent = LoanSevaJourneyService.buildRmTask(j, 'WhatsApp nudge sent', body, LoanSevaI18n.todayIst());
        sent.OwnerId = UserInfo.getUserId();
        sent.Status = 'Completed';
        sent.Priority = 'Normal';
        sent.Type = 'Other';
        open.add(sent);
        upsert open;

        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        LoanSevaWhatsAppSender.enqueue(new List<LoanSevaWhatsAppSender.Outbound>{
            new LoanSevaWhatsAppSender.Outbound(j.Id, body, cfg.Reengage_Definition__c)
        });
        return body;
    }

    // ------------------------------------------------------------------ Resume and conversion
    /** The customer came back to a dropped journey. */
    public static void markResumed(Loan_Journey__c j) {
        if (j.Lead__c == null) {
            return;
        }
        List<Lead> leads = [SELECT Id FROM Lead WHERE Id = :j.Lead__c AND IsConverted = FALSE];
        for (Lead l : leads) {
            l.LoanSeva_Resumed_At__c = Datetime.now();
        }
        update leads;
    }

    public static final String EVENT_CONVERT = 'ConvertLead';

    /**
     * The prospect submitted the application: the Lead converts into the new customer's Contact. The agent user's
     * licence can't convert Leads, so this publishes a LoanSeva_Event__e handled as the admin subscriber user.
     */
    public static void convert(Loan_Journey__c j) {
        if (j.Lead__c != null && j.Contact__c != null) {
            EventBus.publish(new LoanSeva_Event__e(Event_Type__c = EVENT_CONVERT, Source__c = j.Id));
        }
    }

    /** Event subscriber: converts each journey's Lead into its Contact; Qualified if it can't. Never throws. */
    public static void convertJourneys(Set<Id> journeyIds) {
        List<LeadStatus> converted = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE ORDER BY SortOrder LIMIT 1];
        for (Loan_Journey__c j : [
            SELECT Id, Lead__c, Contact__c, Contact__r.AccountId FROM Loan_Journey__c
            WHERE Id IN :journeyIds AND Lead__c != null AND Contact__c != null AND Lead__r.IsConverted = FALSE
        ]) {
            Savepoint sp = Database.setSavepoint();
            try {
                if (j.Contact__r.AccountId == null || converted.isEmpty()) {
                    throw new LoanSevaException('No account or converted status');
                }
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(j.Lead__c);
                lc.setContactId(j.Contact__c);
                lc.setAccountId(j.Contact__r.AccountId);
                lc.setDoNotCreateOpportunity(true);
                lc.setConvertedStatus(converted[0].MasterLabel);
                Database.convertLead(lc);
            } catch (Exception e) {
                Database.rollback(sp);
                System.debug(LoggingLevel.WARN, 'LoanSeva lead conversion skipped: ' + e.getMessage());
                Database.update(new Lead(Id = j.Lead__c, Status = 'Qualified'), false);
            }
        }
    }
}
