// Creates the Agentforce agent user for Bandhu (idempotent) and grants Bandhu_Agent + AgentforceServiceAgentUser.
// Run: sf apex run -f scripts/bandhan/apex/create_agent_user.apex -o bandhan
String username = 'bandhu.agent.' + UserInfo.getOrganizationId().left(15).toLowerCase() + '@example.com';
List<User> existing = [SELECT Id FROM User WHERE Username = :username];
User u;
if (existing.isEmpty()) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Einstein Agent User' LIMIT 1];
    u = new User(Username = username, LastName = 'Agent', FirstName = 'Bandhu', Alias = 'bandhu', Email = UserInfo.getUserEmail(),
        ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8');
    insert u;
} else {
    u = existing[0];
}
for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('Bandhu_Agent', 'AgentforceServiceAgentUser')]) {
    if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetId = :ps.Id] == 0) {
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }
}
System.debug('### agent user ' + username + ' ' + u.Id);
