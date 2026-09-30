public with sharing class LoanSevaVerifyAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Customer Name' description='Full name as given by the customer (leave empty to ask for it)')
        public String customerName;
        @InvocableVariable(label='Registered Mobile' description='Registered 10-digit mobile number as given by the customer (leave empty to ask for it)')
        public String registeredMobile;
    }

    @InvocableMethod(label='LoanSeva - Verify Customer' description='Looks up the customer by name and registered mobile number and sends the OTP.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.verifyCustomer(j, r.customerName, r.registeredMobile)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
