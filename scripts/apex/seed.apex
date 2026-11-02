// LoanSeva by Kotak — demo seed. Idempotent: re-running updates the same records.
// >>> The real WhatsApp phone of the person demoing (10 digits, no +91), and who is on it for this demo. <<<
//     'Priya': existing customer, pre-approved Top-Up.   'Rahul': existing customer applying for a new loan.
//     The other one moves to a parking number, so switching is just this line and a re-run.
String DEMO_PHONE = '9320484281';
String ON_DEMO_PHONE = 'Priya';
Map<String, String> PARKING = new Map<String, String>{ 'Priya' => '9000000001', 'Rahul' => '9000000002', 'Ananya' => '9000000003' };
// Every run resets these numbers to "never banked with Kotak": no Contact, loan, application or journey.
List<String> NEW_TO_BANK_MOBILES = new List<String>{ '9063480755' };

// Name, loan account, outstanding, EMI, rate, tenure left, on-time, due, pre-approved limit
List<List<Object>> CUSTOMERS = new List<List<Object>>{
    new List<Object>{ 'Priya', 'Sharma', 'PL00012345678901', 320000, 11800, 11.49, 30, 12, 12, 500000 },
    new List<Object>{ 'Rahul', 'Deshmukh', 'PL00012345678902', 185000, 8600, 12.25, 24, 11, 12, 300000 },
    new List<Object>{ 'Ananya', 'Iyer', 'PL00012345678903', 640000, 21500, 10.99, 36, 12, 12, 1000000 }
};
// KYC on file from Rahul's first Kotak loan: prefilled when he applies again, so only work, income and the loan are asked
String RAHUL_PAN = 'ABCPD4321K';   // mock CIBIL 777
String RAHUL_FIRST_APP = 'LS-2024-000418';

List<String> DEMO_MOBILES = new List<String>();
for (List<Object> row : CUSTOMERS) {
    String first = (String) row[0];
    DEMO_MOBILES.add(first == ON_DEMO_PHONE ? DEMO_PHONE : PARKING.get(first));
}
List<String> ALL_DEMO_MOBILES = new List<String>(PARKING.values());
ALL_DEMO_MOBILES.add(DEMO_PHONE);

Account acct;
List<Account> existing = [SELECT Id FROM Account WHERE Name = 'LoanSeva Demo Customers' LIMIT 1];
if (existing.isEmpty()) {
    acct = new Account(Name = 'LoanSeva Demo Customers');
    insert acct;
} else {
    acct = existing[0];
}

