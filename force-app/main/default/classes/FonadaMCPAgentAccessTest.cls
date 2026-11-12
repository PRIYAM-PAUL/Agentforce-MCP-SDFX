/**
 * Tests for FonadaMCPAgentAccess and FonadaMCPAgentUserTrigger.
 */
@IsTest
private class FonadaMCPAgentAccessTest {

    /** Creates an agent user, or returns null when the org has no Einstein Agent profile/licence. */
    private static User newAgentUser() {
        List<Profile> p = [
            SELECT Id FROM Profile
            WHERE UserLicense.LicenseDefinitionKey IN :FonadaMCPAgentAccess.AGENT_LICENSE_KEYS
               OR Name = :FonadaMCPAgentAccess.AGENT_PROFILE_NAME
            LIMIT 1
        ];
        if (p.isEmpty()) return null;
        String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            Alias = 'fagt', Email = 'fonada.agent.test@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'FonadaAgentTest', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata', ProfileId = p[0].Id,
            Username = 'fonada.agent.' + key + '@example.com.ext');
    }

    private static Integer assignmentCount(Id userId, Id psId) {
        return [SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetId = :psId];
    }

    @IsTest
    static void triggerGrantsBothPermissionSetsToNewAgentUser() {
        User u = newAgentUser();
        if (u == null) return;
        Test.startTest();
        try {
            insert u;                       // trigger -> queueable runs at stopTest
        } catch (DmlException e) {
            Test.stopTest();
            return;                         // no free agent licence in this org
        }
        Test.stopTest();

        Id pkgPs = FonadaMCPPostInstall.resolvePermissionSetId();
        Id credPs = [SELECT Id FROM PermissionSet
                     WHERE Name = :FonadaMCPAgentAccess.CRED_READ_PS_NAME LIMIT 1].Id;
        System.assertEquals(1, assignmentCount(u.Id, pkgPs), 'Agent user must get the Fonada MCP permission set.');
        System.assertEquals(1, assignmentCount(u.Id, credPs), 'Agent user must get the credential-read permission set.');
    }

    @IsTest
    static void credentialReadPermSetIsCreatedOnceWithRead() {
        Test.startTest();
        Id first = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        Id second = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        Test.stopTest();
        System.assertEquals(first, second, 'The permission set must be reused, not duplicated.');
        System.assertEquals(1, [SELECT COUNT() FROM ObjectPermissions
            WHERE ParentId = :first AND SobjectType = 'UserExternalCredential' AND PermissionsRead = true],
            'UserExternalCredential read must be granted.');
    }

    @IsTest
    static void ignoresNonAgentUsers() {
        Id me = UserInfo.getUserId();
        Test.startTest();
        Set<Id> filtered = FonadaMCPAgentAccess.filterAgentUsers(new Set<Id>{ me });
        FonadaMCPAgentAccess.grant(new Set<Id>{ me });
        Test.stopTest();
        System.assert(filtered.isEmpty(), 'The running admin is not an agent user.');
    }

    @IsTest
    static void missingAssigneesSkipsExistingAssignments() {
        Id me = UserInfo.getUserId();
        Id psId = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        insert new PermissionSetAssignment(AssigneeId = me, PermissionSetId = psId);
        Test.startTest();
        Set<Id> missing = FonadaMCPAgentAccess.missingAssignees(new Set<Id>{ me }, psId);
        Test.stopTest();
        System.assert(missing.isEmpty(), 'Already-assigned users must be skipped.');
    }

    @IsTest
    static void emptyAndNullInputsAreNoOps() {
        Test.startTest();
        FonadaMCPAgentAccess.enqueue(null);
        FonadaMCPAgentAccess.enqueue(new Set<Id>());
        FonadaMCPAgentAccess.grant(null);
        Set<Id> none = FonadaMCPAgentAccess.filterAgentUsers(null);
        Test.stopTest();
        System.assert(none.isEmpty(), 'Null input must return an empty set.');
    }

    @IsTest
    static void triggerHandlesUpdatesAndInactiveUsers() {
        User me = [SELECT Id, Title FROM User WHERE Id = :UserInfo.getUserId()];
        Profile std = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User inactive = new User(
            Alias = 'finact', Email = 'fonada.inactive.test@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'FonadaInactiveTest', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata', ProfileId = std.Id, IsActive = false,
            Username = 'fonada.inactive.' + key + '@example.com');
        Test.startTest();
        insert inactive;                    // inactive -> skipped
        me.Title = 'Fonada trigger test';
        update me;                          // update without profile change -> skipped
        Test.stopTest();
        System.assertEquals(0, assignmentCount(inactive.Id, FonadaMCPPostInstall.resolvePermissionSetId()),
            'Inactive users must not be granted access.');
    }

    @IsTest
    static void queueableAndBackfillRun() {
        Test.startTest();
        FonadaMCPAgentAccess.enqueue(new Set<Id>{ UserInfo.getUserId() });
        Set<Id> all = FonadaMCPAgentAccess.allAgentUserIds();
        FonadaMCPAgentAccess.grant(all);
        Test.stopTest();
        System.assertNotEquals(null, all, 'Backfill query must never return null.');
    }

    @IsTest
    static void lookAlikeCredentialPermSetWithMorePermissionsIsNotUsed() {
        PermissionSet fake = new PermissionSet(
            Name = FonadaMCPAgentAccess.CRED_READ_PS_NAME, Label = 'Look-alike credential read');
        insert fake;
        insert new ObjectPermissions(ParentId = fake.Id, SobjectType = 'Account', PermissionsRead = true);
        Test.startTest();
        Id result = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        Test.stopTest();
        System.assertEquals(null, result, 'A pre-created permission set granting more than UEC read must not be used.');
    }

    @IsTest
    static void cleanCredentialPermSetPassesTheCheck() {
        Id psId = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        PermissionSet ps = [SELECT Id, PermissionsModifyAllData, PermissionsViewAllData, PermissionsManageUsers,
                                   PermissionsAuthorApex, PermissionsCustomizeApplication
                            FROM PermissionSet WHERE Id = :psId];
        System.assert(FonadaMCPAgentAccess.isCredentialReadOnly(ps), 'Our own permission set is read-only.');
    }

    @IsTest
    static void enqueueIsSkippedWhenAutomaticAccessIsOff() {
        FonadaSettings.testOverride = new Fonada_Settings__c(Disable_Auto_Access__c = true);
        Test.startTest();
        FonadaMCPAgentAccess.enqueue(new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, Limits.getQueueableJobs(), 'No job may be queued when automatic access is off.');
        Test.stopTest();
    }

    @IsTest
    static void ordinaryUserChangesQueueNoJob() {
        Profile std = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User normal = new User(Alias = 'fnrm', Email = 'fonada.normal@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'FonadaNormalTest', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata', ProfileId = std.Id, Username = 'fonada.normal.' + key + '@example.com');
        Test.startTest();
        insert normal;
        System.assertEquals(0, Limits.getQueueableJobs(), 'Creating an ordinary user must not queue a job.');
        Test.stopTest();
        System.assert(FonadaMCPAgentAccess.agentProfileIds(new Set<Id>{ std.Id }).isEmpty(),
            'The admin profile is not an agent profile.');
        System.assert(FonadaMCPAgentAccess.agentProfileIds(null).isEmpty(), 'Null input returns an empty set.');
    }

    @IsTest
    static void agentUserQueuesExactlyOneJob() {
        User u = newAgentUser();
        if (u == null) return;                      // org without the Einstein Agent licence
        Test.startTest();
        try {
            insert u;
        } catch (DmlException e) {
            Test.stopTest();
            return;                                 // no free agent licence in this org
        }
        System.assertEquals(1, Limits.getQueueableJobs(), 'A new agent user queues one grant job.');
        Test.stopTest();
    }

    @IsTest
    static void handlerIgnoresEmptyInput() {
        Test.startTest();
        FonadaMCPAgentAccess.onUserChange(null, null);
        FonadaMCPAgentAccess.onUserChange(new List<User>(), null);
        FonadaSettings.testOverride = new Fonada_Settings__c(Disable_Auto_Access__c = true);
        FonadaMCPAgentAccess.onUserChange(new List<User>{ new User(IsActive = true, ProfileId = UserInfo.getProfileId()) }, null);
        System.assertEquals(0, Limits.getQueueableJobs(), 'Nothing is queued.');
        Test.stopTest();
    }
}
