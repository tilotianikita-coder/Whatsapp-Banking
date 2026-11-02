@IsTest
private class LoanSevaHandoffTest {
    // a well-formed MessagingSession Id: the card finds the journey by the Id the bot stamped on it
    private static final Id SESSION_ID = Id.valueOf('0Mw000000000001');

    @IsTest
    static void existingCustomerNewLoanShowsTheLoanAnswersAndWhyTheyAskedForAPerson() {
        List<Contact> contacts = LoanSevaTestData.createCustomers();
        Contact rahul = contacts[1];
        insert new Loan_Application__c(
            Contact__c = rahul.Id, Applicant_Name__c = 'Rahul Deshmukh', Mobile__c = LoanSevaTestData.RAHUL_MOBILE,
            PAN__c = 'ABCPD4321K', Submitted_At__c = Datetime.now().addYears(-1)
        );
        Loan_Journey__c j = new Loan_Journey__c(
            Contact__c = rahul.Id, Mobile__c = LoanSevaTestData.RAHUL_MOBILE, Customer_Name__c = 'Rahul', Status__c = 'Active',
            Journey_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN, Messaging_Session_Id__c = String.valueOf(SESSION_ID).left(15),
            Language__c = 'EN', OTP_Verified__c = true, Date_Of_Birth__c = Date.newInstance(1987, 6, 14), PAN__c = 'ABCPD4321K',
            Email__c = 'rahul.deshmukh@example.com', City__c = 'Mumbai', PIN_Code__c = '400076', Prefilled_Fields__c = 'dob;pan;email;pincode',
            Employment_Type__c = 'Salaried', Company_Name__c = 'Wipro', Monthly_Income__c = 140000, Offer_Amount__c = 300000,
            Offer_Rate__c = 10.99, Offer_Tenure_Months__c = 36, Offer_EMI__c = 9820
        );
        insert j;
        insert new Task(WhatId = j.Id, WhoId = rahul.Id, Subject = 'LoanSeva: Human requested - wants to talk about the rate (New loan 3L)');

        LoanSevaHandoff.Context ctx = LoanSevaHandoff.getContext(SESSION_ID);
        System.assert(ctx.hasJourney);
        System.assert(ctx.existingCustomer);
        System.assertEquals('Rahul Deshmukh', ctx.customerName, 'the Contact name, not what was typed');
        System.assertEquals('wants to talk about the rate', ctx.reason);
        System.assertEquals('11/12 EMIs on time', ctx.loanTrack);
        System.assertEquals(300000, ctx.preApproved);
        System.assertEquals(1, ctx.earlierApplications);
        System.assertEquals(4, ctx.onFileCount);
        System.assertEquals(3, ctx.todayCount);
        System.assertEquals(LoanSevaNewLoan.FIELDS.size(), ctx.answers.size());

        Map<String, LoanSevaHandoff.Answer> byLabel = new Map<String, LoanSevaHandoff.Answer>();
        for (LoanSevaHandoff.Answer a : ctx.answers) {
            byLabel.put(a.label, a);
        }
        System.assertEquals('On file', byLabel.get('Date of birth').source);
        System.assertEquals('14/06/1987', byLabel.get('Date of birth').value);
        System.assertEquals('Mumbai 400076', byLabel.get('City and PIN').value);
        System.assert(!byLabel.get('PAN').value.contains('ABCPD'), 'the PAN is masked');
        System.assertEquals('Today', byLabel.get('Company').source);
        System.assertEquals('Not yet', byLabel.get('Purpose').source);
        System.assertEquals(300000, ctx.offerAmount);
    }

    @IsTest
    static void noJourneyForTheChat() {
        LoanSevaHandoff.Context ctx = LoanSevaHandoff.getContext(SESSION_ID);
        System.assert(!ctx.hasJourney);
        System.assert(ctx.answers.isEmpty());
    }
}
