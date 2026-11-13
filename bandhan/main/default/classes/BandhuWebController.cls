/**
 * The DIY web journey (Visualforce page BandhuWeb on the public site): the same Bandhu engine as WhatsApp, with the
 * options returned for buttons and card tiles. Runs without sharing because the site guest cannot own the journey;
 * every call is bound to an unguessable per-journey token, and only the fields the page needs are returned.
 */
public without sharing class BandhuWebController {
    public class Turn {
        public String token;
        public String message;
        public List<String> options;
        public List<BandhuEngine.CardView> cards;
        public String step;
        public Boolean handoff;
        public String language;
    }

    @RemoteAction
    public static Turn start(String language, String source) {
        Card_Journey__c j = new Card_Journey__c(
            Channel__c = 'Web', Language__c = BandhuI18n.parseLanguage(language) == null ? BandhuI18n.EN : BandhuI18n.parseLanguage(language),
            Status__c = BandhuJourneyService.STATUS_ACTIVE, Stage__c = 'Start', Last_Activity__c = Datetime.now(), Fields_Done__c = 0,
            Nudges_Sent__c = 0, OTP_Attempts__c = 0, KYC_Status__c = 'Not started', Web_Token__c = newToken()
        );
        insert j;
        return turn(BandhuEngine.start(BandhuJourneyService.byId(j.Id)));
    }

    @RemoteAction
    public static Turn send(String token, String text) {
        Card_Journey__c j = BandhuJourneyService.byToken(token);
        if (j == null) {
            throw new BandhuException('Your session has expired. Please refresh the page to start again.');
        }
        return turn(BandhuEngine.reply(j, text == null ? '' : text.abbreviate(500)));
    }

    @RemoteAction
    public static Turn language(String token, String language) {
        Card_Journey__c j = BandhuJourneyService.byToken(token);
        String lang = BandhuI18n.parseLanguage(language);
        if (j == null || lang == null) {
            throw new BandhuException('Please refresh the page to start again.');
        }
        return turn(BandhuEngine.setLanguage(j, lang));
    }

    private static Turn turn(BandhuEngine.Result r) {
        Turn t = new Turn();
        t.token = r.journey.Web_Token__c;
        t.message = r.message;
        t.options = r.options;
        t.cards = r.cards;
        t.step = r.step;
        t.handoff = r.handoff;
        t.language = r.journey.Language__c;
        return t;
    }

    private static String newToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }
}
