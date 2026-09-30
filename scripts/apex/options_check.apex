// Walks one scenario through the same invocable actions the agent calls, then rolls everything back.
// Run all scenarios: python3 scripts/options_check.py   (substitutes SCENARIO below)
String scenario = 'SCENARIO';
Map<String, List<String>> scenarios = new Map<String, List<String>>{
    'menu_question'  => new List<String>{ '2', 'I would like to know more about PL', '2', 'What documents do I need', 'Hi', 'HI', 'EN' },
    'menu_specialist' => new List<String>{ '3' },
    'menu_typed_human' => new List<String>{ 'I want to talk to someone' },
    'loan_dispute'   => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', '2' },
    'offer_question' => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', '1', '1', 'Infosys', '3', '1', '1',
                                          '3', 'Yes', '3', 'I would like to know more about PL', 'what are the fees?', '3', 'tell me about the interest rate' },
    'offer_change'   => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', 'Yes', '2', 'TCS', '2', '4', '2',
                                          '2', '3 lakh for 48 months', '36 months', '1', '1', '5', '1', 'Great service' },
    'callback_slot'  => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', '1', '1', 'Wipro', '4', '6', '3', '1', '2', '4', '2', 'Skip' },
    'refer_retry'    => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', '1', '1', 'Infosys', '1', '2', '4', '1', 'hmm', '2 lakh for 48 months', '1' },
    'callback_typed' => new List<String>{ '1', 'Ananya Iyer 9000000003', '123456', '1', '1', 'Infosys', '1', '2', '1', 'accept', 'Thu 11am', '3', '3', 'Skip', 'Thanks' },
    'otp_wrong'      => new List<String>{ '1', 'Ananya Iyer 9000000003', '111111', '222222', '333333' },
    'hindi'          => new List<String>{ 'HI', '1', 'Ananya Iyer 9000000003', '123456', 'हाँ', '1', 'Infosys', '1', '1', '1', '3', 'क्या शुल्क है?', '1' }
};
Savepoint sp = Database.setSavepoint();
try {
    LoanSevaStartAction.Request s = new LoanSevaStartAction.Request();
    LoanSevaActionResult r = LoanSevaStartAction.run(new List<LoanSevaStartAction.Request>{ s })[0];
    String out = '### ' + scenario + '\nSTART -> ' + r.awaiting + ' | ' + r.message.left(90).replace('\n', ' ');
    for (String m : scenarios.get(scenario)) {
        if (new Set<String>{ 'HI', 'EN', 'MR' }.contains(m) && m.equals(m.toUpperCase())) {
            LoanSevaLanguageAction.Request l = new LoanSevaLanguageAction.Request();
            l.journeyId = r.journeyId;
            l.language = m;
            r = LoanSevaLanguageAction.run(new List<LoanSevaLanguageAction.Request>{ l })[0];
        } else {
            LoanSevaReplyAction.Request q = new LoanSevaReplyAction.Request();
            q.journeyId = r.journeyId;
            q.message = m;
            r = LoanSevaReplyAction.run(new List<LoanSevaReplyAction.Request>{ q })[0];
        }
        Loan_Journey__c j = [SELECT Offer_Accepted__c, Offer_Amount__c, Offer_Tenure_Months__c, Callback_DateTime__c, Escalated__c
                             FROM Loan_Journey__c WHERE Id = :r.journeyId];
        out += '\n[' + m + '] -> ' + r.awaiting + (r.success == false ? ' (not ok)' : '') + (r.handoff == true ? ' HANDOFF' : '')
            + (j.Offer_Accepted__c ? ' ACCEPTED' : '') + ' | ' + r.message.left(110).replace('\n', ' ');
    }
    System.debug(out + '\nSOQL ' + Limits.getQueries());
} finally {
    Database.rollback(sp);
}
