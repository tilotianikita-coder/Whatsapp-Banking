// Bandhu demo data for lead management and underwriting (org: bandhan). Idempotent: replaces the same records.
// Run once per prospect (one journey per transaction keeps within the SOQL limit): set WHICH to 0, 1, 2, 3, or use
//   for i in 0 1 2 3; do sed "s/^Integer WHICH = .*/Integer WHICH = $i;/" scripts/bandhan/apex/demo_leads.apex > /tmp/dl.apex; sf apex run -f /tmp/dl.apex -o bandhan; done
//   Priya Das      - Hot:  Lumina match, CIBIL 772, dropped at Aadhaar eKYC
//   Arjun Roy      - Hot:  Ignite match, CIBIL 730, dropped at the recommendation
//   Moumita Saha   - Unqualified, Cold: knocked out at the Credit Bureau gate (CIBIL 630), told about an Overdraft against FD, no RM nudge
//   Sourav Ghosh   - application in the underwriter's queue: Flare, CIBIL 772 but a settled credit card on file (manual review)
Integer WHICH = 0;
String OTP = BandhuConfig.get().Demo_OTP__c;
// name, mobile, needs answers (spend, monthly, fee), employment, income, company, PAN, DOB, PIN, Account Aggregator answer,
// then the answers after the recommendation (where the prospect stops). Answers go by step, so the question order can change.
List<List<Object>> PROSPECTS = new List<List<Object>>{
    new List<Object>{ 'Priya Das', '9000000201', new List<String>{ '1, 2, 3', '4', '2' }, '1', '2.5 lakh', 'TCS', 'ABCPK5521K', '18/09/1991', 'Kolkata 700064', '1', new List<String>{ '1' } },
    new List<Object>{ 'Arjun Roy', '9000000202', new List<String>{ '4, 1', '2', '2' }, '1', '55000', 'Wipro', 'ABCPR3310R', '02/02/1994', 'Howrah 711101', '2', new List<String>() },
    new List<Object>{ 'Moumita Saha', '9000000203', new List<String>{ '3', '2', '1' }, '3', '60000', 'Saha Sweets', 'ABCPS8890Z', '11/07/1987', 'Durgapur 713204', '2', new List<String>() },
    new List<Object>{ 'Sourav Ghosh', '9000000204', new List<String>{ '1, 3', '3', '2' }, '1', '95000', 'Cognizant', 'ABCPH4417K', '23/03/1989', 'Kolkata 700091', '1', new List<String>{ '1', '5678', OTP, 'Done', '1' } }
};
PROSPECTS = new List<List<Object>>{ PROSPECTS[WHICH] };
List<String> mobiles = new List<String>();
for (List<Object> p : PROSPECTS) {
    mobiles.addAll(BandhuI18n.mobileVariants((String) p[1]));
}
List<Lead> oldLeads = [SELECT Id FROM Lead WHERE MobilePhone IN :mobiles];
delete [SELECT Id FROM Task WHERE WhoId IN :oldLeads];
delete [SELECT Id FROM Bandhu_Lead_Check__c WHERE Lead__c IN :oldLeads];
List<Card_Journey__c> oldJourneys = [SELECT Id, Card_Application__c FROM Card_Journey__c WHERE Mobile__c IN :mobiles];
Set<Id> apps = new Set<Id>();
for (Card_Journey__c j : oldJourneys) {
    if (j.Card_Application__c != null) {
        apps.add(j.Card_Application__c);
    }
}
delete [SELECT Id FROM Card_Application__c WHERE Id IN :apps];
delete oldJourneys;
delete oldLeads;

List<Id> dropped = new List<Id>();
for (List<Object> p : PROSPECTS) {
    BandhuEngine.Result r = BandhuEngine.start(BandhuJourneyService.resolve(null, null, (String) p[1], 'WhatsApp'));
    for (String a : new List<String>{ '1', '1', (String) p[0], OTP }) {
        r = BandhuEngine.reply(BandhuJourneyService.byId(r.journey.Id), a);
    }
    List<String> needs = (List<String>) p[2];
    Map<String, String> byStep = new Map<String, String>{ 'email' => ((String) p[0]).toLowerCase().replace(' ', '.') + '@example.com', 'employment' => (String) p[3], 'income' => (String) p[4], 'company' => (String) p[5],
        'pan' => (String) p[6], 'dob' => (String) p[7], 'pincode' => (String) p[8], 'aa' => (String) p[9], 'bureau' => '1',
        'spend' => needs[0], 'monthly_spend' => needs[1], 'fee' => needs[2] };
    Integer guard = 0;
    while (byStep.containsKey(r.step) && guard++ < 20) {
        r = BandhuEngine.reply(BandhuJourneyService.byId(r.journey.Id), byStep.remove(r.step));
    }
    for (String a : (List<String>) p[10]) {
        r = BandhuEngine.reply(BandhuJourneyService.byId(r.journey.Id), a);
    }
    System.debug('### ' + p[0] + ' -> ' + r.step + ' (' + r.journey.Recommended_Card__c + ')');
    if (r.step != 'done') {
        dropped.add(r.journey.Id);
    }
}
List<Card_Journey__c> quiet = new List<Card_Journey__c>();
for (Id jid : dropped) {
    quiet.add(new Card_Journey__c(Id = jid, Last_Activity__c = Datetime.now().addMinutes(-60)));
}
update quiet;
BandhuDropOffJob.run();
for (Lead l : [SELECT Name, Status, Bandhu_Stage_Gate__c, Rating, Bandhu_Intent_Score__c, Bandhu_Credit_Score__c, Bandhu_CIBIL__c, Bandhu_Recommended_Card__c, Bandhu_Drop_Point__c
               FROM Lead WHERE MobilePhone IN :mobiles]) {
    System.debug('### lead ' + l.Name + ' ' + l.Status + ' [' + l.Bandhu_Stage_Gate__c + '] ' + l.Rating + ' intent ' + l.Bandhu_Intent_Score__c + ' credit ' + l.Bandhu_Credit_Score__c
        + ' CIBIL ' + l.Bandhu_CIBIL__c + ' card ' + l.Bandhu_Recommended_Card__c + ' @ ' + l.Bandhu_Drop_Point__c);
}
for (Card_Application__c a : [SELECT Applicant_Name__c, Card_Product__c, Status__c, Recommendation__c FROM Card_Application__c WHERE Mobile__c IN :mobiles]) {
    System.debug('### application ' + a.Applicant_Name__c + ' ' + a.Card_Product__c + ' ' + a.Status__c + ' (' + a.Recommendation__c + ')');
}
