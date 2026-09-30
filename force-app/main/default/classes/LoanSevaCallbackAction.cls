public with sharing class LoanSevaCallbackAction {
    public class Request {
        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
        @InvocableVariable(label='Preference' description='The reply exactly as typed: an option number or a date/time such as Thu 11am' required=true)
        public String preference;
        @InvocableVariable(label='Preferred Date Time (ISO)' description='Optional ISO 8601 IST date-time (yyyy-MM-ddTHH:mm) if the customer named a specific time')
        public String preferredDateTime;
    }

    @InvocableMethod(label='LoanSeva - Schedule Callback' description='Books the specialist callback from the customer choice and creates the RM Task and Event. Returns the confirmation plus the first feedback question.' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {
            try {
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, null);
                results.add(LoanSevaActionResult.of(LoanSevaEngine.scheduleCallback(j, r.preference, r.preferredDateTime)));
            } catch (Exception e) {
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }
        }
        return results;
    }
}
