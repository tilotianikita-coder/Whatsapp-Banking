/**
 * Every LoanSeva amount is in rupees. Stamps INR on new records so they don't take the creating user's currency
 * (the Automated Process and site guest users default to the org's corporate currency). No-op without multi-currency.
 */
public with sharing class LoanSevaCurrency {
    public static final String INR = 'INR';

    public static void stampInr(List<SObject> records) {
        if (records == null || records.isEmpty() || !UserInfo.isMultiCurrencyOrganization()) {
            return;
        }
        for (SObject r : records) {
            r.put('CurrencyIsoCode', INR);
        }
    }
}
