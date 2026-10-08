/**
 * New loans, journeys and applications are in rupees whoever creates them.
 */
@IsTest
private class LoanSevaCurrencyTest {
    @IsTest
    static void newRecordsAreStampedInr() {
        List<Contact> contacts = LoanSevaTestData.createCustomers();
        Loan_Journey__c j = LoanSevaTestData.startedJourney(LoanSevaTestData.PRIYA_MOBILE);
        insert new Loan_Application__c(Loan_Journey__c = j.Id, Contact__c = contacts[0].Id);
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return;
        }
        for (String obj : new List<String>{ 'Existing_Loan__c', 'Loan_Journey__c', 'Loan_Application__c' }) {
            for (SObject r : Database.query('SELECT CurrencyIsoCode FROM ' + obj)) {
                System.assertEquals(LoanSevaCurrency.INR, r.get('CurrencyIsoCode'), obj);
            }
        }
    }

    @IsTest
    static void emptyListIsANoOp() {
        LoanSevaCurrency.stampInr(new List<SObject>());
        LoanSevaCurrency.stampInr(null);
        System.assert(true);
    }
}
