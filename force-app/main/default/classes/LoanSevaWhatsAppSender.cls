/**
 * Proactive (business-initiated) WhatsApp messages: the Stage 1 nudge and the drop-off re-engagement nudges.
 * Sends through the standard `sendConversationMessages` action (via the LoanSeva_Send_Conversation_Message flow)
 * on the BYOC messaging channel, which the
 * installed WhatsApp BYOC package relays to Meta. Replies inside a live conversation go through Agentforce instead.
 *
 * Send_Mode__c: ConversationMessage (real send) or LogOnly (records what would be sent; for dry demos/tests).
 */
public with sharing class LoanSevaWhatsAppSender implements Queueable, Database.AllowsCallouts {
    public static final String MODE_LOG_ONLY = 'LogOnly';
    public static final String PARAM_NAME = 'MessageText';
    private static final String SEND_FLOW = 'LoanSeva_Send_Conversation_Message';
    /** Stays well inside per-transaction callout limits; the remainder is chained. */
    public static final Integer MAX_PER_JOB = 50;

    public class Outbound {
        public Id journeyId;
        public String body;
        public String definitionName;

        public Outbound(Id journeyId, String body, String definitionName) {
            this.journeyId = journeyId;
            this.body = body;
            this.definitionName = definitionName;
        }
    }

    private final List<Outbound> items;

    public LoanSevaWhatsAppSender(List<Outbound> items) {
        this.items = items;
    }

    /** Queues the sends (async so it works from triggers, schedulers and guest-initiated events). */
    public static void enqueue(List<Outbound> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        if (Test.isRunningTest() && Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(new LoanSevaWhatsAppSender(items));
    }

    public void execute(QueueableContext ctx) {
        List<Outbound> now = new List<Outbound>();
        List<Outbound> later = new List<Outbound>();
        for (Outbound o : items) {
            (now.size() < MAX_PER_JOB ? now : later).add(o);
        }
        send(now);
        if (!later.isEmpty()) {
            enqueue(later);
        }
    }

    /** Synchronous send; must run in a context that allows callouts (no uncommitted DML before it). */
    public static void send(List<Outbound> outbound) {
        if (outbound == null || outbound.isEmpty()) {
            return;
        }
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Set<Id> journeyIds = new Set<Id>();
        for (Outbound o : outbound) {
            journeyIds.add(o.journeyId);
        }
        Map<Id, Loan_Journey__c> journeys = new Map<Id, Loan_Journey__c>([
            SELECT Id, Mobile__c, Customer_Name__c, Contact__c, Messaging_End_User_Id__c, Consent_WhatsApp__c
            FROM Loan_Journey__c
            WHERE Id IN :journeyIds
        ]);

        Map<Id, String> statusByJourney = new Map<Id, String>();
        Map<Id, String> endUserByJourney = new Map<Id, String>();
        if (cfg.Send_Mode__c == MODE_LOG_ONLY) {
            for (Outbound o : outbound) {
                statusByJourney.put(o.journeyId, 'LogOnly ' + stamp() + ': ' + o.body.abbreviate(200));
            }
        } else {
            endUserByJourney = ensureEndUsers(journeys.values(), cfg);
            if (createdEndUsers && !Test.isRunningTest()) {
                // new end users were just inserted: send from a fresh transaction so no DML precedes the send
                for (Outbound o : outbound) {
                    statusByJourney.put(o.journeyId, 'Queued ' + stamp());
                }
                saveStatus(statusByJourney, endUserByJourney);
                createdEndUsers = false;
                System.enqueueJob(new LoanSevaWhatsAppSender(outbound));
                return;
            }
            for (Outbound o : outbound) {
                statusByJourney.put(o.journeyId, callSend(o, endUserByJourney.get(o.journeyId), cfg));
            }
        }
        saveStatus(statusByJourney, endUserByJourney);
    }

    private static void saveStatus(Map<Id, String> statusByJourney, Map<Id, String> endUserByJourney) {
        List<Loan_Journey__c> updates = new List<Loan_Journey__c>();
        for (Id jid : statusByJourney.keySet()) {
            Loan_Journey__c j = new Loan_Journey__c(Id = jid, Last_Send_Status__c = statusByJourney.get(jid).abbreviate(255));
            if (endUserByJourney.containsKey(jid) && String.isNotBlank(endUserByJourney.get(jid))) {
                j.Messaging_End_User_Id__c = endUserByJourney.get(jid);
            }
            updates.add(j);
        }
        update updates;
    }

    private static Boolean createdEndUsers = false;

    /**
     * Finds (or creates) the MessagingEndUser per journey on the configured channel, keyed by the
     * E.164-style platform key used by the BYOC router (e.g. 919876543210). Creation happens before any callout.
     */
    @TestVisible
    private static Map<Id, String> ensureEndUsers(List<Loan_Journey__c> journeys, LoanSeva_Config__mdt cfg) {
        Map<Id, String> result = new Map<Id, String>();
        List<MessagingChannel> channels = [
            SELECT Id FROM MessagingChannel WHERE DeveloperName = :cfg.WhatsApp_Channel__c LIMIT 1
        ];
        if (channels.isEmpty()) {
            throw new LoanSevaException('Messaging channel not found: ' + cfg.WhatsApp_Channel__c);
        }
        Id channelId = channels[0].Id;
        String cc = String.isBlank(cfg.Country_Code__c) ? '91' : cfg.Country_Code__c;

        Map<String, Loan_Journey__c> byKey = new Map<String, Loan_Journey__c>();
        for (Loan_Journey__c j : journeys) {
            if (String.isNotBlank(j.Mobile__c)) {
                byKey.put(cc + j.Mobile__c, j);
            }
        }
        Map<String, MessagingEndUser> existing = new Map<String, MessagingEndUser>();
        for (MessagingEndUser u : [
            SELECT Id, MessagingPlatformKey, ContactId
            FROM MessagingEndUser
            WHERE MessagingChannelId = :channelId AND MessagingPlatformKey IN :byKey.keySet()
        ]) {
            existing.put(u.MessagingPlatformKey, u);
        }
        List<MessagingEndUser> toInsert = new List<MessagingEndUser>();
        List<MessagingEndUser> toUpdate = new List<MessagingEndUser>();
        for (String key : byKey.keySet()) {
            Loan_Journey__c j = byKey.get(key);
            MessagingEndUser u = existing.get(key);
            if (u == null) {
                toInsert.add(new MessagingEndUser(
                    Name = String.isBlank(j.Customer_Name__c) ? key : j.Customer_Name__c,
                    MessagingChannelId = channelId,
                    MessagingPlatformKey = key,
                    MessageType = 'Custom',
                    MessagingConsentStatus = 'ExplicitlyOptedIn',
                    ContactId = j.Contact__c
                ));
            } else if (u.ContactId == null && j.Contact__c != null) {
                toUpdate.add(new MessagingEndUser(Id = u.Id, ContactId = j.Contact__c));
            }
        }
        insert toInsert;
        update toUpdate;
        createdEndUsers = !toInsert.isEmpty();
        for (MessagingEndUser u : toInsert) {
            existing.put(u.MessagingPlatformKey, u);
        }
        for (String key : byKey.keySet()) {
            result.put(byKey.get(key).Id, existing.get(key).Id);
        }
        return result;
    }

    @TestVisible
    private static String callSend(Outbound o, String endUserId, LoanSeva_Config__mdt cfg) {
        if (String.isBlank(endUserId)) {
            return 'Failed ' + stamp() + ': no mobile on journey';
        }
        String definition = String.isBlank(o.definitionName) ? cfg.Nudge_Definition__c : o.definitionName;
        richMessaging.MessageDefinitionInputParameter p = new richMessaging.MessageDefinitionInputParameter();
        p.name = PARAM_NAME;
        p.textValue = o.body;
        // Through a flow: Invocable.Action rejects messagingEndUserIds for this action ("expected String[]")
        Map<String, Object> inputs = new Map<String, Object>{
            'definitionName' => definition,
            'endUserIds' => new List<String>{ endUserId },
            'params' => new List<richMessaging.MessageDefinitionInputParameter>{ p }
        };
        try {
            String error = Test.isRunningTest() ? mockError : runSendFlow(inputs);
            return String.isBlank(error) ? 'Sent ' + stamp() + ' via ' + definition : 'Failed ' + stamp() + ': ' + error;
        } catch (Exception e) {
            return 'Failed ' + stamp() + ': ' + e.getMessage();
        }
    }

    private static String runSendFlow(Map<String, Object> inputs) {
        Flow.Interview send = Flow.Interview.createInterview(SEND_FLOW, inputs);
        send.start();
        return (String) send.getVariableValue('errorMessage');
    }

    /** Tests cannot send a real message; the send flow's errorMessage is simulated instead (null = sent). */
    @TestVisible
    private static String mockError;

    private static String stamp() {
        return Datetime.now().format('d MMM HH:mm', LoanSevaI18n.TIMEZONE);
    }
}
