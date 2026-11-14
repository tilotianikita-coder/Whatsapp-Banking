/**
 * Finds or starts a Card_Journey__c (by journey id, WhatsApp messaging session, web token or mobile), recognises
 * existing Bandhan Bank customers from the mobile, and keeps the bookkeeping fields (activity, stage, details shared).
 */
public inherited sharing class BandhuJourneyService {
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_DROPPED = 'Dropped';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_EXITED = 'Exited';
    public static final String EXISTING = 'Existing';
    public static final String NEW_TO_BANK = 'New';
    public static final List<String> STAGES = new List<String>{ 'Start', 'Verify', 'Needs', 'Profile', 'Recommend', 'KYC', 'Decision', 'Issued' };

    private static final String FIELDS = 'Id, Name, Mobile__c, PAN__c, Date_Of_Birth__c, Email__c, PIN_Code__c, City__c, Employment_Type__c, '
        + 'Company_Name__c, Monthly_Income__c, Verified_Income__c, Customer_Type__c, CIBIL_Score__c, Eligible_Cards__c, Contact__c, '
        + 'Lead__c, Card_Application__c, Channel__c, Language__c, Status__c, Stage__c, Step__c, Customer_Name__c, Consent__c, '
        + 'Consent_At__c, Bureau_Consent__c, OTP_Verified__c, OTP_Attempts__c, Spend_Focus__c, Monthly_Spend__c, Travel_Frequency__c, '
        + 'Fee_Preference__c, Recommended_Card__c, Alternative_Card__c, Upgrade_Card__c, Recommendation_Reason__c, Chosen_Card__c, '
        + 'Credit_Limit__c, KYC_Status__c, Messaging_Session_Id__c, Web_Token__c, Reference_Number__c, Last_Activity__c, '
        + 'Dropped_At__c, Drop_Point__c, Fields_Done__c, Nudges_Sent__c, Last_Nudged__c, Escalated__c, Last_Send_Status__c, '
        + 'AA_Insights__c, AA_Consent_Id__c, AA_Consent_At__c, ETB_Tier__c, Relationship_Score__c, Hold_Reason__c, Bureau_Data__c, Bureau_At__c, Bandhan_Score__c, Applied_Card__c, '
        + 'FD_Amount__c, CreatedDate';

    public static Card_Journey__c byId(Id journeyId) {
        List<Card_Journey__c> js = Database.query('SELECT ' + FIELDS + ' FROM Card_Journey__c WHERE Id = :journeyId');
        return js.isEmpty() ? null : js[0];
    }

    public static Card_Journey__c byToken(String token) {
        if (String.isBlank(token)) {
            return null;
        }
        List<Card_Journey__c> js = Database.query('SELECT ' + FIELDS + ' FROM Card_Journey__c WHERE Web_Token__c = :token LIMIT 1');
        return js.isEmpty() ? null : js[0];
    }

    /**
     * The open journey for this conversation: by id, else by WhatsApp session, else the latest open journey on the
     * mobile (a resumed drop-off), else a new one.
     */
    public static Card_Journey__c resolve(String journeyId, String sessionId, String mobile, String channel) {
        if (String.isNotBlank(journeyId) && journeyId instanceof Id) {
            Card_Journey__c j = byId(journeyId);
            if (j != null) {
                return j;
            }
        }
        String mobile10 = BandhuI18n.normalizeMobile(mobile);
        if (String.isNotBlank(sessionId)) {
            List<Card_Journey__c> bySession = Database.query('SELECT ' + FIELDS + ' FROM Card_Journey__c WHERE Messaging_Session_Id__c = :sessionId ORDER BY CreatedDate DESC LIMIT 1');
            if (!bySession.isEmpty()) {
                return bySession[0];
            }
            if (mobile10 == null) {
                mobile10 = sessionMobile(sessionId);
            }
        }
        if (mobile10 != null) {
            List<String> open = new List<String>{ STATUS_ACTIVE, STATUS_DROPPED };
            List<Card_Journey__c> byMobile = Database.query('SELECT ' + FIELDS + ' FROM Card_Journey__c WHERE Mobile__c = :mobile10 AND Status__c IN :open ORDER BY CreatedDate DESC LIMIT 1');
            if (!byMobile.isEmpty()) {
                Card_Journey__c j = byMobile[0];
                if (String.isNotBlank(sessionId) && j.Messaging_Session_Id__c != sessionId) {
                    j.Messaging_Session_Id__c = sessionId;
                }
                return j;
            }
        }
        Card_Journey__c j = new Card_Journey__c(
            Mobile__c = mobile10, Messaging_Session_Id__c = sessionId, Channel__c = String.isBlank(channel) ? 'WhatsApp' : channel,
            Language__c = BandhuI18n.EN, Status__c = STATUS_ACTIVE, Stage__c = 'Start', Last_Activity__c = Datetime.now(),
            Fields_Done__c = 0, Nudges_Sent__c = 0, OTP_Attempts__c = 0, KYC_Status__c = 'Not started'
        );
        insert j;
        return byId(j.Id);
    }

    /** Mobile of the WhatsApp end user on a messaging session (platform key such as 919876543210). */
    public static String sessionMobile(String sessionId) {
        if (String.isBlank(sessionId) || !(sessionId instanceof Id)) {
            return null;
        }
        for (MessagingSession s : [SELECT MessagingEndUser.MessagingPlatformKey FROM MessagingSession WHERE Id = :sessionId LIMIT 1]) {
            return BandhuI18n.normalizeMobile(s.MessagingEndUser.MessagingPlatformKey);
        }
        return null;
    }

    /** The existing customer on this mobile, or null. */
    public static Contact findContact(String mobile10) {
        if (mobile10 == null) {
            return null;
        }
        List<String> variants = BandhuI18n.mobileVariants(mobile10);
        for (Contact c : [
            SELECT Id, FirstName, LastName, Name, Email, Birthdate, MailingCity, MailingPostalCode
            FROM Contact WHERE MobilePhone IN :variants OR Phone IN :variants ORDER BY CreatedDate ASC LIMIT 1
        ]) {
            return c;
        }
        return null;
    }

    public static List<Bank_Relationship__c> relationships(Id contactId) {
        if (contactId == null) {
            return new List<Bank_Relationship__c>();
        }
        return [
            SELECT Relationship_Type__c, Account_Number__c, Average_Balance__c, FD_Value__c, Monthly_Salary_Credit__c,
                Vintage_Months__c, Pre_Approved_Card__c, Pre_Approved_Limit__c, PAN__c, Account_Status__c, KYC_Status__c, AML_Flag__c,
                Outstanding__c, Monthly_EMI__c, Max_DPD_12M__c, Holding_Value__c
            FROM Bank_Relationship__c WHERE Contact__c = :contactId ORDER BY CreatedDate ASC
        ];
    }

    public static void touch(Card_Journey__c j) {
        j.Last_Activity__c = Datetime.now();
        if (j.Status__c == STATUS_DROPPED) {
            j.Status__c = STATUS_ACTIVE;
        }
    }

    /** Stages only move forward. */
    public static void advance(Card_Journey__c j, String stage) {
        Integer current = j.Stage__c == null ? 0 : STAGES.indexOf(j.Stage__c);
        if (STAGES.indexOf(stage) > current) {
            j.Stage__c = stage;
        }
    }

    /** The 10 details that make an application: name, mobile, 3 needs, employment, income, PAN, DOB, PIN. */
    public static Integer fieldsDone(Card_Journey__c j) {
        Integer n = 0;
        for (Object v : new List<Object>{ j.Customer_Name__c, j.OTP_Verified__c ? 'y' : null, j.Spend_Focus__c, j.Monthly_Spend__c,
                j.Fee_Preference__c, j.Employment_Type__c, j.Monthly_Income__c, j.PAN__c, j.Date_Of_Birth__c, j.PIN_Code__c }) {
            if (v != null && String.valueOf(v) != '') {
                n++;
            }
        }
        return n;
    }

    public static Integer age(Date dob) {
        if (dob == null) {
            return null;
        }
        Date today = BandhuI18n.today();
        Integer years = today.year() - dob.year();
        if (today.month() < dob.month() || (today.month() == dob.month() && today.day() < dob.day())) {
            years--;
        }
        return years;
    }

    /** The eligibility profile from everything the journey knows. */
    public static BandhuEligibility.Profile profile(Card_Journey__c j) {
        BandhuEligibility.Profile p = new BandhuEligibility.Profile();
        p.age = age(j.Date_Of_Birth__c);
        p.employment = j.Employment_Type__c;
        p.income = j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c;
        p.cibil = j.CIBIL_Score__c == null ? null : j.CIBIL_Score__c.intValue();
        p.existing = j.Customer_Type__c == EXISTING;
        BandhuCustomer.Insight etb = j.Contact__c == null ? null : BandhuCustomer.forContact(j.Contact__c);
        if (etb != null) {
            p.relationshipValue = etb.relationshipValue;
            p.preApprovedCard = etb.preApprovedCard;
            p.preApprovedLimit = etb.preApprovedLimit;
            p.etbTier = etb.tier;
            p.internalDpd = etb.maxDpd;
            p.relationshipScore = etb.score;
        }
        p.channel = j.Channel__c;
        p.incomeVerified = j.Verified_Income__c != null;
        p.monthlySpend = j.Monthly_Spend__c;
        if (String.isNotBlank(j.Spend_Focus__c)) {
            p.focus.addAll(j.Spend_Focus__c.split(';'));
        }
        if (j.Monthly_Spend__c != null) {
            p.spendBand = j.Monthly_Spend__c < 15000 ? 1 : j.Monthly_Spend__c < 50000 ? 2 : j.Monthly_Spend__c <= 100000 ? 3 : 4;
        }
        p.feePreference = j.Fee_Preference__c;
        p.cashFlow = BandhuCashFlow.fromJourney(j);
        p.bureau = BandhuBureau.fromJourney(j);
        return p;
    }
}
