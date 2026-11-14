/**
 * Regulatory steps built into the card journey, each logged in Bandhu_Consent__c (what, when, purpose, the exact text,
 * expiry and DPDP retention):
 *   DPDP Act 2023         consent at the start (purpose-limited), withdrawal anytime ("withdraw consent")
 *   Credit bureau         soft check with consent; the hard enquiry on submission is declared to the customer first
 *   Account Aggregator    purpose credit underwriting, 24 months of data, consent valid 30 days
 *   RBI MD Credit Cards   MITC delivered with the approval; activation only with the customer's OTP consent, card closed
 *   (2022)                if not activated within 30 days; cancellation without charges in the cooling-off period;
 *                         limit enhancement only with explicit consent (BandhuPostIssue)
 * Retention and cooling-off days are PLACEHOLDERS for Bandhan's compliance team to confirm.
 */
public inherited sharing class BandhuCompliance {
    public static final Integer ACTIVATION_DAYS = 30;
    public static final Integer COOLING_OFF_DAYS = 7;
    public static final Integer RETAIN_PROSPECT_DAYS = 180;
    public static final Integer RETAIN_CUSTOMER_YEARS = 5;
    public static final String MITC_VERSION = 'MITC-BANDHU-2026.1';

    public static Bandhu_Consent__c record(Card_Journey__c j, String type, String purpose, String reference, Date expiresOn, String textShown) {
        Bandhu_Consent__c c = new Bandhu_Consent__c(
            Card_Journey__c = j.Id, Card_Application__c = j.Card_Application__c, Contact__c = j.Contact__c, Type__c = type,
            Purpose__c = purpose == null ? null : purpose.abbreviate(255), Given_At__c = Datetime.now(), Expires_On__c = expiresOn,
            Retain_Until__c = BandhuI18n.today().addDays(RETAIN_PROSPECT_DAYS), Channel__c = j.Channel__c,
            Reference__c = reference == null ? null : reference.abbreviate(80), Text_Shown__c = textShown, Status__c = 'Active');
        if (j.Id != null) {
            insert c;
        }
        return c;
    }

    /** A cardholder's records are kept for the customer retention period instead of the prospect one. */
    public static void retainAsCustomer(Card_Journey__c j) {
        List<Bandhu_Consent__c> cs = [SELECT Id FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id];
        for (Bandhu_Consent__c c : cs) {
            c.Retain_Until__c = BandhuI18n.today().addYears(RETAIN_CUSTOMER_YEARS);
            c.Card_Application__c = j.Card_Application__c;
        }
        update cs;
    }

    public static String mitcLink(String card) {
        String base = BandhuConfig.get().Site_Url__c;
        return (String.isBlank(base) ? 'bandhan.bank.in/cards/mitc' : base.removeEnd('/') + '?view=mitc') + (card == null ? '' : '&card=' + card);
    }

    /** On issue: MITC delivered, activation window and cooling-off period set. Returns the customer copy to append. */
    public static String onIssue(Card_Journey__c j, Card_Application__c app) {
        app.MITC_Sent_At__c = Datetime.now();
        app.Activation_Due__c = BandhuI18n.today().addDays(ACTIVATION_DAYS);
        app.Cooling_Off_Until__c = BandhuI18n.today().addDays(COOLING_OFF_DAYS);
        record(j, 'MITC delivered', 'Most Important Terms and Conditions for the ' + app.Card_Product__c + ' card', MITC_VERSION, null, mitcLink(app.Card_Product__c));
        retainAsCustomer(j);
        return BandhuI18n.msg('Issued_Terms', j.Language__c, new Map<String, Object>{
            'mitc' => mitcLink(app.Card_Product__c), 'days' => ACTIVATION_DAYS, 'cooling' => COOLING_OFF_DAYS });
    }

    public static Card_Application__c issuedApplication(Card_Journey__c j) {
        if (j.Card_Application__c == null) {
            return null;
        }
        Card_Application__c app = [SELECT Id, Status__c, Card_Product__c, Activated_At__c, Activation_Due__c, Cooling_Off_Until__c, Card_Number_Masked__c
                                   FROM Card_Application__c WHERE Id = :j.Card_Application__c];
        return app.Status__c == 'Card Issued' ? app : null;
    }

    public static void activate(Card_Journey__c j, Card_Application__c app) {
        app.Activated_At__c = Datetime.now();
        update app;
        record(j, 'Card activation', 'Activate the ' + app.Card_Product__c + ' card', 'OTP ' + Datetime.now().format('yyyyMMddHHmmss'), null,
            BandhuI18n.msg('Q_Activate_OTP', j.Language__c));
    }

    public static Boolean inCoolingOff(Card_Application__c app) {
        return app.Cooling_Off_Until__c != null && BandhuI18n.today() <= app.Cooling_Off_Until__c;
    }

    public static void cancel(Card_Journey__c j, Card_Application__c app) {
        app.Status__c = 'Cancelled';
        update app;
        record(j, 'Card cancellation', 'Cancelled in the cooling-off period without charges', app.Card_Number_Masked__c, null, null);
    }

    /** DPDP: withdraw consent. Consents are marked withdrawn, the journey stops and the RM is asked to action erasure. */
    public static void withdraw(Card_Journey__c j) {
        List<Bandhu_Consent__c> cs = [SELECT Id FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id AND Status__c = 'Active'];
        for (Bandhu_Consent__c c : cs) {
            c.Status__c = 'Withdrawn';
        }
        update cs;
        record(j, 'Consent withdrawn', 'Customer withdrew consent: stop processing and erase per the retention policy', null, null, null);
        j.Consent__c = false;
        j.Status__c = BandhuJourneyService.STATUS_EXITED;
        j.Step__c = 'done';
    }

    /** Close cards not activated within the window (RBI MD 2022): run daily with the drop-off job. */
    public static Integer closeUnactivated() {
        List<Card_Application__c> stale = [SELECT Id FROM Card_Application__c WHERE Status__c = 'Card Issued' AND Activated_At__c = null
                                           AND Activation_Due__c < :BandhuI18n.today() LIMIT 200];
        for (Card_Application__c a : stale) {
            a.Status__c = 'Cancelled';
            a.Decision_Notes__c = 'Closed: not activated within ' + ACTIVATION_DAYS + ' days of issue (no OTP consent)';
        }
        update stale;
        return stale.size();
    }
}
