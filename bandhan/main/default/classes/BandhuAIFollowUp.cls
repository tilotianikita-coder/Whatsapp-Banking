/**
 * WhatsApp: the AI note that follows a recommendation ('why') or an issued card ('tip'), sent a few seconds after the
 * turn (the LLM call cannot run in the same transaction as the journey's DML). Silent when the AI is unavailable.
 */
public with sharing class BandhuAIFollowUp implements Queueable, Database.AllowsCallouts {
    private final Id journeyId;
    private final String kind;

    public BandhuAIFollowUp(Id journeyId, String kind) {
        this.journeyId = journeyId;
        this.kind = kind;
    }

    public void execute(QueueableContext ctx) {
        Card_Journey__c j = BandhuJourneyService.byId(journeyId);
        String note = j == null ? null : BandhuAI.personalNote(j, kind);
        if (note != null) {
            BandhuWhatsAppSender.send(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(j.Id, note, null) });
        }
    }

    /** Queue the note for a WhatsApp turn (web pages fetch it themselves). */
    public static void queueFor(BandhuEngine.Result r) {
        if (r == null || String.isBlank(r.aiFollowUp) || r.journey == null || r.journey.Channel__c == 'Web') {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new BandhuAIFollowUp(r.journey.Id, r.aiFollowUp));
        }
    }
}
