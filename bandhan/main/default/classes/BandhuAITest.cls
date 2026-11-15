/**
 * Agentforce (Prompt Builder) in the journey: free-form card answers, the personal note after the recommendation on
 * WhatsApp and the web, and the underwriter brief. The template call is stubbed (BandhuAI.stub).
 */
@IsTest
private class BandhuAITest {
    @IsTest
    static void freeFormQuestionIsAnsweredFromTheCardsThenThePendingQuestionAgain() {
        BandhuTestData.useLogOnly();
        BandhuAI.stub = 'Yes, Flare works in Dubai: 4 domestic + 1 international lounge visits a quarter.';
        BandhuEngine.Result r = BandhuTestData.drive(BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE), new Map<String, String>{
            'email' => 'a@example.com', 'dob' => '12/04/1990', 'pincode' => 'Kolkata 700091', 'pan' => BandhuTestData.GOOD_PAN,
            'employment' => '1', 'income' => '1 lakh', 'aa' => '2', 'company' => 'Infosys' });
        System.assertEquals('spend', r.step, r.message);
        r = BandhuTestData.say(r, 'Can I use Flare in Dubai?');
        System.assert(r.message.startsWith(BandhuAI.stub), r.message);
        System.assertEquals('spend', r.step, 'the pending question is asked again');
        System.assertEquals(BandhuAI.TEMPLATE_ANSWER, BandhuAI.lastTemplate);
        System.assert(BandhuAI.lastInputs.get('Facts').contains('Flare | lounges'), 'grounded on the card catalogue');
        System.assertEquals('Can I use Flare in Dubai?', BandhuAI.lastInputs.get('Question'));
    }

    @IsTest
    static void withoutTheAiTheJourneyCarriesOn() {
        BandhuTestData.useLogOnly();
        BandhuAI.stub = null;
        BandhuEngine.Result r = BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE);
        r = BandhuTestData.say(r, 'what is the weather like in Kolkata today?');
        System.assertEquals('email', r.step, 'no answer: back to the pending question');
    }

    @IsTest
    static void personalDetailsAreNeverTreatedAsQuestions() {
        BandhuTestData.useLogOnly();
        BandhuAI.stub = 'should not be used';
        BandhuEngine.Result r = BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE);
        r = BandhuTestData.say(r, 'is this ok@example.com?');
        System.assertNotEquals(BandhuAI.stub, r.message);
        System.assert(BandhuEngine.isQuestion('Which card is best for groceries?'));
        System.assert(!BandhuEngine.isQuestion('Kolkata'));
    }

    @IsTest
    static void aPersonalNoteFollowsTheRecommendationOnBothChannels() {
        BandhuTestData.useLogOnly();
        BandhuAI.stub = '✨ Ananya, your travel spends earn 20 points per ₹200 on Flare.';
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '4', '2', '2' }, '1 lakh', 'ABCPT1234K');
        System.assertEquals('choose', r.step);
        System.assertEquals('why', r.aiFollowUp);
        // WhatsApp: queued, then sent
        Test.startTest();
        BandhuAIFollowUp.queueFor(r);
        Test.stopTest();
        System.assertEquals(BandhuAI.TEMPLATE_NOTE, BandhuAI.lastTemplate);
        System.assert(BandhuAI.lastInputs.get('Facts').contains('Bandhan Flare'), BandhuAI.lastInputs.get('Facts'));
        System.assert(BandhuAI.lastInputs.get('Facts').contains('trips abroad'), 'grounded on the statements');
        System.assert(BandhuJourneyService.byId(r.journey.Id).Last_Send_Status__c.startsWith('LogOnly'));
    }

    @IsTest
    static void theWebPageFetchesTheNoteItself() {
        BandhuTestData.useLogOnly();
        BandhuAI.stub = '✨ a note';
        BandhuWebController.Turn t = BandhuWebController.start('EN', 'Web');
        Card_Journey__c j = BandhuJourneyService.byToken(t.token);
        update new Card_Journey__c(Id = j.Id, Recommended_Card__c = 'Flare', Customer_Name__c = 'Ananya Sen');
        System.assertEquals('✨ a note', BandhuWebController.followUp(t.token, 'why'));
        System.assertEquals(null, BandhuWebController.followUp(t.token, 'something else'));
        System.assertEquals(null, BandhuWebController.followUp('no-such-token', 'why'));
    }

    @IsTest
    static void theUnderwriterBriefIsWrittenAndSaved() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1, 3', '3', '2' }, '1 lakh', 'ABCPS1237K');
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Id appId = [SELECT Id FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id].Id;
        BandhuAI.stub = 'SUMMARY: ...\nSTRENGTHS:\n+ Excellent CIBIL\nCONCERNS:\n- Settled account\nSUGGESTED DECISION: Approve with a lower limit.';
        Card_Application__c a = BandhuConsoleController.generateBrief(appId);
        System.assert(a.AI_Brief__c.contains('SUGGESTED DECISION'));
        System.assertNotEquals(null, a.AI_Brief_At__c);
        System.assertEquals(BandhuAI.TEMPLATE_BRIEF, BandhuAI.lastTemplate);
        String facts = BandhuAI.lastInputs.get('Facts');
        System.assert(facts.contains('Bandhan Score') && facts.contains('Settled') && facts.contains('Bank statements'), facts);
        BandhuAI.stub = null;
        try {
            BandhuConsoleController.generateBrief(appId);
            System.assert(false, 'no brief without the AI');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
