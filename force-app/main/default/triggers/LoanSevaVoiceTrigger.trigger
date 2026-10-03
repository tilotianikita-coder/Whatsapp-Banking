trigger LoanSevaVoiceTrigger on LoanSeva_Voice__e (after insert) {
    LoanSevaVoice.handleEvents(Trigger.new);
}
