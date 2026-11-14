/**
 * Bandhu test fixtures: an existing Bandhan Bank customer (salary account, pre-approved Flare) and helpers that walk a
 * new-to-bank applicant through the journey. Sends are pinned to LogOnly.
 */
@IsTest
public class BandhuTestData {
    public static final String ETB_MOBILE = '9876500001';
    public static final String NTB_MOBILE = '9876500002';
    public static final String GOOD_PAN = 'ABCPS1234K';    // CIBIL 779
    public static final String REFER_PAN = 'ABCPS1234R';   // CIBIL 730
    public static final String LOW_PAN = 'ABCPS1234Y';     // CIBIL 690
    public static final String DECLINE_PAN = 'ABCPS1234Z'; // CIBIL 630
    public static final String FRAUD_PAN = 'ABCPS1234X';   // negative list

    public static void useLogOnly() {
        Bandhu_Config__mdt cfg = BandhuConfig.get().clone();
        cfg.Send_Mode__c = BandhuWhatsAppSender.MODE_LOG_ONLY;
        BandhuConfig.cached = cfg;
    }

    public static Contact existingCustomer() {
        Account a = new Account(Name = 'Bandhu Test Customers');
        insert a;
        Contact c = new Contact(FirstName = 'Rohan', LastName = 'Mukherjee', MobilePhone = ETB_MOBILE, AccountId = a.Id,
            Birthdate = Date.newInstance(1988, 6, 14), Email = 'rohan@example.com', MailingCity = 'Kolkata', MailingPostalCode = '700019');
        insert c;
        insert new List<Bank_Relationship__c>{
            new Bank_Relationship__c(Contact__c = c.Id, Relationship_Type__c = 'Salary Account', Account_Number__c = '50200011112222',
                Average_Balance__c = 180000, Monthly_Salary_Credit__c = 120000, Vintage_Months__c = 48, PAN__c = GOOD_PAN,
                Pre_Approved_Card__c = 'Flare', Pre_Approved_Limit__c = 350000),
            new Bank_Relationship__c(Contact__c = c.Id, Relationship_Type__c = 'Fixed Deposit', FD_Value__c = 500000, Vintage_Months__c = 20)
        };
        return c;
    }

    public static BandhuEngine.Result say(BandhuEngine.Result r, String text) {
        return BandhuEngine.reply(BandhuJourneyService.byId(r.journey.Id), text);
    }

    public static BandhuEngine.Result sayAll(BandhuEngine.Result r, List<String> texts) {
        for (String t : texts) {
            r = say(r, t);
        }
        return r;
    }

    /** A new-to-bank applicant on WhatsApp: consent, name and OTP done (now at the first profile question). */
    public static BandhuEngine.Result newToBankVerified(String mobile) {
        Card_Journey__c j = BandhuJourneyService.resolve(null, null, mobile, 'WhatsApp');
        BandhuEngine.Result r = BandhuEngine.start(j);
        return sayAll(r, new List<String>{ '1', '1', 'Ananya Sen', BandhuConfig.get().Demo_OTP__c });
    }

    /** Answers by step name, so tests don't depend on the question order; stops at the first step without an answer. */
    public static BandhuEngine.Result drive(BandhuEngine.Result r, Map<String, String> answers) {
        Map<String, String> left = answers.clone();
        Integer guard = 0;
        while (left.containsKey(r.step) && guard++ < 40) {
            r = say(r, left.remove(r.step));
        }
        return r;
    }

    /** Standard answers: salaried, the given income and PAN, soft check yes, Account Aggregator yes; needs = spend, monthly spend, fee. */
    public static Map<String, String> answers(List<String> needs, String income, String pan) {
        Map<String, String> a = new Map<String, String>{
            'employment' => '1', 'income' => income, 'pan' => pan, 'aa' => '1', 'company' => 'Infosys', 'dob' => '12/04/1990',
            'pincode' => 'Kolkata 700091', 'bureau' => '1'
        };
        List<String> keys = new List<String>{ 'spend', 'monthly_spend', 'fee' };
        for (Integer i = 0; i < Math.min(needs.size(), 3); i++) {
            a.put(keys[i], needs[i]);
        }
        return a;
    }

    /** ... up to the recommendation. */
    public static BandhuEngine.Result toRecommendation(String mobile, List<String> needs, String income, String pan) {
        return drive(newToBankVerified(mobile), answers(needs, income, pan));
    }
}
