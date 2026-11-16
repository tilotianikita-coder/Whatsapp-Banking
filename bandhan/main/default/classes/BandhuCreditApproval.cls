/**
 * NSTP card upgrades and higher limits, with maker-checker approval up the card credit hierarchy.
 *
 * Only for applications in the underwriter's queue (Under Review: referred, not straight-through). The underwriter
 * proposes a higher card and / or a limit above the card policy, records the findings and a reason, and the rules pick
 * the approval level; the request is assigned to an approver at that level (the requester's manager chain first, then
 * anyone holding the level). The approver approves, rejects or returns it for more information.
 *
 * Hierarchy (User.Bandhu_Credit_Level__c, caps in Bandhu_Credit_Authority__mdt; PLACEHOLDERS for Bandhan's credit policy):
 *   L1 Credit Underwriter          total limit up to ₹3L,  at the policy limit,    up to 3x monthly income, no upgrade
 *   L2 Senior Credit Manager       up to ₹5L,   up to 25% over policy,  4x income, 1 tier up,  income ≥ 90% of the new card's minimum
 *   L3 Regional Credit Head        up to ₹10L,  up to 50% over policy,  5x income, 2 tiers up, income ≥ 80%
 *   L4 Chief Credit Officer        up to ₹25L,  up to 100% over policy, 6x income, 3 tiers up, income ≥ 70%
 * The required level is the lowest whose every cap covers the request, then the risk rules raise it:
 *   +1  CIBIL below 750 (Good or Fair)            +1  a Refer on Credit Bureau or Dedupe & Fraud
 *   +1  income not verified (no AA / document)    +1  FOIR above 50% in the bank statements
 *   →L4 a written-off or settled account on the bureau report
 * Hard stops (no approver can override): a Fail on any check, CIBIL below 650, income below 70% of the new card's
 * minimum, a limit over ₹25L, the proposer approving their own request.
 * A card upgrade is issued only with the customer's consent (RBI MD on Credit Cards 2022): approved → the customer is
 * offered the upgrade on WhatsApp; Yes issues it, No issues the applied-for card at the approved limit.
 */
