// Bandhu smoke test: a new-to-bank WhatsApp applicant from hello to card issued. Prints every reply.
// Run: sf apex run -f scripts/bandhan/apex/smoke.apex -o bandhan   (rolls back: nothing is saved)
Savepoint sp = Database.setSavepoint();
Card_Journey__c j = BandhuJourneyService.resolve(null, null, '9876500011', 'WhatsApp');
List<String> said = new List<String>{ '1', '1', 'Ananya Sen', '123456', '1, 2, 3', '4', '2', '1', '2.5 lakh', 'Infosys', 'ABCPS1234K',
    '12/04/1990', 'Kolkata 700091', '1', '1', '1', 'ananya@example.com', '1234', '123456', 'Done', '1' };
BandhuEngine.Result r = BandhuEngine.start(j);
System.debug('### 0 [' + r.step + '] ' + r.whatsapp().replace('\n', ' / ').left(400));
Integer i = 1;
for (String s : said) {
    r = BandhuEngine.reply(BandhuJourneyService.byId(r.journey.Id), s);
    System.debug('### ' + (i++) + ' > ' + s + ' [' + r.step + '] ' + r.whatsapp().replace('\n', ' / ').left(500));
}
Card_Journey__c fin = BandhuJourneyService.byId(r.journey.Id);
System.debug('### JOURNEY ' + fin.Status__c + ' ' + fin.Stage__c + ' card ' + fin.Chosen_Card__c + ' eligible ' + fin.Eligible_Cards__c + ' lead ' + fin.Lead__c);
for (Card_Application__c a : [SELECT Status__c, Recommendation__c, Card_Product__c, Credit_Limit__c, Card_Number_Masked__c, Reference_Number__c, (SELECT Check__c, Result__c, Summary__c FROM Card_Checks__r ORDER BY Sort_Order__c) FROM Card_Application__c WHERE Card_Journey__c = :fin.Id]) {
    System.debug('### APP ' + a.Status__c + ' ' + a.Recommendation__c + ' ' + a.Card_Product__c + ' ' + a.Credit_Limit__c + ' ' + a.Card_Number_Masked__c + ' ' + a.Reference_Number__c);
    for (Card_Check__c c : a.Card_Checks__r) {
        System.debug('###   ' + c.Check__c + ': ' + c.Result__c + ' - ' + c.Summary__c);
    }
}
Database.rollback(sp);
