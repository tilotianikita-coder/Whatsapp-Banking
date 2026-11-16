@IsTest
private class BandhuLeadDashboardTest {
    @IsTest
    static void dashboardCountsTheFunnelDropOffsAndKnockouts() {
        BandhuTestData.useLogOnly();
        // an open lead dropped at the PIN code
        BandhuEngine.Result r = BandhuTestData.drive(BandhuTestData.newToBankVerified(BandhuTestData.NTB_MOBILE), new Map<String, String>{
            'email' => 'a@example.com', 'dob' => '12/04/1990', 'employment' => '1', 'income' => '1.5 lakh', 'pan' => BandhuTestData.GOOD_PAN });
        update new Card_Journey__c(Id = r.journey.Id, Last_Activity__c = Datetime.now().addMinutes(-30));
        Test.startTest();
        BandhuDropOffJob.run();
        Test.stopTest();
        Card_Journey__c j = BandhuJourneyService.byId(r.journey.Id);
        // a knocked-out lead (CIBIL below the cut-off), added directly
        Lead ko = new Lead(LastName = 'Saha', FirstName = 'Moumita', Company = 'Individual', LeadSource = BandhuLeadService.SOURCE,
            Status = 'Unqualified', Rating = 'Cold', Bandhu_CIBIL__c = 630, Bandhu_Stage_Gate__c = 'Knocked out at Credit Bureau',
            Bandhu_Drop_Point__c = 'Not eligible (10/10 details)');
        insert ko;
        insert new Bandhu_Lead_Check__c(Lead__c = ko.Id, Gate__c = 'Credit Bureau', Result__c = 'Fail', Knockout__c = true,
            Summary__c = 'CIBIL 630 (Poor) - below 650', Sort_Order__c = 4);

        BandhuLeadDashboard.Dashboard d = BandhuLeadDashboard.getDashboard(30, null);
        System.assertEquals(1, d.journeys);
        System.assertEquals(2, d.leads.size());
        System.assertEquals(BandhuLeadDashboard.FUNNEL.size(), d.funnel.size());
        System.assertEquals(1, d.funnel[0].count, 'started');
        System.assertEquals(1, d.funnel[1].count, 'mobile verified');
        System.assertEquals(0, d.funnel[8].count, 'no card issued');
        System.assertEquals(1, d.dropOffs.size());
        System.assertEquals('Verified & details', d.dropOffs[0].label);
        System.assertEquals('PIN code 1', d.dropOffs[0].note);
        System.assertEquals(1, d.knockouts.size());
        System.assertEquals('Credit Bureau', d.knockouts[0].label);
        System.assertEquals('CIBIL below the cut-off', d.knockouts[0].note);
        System.assertEquals(8, d.kpis.size());
        Boolean found = false;
        for (BandhuLeadDashboard.Row row : d.leads) {
            if (row.id == ko.Id) {
                found = true;
                System.assertEquals('Knocked out', row.outcome);
                System.assertEquals('Poor (below 650)', row.cibilBand);
            } else {
                System.assertEquals(j.Lead__c, row.id);
                System.assertEquals('Open', row.outcome);
                System.assertEquals('WhatsApp', row.channel);
            }
        }
        System.assert(found);

        // channel filter: no web journeys
        BandhuLeadDashboard.Dashboard web = BandhuLeadDashboard.getDashboard(0, 'Web');
        System.assertEquals(0, web.journeys);
        System.assertEquals(0, web.leads.size());
    }

    @IsTest
    static void reasonsGroupWithoutTheApplicantsNumbers() {
        System.assertEquals('CIBIL below the cut-off', BandhuLeadDashboard.reason('CIBIL 610 (Poor) - below 650, write-off on record'));
        System.assertEquals('Income below the minimum', BandhuLeadDashboard.reason('₹18,000/month, below the ₹25,000 minimum for any card'));
        System.assertEquals('PIN outside the card footprint', BandhuLeadDashboard.reason('PIN 744101 (Not serviceable) is outside the card footprint'));
        System.assertEquals('Aadhaar eKYC', BandhuLeadDashboard.stopLabel('Aadhaar eKYC (10/10 details)'));
        System.assertEquals('Card issued', BandhuLeadDashboard.stopLabel('Done'));
        System.assertEquals(null, BandhuLeadDashboard.stopLabel(null));
    }
}
