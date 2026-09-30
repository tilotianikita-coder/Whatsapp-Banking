public with sharing class LoanSevaEscalateAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Reason' description='Short reason for the handoff')
        public String reason;
    }

    @InvocableMethod(label='LoanSeva - Escalate to Specialist' description='Logs a high-priority RM task with the intent summary before handing off to a human specialist.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.escalate(j, r.reason)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
