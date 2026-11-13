public with sharing class BandhuReplyAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Card journey id from a previous Bandhu action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Customer Message' description='The customer message exactly as typed' required=true)
        public String message;
    }

    @InvocableMethod(label='Bandhu - Reply to Card Journey' description='Handles every customer reply in the credit card journey (menu choice, consent, name, mobile, OTP, spend answers, income, PAN, date of birth, PIN code, credit check consent, card choice, KYC, confirmation), questions about cards, comparisons, language changes and requests for a specialist. Routes on the saved journey state and returns the next message.' category='Bandhu')
    public static List<BandhuActionResult> run(List<Request> requests) {
        List<BandhuActionResult> results = new List<BandhuActionResult>();
        for (Request r : requests) {
            try {
                Card_Journey__c j = BandhuJourneyService.resolve(r.journeyId, r.sessionId, null, 'WhatsApp');
                results.add(BandhuActionResult.of(BandhuEngine.reply(j, r.message)));
            } catch (Exception e) {
                results.add(BandhuActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
