@IsTest
private class LoanSevaVoiceTest {
    private static final String MOBILE = '9123456780';
    private static Loan_Journey__c j;

    private class SttMock implements HttpCalloutMock {
        Integer status;
        String text;
        Integer calls = 0;
        HttpRequest last;

        SttMock(Integer status, String text) {
            this.status = status;
            this.text = text;
        }

        public HttpResponse respond(HttpRequest req) {
            calls++;
            last = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(status == 200 ? JSON.serialize(new Map<String, Object>{ 'text' => text, 'language_code' => 'eng' }) : '{"detail":"invalid_api_key"}');
            return res;
        }
    }

    private static void say(String text) {
        j = LoanSevaEngine.reply(j, text).journey;
    }

    /** New-loan customer, verified, now asked for their PAN. */
    private static void atPanStep() {
        LoanSevaTestData.useLogOnly();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        say('1');
        say('Asha Patil ' + MOBILE);
        say(LoanSevaConfig.get().Demo_OTP__c);
        say('15/08/1990');
        System.assertEquals('pan', LoanSevaEngine.awaiting(j));
    }

    private static Id addAudio(Id linkedTo) {
        ContentVersion v = new ContentVersion(Title = 'PTT-20261003-WA0001', PathOnClient = 'PTT-20261003-WA0001.opus',
            VersionData = Blob.valueOf('OggS-not-really-audio'), FirstPublishLocationId = linkedTo);
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    private static List<LoanSevaVoice.Note> note(Id fileId) {
        return new List<LoanSevaVoice.Note>{ new LoanSevaVoice.Note(fileId, j.Id) };
    }

    @IsTest
    static void spokenPanIsCapturedAndOnlyShownMasked() {
        atPanStep();
        Id fileId = addAudio(j.Id);
        SttMock mock = new SttMock(200, 'My PAN is A B C P P one two three four K.');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new LoanSevaVoice(note(fileId)).execute(null);
        Test.stopTest();

        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('ABCPP1234K', j.PAN__c);
        System.assertEquals('email', LoanSevaEngine.awaiting(j), 'the voice note answered the PAN step');
        System.assertEquals(fileId, j.Last_Voice_File_Id__c);
        System.assert(j.Last_Voice_Note__c.contains(LoanSevaNewLoan.maskPan('ABCPP1234K')), j.Last_Voice_Note__c);
        System.assert(!j.Last_Voice_Note__c.contains('ABCPP1234K'), 'the full PAN is never stored in the note');
        System.assert(mock.calls >= 1);
        System.assertEquals('callout:LoanSeva_ElevenLabs/v1/speech-to-text', mock.last.getEndpoint());
        System.assertEquals('POST', mock.last.getMethod());
        System.assert(mock.last.getHeader('Content-Type').startsWith('multipart/form-data; boundary='));
        String body = mock.last.getBodyAsBlob().toString();
        System.assert(body.contains('name="model_id"\r\n\r\n' + LoanSevaConfig.get().Voice_Model__c), body);
        System.assert(body.contains('filename="PTT-20261003-WA0001.opus"'), body);
        System.assert(body.contains('OggS-not-really-audio'));
    }

    @IsTest
    static void theSameNoteIsHandledOnce() {
        atPanStep();
        Id fileId = addAudio(j.Id);
        SttMock mock = new SttMock(200, 'A B C P P 1 2 3 4 K');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new LoanSevaVoice(note(fileId)).execute(null);
        Integer callsAfterFirst = mock.calls;
        new LoanSevaVoice(note(fileId)).execute(null);
        System.assertEquals(callsAfterFirst, mock.calls, 'a redelivered event must not answer the next step');
        Test.stopTest();
        System.assertEquals('email', LoanSevaEngine.awaiting(LoanSevaJourneyService.byId(j.Id)));
    }

    @IsTest
    static void serviceErrorAsksTheCustomerToRetry() {
        atPanStep();
        Id fileId = addAudio(j.Id);
        Test.setMock(HttpCalloutMock.class, new SttMock(401, null));
        Test.startTest();
        String text = LoanSevaVoice.transcribe(Blob.valueOf('x'), 'a.ogg');
        Test.stopTest();
        System.assertEquals(null, text);

        String reply = LoanSevaVoice.reply(j, fileId, text);
        System.assert(reply.startsWith(LoanSevaI18n.msg('Voice_Failed', 'EN')), reply);
        System.assert(reply.contains(LoanSevaEngine.pendingPrompt(LoanSevaJourneyService.byId(j.Id), false).left(20)), reply);
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('pan', LoanSevaEngine.awaiting(j), 'nothing was answered');
        System.assertEquals(fileId, j.Last_Voice_File_Id__c);
    }

    @IsTest
    static void spokenAnswersAreEchoedButTheOtpIsNot() {
        LoanSevaTestData.useLogOnly();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        say('1');
        Id fileId = addAudio(j.Id);

        String reply = LoanSevaVoice.reply(j, fileId, 'Asha Patil, nine one two three four five six seven eight zero.');
        System.assert(reply.startsWith(LoanSevaI18n.msg('Voice_Heard', 'EN', new Map<String, Object>{ 'text' => 'Asha Patil 9123456780' })), reply);
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals('9123456780', j.Mobile__c);

        say('1');
        System.assertEquals('otp', LoanSevaEngine.awaiting(j));
        String otp = LoanSevaConfig.get().Demo_OTP__c;
        reply = LoanSevaVoice.reply(j, fileId, String.join(otp.split(''), ' '));
        System.assert(reply.startsWith(LoanSevaI18n.msg('Voice_Received', 'EN')), reply);
        System.assert(!reply.contains(otp), 'the OTP is never echoed back');
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(true, j.OTP_Verified__c);
        System.assertEquals('dob', LoanSevaEngine.awaiting(j));
        System.assert(j.Last_Voice_Note__c.contains('(hidden)'));
    }

    @IsTest
    static void spokenRequestForAHumanAsksToTypeAgent() {
        LoanSevaTestData.useLogOnly();
        j = LoanSevaEngine.start(LoanSevaJourneyService.resolve(null, null, MOBILE)).journey;
        Id fileId = addAudio(j.Id);
        String reply = LoanSevaVoice.reply(j, fileId, 'I want to talk to a specialist.');
        System.assert(reply.endsWith(LoanSevaI18n.msg('Voice_Handoff', 'EN')), reply);
        System.assert([SELECT COUNT() FROM Task WHERE Subject LIKE 'LoanSeva: Human requested%'] > 0, 'the RM is still notified');
    }

    @IsTest
    static void voiceNoteOnTheDocumentStepIsNotADocument() {
        atPanStep();
        for (String answer : new List<String>{ 'abcpp1234k', 'asha.patil@example.com', 'Pune 411001', '1', 'Infosys', '85k', '0', '1', '3 lakh', '1' }) {
            say(answer);
        }
        System.assertEquals('doc_pan', LoanSevaEngine.awaiting(j));
        Test.setMock(HttpCalloutMock.class, new SttMock(200, 'I will send it later'));
        Test.startTest();
        Id fileId = addAudio(j.Id);
        Test.stopTest();
        j = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(0, [SELECT COUNT() FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c]);
        System.assertEquals(0, LoanSevaDocumentService.collect(j, 'PAN Card'), 'audio is skipped when collecting documents');
        System.assertNotEquals(null, fileId);
    }

    @IsTest
    static void eventsQueueOneTranscriptionJob() {
        System.assert(LoanSevaVoice.isAudio('OPUS'));
        System.assert(LoanSevaVoice.isAudio('ogg'));
        System.assert(!LoanSevaVoice.isAudio('jpg'));
        System.assert(!LoanSevaVoice.isAudio(null));
        Id docLike = '069000000000001AAA';
        Test.startTest();
        LoanSevaVoice.handleEvents(new List<LoanSeva_Voice__e>{
            new LoanSeva_Voice__e(Content_Document_Id__c = docLike, Source_Id__c = '0Mw000000000001AAA'),
            new LoanSeva_Voice__e(Content_Document_Id__c = docLike, Source_Id__c = '0Mw000000000001AAA'),
            new LoanSeva_Voice__e(Content_Document_Id__c = 'not-an-id')
        });
        System.assertEquals(1, Limits.getQueueableJobs());
        LoanSevaVoice.handleEvents(new List<LoanSeva_Voice__e>{ new LoanSeva_Voice__e(Content_Document_Id__c = 'x') });
        System.assertEquals(1, Limits.getQueueableJobs(), 'nothing valid, nothing queued');
        Test.stopTest();
    }
}
