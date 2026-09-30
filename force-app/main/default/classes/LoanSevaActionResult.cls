/**
 * Output shared by every LoanSeva agent action. The agent sends `message` to the
 * customer verbatim (it is already localised and formatted for WhatsApp).
 */
public with sharing class LoanSevaActionResult {
    @InvocableVariable(label='Message' description='Reply to send to the customer exactly as written. Already in the customer language.')
    public String message;
    @InvocableVariable(label='Journey Id' description='Loan journey record id. Pass it to every subsequent LoanSeva action.')
    public String journeyId;
    @InvocableVariable(label='Stage' description='Journey stage: Nudge, Start, Verify, Personalise, Offer, Callback, Feedback, Completed')
    public String stage;
    @InvocableVariable(label='Status' description='Active, Completed, Dropped or Exited')
    public String status;
    @InvocableVariable(label='Language' description='EN, HI or MR')
    public String language;
    @InvocableVariable(label='Success' description='False when the input could not be used and the customer is being re-asked')
    public Boolean success;
    @InvocableVariable(label='Handoff Recommended' description='True when a human specialist should take over')
    public Boolean handoff;
    @InvocableVariable(label='Verified' description='True once the customer passed OTP verification')
    public Boolean verified;
    @InvocableVariable(label='Awaiting' description='What the journey needs next, e.g. identity, otp, loan_confirm, employment, amount, offer_decision, callback, feedback_csat, done')
    public String awaiting;
    @InvocableVariable(label='Reference Number' description='Application reference number once the offer is accepted')
    public String referenceNumber;

    public static LoanSevaActionResult of(LoanSevaEngine.Result r) {
        LoanSevaActionResult out = new LoanSevaActionResult();
        out.message = r.message;
        out.success = r.success;
        out.handoff = r.handoff;
        Loan_Journey__c j = r.journey;
        if (j != null) {
            out.journeyId = j.Id;
            out.stage = j.Stage__c;
            out.status = j.Status__c;
            out.language = j.Language__c;
            out.verified = j.OTP_Verified__c;
            out.referenceNumber = j.Reference_Number__c;
            out.awaiting = LoanSevaEngine.awaiting(j);
        }
        return out;
    }

    /** Graceful fallback so a live demo never shows a raw error. */
    public static LoanSevaActionResult error(Exception e, String journeyId) {
        System.debug(LoggingLevel.ERROR, 'LoanSeva action failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        LoanSevaActionResult out = new LoanSevaActionResult();
        out.journeyId = journeyId;
        out.success = false;
        out.handoff = true;
        out.message = 'Sorry, I hit a small snag on my side. 🙏 A Kotak specialist can help right away — reply *Agent* to connect, or try again in a moment.';
        return out;
    }
}
