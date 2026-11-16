// Bandhu demo data for the RM's Leads dashboard (org: bandhan): ~30 card journeys over the past month, spread across every
// step, channel, region, card and outcome, each scored into a Lead by the same qualification as a live journey.
// Run after reset_demo.apex, seed.apex and demo_leads.apex, once per batch (keeps within the SOQL limit):
//   for b in 0 1 2; do sed "s/^Integer BATCH = .*/Integer BATCH = $b;/" scripts/bandhan/apex/demo_dashboard.apex > /tmp/dd.apex; sf apex run -f /tmp/dd.apex -o bandhan; done
// Idempotent: replaces its own records (mobiles 90000003NN).
Integer BATCH = 0;
// name, channel, step reached, days ago, monthly income, PAN, PIN, outcome (open / dropped / knock / review / issued / etb)
List<List<Object>> ALL = new List<List<Object>>{
    new List<Object>{ 'Ananya Mitra', 'WhatsApp', 'aadhaar', 1, 120000, 'ABCPM4411K', '700019', 'dropped' },
    new List<Object>{ 'Rahul Banerjee', 'Web', 'choose', 1, 65000, 'ABCPB2201K', '700156', 'dropped' },
    new List<Object>{ 'Sneha Chatterjee', 'WhatsApp', 'aa', 2, 90000, 'ABCPC3301K', '711102', 'dropped' },
    new List<Object>{ 'Amit Kumar', 'Web', 'spend', 2, 48000, 'ABCPK6601K', '800001', 'dropped' },
    new List<Object>{ 'Riya Sen', 'WhatsApp', 'vkyc', 3, 210000, 'ABCPS7701K', '700091', 'dropped' },
    new List<Object>{ 'Tanmoy Dutta', 'Web', 'choose', 3, 82000, 'ABCPD8801K', '713216', 'dropped' },
    new List<Object>{ 'Payel Ghosh', 'Branch', 'review', 4, 140000, 'ABCPG9901K', '700064', 'dropped' },
    new List<Object>{ 'Subhajit Paul', 'WhatsApp', 'pan', 4, null, null, '700032', 'dropped' },
    new List<Object>{ 'Debolina Roy', 'Web', 'income', 5, null, 'ABCPR1102K', '781005', 'dropped' },
    new List<Object>{ 'Kunal Das', 'WhatsApp', 'otp', 5, null, null, null, 'dropped' },
    new List<Object>{ 'Ishita Bose', 'Web', 'choose', 6, 260000, 'ABCPB1203K', '700016', 'dropped' },
    new List<Object>{ 'Arnab Sarkar', 'WhatsApp', 'monthly_spend', 7, 55000, 'ABCPS1304K', '734001', 'dropped' },
    new List<Object>{ 'Priyanka Saha', 'Web', 'aadhaar', 8, 76000, 'ABCPS1401K', '751001', 'dropped' },
    new List<Object>{ 'Rajesh Mondal', 'WhatsApp', 'bureau', 9, 42000, 'ABCPM1501K', '713101', 'dropped' },
    new List<Object>{ 'Souvik Halder', 'Web', 'email', 10, null, null, null, 'dropped' },
    new List<Object>{ 'Nandini Pal', 'WhatsApp', 'choose', 12, 95000, 'ABCPP1601K', '700091', 'dropped' },
    new List<Object>{ 'Bikash Nath', 'WhatsApp', 'not_eligible', 2, 45000, 'ABCPN2101Z', '700150', 'knock' },
    new List<Object>{ 'Mithu Biswas', 'Web', 'not_eligible', 6, 18000, 'ABCPB2211K', '712101', 'knock' },
    new List<Object>{ 'Joydeep Ghoshal', 'WhatsApp', 'not_eligible', 9, 70000, 'ABCPG2301K', '744101', 'knock' },
    new List<Object>{ 'Shreya Kundu', 'Web', 'not_eligible', 14, 52000, 'ABCPK2401Z', '713204', 'knock' },
    new List<Object>{ 'Abhishek Jha', 'Web', 'not_eligible', 20, 21000, 'ABCPJ2501K', '800020', 'knock' },
    new List<Object>{ 'Sayantani Dey', 'WhatsApp', 'done', 3, 110000, 'ABCPD3101K', '700029', 'review' },
    new List<Object>{ 'Avik Chakraborty', 'Branch', 'done', 11, 68000, 'ABCPC3201K', '700101', 'review' },
    new List<Object>{ 'Moumita Ray', 'Web', 'done', 4, 150000, 'ABCPR3301K', '700020', 'issued' },
    new List<Object>{ 'Sandip Majumdar', 'WhatsApp', 'done', 8, 85000, 'ABCPM3401K', '711201', 'issued' },
    new List<Object>{ 'Rupa Basu', 'Branch', 'done', 13, 240000, 'ABCPB3501K', '700027', 'issued' },
    new List<Object>{ 'Partha Sinha', 'Web', 'done', 18, 47000, 'ABCPS3601K', '781001', 'issued' },
    new List<Object>{ 'Indrani Lahiri', 'WhatsApp', 'done', 24, 98000, 'ABCPL3701K', '700045', 'issued' },
    new List<Object>{ 'Gautam Saha', 'Branch', 'choose', 5, 130000, 'ABCPS4101K', '700068', 'etb' },
    new List<Object>{ 'Kakoli Das', 'WhatsApp', 'done', 16, 60000, 'ABCPD4201K', '700084', 'etb' }
};
Integer PER = 10;
List<List<Object>> mine = new List<List<Object>>();
for (Integer i = BATCH * PER; i < Math.min(ALL.size(), (BATCH + 1) * PER); i++) {
    mine.add(ALL[i]);
}
Map<String, Integer> FIELD_STEP = new Map<String, Integer>{ 'otp' => 0, 'email' => 1, 'dob' => 2, 'pincode' => 3, 'pan' => 4, 'employment' => 5,
    'income' => 6, 'aa' => 7, 'company' => 8, 'spend' => 9, 'monthly_spend' => 10, 'fee' => 11, 'bureau' => 12, 'choose' => 13,
    'not_eligible' => 13, 'aadhaar' => 14, 'vkyc' => 15, 'review' => 16, 'done' => 17 };

