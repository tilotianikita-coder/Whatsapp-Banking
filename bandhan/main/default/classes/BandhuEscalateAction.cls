public with sharing class BandhuEscalateAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Card journey id from a previous Bandhu action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Reason' description='Why the customer needs a specialist, in a few words')
        public String reason;
    }

    @InvocableMethod(label='Bandhu - Log Specialist Request' description='Records that the customer wants a human Bandhan Bank card specialist: creates a high-priority task with everything captured so far, before the conversation is transferred.' category='Bandhu')
    public static List<BandhuActionResult> run(List<Request> requests) {
        List<BandhuActionResult> results = new List<BandhuActionResult>();
        for (Request r : requests) {
            try {
                Card_Journey__c j = BandhuJourneyService.resolve(r.journeyId, r.sessionId, null, 'WhatsApp');
                results.add(BandhuActionResult.of(BandhuEngine.handoff(j, String.isBlank(r.reason) ? 'Customer asked for a specialist' : r.reason)));
            } catch (Exception e) {
                results.add(BandhuActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
