public with sharing class LoanSevaFeedbackAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Answer' description='The reply exactly as the customer typed it')
        public String answer;
    }

    @InvocableMethod(label='LoanSeva - Capture Feedback' description='Captures the answer to the current feedback question (CSAT 1-5, resolution, optional comment) and returns the next question or the sign-off. Pass an empty answer to start the survey.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.feedback(j, r.answer)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
