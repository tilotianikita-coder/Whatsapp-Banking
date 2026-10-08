trigger LoanSevaExistingLoanTrigger on Existing_Loan__c (before insert) {
    LoanSevaCurrency.stampInr(Trigger.new);
}
