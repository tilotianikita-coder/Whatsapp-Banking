trigger LoanSevaLoanApplicationTrigger on Loan_Application__c (before insert) {
    LoanSevaCurrency.stampInr(Trigger.new);
}
