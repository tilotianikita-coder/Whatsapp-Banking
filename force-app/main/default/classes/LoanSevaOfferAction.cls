public with sharing class LoanSevaOfferAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Amount' description='New desired amount as typed, e.g. 3 lakh (optional)')
        public String amount;
        @InvocableVariable(label='Tenure' description='New tenure as typed, e.g. 48 months or 4 years (optional)')
        public String tenure;
    }

    @InvocableMethod(label='LoanSeva - Get or Update Offer' description='Runs the eligibility check and returns the personalised preliminary offer. Pass amount and/or tenure when the customer wants to change them.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.offer(j, r.amount, r.tenure)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
