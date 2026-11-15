/**
 * "Earn more with your card": after activation, what the customer pays today by UPI / debit card that could go on the
 * new card, and the reward points it would earn at the card's rates (from the Account Aggregator statements).
 *   base rate         first number in Rewards__c        ("10 reward points per ₹200")
 *   accelerated rate  first number in Accelerated__c    ("20 points per ₹200 on travel"), for the categories it names
 *   bills             electricity / mobile bills go on the card at the base rate
 *   point value       POINT_VALUE rupees: PLACEHOLDER for Bandhan's redemption value
 */
public inherited sharing class BandhuRewards {
    public static final Decimal POINT_VALUE = 0.25;
    private static final Map<String, String> KEYWORDS = new Map<String, String>{
        'grocer' => 'Groceries', 'apparel' => 'Shopping', 'shopping' => 'Shopping', 'travel' => 'Travel', 'international' => 'International',
        'dining' => 'Dining', 'fuel' => 'Fuel'
    };

    public class Line implements Comparable {
        public String category;
        public Decimal monthly;
        public Integer rate;
        public Integer points;
        public Integer compareTo(Object o) {
            return ((Line) o).points - points;
        }
    }

    public class Tip {
        public List<Line> lines = new List<Line>();
        public Decimal monthly = 0;
        public Integer points = 0;
        public Decimal value = 0;
        public String fuelNote;
    }

    private static Integer firstNumber(String s) {
        if (String.isBlank(s)) {
            return 0;
        }
        Matcher m = Pattern.compile('(\\d+)').matcher(s);
        return m.find() ? Integer.valueOf(m.group(1)) : 0;
    }

    public static Tip compute(BandhuCashFlow.Analysis a, Bandhu_Card__mdt card) {
        if (a == null || card == null) {
            return null;
        }
        Tip t = new Tip();
        Integer base = firstNumber(card.Rewards__c);
        Integer fast = firstNumber(card.Accelerated__c);
        Set<String> fastCats = new Set<String>();
        String acc = card.Accelerated__c == null ? '' : card.Accelerated__c.toLowerCase();
        for (String k : KEYWORDS.keySet()) {
            if (acc.contains(k)) {
                fastCats.add(KEYWORDS.get(k));
            }
        }
        Map<String, Decimal> pot = new Map<String, Decimal>(a.spend);
        if (a.outflowBy != null && a.outflowBy.containsKey('Bills')) {
            pot.put('Bills', a.outflowBy.get('Bills'));
        }
        for (String c : pot.keySet()) {
            Decimal amt = pot.get(c);
            if (amt == null || amt <= 0) {
                continue;
            }
            Line l = new Line();
            l.category = c == 'International' ? 'Travel abroad' : c;
            l.monthly = amt;
            // fuel earns no points on most cards: it is the surcharge waiver that saves money there
            l.rate = c == 'Fuel' ? 0 : fastCats.contains(c) && fast > base ? fast : base;
            l.points = (amt / 200 * l.rate).intValue();
            t.monthly += amt;
            t.points += l.points;
            if (l.points > 0) {
                t.lines.add(l);
            }
        }
        t.lines.sort();
        t.value = (t.points * POINT_VALUE).setScale(0);
        if (pot.containsKey('Fuel') && String.isNotBlank(card.Fuel__c)) {
            t.fuelNote = card.Fuel__c;
        }
        return t.points > 0 ? t : null;
    }

    /** The customer message (WhatsApp / web), or null when there are no statements to go on. */
    public static String message(Card_Journey__c j, String cardName) {
        Tip t = compute(BandhuCashFlow.fromJourney(j), BandhuConfig.card(cardName));
        if (t == null) {
            return null;
        }
        List<String> rows = new List<String>();
        for (Integer i = 0; i < Math.min(4, t.lines.size()); i++) {
            Line l = t.lines[i];
            rows.add('• ' + l.category + ' ' + BandhuI18n.inr(l.monthly) + ' → *' + Decimal.valueOf(l.points).format() + ' points* (' + l.rate + ' per ₹200)');
        }
        return BandhuI18n.msg('Rewards_Tip', j.Language__c, new Map<String, Object>{
            'card' => cardName, 'total' => BandhuI18n.inr(t.monthly), 'lines' => String.join(rows, '\n'),
            'points' => Decimal.valueOf(t.points).format(), 'value' => BandhuI18n.inr(t.value),
            'fuel' => t.fuelNote == null ? '' : '\n⛽ ' + t.fuelNote });
    }
}