// clean up this batch's earlier run
List<String> mobiles = new List<String>();
for (Integer i = 0; i < mine.size(); i++) {
    mobiles.add('90000003' + String.valueOf(BATCH * PER + i).leftPad(2, '0'));
}
List<String> variants = new List<String>();
for (String m : mobiles) {
    variants.addAll(BandhuI18n.mobileVariants(m));
}
List<Lead> oldLeads = [SELECT Id FROM Lead WHERE MobilePhone IN :variants];
delete [SELECT Id FROM Task WHERE WhoId IN :oldLeads];
delete [SELECT Id FROM Bandhu_Lead_Check__c WHERE Lead__c IN :oldLeads];
List<Card_Journey__c> oldJ = [SELECT Id, Card_Application__c FROM Card_Journey__c WHERE Mobile__c IN :variants];
Set<Id> oldApps = new Set<Id>();
for (Card_Journey__c j : oldJ) {
    if (j.Card_Application__c != null) {
        oldApps.add(j.Card_Application__c);
    }
}
delete [SELECT Id FROM Card_Application__c WHERE Id IN :oldApps];
delete oldJ;
delete oldLeads;

List<Card_Journey__c> journeys = new List<Card_Journey__c>();
for (Integer i = 0; i < mine.size(); i++) {
    List<Object> p = mine[i];
    String step = (String) p[2];
    Integer reached = FIELD_STEP.get(step);
    Integer daysAgo = (Integer) p[3];
    Decimal income = (Decimal) p[4];
    String outcome = (String) p[7];
    Datetime started = Datetime.now().addDays(-daysAgo).addHours(-Math.mod(i * 5, 9));
    Card_Journey__c j = new Card_Journey__c(Customer_Name__c = (String) p[0], Mobile__c = mobiles[i], Channel__c = (String) p[1],
        Language__c = Math.mod(i, 3) == 0 ? 'BN' : Math.mod(i, 5) == 0 ? 'HI' : 'EN', Consent__c = true, Consent_At__c = started,
        Customer_Type__c = outcome == 'etb' ? 'Existing' : 'New', OTP_Verified__c = reached >= 1, Step__c = step,
        Status__c = outcome == 'dropped' ? 'Dropped' : outcome == 'knock' ? 'Exited' : step == 'done' ? 'Completed' : 'Active',
        Last_Activity__c = started.addMinutes(6 + reached), Fields_Done__c = 0);
    if (reached >= 2) { j.Email__c = ((String) p[0]).toLowerCase().replace(' ', '.') + '@example.com'; }
    if (reached >= 3) { j.Date_Of_Birth__c = Date.newInstance(1985 + Math.mod(i, 12), 1 + Math.mod(i, 12), 3 + i); }
    if (reached >= 4 && p[6] != null) {
        j.PIN_Code__c = (String) p[6];
        j.City__c = BandhuRisk.cityForPin(j.PIN_Code__c);
    }
    if (reached >= 5 && p[5] != null) { j.PAN__c = (String) p[5]; }
    if (reached >= 6) { j.Employment_Type__c = Math.mod(i, 4) == 3 ? 'Self-employed' : 'Salaried'; }
    if (reached >= 7 && income != null) { j.Monthly_Income__c = income; }
    if (reached >= 8 && income != null && Math.mod(i, 3) != 2) { j.Verified_Income__c = (income * 0.96).setScale(0); j.AA_Consent_At__c = started.addMinutes(4); j.AA_Consent_Id__c = 'AA-DEMO-' + mobiles[i]; }
    if (reached >= 9) { j.Company_Name__c = new List<String>{ 'TCS', 'Infosys', 'ITC Ltd', 'Wipro', 'Tata Steel', 'CESC', 'Accenture' }[Math.mod(i, 7)]; }
    if (reached >= 10) { j.Spend_Focus__c = new List<String>{ 'Travel;Dining', 'Groceries;Shopping', 'Fuel;Groceries', 'Travel;International', 'Dining;Shopping' }[Math.mod(i, 5)]; }
    if (reached >= 11) { j.Monthly_Spend__c = income == null ? 20000 : (income * 0.35).setScale(0); }
    if (reached >= 12) { j.Fee_Preference__c = Math.mod(i, 2) == 0 ? 'Best benefits' : 'Lowest fee'; }
    if (reached >= 13 && j.PAN__c != null) {
        j.Bureau_Consent__c = true;
        j.CIBIL_Score__c = BandhuProviders.cibil(j.PAN__c);
        j.Bureau_At__c = started.addMinutes(8);
    }
    if (reached >= 13 && step != 'not_eligible' && income != null && income >= 25000) {
        String card = income >= 200000 ? 'Lumina' : income >= 75000 ? 'Flare' : income >= 40000 ? 'Ignite' : 'Sparks';
        j.Recommended_Card__c = card;
        j.Eligible_Cards__c = income >= 200000 ? 'Sparks;Ignite;Flare;Lumina' : income >= 75000 ? 'Sparks;Ignite;Flare' : income >= 40000 ? 'Sparks;Ignite' : 'Sparks';
        j.Credit_Limit__c = (income * 2.5 / 5000).setScale(0) * 5000;
        j.Chosen_Card__c = reached >= 14 ? card : null;
    }
    if (reached >= 15) { j.KYC_Status__c = reached >= 16 ? 'Complete' : 'Not started'; }
    j.Stage__c = reached >= 17 ? (outcome == 'issued' ? 'Issued' : 'Decision') : reached >= 14 ? 'KYC' : reached >= 13 ? 'Recommend' : reached >= 7 ? 'Profile' : reached >= 1 ? 'Verify' : 'Start';
    if (outcome == 'dropped') {
        j.Dropped_At__c = j.Last_Activity__c.addMinutes(30);
        j.Drop_Point__c = BandhuLeadService.stepLabel(j) + ' (' + BandhuJourneyService.fieldsDone(j) + '/10 details)';
    }
    j.Fields_Done__c = BandhuJourneyService.fieldsDone(j);
    journeys.add(j);
}
insert journeys;

