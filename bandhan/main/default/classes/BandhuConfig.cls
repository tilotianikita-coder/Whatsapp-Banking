/**
 * Bandhu settings (Bandhu_Config__mdt.Default) and the card catalogue (Bandhu_Card__mdt), cached per transaction.
 * Tests swap either in through the @TestVisible fields.
 */
public inherited sharing class BandhuConfig {
    @TestVisible
    private static Bandhu_Config__mdt cached;
    @TestVisible
    private static List<Bandhu_Card__mdt> cards;

    public static Bandhu_Config__mdt get() {
        if (cached == null) {
            cached = Bandhu_Config__mdt.getInstance('Default');
            if (cached == null) {
                cached = new Bandhu_Config__mdt(Demo_OTP__c = '123456', Max_OTP_Attempts__c = 3, Min_Age__c = 21, Max_Age_Salaried__c = 60,
                    Max_Age_Self_Employed__c = 65, Decline_Cibil__c = 650, Send_Mode__c = 'LogOnly', Country_Code__c = '91',
                    Idle_Minutes__c = 2, Reference_Prefix__c = 'BBL-CC', Card_Bin__c = '524193');
            }
        }
        return cached;
    }

    /** Cards from entry to premium. */
    public static List<Bandhu_Card__mdt> cards() {
        if (cards == null) {
            cards = [
                SELECT DeveloperName, MasterLabel, Tier__c, Tagline__c, Joining_Fee__c, Annual_Fee__c, Fee_Waiver__c, Rewards__c,
                    Accelerated__c, Welcome__c, Milestone__c, Lounge__c, Dining__c, Movies__c, Fuel__c, Extras__c,
                    Min_Monthly_Income__c, Min_Cibil__c, Refer_Cibil__c, ETB_Min_Balance__c, ETB_Tiers__c, Limit_Multiple__c, Limit_Min__c,
                    Limit_Max__c, Fit_Travel__c, Fit_International__c, Fit_Dining__c, Fit_Groceries__c, Fit_Shopping__c,
                    Fit_Fuel__c, Fit_Low_Fee__c, Fit_High_Spend__c, Color__c, Tier_Label__c, Co_Brand__c, Secured__c, FD_Limit_Pct__c,
                    Limit_Multiple_Max__c
                FROM Bandhu_Card__mdt
                ORDER BY Tier__c ASC, DeveloperName ASC
            ];
        }
        return cards;
    }

    public static Bandhu_Card__mdt card(String name) {
        for (Bandhu_Card__mdt c : cards()) {
            if (c.DeveloperName == name) {
                return c;
            }
        }
        return null;
    }
}
