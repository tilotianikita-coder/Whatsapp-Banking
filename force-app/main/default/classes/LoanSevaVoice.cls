/**
 * WhatsApp voice notes. A note arrives as an audio file linked to the conversation; LoanSevaInboundFiles
 * (running as Automated Process) publishes LoanSeva_Voice__e, and LoanSevaVoiceTrigger runs as the
 * subscriber user, who has access to the ElevenLabs credential. This job transcribes the note
 * (ElevenLabs speech-to-text via Named Credential LoanSeva_ElevenLabs), shapes the text for the current
 * step (LoanSevaVoiceText), runs it through the journey exactly like a typed reply, and sends the answer
 * on WhatsApp with what was heard (PAN masked, OTP never echoed).
 */
public with sharing class LoanSevaVoice implements Queueable, Database.AllowsCallouts {
    public static final Set<String> AUDIO_EXTENSIONS = new Set<String>{ 'ogg', 'oga', 'opus', 'mp3', 'm4a', 'aac', 'amr', 'wav' };
    private static final String ENDPOINT = 'callout:LoanSeva_ElevenLabs/v1/speech-to-text';
    private static final Integer MAX_BYTES = 5 * 1024 * 1024;
    /** One job handles them all (it may enqueue only the WhatsApp send); a customer sends one note at a time. */
    private static final Integer MAX_PER_JOB = 20;

    public class Note {
        public Id fileId;
        public String sourceId;

        public Note(Id fileId, String sourceId) {
            this.fileId = fileId;
            this.sourceId = sourceId;
        }
    }

    private final List<Note> notes;

    public LoanSevaVoice(List<Note> notes) {
        this.notes = notes;
    }

    public static Boolean isAudio(String extension) {
        return extension != null && AUDIO_EXTENSIONS.contains(extension.toLowerCase());
    }

    public static Boolean enabled() {
        return LoanSevaConfig.get().Voice_Enabled__c == true;
    }

    /** From the file trigger: one event per voice note, keyed to the conversation record it is linked to. */
    public static void publish(Map<Id, String> sourceByFile) {
        if (sourceByFile.isEmpty() || !enabled()) {
            return;
        }
        List<LoanSeva_Voice__e> events = new List<LoanSeva_Voice__e>();
        for (Id fileId : sourceByFile.keySet()) {
            events.add(new LoanSeva_Voice__e(Content_Document_Id__c = fileId, Source_Id__c = sourceByFile.get(fileId)));
        }
        EventBus.publish(events);
    }

    /** LoanSevaVoiceTrigger: callouts can't run in a trigger, so the work is queued. */
    public static void handleEvents(List<LoanSeva_Voice__e> events) {
        Map<String, Note> byFile = new Map<String, Note>();
        for (LoanSeva_Voice__e e : events) {
            if (LoanSevaJourneyService.isId(e.Content_Document_Id__c) && byFile.size() < MAX_PER_JOB) {
                byFile.put(e.Content_Document_Id__c, new Note(e.Content_Document_Id__c, e.Source_Id__c));
            }
        }
        if (!byFile.isEmpty()) {
            System.enqueueJob(new LoanSevaVoice(byFile.values()));
        }
    }

    public void execute(QueueableContext ctx) {
        // Everything is read and every callout made before the first DML.
        Map<Id, Loan_Journey__c> journeyByFile = journeys(notes);
        Set<Id> fileIds = new Set<Id>();
        for (Id fileId : journeyByFile.keySet()) {
            if (journeyByFile.get(fileId).Last_Voice_File_Id__c != fileId) {
                fileIds.add(fileId);
            }
        }
        Map<Id, String> transcripts = new Map<Id, String>();
        for (ContentVersion v : [
            SELECT ContentDocumentId, Title, FileExtension, ContentSize, VersionData
            FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true
        ]) {
            transcripts.put(v.ContentDocumentId, v.ContentSize > MAX_BYTES ? null : transcribe(v.VersionData, v.Title + '.' + v.FileExtension));
        }

        String definition = LoanSevaConfig.get().Reengage_Definition__c;
        List<LoanSevaWhatsAppSender.Outbound> outbound = new List<LoanSevaWhatsAppSender.Outbound>();
        for (Id fileId : fileIds) {
            Loan_Journey__c j = journeyByFile.get(fileId);
            String transcript = transcripts.get(fileId);
            outbound.add(new LoanSevaWhatsAppSender.Outbound(j.Id, reply(j, fileId, transcript), definition));
        }
        LoanSevaWhatsAppSender.enqueue(outbound);
    }

    /** Runs the transcript through the journey as a typed reply; returns the WhatsApp answer. */
    @TestVisible
    private static String reply(Loan_Journey__c j, Id fileId, String transcript) {
        String lang = j.Language__c;
        String state = LoanSevaEngine.awaiting(j);
        if (String.isBlank(transcript)) {
            update new Loan_Journey__c(Id = j.Id, Last_Voice_File_Id__c = fileId, Last_Voice_Note__c = '(not understood)');
            return LoanSevaI18n.msg('Voice_Failed', lang) + '\n\n' + LoanSevaEngine.pendingPrompt(j, false);
        }
        String typed = LoanSevaVoiceText.forState(transcript, state);
        String heard = heardAs(state, typed);
        LoanSevaEngine.Result r = LoanSevaEngine.reply(j, typed);
        update new Loan_Journey__c(Id = j.Id, Last_Voice_File_Id__c = fileId, Last_Voice_Note__c = (state + ': ' + (heard == null ? '(hidden)' : heard)).abbreviate(255));
        String echo = heard == null
            ? LoanSevaI18n.msg('Voice_Received', lang)
            : LoanSevaI18n.msg('Voice_Heard', lang, new Map<String, Object>{ 'text' => heard });
        // Only the agent can transfer the chat to Omni-Channel, and a voice note never reaches it: ask for a typed request.
        return echo + '\n\n' + (r.handoff == true ? LoanSevaI18n.msg('Voice_Handoff', lang) : r.message);
    }

    /** What is shown back: the PAN masked, the OTP never. Null means don't echo. */
    private static String heardAs(String state, String typed) {
        if (state == 'otp') {
            return null;
        }
        if (state == 'pan') {
            String pan = LoanSevaNewLoan.parsePan(typed);
            return pan == null ? null : 'PAN ' + LoanSevaNewLoan.maskPan(pan);
        }
        return typed.abbreviate(200);
    }

    /** The open journey for each note: by the conversation it came in on, its end user, or their mobile. */
    private static Map<Id, Loan_Journey__c> journeys(List<Note> notes) {
        Set<String> sessionIds = new Set<String>();
        for (Note n : notes) {
            if (LoanSevaJourneyService.isId(n.sourceId) && ((Id) n.sourceId).getSobjectType() == MessagingSession.SObjectType) {
                sessionIds.add(n.sourceId);
            }
        }
        Map<String, Set<String>> keysBySource = new Map<String, Set<String>>();
        for (Note n : notes) {
            if (LoanSevaJourneyService.isId(n.sourceId)) {
                keysBySource.put(n.sourceId, new Set<String>{ n.sourceId, n.sourceId.left(15) });
            }
        }
        for (MessagingSession s : [
            SELECT Id, MessagingEndUserId, MessagingEndUser.MessagingPlatformKey FROM MessagingSession WHERE Id IN :sessionIds
        ]) {
            Set<String> keys = keysBySource.get(s.Id);
            if (keys == null) {
                keys = keysBySource.get(String.valueOf(s.Id).left(15));
            }
            if (keys != null && s.MessagingEndUserId != null) {
                keys.add(s.MessagingEndUserId);
                keys.add(String.valueOf(s.MessagingEndUserId).left(15));
                String mobile = LoanSevaJourneyService.normalizeMobile(s.MessagingEndUser.MessagingPlatformKey);
                if (mobile != null) {
                    keys.add('mobile:' + mobile);
                }
            }
        }
        Set<String> ids = new Set<String>();
        Set<String> mobiles = new Set<String>();
        for (Set<String> keys : keysBySource.values()) {
            for (String k : keys) {
                if (k.startsWith('mobile:')) {
                    mobiles.add(k.removeStart('mobile:'));
                } else {
                    ids.add(k);
                }
            }
        }
        List<Loan_Journey__c> open = Database.query(
            'SELECT ' + LoanSevaJourneyService.journeyFields() + ' FROM Loan_Journey__c' +
            ' WHERE Status__c IN (\'' + LoanSevaJourneyService.STATUS_ACTIVE + '\', \'' + LoanSevaJourneyService.STATUS_DROPPED + '\')' +
            ' AND (Id IN :ids OR Messaging_Session_Id__c IN :ids OR Messaging_End_User_Id__c IN :ids OR Mobile__c IN :mobiles)' +
            ' ORDER BY LastModifiedDate DESC'
        );
        Map<Id, Loan_Journey__c> result = new Map<Id, Loan_Journey__c>();
        for (Note n : notes) {
            Set<String> keys = keysBySource.get(n.sourceId);
            for (Loan_Journey__c j : keys == null ? new List<Loan_Journey__c>() : open) {
                if (keys.contains(j.Id) || keys.contains(j.Messaging_Session_Id__c) || keys.contains(j.Messaging_End_User_Id__c)
                        || keys.contains('mobile:' + j.Mobile__c)) {
                    result.put(n.fileId, j);
                    break;
                }
            }
        }
        return result;
    }

    /** ElevenLabs speech-to-text (multipart upload). Null on any failure, so the customer is asked to retry. */
    @TestVisible
    private static String transcribe(Blob audio, String fileName) {
        String boundary = '----LoanSeva' + String.valueOf(Crypto.getRandomLong()).replace('-', '');
        Map<String, String> fields = new Map<String, String>{
            'model_id' => String.isBlank(LoanSevaConfig.get().Voice_Model__c) ? 'scribe_v1' : LoanSevaConfig.get().Voice_Model__c,
            'tag_audio_events' => 'false'
        };
        String hex = '';
        for (String name : fields.keySet()) {
            hex += EncodingUtil.convertToHex(Blob.valueOf('--' + boundary + '\r\nContent-Disposition: form-data; name="' + name + '"\r\n\r\n' + fields.get(name) + '\r\n'));
        }
        hex += EncodingUtil.convertToHex(Blob.valueOf('--' + boundary + '\r\nContent-Disposition: form-data; name="file"; filename="'
            + fileName.replaceAll('[^A-Za-z0-9._-]', '_') + '"\r\nContent-Type: application/octet-stream\r\n\r\n'));
        hex += EncodingUtil.convertToHex(audio);
        hex += EncodingUtil.convertToHex(Blob.valueOf('\r\n--' + boundary + '--\r\n'));

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setBodyAsBlob(EncodingUtil.convertFromHex(hex));
        req.setTimeout(60000);
        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.ERROR, 'LoanSevaVoice: ElevenLabs ' + res.getStatusCode() + ' ' + res.getBody().abbreviate(500));
                return null;
            }
            Object text = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('text');
            return text == null ? null : String.valueOf(text).trim();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoanSevaVoice: ' + e.getMessage());
            return null;
        }
    }
}
