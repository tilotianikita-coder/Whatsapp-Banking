public with sharing class BandhuStartAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Card journey id from a previous Bandhu action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
    }

    @InvocableMethod(label='Bandhu - Start Card Journey' description='Starts (or resumes) the Bandhan Bank credit card advisor journey and returns the welcome menu. Use for the first message of a conversation and for greetings.' category='Bandhu')
    public static List<BandhuActionResult> run(List<Request> requests) {
        List<BandhuActionResult> results = new List<BandhuActionResult>();
        for (Request r : requests) {
            try {
                Card_Journey__c j = BandhuJourneyService.resolve(r.journeyId, r.sessionId, null, 'WhatsApp');
                results.add(BandhuActionResult.of(BandhuEngine.start(j)));
            } catch (Exception e) {
                results.add(BandhuActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
