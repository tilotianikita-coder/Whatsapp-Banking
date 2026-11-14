// Bandhu demo seed (org: bandhan). Idempotent: re-run before every demo.
// Run: sf apex run -f scripts/bandhan/apex/seed.apex -o bandhan
//
// >>> The presenter's WhatsApp phone (10 digits, no +91) and who is on it: '' = new to bank (the default demo),
//     'Rohan' = existing customer with a salary account and a pre-approved Flare, 'Sutapa' = existing customer whose
//     balances + FDs + demat qualify her for Lumina (Wealth tier, relationship route), 'Rina' = microfinance-only customer
//     (Sparks only), 'Debasish' = dormant savings account (the journey is held and the RM gets a task). <<<
String DEMO_PHONE = '9063480755';
String ON_DEMO_PHONE = '';
Map<String, String> PARKING = new Map<String, String>{ 'Rohan' => '9000000101', 'Sutapa' => '9000000102', 'Rina' => '9000000103', 'Debasish' => '9000000104' };

// ---------------------------------------------------------------- existing customers (mock core banking)
Account acct;
for (Account a : [SELECT Id FROM Account WHERE Name = 'Bandhan Bank Demo Customers' LIMIT 1]) {
    acct = a;
}
if (acct == null) {
    acct = new Account(Name = 'Bandhan Bank Demo Customers');
    insert acct;
}
Map<String, Contact> customers = new Map<String, Contact>();
for (Contact c : [SELECT Id, FirstName FROM Contact WHERE AccountId = :acct.Id]) {
    customers.put(c.FirstName, c);
}
List<Contact> people = new List<Contact>{
    new Contact(FirstName = 'Rohan', LastName = 'Mukherjee', Birthdate = Date.newInstance(1988, 6, 14), Email = 'rohan.mukherjee@example.com',
        MailingCity = 'Kolkata', MailingPostalCode = '700019'),
    new Contact(FirstName = 'Sutapa', LastName = 'Banerjee', Birthdate = Date.newInstance(1979, 11, 2), Email = 'sutapa.banerjee@example.com',
        MailingCity = 'Kolkata', MailingPostalCode = '700029'),
    new Contact(FirstName = 'Rina', LastName = 'Khatun', Birthdate = Date.newInstance(1991, 3, 21), Email = 'rina.khatun@example.com',
        MailingCity = 'Howrah', MailingPostalCode = '711101'),
    new Contact(FirstName = 'Debasish', LastName = 'Pal', Birthdate = Date.newInstance(1983, 8, 9), Email = 'debasish.pal@example.com',
        MailingCity = 'Durgapur', MailingPostalCode = '713201')
};
for (Contact c : people) {
    if (customers.containsKey(c.FirstName)) {
        c.Id = customers.get(c.FirstName).Id;
    } else {
        c.AccountId = acct.Id;
    }
    c.MobilePhone = c.FirstName == ON_DEMO_PHONE ? DEMO_PHONE : PARKING.get(c.FirstName);
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    c.setOptions(dml);
}
upsert people;
delete [SELECT Id FROM Bank_Relationship__c WHERE Contact__c IN :people];
insert new List<Bank_Relationship__c>{
    new Bank_Relationship__c(Contact__c = people[0].Id, Relationship_Type__c = 'Salary Account', Account_Number__c = '50200011112222',
        Average_Balance__c = 180000, Monthly_Salary_Credit__c = 120000, Vintage_Months__c = 48, PAN__c = 'AMKPM4521K',
        Pre_Approved_Card__c = 'Flare', Pre_Approved_Limit__c = 350000),
    new Bank_Relationship__c(Contact__c = people[0].Id, Relationship_Type__c = 'Fixed Deposit', FD_Value__c = 500000, Vintage_Months__c = 20),
    new Bank_Relationship__c(Contact__c = people[1].Id, Relationship_Type__c = 'Savings Account', Account_Number__c = '50100033334444',
        Average_Balance__c = 800000, Vintage_Months__c = 96, PAN__c = 'BSTPB7788L'),
    new Bank_Relationship__c(Contact__c = people[1].Id, Relationship_Type__c = 'Fixed Deposit', FD_Value__c = 600000, Vintage_Months__c = 36),
    new Bank_Relationship__c(Contact__c = people[1].Id, Relationship_Type__c = 'Demat', Holding_Value__c = 450000, Vintage_Months__c = 30),
    new Bank_Relationship__c(Contact__c = people[2].Id, Relationship_Type__c = 'Microfinance Loan', Account_Number__c = '60300055556666',
        Outstanding__c = 38000, Monthly_EMI__c = 2400, Max_DPD_12M__c = 0, Vintage_Months__c = 54, PAN__c = 'CRKPK3141M'),
    new Bank_Relationship__c(Contact__c = people[3].Id, Relationship_Type__c = 'Savings Account', Account_Number__c = '50100077778888',
        Account_Status__c = 'Dormant', Average_Balance__c = 1500, Vintage_Months__c = 84, PAN__c = 'DPLPP2718N')
};

// ---------------------------------------------------------------- reset the demo phone and the customers' journeys
List<String> phoneKeys = BandhuI18n.mobileVariants(DEMO_PHONE);
List<String> allMobiles = new List<String>{ DEMO_PHONE };
allMobiles.addAll(PARKING.values());
List<Card_Journey__c> old = [SELECT Id, Card_Application__c FROM Card_Journey__c WHERE Mobile__c IN :allMobiles OR Contact__c IN :people];
Set<Id> oldApps = new Set<Id>();
for (Card_Journey__c j : old) {
    if (j.Card_Application__c != null) {
        oldApps.add(j.Card_Application__c);
    }
}
delete [SELECT Id FROM Card_Application__c WHERE Id IN :oldApps OR Mobile__c IN :allMobiles];
delete old;
List<Lead> phoneLeads = [SELECT Id FROM Lead WHERE MobilePhone IN :phoneKeys];
delete [SELECT Id FROM Task WHERE WhoId IN :phoneLeads];
Database.delete(phoneLeads, false);
List<Contact> strays = [SELECT Id FROM Contact WHERE MobilePhone IN :phoneKeys AND AccountId != :acct.Id];
Database.delete(strays, false);
// the WhatsApp user on the demo phone belongs to whoever is on it now (nobody when new to bank)
Contact onPhone;
for (Contact c : people) {
    if (c.FirstName == ON_DEMO_PHONE) {
        onPhone = c;
    }
}
List<MessagingEndUser> users = [SELECT Id FROM MessagingEndUser WHERE MessagingPlatformKey IN :phoneKeys];
for (MessagingEndUser u : users) {
    u.ContactId = onPhone == null ? null : onPhone.Id;
}
update users;

System.debug('### Bandhu seed: ' + (String.isBlank(ON_DEMO_PHONE) ? 'new to bank' : ON_DEMO_PHONE) + ' on ' + DEMO_PHONE + '; customers Rohan '
    + people[0].MobilePhone + ', Sutapa ' + people[1].MobilePhone
    + ', Rina ' + people[2].MobilePhone + ', Debasish ' + people[3].MobilePhone + '; reset ' + old.size() + ' journey(s), ' + phoneLeads.size() + ' lead(s)');
