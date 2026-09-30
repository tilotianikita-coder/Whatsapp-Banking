// LoanSeva post-deploy setup. Idempotent. Run: sf apex run -f scripts/apex/post_deploy.apex -o kotak-demo
Map<String, Id> ps = new Map<String, Id>();
for (PermissionSet p : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('LoanSeva_Guest', 'LoanSeva_Admin', 'LoanSeva_Agent')]) {
    ps.put(p.Name, p.Id);
}
Set<String> existing = new Set<String>();
for (PermissionSetAssignment a : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE PermissionSetId IN :ps.values()]) {
    existing.add(a.AssigneeId + ':' + a.PermissionSetId);
}
List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
// 1. Site guest user -> registration page + publish event only
for (Site s : [SELECT GuestUserId FROM Site WHERE Name = 'LoanSeva']) {
    if (!existing.contains(s.GuestUserId + ':' + ps.get('LoanSeva_Guest'))) {
        toAssign.add(new PermissionSetAssignment(AssigneeId = s.GuestUserId, PermissionSetId = ps.get('LoanSeva_Guest')));
    }
}
// 2. Running admin (also the platform event subscriber user) -> full LoanSeva access
if (!existing.contains(UserInfo.getUserId() + ':' + ps.get('LoanSeva_Admin'))) {
    toAssign.add(new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.get('LoanSeva_Admin')));
}
// 3. Agentforce service agent users -> action + object access
for (User u : [SELECT Id FROM User WHERE IsActive = TRUE AND Profile.Name = 'Einstein Agent User' AND Username LIKE 'loanseva%']) {
    if (!existing.contains(u.Id + ':' + ps.get('LoanSeva_Agent'))) {
        toAssign.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.get('LoanSeva_Agent')));
    }
}
insert toAssign;
// 4. Drop-off / re-engagement job (self-rescheduling every Job_Interval_Minutes__c)
LoanSevaDropOffJob.start();
System.debug('### LoanSeva post-deploy: ' + toAssign.size() + ' permission set assignment(s); drop-off job scheduled');
