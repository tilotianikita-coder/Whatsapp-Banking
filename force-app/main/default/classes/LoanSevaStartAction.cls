public with sharing class LoanSevaStartAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Mobile' description='Customer mobile number if known (optional)')
        public String mobile;
    }

    @InvocableMethod(label='LoanSeva - Start Journey' description='Starts or resumes the LoanSeva PL Top-Up journey and returns the personalised welcome menu.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, r.mobile, true);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.start(j)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
