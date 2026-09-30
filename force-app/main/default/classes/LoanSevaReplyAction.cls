public with sharing class LoanSevaReplyAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Customer Message' description='The customer message exactly as typed' required=true)
        public String message;
    }

    @InvocableMethod(label='LoanSeva - Reply to Journey' description='Handles any customer reply to the question the journey is waiting for (name and mobile, OTP, loan confirmation, personalisation answers, offer decision, amount or tenure change, callback time, feedback). Routes on the saved journey state and returns the next message.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.reply(j, r.message)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
