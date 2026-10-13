// LoanSeva by Kotak — one-off: frees Rahul's demo number for Asha, a new-to-bank customer.
// Moves Rahul's Contact (his loans follow it), applications and journeys to a parking number, and unlinks the
// WhatsApp end user from him. seed.apex then keeps Rahul on the parking number and resets Asha's number each run.
String FREED = '9063480755';
String PARKED = '9000000002';

List<Contact> rahul = [SELECT Id, MobilePhone FROM Contact WHERE MobilePhone = :FREED OR MobilePhone = :('+91' + FREED) OR MobilePhone = :('+91 ' + FREED)];
for (Contact c : rahul) {
    c.MobilePhone = PARKED;
}
update rahul;

List<Loan_Application__c> apps = [SELECT Id, Mobile__c FROM Loan_Application__c WHERE Mobile__c = :FREED OR Contact__c IN :rahul];
for (Loan_Application__c a : apps) {
    a.Mobile__c = PARKED;
}
update apps;

List<Loan_Journey__c> journeys = [SELECT Id, Mobile__c FROM Loan_Journey__c WHERE Mobile__c = :FREED];
for (Loan_Journey__c j : journeys) {
    j.Mobile__c = PARKED;
}
update journeys;

List<MessagingEndUser> endUsers = [SELECT Id, Name, ContactId FROM MessagingEndUser WHERE MessagingPlatformKey LIKE :('%' + FREED)];
for (MessagingEndUser u : endUsers) {
    u.ContactId = null;
    u.Name = 'Asha Patil';
}
update endUsers;

System.debug('Parked Rahul on ' + PARKED + ': ' + rahul.size() + ' contact, ' + apps.size() + ' applications, '
    + journeys.size() + ' journeys; ' + endUsers.size() + ' WhatsApp end user unlinked');