public with sharing class BandhuCreditApproval {
    public static final Integer TOP_LEVEL = 4;
    public static final Decimal ABSOLUTE_MAX = 2500000;
    public static final Decimal HARD_STOP_CIBIL = 650;
    public static final String PENDING = 'Pending';

    public class Assessment {
        @AuraEnabled public Integer level;
        @AuraEnabled public String title;
        @AuraEnabled public List<String> reasons = new List<String>();
        @AuraEnabled public List<String> hardStops = new List<String>();
        @AuraEnabled public Decimal policyLimit;
        @AuraEnabled public Decimal proposedLimit;
        @AuraEnabled public Decimal overPolicyPct;
        @AuraEnabled public Decimal incomeMultiple;
        @AuraEnabled public Integer tiersUp;
        @AuraEnabled public String requestType;
        @AuraEnabled public Boolean allowed;
    }

    public class Approver {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public Integer level;
        @AuraEnabled public Boolean inChain;     // in the requester's manager chain
    }

    public class Panel {
        @AuraEnabled public Boolean eligible = false;          // the application can take a request
        @AuraEnabled public String notEligibleReason;
        @AuraEnabled public Bandhu_Credit_Approval__c open;    // the pending / approved request, if any
        @AuraEnabled public List<Bandhu_Credit_Approval__c> history = new List<Bandhu_Credit_Approval__c>();
        @AuraEnabled public Boolean canDecide = false;         // the running user may decide the open request
        @AuraEnabled public Boolean onBehalf = false;          // ...as an administrator on behalf of the approver
        @AuraEnabled public Boolean isRequester = false;
        @AuraEnabled public String currentCard;
        @AuraEnabled public Integer currentTier;
        @AuraEnabled public Decimal policyLimit;
        @AuraEnabled public Decimal income;
        @AuraEnabled public List<String> upgradeCards = new List<String>();
        @AuraEnabled public List<Authority> matrix = new List<Authority>();
        @AuraEnabled public Integer myLevel;
        @AuraEnabled public List<String> reasonCodes = new List<String>();
    }

    public class Authority {
        @AuraEnabled public Integer level;
        @AuraEnabled public String title;
        @AuraEnabled public Decimal maxLimit;
        @AuraEnabled public Decimal maxOverPolicyPct;
        @AuraEnabled public Decimal maxIncomeMultiple;
        @AuraEnabled public Integer maxUpgradeTiers;
        @AuraEnabled public Decimal minIncomePctUpgrade;
        @AuraEnabled public String holders;
    }

    // ------------------------------------------------------------------ the rules
    public static List<Bandhu_Credit_Authority__mdt> levels() {
        List<Bandhu_Credit_Authority__mdt> l = Bandhu_Credit_Authority__mdt.getAll().values();
        List<Bandhu_Credit_Authority__mdt> sorted = new List<Bandhu_Credit_Authority__mdt>();
        for (Integer lv = 1; lv <= TOP_LEVEL; lv++) {
            for (Bandhu_Credit_Authority__mdt a : l) {
                if (a.Level__c == lv) {
                    sorted.add(a);
                }
            }
        }
        return sorted;
    }

    private static Bandhu_Credit_Authority__mdt level(Integer lv) {
        for (Bandhu_Credit_Authority__mdt a : levels()) {
            if (a.Level__c == lv) {
                return a;
            }
        }
        return null;
    }

    private static Card_Application__c load(Id appId) {
        return [
            SELECT Id, Name, Status__c, Card_Product__c, Credit_Limit__c, Monthly_Income__c, Verified_Income__c, CIBIL_Score__c,
                Applicant_Name__c, Reference_Number__c, Card_Journey__c, Recommendation__c, Customer_Type__c, Eligible_Cards__c
            FROM Card_Application__c WHERE Id = :appId
        ];
    }

    private static Decimal income(Card_Application__c a) {
        return a.Verified_Income__c != null ? a.Verified_Income__c : a.Monthly_Income__c;
    }

    /** The limit the card policy gave for the applied-for card (the application's limit, else the card's formula). */
    public static Decimal policyLimit(Card_Application__c a) {
        if (a.Credit_Limit__c != null) {
            return a.Credit_Limit__c;
        }
        Bandhu_Card__mdt c = BandhuConfig.card(a.Card_Product__c);
        return c == null ? null : BandhuEligibility.limitFor(c, income(a));
    }

    /** Which level must approve this proposal, and why; hard stops make it not allowed. */
    public static Assessment assess(Id appId, String proposedCard, Decimal proposedLimit) {
        Card_Application__c a = load(appId);
        Assessment r = new Assessment();
        Bandhu_Card__mdt current = BandhuConfig.card(a.Card_Product__c);
        Bandhu_Card__mdt target = String.isBlank(proposedCard) ? current : BandhuConfig.card(proposedCard);
        if (target == null) {
            throw new BandhuException('Unknown card: ' + proposedCard);
        }
        Decimal inc = income(a);
        r.policyLimit = policyLimit(a);
        r.tiersUp = current == null ? 0 : Math.max(0, target.Tier__c.intValue() - current.Tier__c.intValue());
        // no limit entered: the policy limit of the card proposed (an upgrade gets the new card's own policy limit)
        Decimal lim = proposedLimit != null ? proposedLimit
            : current != null && target.Tier__c > current.Tier__c ? BandhuEligibility.limitFor(target, inc) : r.policyLimit;
        r.proposedLimit = lim;
        Boolean higherLimit = lim != null && r.policyLimit != null && lim > r.policyLimit;
        r.requestType = r.tiersUp > 0 && higherLimit ? 'Card upgrade and limit' : r.tiersUp > 0 ? 'Card upgrade' : 'Limit increase';
        r.overPolicyPct = r.policyLimit == null || r.policyLimit == 0 || lim == null ? 0
            : Math.max(0, ((lim - r.policyLimit) / r.policyLimit * 100).setScale(1));
        // an upgrade is measured against the new card's own policy limit, not the old card's
        if (r.tiersUp > 0 && lim != null) {
            Decimal targetPolicy = BandhuEligibility.limitFor(target, inc);
            r.overPolicyPct = targetPolicy == null || targetPolicy == 0 ? 0 : Math.max(0, ((lim - targetPolicy) / targetPolicy * 100).setScale(1));
        }
        r.incomeMultiple = inc == null || inc == 0 || lim == null ? null : (lim / inc).setScale(1);
        Decimal incomePct = inc == null || target.Min_Monthly_Income__c == null || target.Min_Monthly_Income__c == 0 ? 100
            : (inc / target.Min_Monthly_Income__c * 100).setScale(0);

        // hard stops
        if (a.Status__c != 'Under Review') {
            r.hardStops.add('Only applications in the underwriter queue (NSTP, Under Review) can be sent for approval; this one is ' + a.Status__c);
        }
        if (r.tiersUp == 0 && !higherLimit) {
            r.hardStops.add('Nothing to approve: propose a higher card or a limit above the policy limit (' + BandhuI18n.inr(r.policyLimit) + ')');
        }
        if (current != null && target.Tier__c < current.Tier__c) {
            r.hardStops.add('A lower card is not an upgrade: decide it on the application instead');
        }
        List<Card_Check__c> checks = [SELECT Check__c, Result__c, Summary__c FROM Card_Check__c WHERE Card_Application__c = :appId];
        Boolean bureauRefer = false;
        Boolean fraudRefer = false;
        Boolean incomeVerified = a.Verified_Income__c != null;
        for (Card_Check__c c : checks) {
            if (c.Result__c == 'Fail') {
                r.hardStops.add('Failed check: ' + c.Check__c + ' (' + c.Summary__c + ')');
            }
            if (c.Result__c == 'Refer' && c.Check__c == 'Credit Bureau') {
                bureauRefer = true;
            }
            if (c.Result__c == 'Refer' && c.Check__c == 'Dedupe & Fraud') {
                fraudRefer = true;
            }
            if (c.Check__c == 'Income Verification' && c.Result__c == 'Pass') {
                incomeVerified = true;
            }
        }
        if (a.CIBIL_Score__c != null && a.CIBIL_Score__c < HARD_STOP_CIBIL) {
            r.hardStops.add('CIBIL ' + a.CIBIL_Score__c.intValue() + ' below ' + HARD_STOP_CIBIL.intValue() + ': no upgrade or higher limit');
        }
        if (r.tiersUp > 0 && incomePct < level(TOP_LEVEL).Min_Income_Pct_Upgrade__c) {
            r.hardStops.add('Income ' + BandhuI18n.inr(inc) + ' is ' + incomePct + '% of the ' + target.DeveloperName + ' minimum ('
                + BandhuI18n.inr(target.Min_Monthly_Income__c) + '); the floor for any approver is ' + level(TOP_LEVEL).Min_Income_Pct_Upgrade__c.intValue() + '%');
        }
        if (lim != null && lim > ABSOLUTE_MAX) {
            r.hardStops.add('Limit ' + BandhuI18n.inr(lim) + ' above the card maximum of ' + BandhuI18n.inr(ABSOLUTE_MAX));
        }

        // the lowest level whose caps all cover the request
        Integer need = TOP_LEVEL;
        for (Bandhu_Credit_Authority__mdt lv : levels()) {
            Boolean fits = (lim == null || lim <= lv.Max_Limit__c)
                && r.overPolicyPct <= lv.Max_Over_Policy_Pct__c
                && (r.incomeMultiple == null || r.incomeMultiple <= lv.Max_Income_Multiple__c)
                && r.tiersUp <= lv.Max_Upgrade_Tiers__c
                && (r.tiersUp == 0 || incomePct >= lv.Min_Income_Pct_Upgrade__c);
            if (fits) {
                need = lv.Level__c.intValue();
                break;
            }
        }
        // the deviation itself always needs someone above the underwriter
        need = Math.max(need, 2);
        r.reasons.add('L' + need + ' by size: ' + describe(r, lim, target, incomePct));
        Integer base = need;

        // risk rules raise the level
        BandhuCashFlow.Analysis cf = a.Card_Journey__c == null ? null : BandhuCashFlow.fromJourney(BandhuJourneyService.byId(a.Card_Journey__c));
        BandhuBureau.Report br = a.Card_Journey__c == null ? null : BandhuBureau.fromJourney(BandhuJourneyService.byId(a.Card_Journey__c));
        if (a.CIBIL_Score__c != null && a.CIBIL_Score__c < 750 && a.CIBIL_Score__c >= HARD_STOP_CIBIL) {
            need++;
            r.reasons.add('+1: CIBIL ' + a.CIBIL_Score__c.intValue() + ' (' + BandhuBureau.band(a.CIBIL_Score__c.intValue()) + ', below 750)');
        }
        if (bureauRefer || fraudRefer) {
            need++;
            r.reasons.add('+1: ' + (bureauRefer && fraudRefer ? 'Credit Bureau and Dedupe & Fraud' : bureauRefer ? 'Credit Bureau' : 'Dedupe & Fraud') + ' referred');
        }
        if (!incomeVerified) {
            need++;
            r.reasons.add('+1: income not verified (no Account Aggregator or income document)');
        }
        if (cf != null && cf.foirPct > 50) {
            need++;
            r.reasons.add('+1: FOIR ' + cf.foirPct + '% in the bank statements (above 50%)');
        }
        if (br != null && (br.writtenOff || br.settled)) {
            need = TOP_LEVEL;
            r.reasons.add('→L4: ' + (br.writtenOff ? 'written-off' : 'settled') + ' account on the bureau report');
        }
        r.level = Math.min(TOP_LEVEL, need);
        if (r.reasons.size() == 1) {
            r.reasons.add('No risk rule raises the level');
        }
        Bandhu_Credit_Authority__mdt lvl = level(r.level);
        r.title = lvl == null ? 'Level ' + r.level : lvl.Title__c;
        r.allowed = r.hardStops.isEmpty();
        return r;
    }

    private static String describe(Assessment r, Decimal lim, Bandhu_Card__mdt target, Decimal incomePct) {
        List<String> p = new List<String>();
        if (r.tiersUp > 0) {
            p.add(r.tiersUp + ' tier' + (r.tiersUp > 1 ? 's' : '') + ' up to ' + target.DeveloperName + ' (income ' + incomePct + '% of its minimum)');
        }
        if (lim != null) {
            p.add('limit ' + BandhuI18n.inr(lim) + (r.overPolicyPct > 0 ? ', ' + r.overPolicyPct + '% over policy' : ', within policy'));
        }
        if (r.incomeMultiple != null) {
            p.add(r.incomeMultiple + 'x monthly income');
        }
        return String.join(p, ' · ');
    }

    // ------------------------------------------------------------------ approvers
    public static Integer levelOf(Id userId) {
        for (User u : [SELECT Bandhu_Credit_Level__c FROM User WHERE Id = :userId]) {
            return u.Bandhu_Credit_Level__c == null ? null : u.Bandhu_Credit_Level__c.intValue();
        }
        return null;
    }

    /** Approvers at or above the level: the requester's manager chain first, then others by level. Never the requester. */
    public static List<Approver> approvers(Integer minLevel, Id requesterId) {
        Set<Id> chain = new Set<Id>();
        Id cursor = requesterId;
        for (Integer i = 0; i < 6 && cursor != null; i++) {
            User u = [SELECT ManagerId FROM User WHERE Id = :cursor];
            cursor = u.ManagerId;
            if (cursor != null) {
                chain.add(cursor);
            }
        }
        List<Approver> first = new List<Approver>();
        List<Approver> rest = new List<Approver>();
        for (User u : [SELECT Id, Name, Title, Bandhu_Credit_Level__c FROM User WHERE IsActive = true AND Bandhu_Credit_Level__c >= :minLevel
                       AND Id != :requesterId ORDER BY Bandhu_Credit_Level__c ASC, Name ASC LIMIT 50]) {
            Approver a = new Approver();
            a.id = u.Id;
            a.name = u.Name;
            a.level = u.Bandhu_Credit_Level__c.intValue();
            Bandhu_Credit_Authority__mdt lv = level(a.level);
            a.title = lv == null ? u.Title : lv.Title__c;
            a.inChain = chain.contains(u.Id);
            (a.inChain ? first : rest).add(a);
        }
        first.addAll(rest);
        return first;
    }

    // ------------------------------------------------------------------ submit
    public static Bandhu_Credit_Approval__c submit(Id appId, String proposedCard, Decimal proposedLimit, Id approverId, String reasonCode,
                                                   String findings, String mitigants) {
        if (String.isBlank(findings) || findings.trim().length() < 20) {
            throw new BandhuException('Please document your findings (at least a sentence): what you saw and why the deviation is justified.');
        }
        if (String.isBlank(reasonCode)) {
            throw new BandhuException('Please pick a reason.');
        }
        if (![SELECT Id FROM Bandhu_Credit_Approval__c WHERE Card_Application__c = :appId
               AND (Status__c = 'Pending' OR (Status__c = 'Approved' AND Customer_Consent__c = 'Pending'))].isEmpty()) {
            throw new BandhuException('There is already an open credit request on this application.');
        }
        Assessment r = assess(appId, proposedCard, proposedLimit);
        if (!r.allowed) {
            throw new BandhuException(String.join(r.hardStops, '. '));
        }
        Integer approverLevel = levelOf(approverId);
        if (approverId == UserInfo.getUserId()) {
            throw new BandhuException('Maker-checker: you cannot approve your own request. Assign it to someone above you.');
        }
        if (approverLevel == null || approverLevel < r.level) {
            throw new BandhuException('This request needs L' + r.level + ' (' + r.title + ') or above; the person you picked is '
                + (approverLevel == null ? 'not in the card credit hierarchy' : 'L' + approverLevel) + '.');
        }
        Card_Application__c a = load(appId);
        Bandhu_Credit_Approval__c req = new Bandhu_Credit_Approval__c(
            Card_Application__c = appId, Request_Type__c = r.requestType, Current_Card__c = a.Card_Product__c,
            Proposed_Card__c = String.isBlank(proposedCard) ? a.Card_Product__c : proposedCard, Policy_Limit__c = r.policyLimit,
            Proposed_Limit__c = r.proposedLimit, Over_Policy_Pct__c = r.overPolicyPct,
            Income_Multiple__c = r.incomeMultiple, Required_Level__c = r.level, Required_Title__c = r.title,
            Level_Reasons__c = String.join(r.reasons, '\n'), Reason_Code__c = reasonCode, Findings__c = findings, Mitigants__c = mitigants,
            Requested_By__c = UserInfo.getUserId(), Requested_At__c = Datetime.now(), Status__c = PENDING, OwnerId = approverId,
            Customer_Consent__c = r.tiersUp > 0 ? 'Pending' : 'Not needed');
        insert req;
        a.Status__c = 'Pending Approval';
        update a;
        insert new Task(Subject = ('Bandhu: approve ' + r.requestType.toLowerCase() + ' - ' + a.Applicant_Name__c).abbreviate(255), OwnerId = approverId,
            WhatId = req.Id, Priority = 'High', Status = 'Not Started', ActivityDate = BandhuI18n.today(),
            Description = 'Requested by ' + UserInfo.getName() + ': ' + req.Proposed_Card__c + ' at ' + BandhuI18n.inr(req.Proposed_Limit__c)
                + ' (policy ' + BandhuI18n.inr(req.Policy_Limit__c) + ' on ' + req.Current_Card__c + '). Needs L' + r.level + ' ' + r.title + '.\n\nFindings: ' + findings);
        notify(approverId, req.Id, 'Card approval needed: ' + a.Applicant_Name__c,
            UserInfo.getName() + ' asks you to approve ' + req.Proposed_Card__c + ' at ' + BandhuI18n.inr(req.Proposed_Limit__c) + ' (needs L' + r.level + ').');
        return req;
    }

    // ------------------------------------------------------------------ decide
    /** decision: Approved / Rejected / Returned. Returns the customer message to send (null when none). */
    public static Bandhu_Credit_Approval__c decide(Id requestId, String decision, String notes) {
        Bandhu_Credit_Approval__c req = [
            SELECT Id, Status__c, OwnerId, Requested_By__c, Required_Level__c, Card_Application__c, Proposed_Card__c, Proposed_Limit__c,
                Current_Card__c, Policy_Limit__c, Request_Type__c, Customer_Consent__c
            FROM Bandhu_Credit_Approval__c WHERE Id = :requestId FOR UPDATE
        ];
        if (req.Status__c != PENDING) {
            throw new BandhuException('This request is already ' + req.Status__c.toLowerCase() + '.');
        }
        if (new Set<String>{ 'Approved', 'Rejected', 'Returned' }.contains(decision) == false) {
            throw new BandhuException('Unknown decision: ' + decision);
        }
        if ((decision == 'Rejected' || decision == 'Returned') && String.isBlank(notes)) {
            throw new BandhuException('Please add a note for the underwriter.');
        }
        Authority_Check auth = authority(req);
        if (!auth.ok) {
            throw new BandhuException(auth.message);
        }
        req.Status__c = decision;
        req.Decided_By__c = UserInfo.getUserId();
        req.Decided_At__c = Datetime.now();
        req.Decision_Notes__c = notes;
        req.On_Behalf__c = auth.onBehalf;
        if (auth.onBehalf) {
            req.Decision_Notes__c = (String.isBlank(notes) ? '' : notes + '\n') + 'Recorded by ' + UserInfo.getName() + ' on behalf of the assigned approver (demo setting).';
        }
        Card_Application__c a = load(req.Card_Application__c);
        if (decision == 'Approved') {
            Boolean upgrade = req.Proposed_Card__c != req.Current_Card__c;
            if (upgrade) {
                // RBI MD 2022: no card the customer didn't ask for without their explicit consent
                a.Status__c = 'Approved';
                req.Customer_Consent__c = 'Pending';
                update req;
                update a;
                offerUpgrade(a, req);
            } else {
                a.Credit_Limit__c = req.Proposed_Limit__c;
                a.Status__c = 'Under Review';
                update a;
                update req;
                BandhuDecision.decide(a.Id, 'Approved', 'Limit ' + BandhuI18n.inr(req.Proposed_Limit__c) + ' approved above policy by '
                    + UserInfo.getName() + ' (credit request).');
            }
        } else {
            a.Status__c = 'Under Review';
            update a;
            update req;
        }
        if (req.Requested_By__c != null) {
            insert new Task(Subject = ('Bandhu: credit request ' + decision.toLowerCase() + ' - ' + a.Applicant_Name__c).abbreviate(255),
                OwnerId = req.Requested_By__c, WhatId = a.Id, Priority = decision == 'Approved' ? 'Normal' : 'High', Status = 'Not Started',
                ActivityDate = BandhuI18n.today(), Description = (String.isBlank(req.Decision_Notes__c) ? '' : req.Decision_Notes__c));
            notify(req.Requested_By__c, a.Id, 'Credit request ' + decision.toLowerCase() + ': ' + a.Applicant_Name__c,
                UserInfo.getName() + ' ' + decision.toLowerCase() + ' the ' + req.Request_Type__c.toLowerCase() + (String.isBlank(notes) ? '' : ': ' + notes.abbreviate(150)));
        }
        closeTasks(req.Id);
        return req;
    }

    public class Authority_Check {
        public Boolean ok = false;
        public Boolean onBehalf = false;
        public String message;
    }

    /** May the running user decide this request? The assigned approver, anyone at the level (not the requester), or an admin on behalf (demo). */
    public static Authority_Check authority(Bandhu_Credit_Approval__c req) {
        Authority_Check c = new Authority_Check();
        Id me = UserInfo.getUserId();
        Integer mine = levelOf(me);
        Boolean demoOnBehalf = BandhuConfig.get().Approve_On_Behalf__c == true && isAdmin();
        if (me == req.Requested_By__c) {
            // maker-checker; the demo setting lets an administrator record the approver's decision, logged as on behalf
            c.ok = demoOnBehalf;
            c.onBehalf = demoOnBehalf;
            c.message = 'Maker-checker: you raised this request, so someone else has to decide it.';
            return c;
        }
        if (mine != null && mine >= req.Required_Level__c) {
            c.ok = true;
            return c;
        }
        if (demoOnBehalf) {
            c.ok = true;
            c.onBehalf = true;
            return c;
        }
        c.message = 'This needs L' + req.Required_Level__c.intValue() + ' or above; you are ' + (mine == null ? 'not in the card credit hierarchy' : 'L' + mine) + '.';
        return c;
    }

    private static Boolean isAdmin() {
        return [SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId()].PermissionsModifyAllData;
    }

    /** Withdraw a pending request (the requester or an admin): the application returns to the underwriter queue. */
    public static void withdraw(Id requestId) {
        Bandhu_Credit_Approval__c req = [SELECT Id, Status__c, Requested_By__c, Card_Application__c FROM Bandhu_Credit_Approval__c WHERE Id = :requestId];
        if (req.Status__c != PENDING) {
            throw new BandhuException('Only a pending request can be withdrawn.');
        }
        if (req.Requested_By__c != UserInfo.getUserId() && !isAdmin()) {
            throw new BandhuException('Only the underwriter who raised it can withdraw it.');
        }
        req.Status__c = 'Withdrawn';
        update req;
        update new Card_Application__c(Id = req.Card_Application__c, Status__c = 'Under Review');
        closeTasks(req.Id);
    }

    // ------------------------------------------------------------------ the customer's consent to an upgrade
    private static void offerUpgrade(Card_Application__c a, Bandhu_Credit_Approval__c req) {
        if (a.Card_Journey__c == null) {
            return;
        }
        Card_Journey__c j = BandhuJourneyService.byId(a.Card_Journey__c);
        j.Step__c = 'upgrade_offer';
        j.Status__c = BandhuJourneyService.STATUS_ACTIVE;
        j.Last_Activity__c = Datetime.now();
        update j;
        BandhuWhatsAppSender.enqueue(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(j.Id, offerText(j, a, req), null) });
    }

    public static String offerText(Card_Journey__c j, Card_Application__c a, Bandhu_Credit_Approval__c req) {
        Bandhu_Card__mdt c = BandhuConfig.card(req.Proposed_Card__c);
        String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
        String benefits = c == null ? '' : '✨ ' + c.Tagline__c + '\n• ' + c.Rewards__c + (String.isBlank(c.Accelerated__c) ? '' : '\n• ' + c.Accelerated__c)
            + '\n• ' + c.Lounge__c + '\n• ' + c.Fee_Waiver__c;
        return BandhuI18n.msg('Decision_Upgrade_Offer', j.Language__c, new Map<String, Object>{
            'name' => first, 'ref' => a.Reference_Number__c, 'card' => req.Proposed_Card__c, 'old' => req.Current_Card__c,
            'limit' => BandhuI18n.inr(req.Proposed_Limit__c), 'benefits' => benefits });
    }

    public static Bandhu_Credit_Approval__c pendingOffer(Id appId) {
        for (Bandhu_Credit_Approval__c r : [SELECT Id, Proposed_Card__c, Proposed_Limit__c, Current_Card__c, Policy_Limit__c, Customer_Consent__c
                                            FROM Bandhu_Credit_Approval__c WHERE Card_Application__c = :appId AND Status__c = 'Approved'
                                            AND Customer_Consent__c = 'Pending' ORDER BY Decided_At__c DESC LIMIT 1]) {
            return r;
        }
        return null;
    }

    /** WhatsApp / web reply to the upgrade offer: Yes issues the upgrade, No the applied-for card at the policy limit. */
    public static String respond(Card_Journey__c j, Boolean accepted) {
        Bandhu_Credit_Approval__c req = j.Card_Application__c == null ? null : pendingOffer(j.Card_Application__c);
        if (req == null) {
            j.Step__c = 'done';
            return BandhuI18n.msg('Done', j.Language__c);
        }
        req.Customer_Consent__c = accepted ? 'Accepted' : 'Declined';
        update req;
        Card_Application__c a = new Card_Application__c(Id = j.Card_Application__c, Status__c = 'Under Review',
            Card_Product__c = accepted ? req.Proposed_Card__c : req.Current_Card__c,
            Credit_Limit__c = accepted ? req.Proposed_Limit__c : Math.min(req.Policy_Limit__c, req.Proposed_Limit__c));
        update a;
        j.Chosen_Card__c = a.Card_Product__c;
        BandhuCompliance.record(j, 'Card upgrade', accepted ? 'Accepted the upgrade to ' + req.Proposed_Card__c + ' at ' + BandhuI18n.inr(req.Proposed_Limit__c)
            : 'Declined the upgrade; keeps the ' + req.Current_Card__c, 'UPGRADE-' + req.Id, null, null);
        update j;
        BandhuDecision.decide(a.Id, 'Approved', accepted ? 'Upgrade to ' + req.Proposed_Card__c + ' accepted by the customer (credit request approved).'
            : 'Customer kept the ' + req.Current_Card__c + ' (declined the approved upgrade).');
        String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
        return accepted ? null : BandhuI18n.msg('Upgrade_Kept', j.Language__c, new Map<String, Object>{ 'name' => first, 'card' => req.Current_Card__c });
    }

    // ------------------------------------------------------------------ the panel on the Card Application page
    public static Panel panel(Id appId) {
        Panel p = new Panel();
        Card_Application__c a = load(appId);
        Bandhu_Card__mdt current = BandhuConfig.card(a.Card_Product__c);
        p.currentCard = a.Card_Product__c;
        p.currentTier = current == null ? null : current.Tier__c.intValue();
        p.policyLimit = policyLimit(a);
        p.income = income(a);
        p.myLevel = levelOf(UserInfo.getUserId());
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            if (current == null || (c.Tier__c > current.Tier__c && c.Secured__c != true)) {
                p.upgradeCards.add(c.DeveloperName);
            }
        }
        for (Schema.PicklistEntry e : Bandhu_Credit_Approval__c.Reason_Code__c.getDescribe().getPicklistValues()) {
            p.reasonCodes.add(e.getValue());
        }
        Map<Integer, List<String>> holders = new Map<Integer, List<String>>();
        for (User u : [SELECT Name, Bandhu_Credit_Level__c FROM User WHERE IsActive = true AND Bandhu_Credit_Level__c != null ORDER BY Name LIMIT 100]) {
            Integer lv = u.Bandhu_Credit_Level__c.intValue();
            if (!holders.containsKey(lv)) {
                holders.put(lv, new List<String>());
            }
            holders.get(lv).add(u.Name);
        }
        for (Bandhu_Credit_Authority__mdt lv : levels()) {
            Authority m = new Authority();
            m.level = lv.Level__c.intValue();
            m.title = lv.Title__c;
            m.maxLimit = lv.Max_Limit__c;
            m.maxOverPolicyPct = lv.Max_Over_Policy_Pct__c;
            m.maxIncomeMultiple = lv.Max_Income_Multiple__c;
            m.maxUpgradeTiers = lv.Max_Upgrade_Tiers__c == null ? 0 : lv.Max_Upgrade_Tiers__c.intValue();
            m.minIncomePctUpgrade = lv.Min_Income_Pct_Upgrade__c;
            m.holders = holders.containsKey(m.level) ? String.join(holders.get(m.level), ', ') : 'No one assigned';
            p.matrix.add(m);
        }
        p.history = [
            SELECT Id, Name, Request_Type__c, Current_Card__c, Proposed_Card__c, Policy_Limit__c, Proposed_Limit__c, Over_Policy_Pct__c,
                Income_Multiple__c, Required_Level__c, Required_Title__c, Level_Reasons__c, Reason_Code__c, Findings__c, Mitigants__c,
                Requested_By__c, Requested_By__r.Name, Requested_At__c, Status__c, OwnerId, Owner.Name, Decided_By__r.Name, Decided_At__c,
                Decision_Notes__c, On_Behalf__c, Customer_Consent__c
            FROM Bandhu_Credit_Approval__c WHERE Card_Application__c = :appId ORDER BY CreatedDate DESC LIMIT 20
        ];
        for (Bandhu_Credit_Approval__c r : p.history) {
            if (r.Status__c == PENDING || (r.Status__c == 'Approved' && r.Customer_Consent__c == 'Pending')) {
                p.open = r;
                break;
            }
        }
        if (p.open != null && p.open.Status__c == PENDING) {
            Authority_Check c = authority(p.open);
            p.canDecide = c.ok;
            p.onBehalf = c.onBehalf;
            p.isRequester = p.open.Requested_By__c == UserInfo.getUserId();
        }
        p.eligible = a.Status__c == 'Under Review' && p.open == null;
        p.notEligibleReason = p.open != null ? null
            : a.Status__c == 'Under Review' ? null
            : 'Upgrades and higher limits are for NSTP applications in the underwriter queue (this one is ' + a.Status__c + ').';
        return p;
    }

    // ------------------------------------------------------------------ Lightning endpoints
    public class Proposal {
        @AuraEnabled public Assessment assessment;
        @AuraEnabled public List<Approver> approvers = new List<Approver>();
    }

    @AuraEnabled
    public static Panel getPanel(Id applicationId) {
        return panel(applicationId);
    }

    @AuraEnabled
    public static Proposal propose(Id applicationId, String proposedCard, Decimal proposedLimit) {
        try {
            Proposal p = new Proposal();
            p.assessment = assess(applicationId, proposedCard, proposedLimit);
            p.approvers = approvers(p.assessment.level, UserInfo.getUserId());
            return p;
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Panel submitRequest(Id applicationId, String proposedCard, Decimal proposedLimit, Id approverId, String reasonCode,
                                      String findings, String mitigants) {
        try {
            submit(applicationId, proposedCard, proposedLimit, approverId, reasonCode, findings, mitigants);
            return panel(applicationId);
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Panel decideRequest(Id requestId, String decision, String notes) {
        try {
            Bandhu_Credit_Approval__c r = decide(requestId, decision, notes);
            return panel(r.Card_Application__c);
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Panel withdrawRequest(Id requestId) {
        try {
            withdraw(requestId);
            return panel([SELECT Card_Application__c FROM Bandhu_Credit_Approval__c WHERE Id = :requestId].Card_Application__c);
        } catch (BandhuException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ------------------------------------------------------------------ helpers
    private static void closeTasks(Id requestId) {
        List<Task> open = [SELECT Id FROM Task WHERE WhatId = :requestId AND IsClosed = false];
        for (Task t : open) {
            t.Status = 'Completed';
        }
        update open;
    }

    private static void notify(Id userId, Id targetId, String title, String body) {
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Bandhu_Credit_Approval' LIMIT 1];
        if (types.isEmpty() || Test.isRunningTest()) {
            return;
        }
        try {
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(types[0].Id);
            n.setTitle(title.abbreviate(250));
            n.setBody(body.abbreviate(750));
            n.setTargetId(targetId);
            n.send(new Set<String>{ userId });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Bandhu notification failed: ' + e.getMessage());
        }
    }
}
