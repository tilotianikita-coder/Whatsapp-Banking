// Bandhu demo card credit hierarchy (org: bandhan): sets User.Bandhu_Credit_Level__c and the manager chain on existing
// SDO users (no new licences). Titles are the card credit roles; the user names stay the SDO ones.
//   L4 Chief Credit Officer (Cards)  Elliott Executive
//   L3 Regional Credit Head (East)   Alf Operations       -> manager Elliott
//   L2 Senior Credit Manager         Cindy Central        -> manager Alf
//   L2 Senior Credit Manager         Ely East             -> manager Alf
//   L1 Credit Underwriter            the running admin    -> manager Cindy   (raises the requests in the demo)
//   L1 Credit Underwriter            Bill South           -> manager Ely
// The running admin is L1, so raising a request works as the underwriter would; with Bandhu_Config Approve_On_Behalf the
// admin can also record the approver's decision (logged "on behalf"). Run: sf apex run -f scripts/bandhan/apex/credit_hierarchy.apex -o bandhan
Map<String, List<Object>> plan = new Map<String, List<Object>>{
    'Elliott Executive' => new List<Object>{ 4, 'Chief Credit Officer (Cards)', null },
    'Alf Operations' => new List<Object>{ 3, 'Regional Credit Head (East)', 'Elliott Executive' },
    'Cindy Central' => new List<Object>{ 2, 'Senior Credit Manager', 'Alf Operations' },
    'Ely East' => new List<Object>{ 2, 'Senior Credit Manager', 'Alf Operations' },
    'Bill South' => new List<Object>{ 1, 'Credit Underwriter', 'Ely East' }
};
Map<String, User> byName = new Map<String, User>();
for (User u : [SELECT Id, Name FROM User WHERE Name IN :plan.keySet() AND IsActive = true]) {
    byName.put(u.Name, u);
}
List<User> upd = new List<User>();
for (String n : plan.keySet()) {
    User u = byName.get(n);
    if (u == null) {
        System.debug('### missing user ' + n);
        continue;
    }
    List<Object> p = plan.get(n);
    User x = new User(Id = u.Id, Bandhu_Credit_Level__c = (Integer) p[0], Title = (String) p[1]);
    if (p[2] != null && byName.containsKey((String) p[2])) {
        x.ManagerId = byName.get((String) p[2]).Id;
    }
    upd.add(x);
}
User me = new User(Id = UserInfo.getUserId(), Bandhu_Credit_Level__c = 1);
if (byName.containsKey('Cindy Central')) {
    me.ManagerId = byName.get('Cindy Central').Id;
}
upd.add(me);
update upd;
for (User u : [SELECT Name, Title, Bandhu_Credit_Level__c, Manager.Name FROM User WHERE Bandhu_Credit_Level__c != null ORDER BY Bandhu_Credit_Level__c DESC, Name]) {
    System.debug('### L' + u.Bandhu_Credit_Level__c + ' ' + u.Name + ' (' + u.Title + ') -> ' + u.Manager.Name);
}
