trigger LoanSevaLoanJourneyTrigger on Loan_Journey__c (before insert) {
    LoanSevaCurrency.stampInr(Trigger.new);
}
