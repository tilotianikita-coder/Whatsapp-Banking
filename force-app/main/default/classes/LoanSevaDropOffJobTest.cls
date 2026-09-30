@IsTest
private class LoanSevaDropOffJobTest {
    @TestSetup
    static void setup() {
        LoanSevaTestData.createCustomers();
    }

    private static Loan_Journey__c idleJourney(Integer minutesIdle) {
        Loan_Journey__c j = LoanSevaTestData.verifiedJourney(LoanSevaTestData.PRIYA_MOBILE, 'Priya Sharma');
        j = LoanSevaEngine.personalise(j, '1').journey;
        j = LoanSevaEngine.personalise(j, 'Infosys').journey;
        j = LoanSevaEngine.personalise(j, '3').journey;
        j = LoanSevaEngine.personalise(j, 'travel').journey;
        update new Loan_Journey__c(Id = j.Id, Last_Activity__c = Datetime.now().addMinutes(-minutesIdle), Consent_WhatsApp__c = true);
        return j;
    }

    @IsTest
    static void idleJourneyIsDroppedWithRmTaskThenNudgedTwice() {
        LoanSevaTestData.useLogOnly();
        Loan_Journey__c j = idleJourney(60);
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();

        LoanSevaDropOffJob.run();
        Loan_Journey__c d = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(LoanSevaJourneyService.STATUS_DROPPED, d.Status__c);
        System.assertEquals('Personalise (4/5 fields)', d.Drop_Point__c, 'Drop point keeps stage and progress');
        System.assertEquals(4, d.Fields_Completed__c);
        System.assertEquals(0, d.Nudges_Sent__c);
        System.assert(d.RM_Followup_Created__c);
        Task t = [SELECT Subject, Description, WhoId FROM Task WHERE WhatId = :j.Id];
        System.assert(t.Subject.contains('Drop-off at Personalise'), t.Subject);
        System.assert(t.Description.contains('travel'), 'Task carries the captured intent');
        System.assertEquals(d.Contact__c, t.WhoId);

        // nudge 1 once its delay has passed
        update new Loan_Journey__c(Id = j.Id, Next_Nudge_At__c = Datetime.now().addMinutes(-1));
        Test.startTest();
        LoanSevaDropOffJob.run();
        Test.stopTest();
        d = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(1, d.Nudges_Sent__c);
        System.assertEquals(d.Dropped_At__c.addMinutes(Integer.valueOf(cfg.Nudge_2_Delay_Minutes__c)), d.Next_Nudge_At__c, 'Nudge 2 is timed from the drop');
        System.assert(d.Last_Send_Status__c.contains('Priya'), d.Last_Send_Status__c);
        System.assert(d.Last_Send_Status__c.contains('for travel'), 'Nudge 1 mentions the purpose');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :j.Id], 'No duplicate RM task');

        // nudge 2, then nothing more
        update new Loan_Journey__c(Id = j.Id, Next_Nudge_At__c = Datetime.now().addMinutes(-1));
        LoanSevaDropOffJob.run();
        d = LoanSevaJourneyService.byId(j.Id);
        System.assertEquals(2, d.Nudges_Sent__c);
        System.assertEquals(null, d.Next_Nudge_At__c);

        // a reply re-activates the journey where it left off
        LoanSevaEngine.Result r = LoanSevaEngine.personalise(d, '2 lakh');
        System.assertEquals(LoanSevaJourneyService.STATUS_ACTIVE, r.journey.Status__c);
        System.assertEquals(200000, r.journey.Desired_Amount__c);
    }

    @IsTest
    static void recentAndNonConsentingJourneysAreLeftAlone() {
        Loan_Journey__c j = idleJourney(0);
        LoanSevaDropOffJob.run();
        System.assertEquals(LoanSevaJourneyService.STATUS_ACTIVE, LoanSevaJourneyService.byId(j.Id).Status__c);

        update new Loan_Journey__c(Id = j.Id, Status__c = 'Dropped', Next_Nudge_At__c = Datetime.now().addMinutes(-5), Consent_WhatsApp__c = false, Nudges_Sent__c = 0);
        LoanSevaDropOffJob.run();
        System.assertEquals(0, LoanSevaJourneyService.byId(j.Id).Nudges_Sent__c, 'No WhatsApp consent, no nudge');
    }

    @IsTest
    static void reengageTextIsLocalised() {
        Loan_Journey__c j = new Loan_Journey__c(Customer_Name__c = 'meera patil', Language__c = 'EN', Purpose__c = 'Medical');
        System.assertEquals(LoanSevaI18n.msg('Reengage_1', 'EN', new Map<String, Object>{ 'name' => 'Meera', 'purpose' => ' for medical' }), LoanSevaDropOffJob.reengageText(j, 1));
        j.Language__c = 'HI';
        System.assertEquals(LoanSevaI18n.msg('Reengage_2', 'HI', new Map<String, Object>{ 'name' => 'Meera', 'purpose' => '' }), LoanSevaDropOffJob.reengageText(j, 2));
    }

    @IsTest
    static void startSchedulesAndStopUnschedules() {
        Test.startTest();
        Id jobId = LoanSevaDropOffJob.start();
        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'LoanSeva Drop-off%']);
        LoanSevaDropOffJob.start();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'LoanSeva Drop-off%'], 'Restart replaces the job');
        new LoanSevaDropOffJob().execute(null);
        LoanSevaDropOffJob.stop();
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'LoanSeva Drop-off%']);
    }
}
