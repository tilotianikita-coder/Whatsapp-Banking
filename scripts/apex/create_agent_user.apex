// Creates the Agentforce service agent user for LoanSeva (idempotent) and grants LoanSeva_Agent.
String username = 'loanseva.agent.' + UserInfo.getOrganizationId().left(15).toLowerCase() + '@example.com';
List<User> existing = [SELECT Id FROM User WHERE Username = :username];
User u;
if (existing.isEmpty()) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Einstein Agent User' LIMIT 1];
    u = new User(
        Username = username, LastName = 'LoanSeva Agent', FirstName = 'Kotak', Alias = 'lsagent',
        Email = UserInfo.getUserEmail(), ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_IN', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
    );
    insert u;
} else {
    u = existing[0];
}
Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'LoanSeva_Agent'].Id;
if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :u.Id AND PermissionSetId = :psId] == 0) {
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
}
System.debug('### agent user ' + username + ' ' + u.Id);
