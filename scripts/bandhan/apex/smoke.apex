// Bandhu smoke test: a new-to-bank WhatsApp applicant from hello to card issued. Prints every reply.
// Run: sf apex run -f scripts/bandhan/apex/smoke.apex -o bandhan   (rolls back: nothing is saved)
Savepoint sp = Database.setSavepoint();
Card_Journey__c j = BandhuJourneyService.resolve(null, null, '9876500011', 'WhatsApp');
// answers by step, so the question order can change; then the answers after the recommendation, in order
Map<String, String> byStep = new Map<String, String>{ 'menu' => '1', 'consent' => '1', 'name' => 'Ananya Sen', 'otp' => '123456', 'employment' => '1',
    'income' => '2.5 lakh', 'pan' => 'ABCPS1234K', 'aa' => '1', 'spend' => '1, 2, 3', 'monthly_spend' => '4', 'fee' => '2', 'company' => 'Infosys',
    'dob' => '12/04/1990', 'pincode' => 'Kolkata 700091', 'bureau' => '1', 'choose' => '1', 'email' => 'ananya@example.com', 'aadhaar' => '1234',
    'aadhaar_otp' => '123456', 'vkyc' => 'Done', 'review' => '1' };
BandhuEngine.Result r = BandhuEngine.start(j);
System.debug('### 0 [' + r.step + '] ' + r.whatsapp().replace('\n', ' / ').left(400));
Integer i = 1;
while (byStep.containsKey(r.step) && i < 40) {
    String s = byStep.remove(r.step);
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
