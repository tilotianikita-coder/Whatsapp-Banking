// Bandhu demo: fast-forward time for the journeys that happen after the decision (org: bandhan).
// Set MOBILE to the customer's 10-digit mobile and MODE, then: sf apex run -f scripts/bandhan/apex/demo_after_issue.apex -o bandhan
//   'limit'       issued card -> activated, 6+ months on book, no missed payments, 75% used -> limit offer on WhatsApp
//   'reapproach'  declined / not-eligible / secured-offer journey -> 7 months later, fresh soft pull -> re-approach if eligible
//   'unactivated' issued card never activated -> 31 days later -> closed (RBI: no activation consent within 30 days)
// DRY_RUN = true prints what would happen and rolls back.
String MOBILE = '9063480755';
String MODE = 'limit';
Boolean DRY_RUN = false;

Savepoint sp = Database.setSavepoint();
List<Card_Journey__c> js = [SELECT Id, Card_Application__c, Customer_Name__c, Reassess_Status__c FROM Card_Journey__c
                            WHERE Mobile__c = :MOBILE ORDER BY CreatedDate DESC LIMIT 1];
if (js.isEmpty()) {
    System.debug('### no journey for ' + MOBILE);
} else if (MODE == 'reapproach') {
    Card_Journey__c j = js[0];
    update new Card_Journey__c(Id = j.Id, Reassess_Status__c = 'Pending', Reassess_On__c = BandhuI18n.today(), Bureau_At__c = Datetime.now().addMonths(-7));
    Integer n = BandhuPostIssue.reassess();
    Card_Journey__c after = [SELECT Reassess_Status__c, Reassess_On__c, CIBIL_Score__c, Recommended_Card__c FROM Card_Journey__c WHERE Id = :j.Id];
    System.debug('### re-approach: ' + (n == 1 ? 'ELIGIBLE now for ' + after.Recommended_Card__c + ' (CIBIL ' + after.CIBIL_Score__c + '): RM task + WhatsApp sent'
        : 'still not eligible (CIBIL ' + after.CIBIL_Score__c + '), next check ' + after.Reassess_On__c));
} else if (js[0].Card_Application__c == null) {
    System.debug('### no card application on the latest journey for ' + MOBILE);
} else if (MODE == 'limit') {
    Id appId = js[0].Card_Application__c;
    update new Card_Application__c(Id = appId, Activated_At__c = Datetime.now().addDays(-190), Card_Issued_At__c = Datetime.now().addDays(-200),
        Missed_Payments__c = 0, On_Time_Payments__c = 6, Avg_Utilisation_Pct__c = 75, Monthly_Card_Spend__c = 60000,
        Limit_Offer_Status__c = null, Limit_Offer__c = null, Upgrade_Offer_Card__c = null);
    Integer n = BandhuPostIssue.limitOffers();
    Card_Application__c a = [SELECT Card_Product__c, Credit_Limit__c, Limit_Offer__c, Upgrade_Offer_Card__c, Limit_Offer_Status__c, Status__c FROM Card_Application__c WHERE Id = :appId];
    System.debug('### limit offer: ' + (n == 1 ? a.Card_Product__c + ' ' + a.Credit_Limit__c + ' -> ' + a.Limit_Offer__c
        + (a.Upgrade_Offer_Card__c == null ? '' : ' (upgrade to ' + a.Upgrade_Offer_Card__c + ')') + ' sent on WhatsApp; customer replies Yes'
        : 'none (status ' + a.Status__c + ': needs an issued card)'));
} else if (MODE == 'unactivated') {
    Id appId = js[0].Card_Application__c;
    update new Card_Application__c(Id = appId, Activated_At__c = null, Activation_Due__c = BandhuI18n.today().addDays(-1));
    System.debug('### closed ' + BandhuCompliance.closeUnactivated() + ' unactivated card(s)');
}
if (DRY_RUN) {
    Database.rollback(sp);
    System.debug('### dry run: rolled back');
}
