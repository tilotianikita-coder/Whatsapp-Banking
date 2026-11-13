/**
 * Output of every Bandhu agent action. The agent sends `message` to the customer verbatim: it is already in the
 * customer's language with the options numbered for WhatsApp.
 */
public with sharing class BandhuActionResult {
    @InvocableVariable(label='Message' description='Reply to send to the customer exactly as written. Already in the customer language.')
    public String message;
    @InvocableVariable(label='Journey Id' description='Card journey record id. Pass it to every subsequent Bandhu action.')
    public String journeyId;
    @InvocableVariable(label='Awaiting' description='What the journey needs next, e.g. menu, consent, name, otp, spend, income, pan, choose, review, done')
    public String awaiting;
    @InvocableVariable(label='Language' description='EN, HI or BN')
    public String language;
    @InvocableVariable(label='Handoff Recommended' description='True when a human specialist should take over the conversation')
    public Boolean handoff;
    @InvocableVariable(label='Success' description='False when the input could not be used and the customer is being re-asked')
    public Boolean success;

    public static BandhuActionResult of(BandhuEngine.Result r) {
        BandhuActionResult out = new BandhuActionResult();
        out.message = r.whatsapp();
        out.handoff = r.handoff;
        out.success = r.success;
        out.awaiting = r.step;
        if (r.journey != null) {
            out.journeyId = r.journey.Id;
            out.language = r.journey.Language__c;
        }
        return out;
    }

    public static BandhuActionResult error(Exception e, String journeyId) {
        System.debug(LoggingLevel.ERROR, 'Bandhu action failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        BandhuActionResult out = new BandhuActionResult();
        out.message = 'Sorry, I hit a small snag on my side. 🙏 Reply *Agent* to talk to a Bandhan Bank specialist, or try again in a moment.';
        out.journeyId = journeyId;
        out.success = false;
        out.handoff = false;
        return out;
    }
}