// The same customer record moves between phones: found by their loan account first, then by mobile
Map<String, Contact> byLoan = new Map<String, Contact>();
List<String> accounts = new List<String>();
for (List<Object> row : CUSTOMERS) {
    accounts.add((String) row[2]);
}
for (Existing_Loan__c l : [SELECT Loan_Account_Number__c, Contact__c, Contact__r.MobilePhone FROM Existing_Loan__c WHERE Loan_Account_Number__c IN :accounts AND Contact__c != null]) {
    byLoan.put(l.Loan_Account_Number__c, new Contact(Id = l.Contact__c));
}
Map<String, Contact> byMobile = new Map<String, Contact>();
for (Contact c : [SELECT Id, MobilePhone FROM Contact WHERE MobilePhone IN :ALL_DEMO_MOBILES]) {
    byMobile.put(c.MobilePhone, c);
}
List<Contact> contacts = new List<Contact>();
for (Integer i = 0; i < CUSTOMERS.size(); i++) {
    List<Object> row = CUSTOMERS[i];
    Contact c = byLoan.containsKey((String) row[2]) ? byLoan.get((String) row[2])
        : byMobile.containsKey(DEMO_MOBILES[i]) ? byMobile.get(DEMO_MOBILES[i]) : new Contact();
    c.FirstName = (String) row[0];
    c.LastName = (String) row[1];
    c.MobilePhone = DEMO_MOBILES[i];
    if (c.Id == null) {
        c.AccountId = acct.Id;
    }
    if (c.FirstName == 'Rahul') {
        c.Birthdate = Date.newInstance(1987, 6, 14);
        c.Email = 'rahul.deshmukh@example.com';
        c.MailingCity = 'Mumbai';
        c.MailingPostalCode = '400076';
    }
    // moving a number between two customers would otherwise trip the duplicate rules
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    c.setOptions(dml);
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

// Rahul's first application (submitted, approved): the source of his PAN and KYC on file
Contact rahul = contacts[1];
List<Loan_Application__c> firstApp = [SELECT Id FROM Loan_Application__c WHERE Reference_Number__c = :RAHUL_FIRST_APP];
Loan_Application__c hist = firstApp.isEmpty() ? new Loan_Application__c() : firstApp[0];
hist.Reference_Number__c = RAHUL_FIRST_APP;
hist.Contact__c = rahul.Id;
hist.Applicant_Name__c = 'Rahul Deshmukh';
hist.Mobile__c = rahul.MobilePhone;
hist.Product__c = 'Personal Loan';
hist.Application_Type__c = 'New Loan';
hist.PAN__c = RAHUL_PAN;
hist.Date_Of_Birth__c = rahul.Birthdate;
hist.Email__c = rahul.Email;
hist.City__c = rahul.MailingCity;
hist.PIN_Code__c = rahul.MailingPostalCode;
hist.Employment_Type__c = 'Salaried';
hist.Company_Name__c = 'Tata Consultancy Services';
hist.Monthly_Income__c = 95000;
hist.Existing_EMIs__c = 0;
hist.Requested_Amount__c = 300000;
hist.Offer_Amount__c = 300000;
hist.Submitted_At__c = Datetime.newInstance(2024, 4, 18, 11, 30, 0);
hist.Status__c = 'Approved';
hist.Decision__c = 'Approved';
upsert hist;
// applications on the demo phone follow whoever is on it now, so the Contact never mixes with the old one's
List<Loan_Application__c> moved = [SELECT Id, Contact__c, PAN__c FROM Loan_Application__c WHERE Contact__c IN :contacts AND Id != :hist.Id];
Map<Id, String> mobileOf = new Map<Id, String>();
for (Contact c : contacts) {
    mobileOf.put(c.Id, c.MobilePhone);
}
for (Loan_Application__c a : moved) {
    a.Mobile__c = mobileOf.get(a.Contact__c);
    // earlier demo runs as Rahul typed real details; his KYC is always the seeded one, so the prefill shows his
    if (a.Contact__c == rahul.Id && a.PAN__c != null) {
        a.PAN__c = RAHUL_PAN;
        a.Date_Of_Birth__c = rahul.Birthdate;
        a.Email__c = rahul.Email;
        a.City__c = rahul.MailingCity;
        a.PIN_Code__c = rahul.MailingPostalCode;
    }
}
update moved;
// the WhatsApp user on the demo phone is the customer now on it
Set<String> phoneKeys = new Set<String>{ DEMO_PHONE, '+91' + DEMO_PHONE, '+91 ' + DEMO_PHONE, '91' + DEMO_PHONE };
Contact onPhone = contacts[DEMO_MOBILES.indexOf(DEMO_PHONE)];
List<MessagingEndUser> phoneUsers = [SELECT Id FROM MessagingEndUser WHERE MessagingPlatformKey IN :phoneKeys];
for (MessagingEndUser u : phoneUsers) {
    u.ContactId = onPhone.Id;
    u.Name = onPhone.FirstName + ' ' + onPhone.LastName;
}
update phoneUsers;

// Reset demo journeys so every run starts clean.
delete [SELECT Id FROM Loan_Journey__c WHERE Mobile__c IN :ALL_DEMO_MOBILES OR Contact__c IN :contacts];
// Reset the new-to-bank numbers. Submitting an application creates a Contact (and approval a loan), so clear them.
Set<String> ntbKeys = new Set<String>();
for (String m : NEW_TO_BANK_MOBILES) {
    ntbKeys.addAll(new List<String>{ m, '+91' + m, '+91 ' + m, '91' + m });
}
List<Contact> ntbContacts = [SELECT Id FROM Contact WHERE MobilePhone IN :ntbKeys];
List<MessagingEndUser> ntbUsers = [SELECT Id, ContactId FROM MessagingEndUser WHERE MessagingPlatformKey IN :ntbKeys AND ContactId != null];
for (MessagingEndUser u : ntbUsers) {
    u.ContactId = null;
}
update ntbUsers;
delete [SELECT Id FROM Loan_Journey__c WHERE Mobile__c IN :NEW_TO_BANK_MOBILES OR Contact__c IN :ntbContacts];
delete [SELECT Id FROM Loan_Application__c WHERE Mobile__c IN :NEW_TO_BANK_MOBILES OR Contact__c IN :ntbContacts];
delete [SELECT Id FROM Existing_Loan__c WHERE Contact__c IN :ntbContacts];
Database.delete(ntbContacts, false);
// drop-off leads (scored, assigned to an RM) and their tasks, so the drop-off -> lead -> nudge demo starts clean
List<Lead> ntbLeads = [SELECT Id FROM Lead WHERE MobilePhone IN :ntbKeys];
delete [SELECT Id FROM Task WHERE WhoId IN :ntbLeads];
Database.delete(ntbLeads, false);

System.debug('LoanSeva seed complete: ' + ON_DEMO_PHONE + ' on ' + DEMO_PHONE + ' (' + phoneUsers.size() + ' WhatsApp user); ' + contacts.size() + ' customers, ' + loans.size() + ' loans; reset ' + NEW_TO_BANK_MOBILES.size() + ' new-to-bank number(s), removed ' + ntbContacts.size() + ' contact(s) and ' + ntbLeads.size() + ' lead(s)');
