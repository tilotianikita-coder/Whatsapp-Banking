@IsTest
private class BandhuCreditApprovalTest {
    // an NSTP application in the underwriter queue: the settled-card PAN refers (CIBIL 765+, manual review)
    private static Card_Application__c referred() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '3', '2' }, '90000', 'ABCPS1237K');
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Card_Application__c app = [SELECT Id, Status__c, Card_Product__c, Credit_Limit__c, Card_Journey__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Under Review', app.Status__c);
        return app;
    }

    private static User approver(Integer level, String alias) {
        Profile p = [SELECT Id FROM Profile WHERE PermissionsModifyAllData = false AND UserLicense.Name = 'Salesforce' LIMIT 1];
        User u = new User(Alias = alias, Email = alias + '@bandhu.test', EmailEncodingKey = 'UTF-8', LastName = 'Approver ' + alias,
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_IN', ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
            Username = alias + '.' + System.currentTimeMillis() + '@bandhu.test', Bandhu_Credit_Level__c = level);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Bandhu_Admin'].Id);
        }
        return u;
    }

    @IsTest
    static void levelsFollowTheMatrixAndTheRiskRules() {
        Card_Application__c app = referred();
        String card = app.Card_Product__c;
        Bandhu_Card__mdt c = BandhuConfig.card(card);
        // a limit increase on the same card: at least L2, and the settled account sends it to L4
        BandhuCreditApproval.Assessment a = BandhuCreditApproval.assess(app.Id, card, app.Credit_Limit__c + 50000);
        System.assert(a.allowed, String.join(a.hardStops, '; '));
        System.assertEquals('Limit increase', a.requestType);
        System.assertEquals(4, a.level, String.join(a.reasons, '\n'));
        System.assert(String.join(a.reasons, '\n').contains('settled'), String.join(a.reasons, '\n'));
        // nothing to approve at the policy limit
        BandhuCreditApproval.Assessment none = BandhuCreditApproval.assess(app.Id, card, app.Credit_Limit__c);
        System.assert(!none.allowed);
        // beyond any authority
        BandhuCreditApproval.Assessment huge = BandhuCreditApproval.assess(app.Id, card, 3000000);
        System.assert(!huge.allowed);
        System.assert(String.join(huge.hardStops, ';').contains('card maximum'));
        System.assertEquals(4, BandhuCreditApproval.levels().size());
        System.assert(c != null);
    }

    @IsTest
    static void limitIncreaseApprovedUpTheHierarchyIssuesTheCard() {
        User l4 = approver(4, 'cco');
        User l2 = approver(2, 'scm');
        Card_Application__c app = referred();
        Decimal proposed = app.Credit_Limit__c + 50000;
        // the request needs L4 (settled account): an L2 approver is refused
        try {
            BandhuCreditApproval.submit(app.Id, app.Card_Product__c, proposed, l2.Id, 'Strong cash flow in bank statements',
                'Salary credits steady for 24 months, spends above the policy limit.', null);
            System.assert(false, 'L2 cannot take an L4 request');
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('L4'), e.getMessage());
        }
        // findings are required
        try {
            BandhuCreditApproval.submit(app.Id, app.Card_Product__c, proposed, l4.Id, 'Other', 'too short', null);
            System.assert(false, 'findings are required');
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('findings'));
        }
        Bandhu_Credit_Approval__c req = BandhuCreditApproval.submit(app.Id, app.Card_Product__c, proposed, l4.Id, 'Strong cash flow in bank statements',
            'Salary credits steady for 24 months; card-able spend above the policy limit. The settled card was 2 years ago.', 'Salary account');
        System.assertEquals('Pending Approval', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :req.Id AND OwnerId = :l4.Id]);
        // the underwriter queue decision is blocked while it is with the approver
        try {
            BandhuDecision.decide(app.Id, 'Approved', null);
            System.assert(false, 'blocked while pending approval');
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('approver'));
        }
        // a second request is refused
        try {
            BandhuCreditApproval.submit(app.Id, app.Card_Product__c, proposed, l4.Id, 'Other', 'Another request with enough words in it.', null);
            System.assert(false, 'one open request at a time');
        } catch (BandhuException e) {
            System.assert(e.getMessage().contains('open credit request'));
        }
        // an L2 user can't decide an L4 request
        System.runAs(l2) {
            System.assert(!BandhuCreditApproval.authority([SELECT Id, Requested_By__c, Required_Level__c FROM Bandhu_Credit_Approval__c WHERE Id = :req.Id]).ok);
        }
        Test.startTest();
        System.runAs(l4) {
            BandhuCreditApproval.decide(req.Id, 'Approved', 'Comfortable with the cash flow.');
        }
        Test.stopTest();
        Card_Application__c done = [SELECT Status__c, Credit_Limit__c, Card_Number_Masked__c FROM Card_Application__c WHERE Id = :app.Id];
        System.assertEquals('Card Issued', done.Status__c);
        System.assertEquals(proposed, done.Credit_Limit__c);
        Bandhu_Credit_Approval__c after = [SELECT Status__c, Decided_By__c, Customer_Consent__c FROM Bandhu_Credit_Approval__c WHERE Id = :req.Id];
        System.assertEquals('Approved', after.Status__c);
        System.assertEquals(l4.Id, after.Decided_By__c);
        System.assertEquals('Not needed', after.Customer_Consent__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :req.Id AND IsClosed = false]);
    }

    @IsTest
    static void upgradeNeedsTheCustomersConsentOnWhatsApp() {
        User l4 = approver(4, 'cco2');
        Card_Application__c app = referred();
        String up = null;
        Bandhu_Card__mdt cur = BandhuConfig.card(app.Card_Product__c);
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            if (c.Tier__c == cur.Tier__c + 1) {
                up = c.DeveloperName;
            }
        }
        if (up == null) {
            return;   // already the top card
        }
        BandhuCreditApproval.Assessment a = BandhuCreditApproval.assess(app.Id, up, null);
        System.assertEquals(1, a.tiersUp);
        Bandhu_Credit_Approval__c req = BandhuCreditApproval.submit(app.Id, up, null, l4.Id, 'Spends exceed the policy limit',
            'Frequent traveller abroad: four trips in 24 months, spends fit the higher card.', null);
        Test.startTest();
        System.runAs(l4) {
            BandhuCreditApproval.decide(req.Id, 'Approved', null);
        }
        Card_Journey__c j = BandhuJourneyService.byId(app.Card_Journey__c);
        System.assertEquals('upgrade_offer', j.Step__c);
        System.assertEquals('Approved', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
        // the customer says yes on WhatsApp
        BandhuEngine.Result r = BandhuEngine.reply(j, '1');
        Test.stopTest();
        Card_Application__c done = [SELECT Status__c, Card_Product__c FROM Card_Application__c WHERE Id = :app.Id];
        System.assertEquals('Card Issued', done.Status__c);
        System.assertEquals(up, done.Card_Product__c);
        System.assertEquals('Accepted', [SELECT Customer_Consent__c FROM Bandhu_Credit_Approval__c WHERE Id = :req.Id].Customer_Consent__c);
        System.assertEquals(1, [SELECT COUNT() FROM Bandhu_Consent__c WHERE Card_Journey__c = :j.Id AND Type__c = 'Card upgrade']);
        System.assertNotEquals(null, r);
    }

    @IsTest
    static void returnedAndWithdrawnGoBackToTheQueue() {
        User l4 = approver(4, 'cco3');
        Card_Application__c app = referred();
        Bandhu_Credit_Approval__c req = BandhuCreditApproval.submit(app.Id, app.Card_Product__c, app.Credit_Limit__c + 25000, l4.Id, 'Other',
            'Spends are higher than the limit allows, see statements.', null);
        System.runAs(l4) {
            try {
                BandhuCreditApproval.decide(req.Id, 'Returned', '');
                System.assert(false, 'a note is required to return');
            } catch (BandhuException e) {
                System.assert(e.getMessage().contains('note'));
            }
            BandhuCreditApproval.decide(req.Id, 'Returned', 'Please attach the latest salary slip.');
        }
        System.assertEquals('Under Review', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
        BandhuCreditApproval.Panel p = BandhuCreditApproval.getPanel(app.Id);
        System.assert(p.eligible, 'a new request can be raised');
        System.assertEquals(4, p.matrix.size());
        Bandhu_Credit_Approval__c again = BandhuCreditApproval.submit(app.Id, app.Card_Product__c, app.Credit_Limit__c + 25000, l4.Id, 'Other',
            'Salary slip attached: income confirmed at the declared level.', null);
        BandhuCreditApproval.withdrawRequest(again.Id);
        System.assertEquals('Withdrawn', [SELECT Status__c FROM Bandhu_Credit_Approval__c WHERE Id = :again.Id].Status__c);
        System.assertEquals('Under Review', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
        BandhuCreditApproval.Proposal pr = BandhuCreditApproval.propose(app.Id, app.Card_Product__c, app.Credit_Limit__c + 25000, null);
        System.assert(!pr.approvers.isEmpty());
    }

    @IsTest
    static void straightThroughApplicationsAreNotNstp() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '3', '2' }, '90000', BandhuTestData.GOOD_PAN);
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Card_Application__c app = [SELECT Id, Status__c, Card_Product__c, Credit_Limit__c FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Card Issued', app.Status__c);
        BandhuCreditApproval.Assessment a = BandhuCreditApproval.assess(app.Id, app.Card_Product__c, app.Credit_Limit__c + 50000);
        System.assert(!a.allowed);
        System.assert(String.join(a.hardStops, ';').contains('NSTP'));
        System.assert(!BandhuCreditApproval.getPanel(app.Id).eligible);
    }

    // ------------------------------------------------------------------ downgrades
    // the tax-record lever (PAN digits ending 2): AIS shows about 55% of the declared income
    private static Card_Application__c inflated() {
        BandhuTestData.useLogOnly();
        BandhuEngine.Result r = BandhuTestData.toRecommendation(BandhuTestData.NTB_MOBILE, new List<String>{ '1', '3', '2' }, '90000', 'ABCPS1232K');
        r = BandhuTestData.sayAll(r, new List<String>{ '1', '1234', BandhuConfig.get().Demo_OTP__c, 'Done', '1' });
        Card_Application__c app = [SELECT Id, Status__c, Card_Product__c, Credit_Limit__c, Card_Journey__c, Monthly_Income__c, Verified_Income__c,
                                       CIBIL_Score__c, Company_Name__c, City__c, PIN_Code__c, Employment_Type__c, PAN__c, Name, Reference_Number__c,
                                       Recommendation__c, Customer_Type__c, Eligible_Cards__c, Applicant_Name__c
                                   FROM Card_Application__c WHERE Card_Journey__c = :r.journey.Id];
        System.assertEquals('Under Review', app.Status__c, 'the tax record disagrees: referred');
        return app;
    }

    @IsTest
    static void mismatchesSupportACounterOfferTheCustomerCanRefuse() {
        User checker = approver(1, 'uw2');
        Card_Application__c app = inflated();
        BandhuCreditApproval.Evidence ev = BandhuCreditApproval.evidence(app);
        Set<String> keys = new Set<String>();
        for (BandhuCreditApproval.Mismatch m : ev.mismatches) {
            keys.add(m.key);
        }
        System.assert(keys.contains('tax'), 'the AIS mismatch is found: ' + keys);
        System.assert(ev.assessedIncome < app.Monthly_Income__c * 0.7, 'assessed on the tax record: ' + ev.assessedIncome);
        System.assertNotEquals(null, ev.suggestedCard);
        Bandhu_Card__mdt cur = BandhuConfig.card(app.Card_Product__c);
        Bandhu_Card__mdt sug = BandhuConfig.card(ev.suggestedCard);
        Boolean cardChange = sug.Tier__c < cur.Tier__c;
        // the counter-offer the evidence supports: L1 (a second underwriter), hard evidence, new to bank
        BandhuCreditApproval.Assessment a = BandhuCreditApproval.assess(app.Id, ev.suggestedCard, ev.suggestedLimit, new List<String>{ 'tax' });
        System.assert(a.allowed, String.join(a.hardStops, '; '));
        System.assertEquals('Downgrade', a.direction);
        System.assertEquals(1, a.level, String.join(a.reasons, '\n'));
        // a limit above what the evidence supports is an upgrade request, not a downgrade
        if (!cardChange) {
            BandhuCreditApproval.Assessment over = BandhuCreditApproval.assess(app.Id, ev.suggestedCard, app.Credit_Limit__c - 5000, new List<String>{ 'tax' });
            System.assert(over.allowed || String.join(over.hardStops, ';').contains('evidence supports'), String.join(over.hardStops, ';'));
        }
        // no mismatch ticked: stop
        BandhuCreditApproval.Assessment none = BandhuCreditApproval.assess(app.Id, ev.suggestedCard, ev.suggestedLimit, new List<String>());
        System.assert(!none.allowed);
        System.assert(String.join(none.hardStops, ';').contains('mismatch'));

        Bandhu_Credit_Approval__c req = BandhuCreditApproval.submit(app.Id, ev.suggestedCard, ev.suggestedLimit, checker.Id, 'Tax / GST records lower',
            'AIS shows about half the declared income; the lower card fits what we can verify instead of a decline.', null, new List<String>{ 'tax' });
        req = [SELECT Direction__c, Mismatches__c, Assessed_Income__c, Customer_Consent__c, Required_Level__c FROM Bandhu_Credit_Approval__c WHERE Id = :req.Id];
        System.assertEquals('Downgrade', req.Direction__c);
        System.assert(req.Mismatches__c.contains('AIS'), req.Mismatches__c);
        System.assertEquals(cardChange ? 'Pending' : 'Not needed', req.Customer_Consent__c);
        Test.startTest();
        System.runAs(checker) {
            BandhuCreditApproval.decide(req.Id, 'Approved', null);
        }
        if (cardChange) {
            Card_Journey__c j = BandhuJourneyService.byId(app.Card_Journey__c);
            System.assertEquals('upgrade_offer', j.Step__c);
            Bandhu_Credit_Approval__c offer = BandhuCreditApproval.pendingOffer(app.Id);
            String text = BandhuCreditApproval.offerText(j, app, offer);
            System.assert(text.contains(ev.suggestedCard) && text.contains('income'), text);
            System.assert(!text.containsIgnoreCase('AIS') && !text.containsIgnoreCase('fraud'), 'the customer is told the income reason only: ' + text);
            BandhuEngine.reply(j, '2');   // No: close the application
            Test.stopTest();
            System.assertEquals('Declined', [SELECT Status__c FROM Card_Application__c WHERE Id = :app.Id].Status__c);
            System.assertEquals('Declined', [SELECT Customer_Consent__c FROM Bandhu_Credit_Approval__c WHERE Id = :req.Id].Customer_Consent__c);
        } else {
            Test.stopTest();
            Card_Application__c done = [SELECT Status__c, Credit_Limit__c FROM Card_Application__c WHERE Id = :app.Id];
            System.assertEquals('Card Issued', done.Status__c);
            System.assertEquals(ev.suggestedLimit, done.Credit_Limit__c);
        }
    }

    @IsTest
    static void goingBelowTheEvidenceOrWithSoftSignalsNeedsMore() {
        User l2 = approver(2, 'scm2');
        Card_Application__c app = inflated();
        BandhuCreditApproval.Evidence ev = BandhuCreditApproval.evidence(app);
        Bandhu_Card__mdt sug = BandhuConfig.card(ev.suggestedCard);
        // the lowest card, below what the evidence supports (when there is one): L2
        String lowest = null;
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            if (c.Secured__c != true && (lowest == null || c.Tier__c < BandhuConfig.card(lowest).Tier__c)) {
                lowest = c.DeveloperName;
            }
        }
        if (BandhuConfig.card(lowest).Tier__c < sug.Tier__c) {
            BandhuCreditApproval.Assessment below = BandhuCreditApproval.assess(app.Id, lowest, null, new List<String>{ 'tax' });
            System.assert(below.allowed, String.join(below.hardStops, '; '));
            System.assert(below.level >= 2, String.join(below.reasons, '\n'));
        }
        // a card the assessed income doesn't support: stop
        BandhuCreditApproval.Assessment same = BandhuCreditApproval.assess(app.Id, app.Card_Product__c, app.Credit_Limit__c - 10000, new List<String>{ 'tax' });
        if (BandhuConfig.card(app.Card_Product__c).Min_Monthly_Income__c > ev.assessedIncome) {
            System.assert(!same.allowed, 'the applied-for card needs more than the assessed income');
        }
        System.assert(BandhuCreditApproval.sameEmployer('INFOSYS LTD', 'Infosys'));
        System.assert(!BandhuCreditApproval.sameEmployer('WIPRO LIMITED', 'Infosys'));
        BandhuCreditApproval.Panel p = BandhuCreditApproval.getPanel(app.Id);
        System.assertNotEquals(null, p.evidence);
        System.assert(!p.evidence.mismatches.isEmpty());
        System.assertNotEquals(null, l2);
    }
}
