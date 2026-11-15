// Bandhu demo reset (org: bandhan): deletes every Bandhu journey, application and their records, the Bandhu card
// leads and Bandhu tasks, and the cached bureau reports on contacts. Then run seed.apex and demo_leads.apex (0-3).
// Only Bandhu data is touched: Bandhu objects, Leads with LeadSource 'Bandhu Card Journey', Tasks 'Bandhu: ...'.
// Run: sf apex run -f scripts/bandhan/apex/reset_demo.apex -o bandhan
Integer docs = [SELECT COUNT() FROM Bandhu_Document__c];
Integer consents = [SELECT COUNT() FROM Bandhu_Consent__c];
delete [SELECT Id FROM Bandhu_Document__c];
delete [SELECT Id FROM Bandhu_Consent__c];
delete [SELECT Id FROM Card_Check__c];
delete [SELECT Id FROM Bandhu_Lead_Check__c];
List<Card_Application__c> apps = [SELECT Id FROM Card_Application__c];
List<Card_Journey__c> journeys = [SELECT Id FROM Card_Journey__c];
List<Lead> leads = [SELECT Id FROM Lead WHERE LeadSource = 'Bandhu Card Journey' AND IsConverted = false];
List<Task> tasks = [SELECT Id FROM Task WHERE Subject LIKE 'Bandhu:%'];
delete tasks;
delete apps;
delete journeys;
Database.delete(leads, false);
List<Contact> cached = [SELECT Id FROM Contact WHERE Bandhu_Bureau_At__c != null];
for (Contact c : cached) {
    c.Bandhu_Bureau_Data__c = null;
    c.Bandhu_Bureau_At__c = null;
}
update cached;
System.debug('### Bandhu reset: ' + journeys.size() + ' journeys, ' + apps.size() + ' applications, ' + leads.size() + ' leads, '
    + tasks.size() + ' tasks, ' + consents + ' consents, ' + docs + ' documents, ' + cached.size() + ' bureau caches cleared');
