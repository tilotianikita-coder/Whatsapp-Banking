/**
 * Personal Loan serviceability by PIN code: LoanSeva_Region__mdt lists PIN prefixes per region, whether Kotak serves
 * it and the RM who owns its leads. The longest matching prefix wins; a region with prefix * catches every other PIN.
 * No PIN yet (the customer left before that step) counts as serviceable and goes to the default RM.
 */
public with sharing class LoanSevaServiceability {
    public class Region {
        public String name;
        public Boolean serviceable;
        public Id rmId;
    }

    @TestVisible
    private static List<LoanSeva_Region__mdt> regions;
    private static Map<String, Id> userIds = new Map<String, Id>();

    public static Region forPin(String pin) {
        String digits = pin == null ? '' : pin.replaceAll('[^0-9]', '');
        LoanSeva_Region__mdt best;
        Integer bestLength = -1;
        if (String.isNotBlank(digits)) {
            for (LoanSeva_Region__mdt r : all()) {
                for (String prefix : String.isBlank(r.PIN_Prefixes__c) ? new List<String>() : r.PIN_Prefixes__c.split(',')) {
                    prefix = prefix.trim();
                    Integer length = prefix == '*' ? 0 : prefix.length();
                    if ((prefix == '*' || String.isNotBlank(prefix) && digits.startsWith(prefix)) && length > bestLength) {
                        best = r;
                        bestLength = length;
                    }
                }
            }
        }
        Region result = new Region();
        if (best == null) {
            result.name = String.isBlank(digits) ? 'PIN not shared yet' : 'Outside serviceable regions';
            result.serviceable = String.isBlank(digits);
        } else {
            result.name = best.MasterLabel;
            result.serviceable = best.Serviceable__c == true;
            result.rmId = userId(best.RM_Username__c);
        }
        return result;
    }

    private static List<LoanSeva_Region__mdt> all() {
        if (regions == null) {
            regions = LoanSeva_Region__mdt.getAll().values();
        }
        return regions;
    }

    private static Id userId(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        if (!userIds.containsKey(username)) {
            userIds.put(username, null);
            for (User u : [SELECT Id FROM User WHERE Username = :username AND IsActive = TRUE LIMIT 1]) {
                userIds.put(username, u.Id);
            }
        }
        return userIds.get(username);
    }
}