// applications for the submitted ones
Map<Id, Card_Application__c> apps = new Map<Id, Card_Application__c>();
for (Integer i = 0; i < journeys.size(); i++) {
    Card_Journey__c j = journeys[i];
    String outcome = (String) mine[i][7];
    if (j.Step__c == 'done' && j.Recommended_Card__c != null) {
        Boolean issued = outcome == 'issued' || outcome == 'etb';
        apps.put(j.Id, new Card_Application__c(Card_Journey__c = j.Id, Applicant_Name__c = j.Customer_Name__c, Mobile__c = j.Mobile__c,
            Card_Product__c = j.Recommended_Card__c, Credit_Limit__c = j.Credit_Limit__c, Monthly_Income__c = j.Monthly_Income__c,
            Verified_Income__c = j.Verified_Income__c, CIBIL_Score__c = j.CIBIL_Score__c, Channel__c = j.Channel__c,
            Customer_Type__c = j.Customer_Type__c, Employment_Type__c = j.Employment_Type__c, Company_Name__c = j.Company_Name__c,
            PAN__c = j.PAN__c, PIN_Code__c = j.PIN_Code__c, City__c = j.City__c,
            Status__c = issued ? 'Card Issued' : 'Under Review', Recommendation__c = issued ? 'Approve' : 'Refer',
            Submitted_At__c = j.Last_Activity__c, Card_Issued_At__c = issued ? j.Last_Activity__c.addMinutes(3) : null,
            Activated_At__c = issued && Math.mod(i, 2) == 0 ? j.Last_Activity__c.addHours(5) : null,
            Activation_Due__c = issued ? j.Last_Activity__c.date().addDays(30) : null,
            Card_Number_Masked__c = issued ? 'XXXX XXXX XXXX ' + String.valueOf(4100 + i) : null,
            Reference_Number__c = 'BDH-DEMO-' + j.Mobile__c.right(4)));
    }
}
insert apps.values();
for (Card_Journey__c j : journeys) {
    if (apps.containsKey(j.Id)) {
        j.Card_Application__c = apps.get(j.Id).Id;
    }
}

