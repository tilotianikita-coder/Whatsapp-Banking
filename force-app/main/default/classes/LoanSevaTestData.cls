/**
 * Test fixtures: demo customers with active personal loans.
 */
@IsTest
public class LoanSevaTestData {
    public static final String PRIYA_MOBILE = '9876500001';
    public static final String RAHUL_MOBILE = '9876500002';
    public static final String VIKRAM_MOBILE = '9876500003';

    /** Priya (perfect 12/12 track, 5L limit), Rahul (good 11/12 track, 3L), Vikram (weak 8/12 track). */
    public static List<Contact> createCustomers() {
        Account a = new Account(Name = 'LoanSeva Test Customers');
        insert a;
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'Priya', LastName = 'Sharma', MobilePhone = PRIYA_MOBILE, AccountId = a.Id),
            new Contact(FirstName = 'Rahul', LastName = 'Deshmukh', MobilePhone = '+91 ' + RAHUL_MOBILE, AccountId = a.Id),
            new Contact(FirstName = 'Vikram', LastName = 'Rao', MobilePhone = VIKRAM_MOBILE, AccountId = a.Id)
        };
        insert contacts;
        insert new List<Existing_Loan__c>{
            loan(contacts[0].Id, 'PL00099990001', 320000, 11800, 30, 12, 500000),
            loan(contacts[1].Id, 'PL00099990002', 185000, 8600, 24, 11, 300000),
            loan(contacts[2].Id, 'PL00099990003', 150000, 7000, 20, 8, 200000)
        };
        return contacts;
    }

    public static Existing_Loan__c loan(Id contactId, String accountNo, Decimal outstanding, Decimal emi, Integer tenureLeft, Integer onTime, Decimal limitAmount) {
        return new Existing_Loan__c(
            Contact__c = contactId,
            Loan_Account_Number__c = accountNo,
            Product__c = 'Personal Loan',
            Outstanding_Principal__c = outstanding,
            Current_EMI__c = emi,
            Interest_Rate__c = 11.49,
            Tenure_Remaining_Months__c = tenureLeft,
            EMIs_Paid_On_Time__c = onTime,
            EMIs_Due__c = 12,
            Pre_Approved_Limit__c = limitAmount,
            Status__c = 'Active'
        );
    }

    /** A journey that has just been started for the given mobile. */
    public static Loan_Journey__c startedJourney(String mobile) {
        Loan_Journey__c j = LoanSevaJourneyService.resolve(null, null, mobile);
        return LoanSevaEngine.start(j).journey;
    }

    /** A journey verified with the demo OTP and with the loan snapshot confirmed. */
    public static Loan_Journey__c verifiedJourney(String mobile, String fullName) {
        Loan_Journey__c j = startedJourney(mobile);
        j = LoanSevaEngine.verifyCustomer(j, fullName, mobile).journey;
        j = LoanSevaEngine.verifyOtp(j, LoanSevaConfig.get().Demo_OTP__c).journey;
        return LoanSevaEngine.confirmLoan(j, true).journey;
    }

    /** Verified and fully personalised: Salaried @ Infosys, 1L-2L, home renovation, top option amount. */
    public static LoanSevaEngine.Result personalisedJourney(String mobile, String fullName) {
        Loan_Journey__c j = verifiedJourney(mobile, fullName);
        LoanSevaEngine.Result r;
        for (String answer : new List<String>{ '1', 'Infosys', '3', '1', '4' }) {
            r = LoanSevaEngine.personalise(j, answer);
            j = r.journey;
        }
        return r;
    }
}
