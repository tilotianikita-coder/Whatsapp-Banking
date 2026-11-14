@IsTest
private class BandhuChannelsTest {
    @IsTest
    static void webJourneyIsBoundToItsToken() {
        BandhuTestData.useLogOnly();
        BandhuWebController.Turn t = BandhuWebController.start('EN', 'Web');
        System.assertNotEquals(null, t.token);
        System.assertEquals('menu', t.step);
        System.assertEquals(4, t.options.size());
        System.assertEquals(6, t.cards.size(), 'four cards, the co-branded and the secured card');
        System.assert(!t.message.contains('Reply *HI*'), 'the web page has its own language buttons');
        t = BandhuWebController.send(t.token, '1');
        System.assertEquals('consent', t.step);
        t = BandhuWebController.send(t.token, '1');
        t = BandhuWebController.send(t.token, 'Ananya Sen');
        System.assertEquals('mobile', t.step, 'the web asks for the mobile');
        t = BandhuWebController.send(t.token, '98765 00002');
        System.assertEquals('otp', t.step);
        t = BandhuWebController.language(t.token, 'BN');
        System.assertEquals('BN', t.language);
        try {
            BandhuWebController.send('not-a-token', 'hi');
            System.assert(false);
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('expired'));
        }
    }

    @IsTest
    static void agentActions() {
        BandhuTestData.useLogOnly();
        BandhuStartAction.Request s = new BandhuStartAction.Request();
        BandhuActionResult r = BandhuStartAction.run(new List<BandhuStartAction.Request>{ s })[0];
        System.assertEquals('menu', r.awaiting);
        System.assert(r.message.contains('1️⃣ Find my card'), r.message);

        BandhuReplyAction.Request rep = new BandhuReplyAction.Request();
        rep.journeyId = r.journeyId;
        rep.message = '2';
        r = BandhuReplyAction.run(new List<BandhuReplyAction.Request>{ rep })[0];
        System.assert(r.message.contains('Bandhan Bank credit cards'), r.message);

        BandhuEscalateAction.Request esc = new BandhuEscalateAction.Request();
        esc.journeyId = r.journeyId;
        esc.reason = 'wants a call';
        r = BandhuEscalateAction.run(new List<BandhuEscalateAction.Request>{ esc })[0];
        System.assert(r.handoff);

        rep.journeyId = 'not-an-id';
        rep.message = null;
        r = BandhuReplyAction.run(new List<BandhuReplyAction.Request>{ rep })[0];
        System.assertNotEquals(null, r.message);
    }

    @IsTest
    static void handoffPanelAndWhatsAppLogOnly() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.newToBankAtProfile(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '3', '2' });
        BandhuEngine.handoff(r.journey, 'asked for a person');
        BandhuConsoleController.Handoff h = BandhuConsoleController.getHandoff(r.journey.Id);
        System.assert(!h.hasJourney, 'no messaging session on this journey');
        Test.startTest();
        BandhuWhatsAppSender.send(new List<BandhuWhatsAppSender.Outbound>{ new BandhuWhatsAppSender.Outbound(r.journey.Id, 'hello', null) });
        Test.stopTest();
        System.assert(BandhuJourneyService.byId(r.journey.Id).Last_Send_Status__c.startsWith('LogOnly'));
    }

    @IsTest
    static void reviewForTheUnderwriter() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 2', '4', '2' }, '2.5 lakh', BandhuTestData.GOOD_PAN);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', 'a@b.co', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Card_Application__c app = [SELECT Id FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        BandhuConsoleController.Review rev = BandhuConsoleController.getReview(app.Id);
        System.assertEquals(9, rev.checks.size());
        System.assertEquals('Lumina', rev.card.name);
        System.assert(rev.decided);
        System.assert(rev.application.PAN__c.startsWith('XXXXX'), 'masked for the console');
        System.assert(rev.needs.contains('travel'), rev.needs);
    }
}
