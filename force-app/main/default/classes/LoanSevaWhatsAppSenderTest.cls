@IsTest
private class LoanSevaWhatsAppSenderTest {
    private static Loan_Journey__c journey(String mobile) {
        Loan_Journey__c j = new Loan_Journey__c(Mobile__c = mobile, Customer_Name__c = 'Test Customer', Stage__c = 'Nudge', Status__c = 'Active', Language__c = 'EN', Consent_WhatsApp__c = true);
        insert j;
        return j;
    }

    private static void useSendMode(String mode) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get().clone();
        cfg.Send_Mode__c = mode;
        LoanSevaConfig.cached = cfg;
    }

    @IsTest
    static void logOnlyRecordsWhatWouldBeSent() {
        useSendMode(LoanSevaWhatsAppSender.MODE_LOG_ONLY);
        Loan_Journey__c j = journey('9811100001');
        Test.startTest();
        LoanSevaWhatsAppSender.enqueue(new List<LoanSevaWhatsAppSender.Outbound>{ new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hello Priya', 'LoanSeva_Text') });
        LoanSevaWhatsAppSender.enqueue(null);
        Test.stopTest();
        String status = [SELECT Last_Send_Status__c FROM Loan_Journey__c WHERE Id = :j.Id].Last_Send_Status__c;
        System.assert(status.startsWith('LogOnly'), status);
        System.assert(status.endsWith('Hello Priya'), status);
    }

    @IsTest
    static void largeBatchesAreChained() {
        useSendMode(LoanSevaWhatsAppSender.MODE_LOG_ONLY);
        List<Loan_Journey__c> js = new List<Loan_Journey__c>();
        for (Integer i = 0; i < LoanSevaWhatsAppSender.MAX_PER_JOB + 5; i++) {
            js.add(new Loan_Journey__c(Mobile__c = String.valueOf(9811200000L + i), Stage__c = 'Nudge', Status__c = 'Active', Language__c = 'EN'));
        }
        insert js;
        List<LoanSevaWhatsAppSender.Outbound> out = new List<LoanSevaWhatsAppSender.Outbound>();
        for (Loan_Journey__c j : js) {
            out.add(new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hi', null));
        }
        Test.startTest();
        new LoanSevaWhatsAppSender(out).execute(null);
        Test.stopTest();
        // the first job sends MAX_PER_JOB and chains the rest into a second job
        System.assertEquals(js.size(), [SELECT COUNT() FROM Loan_Journey__c WHERE Last_Send_Status__c LIKE 'LogOnly%'], 'Every journey is sent across the chained jobs');
    }

    @IsTest
    static void conversationMessageModeCreatesEndUserAndSends() {
        useSendMode('ConversationMessage');
        List<MessagingChannel> channels = [SELECT Id FROM MessagingChannel WHERE DeveloperName = :LoanSevaConfig.get().WhatsApp_Channel__c];
        Loan_Journey__c j = journey('9811100002');
        Loan_Journey__c noMobile = journey(null);
        Test.startTest();
        if (channels.isEmpty()) {
            try {
                LoanSevaWhatsAppSender.send(new List<LoanSevaWhatsAppSender.Outbound>{ new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hi', null) });
                System.assert(false, 'Expected a missing-channel error');
            } catch (LoanSevaException e) {
                System.assert(e.getMessage().contains('Messaging channel not found'));
            }
            Test.stopTest();
            return;
        }
        LoanSevaWhatsAppSender.send(new List<LoanSevaWhatsAppSender.Outbound>{
            new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hi', null),
            new LoanSevaWhatsAppSender.Outbound(noMobile.Id, 'Hi', null)
        });
        Test.stopTest();
        Loan_Journey__c sent = [SELECT Last_Send_Status__c, Messaging_End_User_Id__c FROM Loan_Journey__c WHERE Id = :j.Id];
        System.assert(sent.Last_Send_Status__c.startsWith('Sent'), sent.Last_Send_Status__c);
        MessagingEndUser u = [SELECT MessagingPlatformKey, MessagingChannelId FROM MessagingEndUser WHERE Id = :sent.Messaging_End_User_Id__c];
        System.assertEquals('919811100002', u.MessagingPlatformKey, 'Platform key is country code + mobile');
        System.assertEquals(channels[0].Id, u.MessagingChannelId);
        System.assert([SELECT Last_Send_Status__c FROM Loan_Journey__c WHERE Id = :noMobile.Id].Last_Send_Status__c.startsWith('Failed'), 'No mobile, no send');
    }

    @IsTest
    static void callSendReportsFailures() {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        LoanSevaWhatsAppSender.Outbound o = new LoanSevaWhatsAppSender.Outbound(null, 'Hi', null);
        System.assert(LoanSevaWhatsAppSender.callSend(o, null, cfg).startsWith('Failed'));
        LoanSevaWhatsAppSender.mockResults = null;
        System.assert(LoanSevaWhatsAppSender.callSend(o, '0PAxx0000000001', cfg).startsWith('Sent'));
    }

    @IsTest
    static void resendReusesEndUserAndLinksContact() {
        useSendMode('ConversationMessage');
        if ([SELECT COUNT() FROM MessagingChannel WHERE DeveloperName = :LoanSevaConfig.get().WhatsApp_Channel__c] == 0) {
            return; // channel-less org: covered by the missing-channel assertion above
        }
        Loan_Journey__c j = journey('9811100003');
        LoanSevaWhatsAppSender.send(new List<LoanSevaWhatsAppSender.Outbound>{ new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hi', null) });
        Id endUserId = [SELECT Messaging_End_User_Id__c FROM Loan_Journey__c WHERE Id = :j.Id].Messaging_End_User_Id__c;

        Contact c = new Contact(FirstName = 'Test', LastName = 'Customer', MobilePhone = '9811100003');
        insert c;
        update new Loan_Journey__c(Id = j.Id, Contact__c = c.Id);
        LoanSevaWhatsAppSender.send(new List<LoanSevaWhatsAppSender.Outbound>{ new LoanSevaWhatsAppSender.Outbound(j.Id, 'Hi again', null) });
        LoanSevaWhatsAppSender.send(null);

        System.assertEquals(endUserId, [SELECT Messaging_End_User_Id__c FROM Loan_Journey__c WHERE Id = :j.Id].Messaging_End_User_Id__c, 'Same end user reused');
        System.assertEquals(1, [SELECT COUNT() FROM MessagingEndUser WHERE MessagingPlatformKey = '919811100003']);
        System.assertEquals(c.Id, [SELECT ContactId FROM MessagingEndUser WHERE Id = :endUserId].ContactId, 'Contact linked once known');
    }
}
