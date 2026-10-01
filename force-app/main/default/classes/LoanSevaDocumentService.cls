/**
 * Documents a new-loan applicant shares on WhatsApp. Inbound attachments are stored as Salesforce Files
 * linked to the conversation (MessagingSession / MessagingEndUser) or the journey; each new file is recorded
 * as a Loan_Document__c and also linked to the application, so the RM sees it on the application record.
 */
public with sharing class LoanSevaDocumentService {
    /** Records files not seen before as docType; returns how many were new. */
    public static Integer collect(Loan_Journey__c j, String docType) {
        if (j.Loan_Application__c == null) {
            return 0;
        }
        Set<Id> sources = new Set<Id>{ j.Id };
        for (String candidate : new List<String>{ j.Messaging_Session_Id__c, j.Messaging_End_User_Id__c }) {
            if (LoanSevaJourneyService.isId(candidate)) {
                sources.add(candidate);
            }
        }
        Id appId = j.Loan_Application__c;
        Set<Id> known = new Set<Id>();
        for (Loan_Document__c d : [SELECT Content_Document_Id__c FROM Loan_Document__c WHERE Loan_Application__c = :appId]) {
            if (String.isNotBlank(d.Content_Document_Id__c)) {
                known.add(d.Content_Document_Id__c);
            }
        }
        Set<Id> linkedToApp = new Set<Id>();
        for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :appId]) {
            linkedToApp.add(l.ContentDocumentId);
        }

        Map<Id, ContentDocument> fresh = new Map<Id, ContentDocument>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.CreatedDate
            FROM ContentDocumentLink WHERE LinkedEntityId IN :sources
        ]) {
            if (!known.contains(l.ContentDocumentId)) {
                fresh.put(l.ContentDocumentId, l.ContentDocument);
            }
        }
        if (fresh.isEmpty()) {
            return 0;
        }
        List<Loan_Document__c> docs = new List<Loan_Document__c>();
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentDocument cd : fresh.values()) {
            String fileName = cd.Title + (String.isBlank(cd.FileExtension) || cd.Title.endsWithIgnoreCase('.' + cd.FileExtension) ? '' : '.' + cd.FileExtension);
            docs.add(new Loan_Document__c(
                Loan_Application__c = appId,
                Document_Type__c = docType,
                Status__c = 'Received',
                Content_Document_Id__c = cd.Id,
                File_Name__c = fileName.abbreviate(255),
                Received_At__c = cd.CreatedDate,
                Source__c = 'WhatsApp'
            ));
            if (!linkedToApp.contains(cd.Id)) {
                links.add(new ContentDocumentLink(LinkedEntityId = appId, ContentDocumentId = cd.Id, ShareType = 'V', Visibility = 'AllUsers'));
            }
        }
        insert docs;
        insert links;
        return docs.size();
    }
}
