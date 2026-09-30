// End-to-end walk of the LoanSeva engine (no WhatsApp). Prints every reply. Re-run seed.apex afterwards to reset.
Loan_Journey__c j = LoanSevaJourneyService.resolve(null, null, '9000000001');
List<LoanSevaEngine.Result> rs = new List<LoanSevaEngine.Result>();
LoanSevaEngine.Result r = LoanSevaEngine.start(j); rs.add(r);
rs.add(r = LoanSevaEngine.answerFaq(r.journey, 'What can I use the loan for?'));
rs.add(r = LoanSevaEngine.answerFaq(r.journey, 'how is this different from a new loan'));
rs.add(r = LoanSevaEngine.verifyCustomer(r.journey, 'Priya Sharma', '9000000001'));
rs.add(r = LoanSevaEngine.verifyOtp(r.journey, '111111'));
rs.add(r = LoanSevaEngine.verifyOtp(r.journey, '123456'));
rs.add(r = LoanSevaEngine.confirmLoan(r.journey, true));
rs.add(r = LoanSevaEngine.personalise(r.journey, '1'));
rs.add(r = LoanSevaEngine.personalise(r.journey, 'Infosys'));
rs.add(r = LoanSevaEngine.setLanguage(r.journey, 'HI'));
rs.add(r = LoanSevaEngine.personalise(r.journey, '3'));
rs.add(r = LoanSevaEngine.setLanguage(r.journey, 'EN'));
rs.add(r = LoanSevaEngine.personalise(r.journey, '1'));
rs.add(r = LoanSevaEngine.personalise(r.journey, '4'));
rs.add(r = LoanSevaEngine.offer(r.journey, null, '48 months'));
rs.add(r = LoanSevaEngine.acceptOffer(r.journey));
rs.add(r = LoanSevaEngine.scheduleCallback(r.journey, '2', null));
rs.add(r = LoanSevaEngine.feedback(r.journey, '5'));
rs.add(r = LoanSevaEngine.feedback(r.journey, '1'));
rs.add(r = LoanSevaEngine.feedback(r.journey, 'Super quick!'));
Integer i = 0;
for (LoanSevaEngine.Result x : rs) {
    System.debug('### ' + (i++) + ' [' + x.journey.Stage__c + '/' + x.journey.Status__c + '] ' + x.message);
}
Loan_Journey__c fin = LoanSevaJourneyService.byId(r.journey.Id);
System.debug('### SUMMARY ' + fin.Intent_Summary__c + ' | ref ' + fin.Reference_Number__c);
System.debug('### TASKS ' + [SELECT Subject FROM Task WHERE WhatId = :fin.Id OR WhatId = :fin.Loan_Application__c]);
System.debug('### EVENTS ' + [SELECT Subject, StartDateTime FROM Event WHERE WhatId = :fin.Loan_Application__c]);
