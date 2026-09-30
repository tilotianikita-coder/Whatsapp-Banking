trigger LoanSevaEventTrigger on LoanSeva_Event__e (after insert) {
    LoanSevaRegistrationService.handleEvents(Trigger.new);
}
