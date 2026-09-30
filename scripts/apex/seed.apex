// LoanSeva by Kotak — demo seed. Idempotent: re-running updates the same records.
// >>> Replace these with the WhatsApp numbers of the people demoing (10 digits, no +91). <<<
List<String> DEMO_MOBILES = new List<String>{ '9000000001', '9000000002', '9000000003' };

// Name, loan account, outstanding, EMI, rate, tenure left, on-time, due, pre-approved limit
List<List<Object>> CUSTOMERS = new List<List<Object>>{
    new List<Object>{ 'Priya', 'Sharma', 'PL00012345678901', 320000, 11800, 11.49, 30, 12, 12, 500000 },
    new List<Object>{ 'Rahul', 'Deshmukh', 'PL00012345678902', 185000, 8600, 12.25, 24, 11, 12, 300000 },
    new List<Object>{ 'Ananya', 'Iyer', 'PL00012345678903', 640000, 21500, 10.99, 36, 12, 12, 1000000 }
};

Account acct;
List<Account> existing = [SELECT Id FROM Account WHERE Name = 'LoanSeva Demo Customers' LIMIT 1];
if (existing.isEmpty()) {
    acct = new Account(Name = 'LoanSeva Demo Customers');
    insert acct;
} else {
    acct = existing[0];
}

Map<String, Contact> byMobile = new Map<String, Contact>();
for (Contact c : [SELECT Id, MobilePhone FROM Contact WHERE MobilePhone IN :DEMO_MOBILES]) {
    byMobile.put(c.MobilePhone, c);
}
List<Contact> contacts = new List<Contact>();
for (Integer i = 0; i < CUSTOMERS.size(); i++) {
    List<Object> row = CUSTOMERS[i];
    Contact c = byMobile.containsKey(DEMO_MOBILES[i]) ? byMobile.get(DEMO_MOBILES[i]) : new Contact();
    c.FirstName = (String) row[0];
    c.LastName = (String) row[1];
    c.MobilePhone = DEMO_MOBILES[i];
    if (c.Id == null) {
        c.AccountId = acct.Id;
    }
    contacts.add(c);
}
upsert contacts;

List<Existing_Loan__c> loans = new List<Existing_Loan__c>();
for (Integer i = 0; i < CUSTOMERS.size(); i++) {
    List<Object> row = CUSTOMERS[i];
    loans.add(new Existing_Loan__c(
        Contact__c = contacts[i].Id,
        Loan_Account_Number__c = (String) row[2],
        Product__c = 'Personal Loan',
        Outstanding_Principal__c = (Integer) row[3],
        Current_EMI__c = (Integer) row[4],
        Interest_Rate__c = (Decimal) row[5],
        Tenure_Remaining_Months__c = (Integer) row[6],
        EMIs_Paid_On_Time__c = (Integer) row[7],
        EMIs_Due__c = (Integer) row[8],
        Pre_Approved_Limit__c = (Integer) row[9],
        Status__c = 'Active'
    ));
}
upsert loans Loan_Account_Number__c;

// Reset demo journeys so every run starts clean.
delete [SELECT Id FROM Loan_Journey__c WHERE Mobile__c IN :DEMO_MOBILES];
System.debug('LoanSeva seed complete: ' + contacts.size() + ' customers, ' + loans.size() + ' loans');