// score each new-to-bank prospect into its Lead (the live qualification: gates, rating, drop point)
for (Card_Journey__c j : journeys) {
    if (j.Customer_Type__c != 'Existing') {
        BandhuLeadService.upsertLead(j);
    }
}
update journeys;
List<Lead> nudge = new List<Lead>();
for (Integer i = 0; i < journeys.size(); i++) {
    Card_Journey__c j = journeys[i];
    if (j.Lead__c != null && j.Status__c == 'Dropped' && Math.mod(i, 3) == 1) {
        nudge.add(new Lead(Id = j.Lead__c, Bandhu_Last_Nudged__c = j.Dropped_At__c.addHours(2)));
    } else if (j.Lead__c != null && j.Stage__c == 'Issued') {
        nudge.add(new Lead(Id = j.Lead__c, Status = 'Qualified', Bandhu_Drop_Point__c = 'Card issued'));
    }
}
update nudge;
for (Lead l : [SELECT Name, Status, Rating, Bandhu_Stage_Gate__c, Bandhu_Drop_Point__c, Bandhu_Combined_Score__c FROM Lead WHERE MobilePhone IN :variants ORDER BY Name]) {
    System.debug('### ' + l.Name + ' | ' + l.Status + ' | ' + l.Rating + ' | ' + l.Bandhu_Stage_Gate__c + ' | ' + l.Bandhu_Drop_Point__c + ' | ' + l.Bandhu_Combined_Score__c);
}
System.debug('### batch ' + BATCH + ': ' + journeys.size() + ' journeys, ' + apps.size() + ' applications; SOQL ' + Limits.getQueries());
