/**
 * Picks up files a new-loan applicant sends on WhatsApp as soon as they land. A photo or PDF sent without a
 * caption reaches the agent as an empty message, which the planner answers on its own instead of calling the
 * journey, so the document step would never see the file. Here the file is recorded against the current
 * document step when it is linked to the conversation, and the next prompt is sent proactively.
 */
public with sharing class LoanSevaInboundFiles {
    private static final Set<String> DOC_STATES = new Set<String>{ 'doc_pan', 'doc_bank', 'doc_salary' };

    /** ContentDocumentLink after insert. Never blocks the file being saved. */
    public static void handle(List<ContentDocumentLink> links) {
        try {
            process(links);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoanSevaInboundFiles: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    @TestVisible
    private static void process(List<ContentDocumentLink> links) {
        Map<String, Set<Id>> filesBySource = new Map<String, Set<Id>>();
        for (ContentDocumentLink l : links) {
            Schema.SObjectType t = l.LinkedEntityId.getSobjectType();
            if (t == MessagingSession.SObjectType || t == MessagingEndUser.SObjectType || t == Loan_Journey__c.SObjectType) {
                for (String key : new List<String>{ l.LinkedEntityId, String.valueOf(l.LinkedEntityId).left(15) }) {
                    if (!filesBySource.containsKey(key)) {
                        filesBySource.put(key, new Set<Id>());
                    }
                    filesBySource.get(key).add(l.ContentDocumentId);
                }
            }
        }
        if (filesBySource.isEmpty()) {
            return;
        }
        // WhatsApp files are linked to the session only. A returning customer gets a new session before the
        // journey hears about it, so the session's end user is matched as well.
        Set<Id> sessionIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            if (l.LinkedEntityId.getSobjectType() == MessagingSession.SObjectType) {
                sessionIds.add(l.LinkedEntityId);
            }
        }
        if (!sessionIds.isEmpty()) {
            for (MessagingSession s : [SELECT Id, MessagingEndUserId FROM MessagingSession WHERE Id IN :sessionIds AND MessagingEndUserId != null]) {
                Set<Id> files = filesBySource.get(s.Id);
                for (String key : new List<String>{ s.MessagingEndUserId, String.valueOf(s.MessagingEndUserId).left(15) }) {
                    if (!filesBySource.containsKey(key)) {
                        filesBySource.put(key, new Set<Id>());
                    }
                    filesBySource.get(key).addAll(files);
                }
            }
        }
        Set<String> keys = filesBySource.keySet();
        List<Loan_Journey__c> journeys = Database.query(
            'SELECT ' + LoanSevaJourneyService.journeyFields() + ' FROM Loan_Journey__c WHERE Journey_Type__c = \'' + LoanSevaJourneyService.TYPE_NEW_LOAN + '\'' +
            ' AND Status__c = \'' + LoanSevaJourneyService.STATUS_ACTIVE + '\' AND Submitted_At__c = null AND Loan_Application__c != null' +
            ' AND (Id IN :keys OR Messaging_Session_Id__c IN :keys OR Messaging_End_User_Id__c IN :keys)'
        );
        if (journeys.isEmpty()) {
            return;
        }
        Set<Id> appIds = new Set<Id>();
        for (Loan_Journey__c j : journeys) {
            appIds.add(j.Loan_Application__c);
        }
        Set<String> recorded = new Set<String>();
        for (Loan_Document__c d : [SELECT Content_Document_Id__c FROM Loan_Document__c WHERE Loan_Application__c IN :appIds AND Content_Document_Id__c != null]) {
            recorded.add(d.Content_Document_Id__c);
        }

        String definition = LoanSevaConfig.get().Reengage_Definition__c;
        List<LoanSevaWhatsAppSender.Outbound> outbound = new List<LoanSevaWhatsAppSender.Outbound>();
        for (Loan_Journey__c j : journeys) {
            if (!DOC_STATES.contains(LoanSevaNewLoan.awaiting(j)) || !hasNewFile(j, filesBySource, recorded)) {
                continue;
            }
            // One journey per customer, so this runs once per inbound message, not per record in a bulk load.
            LoanSevaEngine.Result r = LoanSevaNewLoan.document(j, 'Done');
            if (r.success != false) {
                outbound.add(new LoanSevaWhatsAppSender.Outbound(j.Id, r.message, definition));
            }
        }
        LoanSevaWhatsAppSender.enqueue(outbound);
    }

    private static Boolean hasNewFile(Loan_Journey__c j, Map<String, Set<Id>> filesBySource, Set<String> recorded) {
        for (String key : new List<String>{ j.Id, j.Messaging_Session_Id__c, j.Messaging_End_User_Id__c }) {
            if (key != null && filesBySource.containsKey(key)) {
                for (Id fileId : filesBySource.get(key)) {
                    if (!recorded.contains(fileId)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
}
