trigger LoanSevaContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    LoanSevaInboundFiles.handle(Trigger.new);
}
