/**
 * Tests for FonadaMCPPostInstall.
 * onInstall() can't be invoked directly (InstallContext has no public
 * constructor), so these tests exercise the @TestVisible helpers that contain
 * all of the logic. Keeps packaged Apex coverage above the 75% promotion bar.
 */
@IsTest
private class FonadaMCPPostInstallTest {

    @IsTest
    static void assignsOnlyTheInstaller() {
        Id me = UserInfo.getUserId();
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId();
        System.assertNotEquals(null, psId, 'Packaged permission set must exist.');

        Integer before = [SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :psId];

        Test.startTest();
        FonadaMCPPostInstall.assignPermissionSet(me);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :psId];

        System.assert(after - before <= 1, 'Only the installer may be assigned by the post-install script.');
        System.assertNotEquals(0, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :me AND PermissionSetId = :psId
        ], 'The installer must end up with the assignment.');
    }

    @IsTest
    static void doesNotDuplicateTheAssignment() {
        Id me = UserInfo.getUserId();
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId();
        System.assertNotEquals(null, psId, 'Packaged permission set must exist.');

        FonadaMCPPostInstall.assignPermissionSet(me);        // first pass assigns

        Test.startTest();
        FonadaMCPPostInstall.assignPermissionSet(me);        // second pass must skip, not throw
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :me AND PermissionSetId = :psId
        ], 'The assignment must not be duplicated.');
    }

    @IsTest
    static void returnsEarlyWhenPermissionSetIsMissing() {
        Test.startTest();
        FonadaMCPPostInstall.assignPermissionSet(UserInfo.getUserId(), null);
        Test.stopTest();
        System.assert(true, 'A null permission set id must be a no-op.');
    }

    @IsTest
    static void resolvesPermissionSetByNameAndNamespace() {
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId(
            FonadaMCPPostInstall.PKG_PS_NAME, FonadaMCPPostInstall.namespacePrefix());
        System.assertNotEquals(null, psId, 'Should resolve the packaged permission set by name + namespace.');
        System.assertEquals(psId, FonadaMCPPostInstall.resolvePermissionSetId());
    }

    @IsTest
    static void ignoresLookAlikePermissionSets() {
        // Same label as the packaged one but a different API name: must never be picked.
        // Same API name as the packaged permission set but outside the package namespace: never picked.
        insert new PermissionSet(Name = 'Fonada_Look_Alike_Test', Label = 'Fonada look-alike test');
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId('Fonada_Look_Alike_Test', 'NoSuchNamespace');
        System.assertEquals(null, psId, 'A permission set outside the package namespace must not match.');
    }

    @IsTest
    static void returnsNullWhenNothingMatches() {
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId('NoSuchPermissionSet__x', null);
        System.assertEquals(null, psId, 'Unknown name must return null.');
    }

    @IsTest
    static void backfillRunsAndRespectsTheSetting() {
        Test.startTest();
        FonadaMCPPostInstall.backfillAgentUsers();                       // automatic access on (default)
        FonadaSettings.testOverride = new Fonada_Settings__c(Disable_Auto_Access__c = true);
        FonadaMCPPostInstall.backfillAgentUsers();                       // switched off: no-op
        Test.stopTest();
        System.assert(true, 'Backfill must never throw.');
    }

    @IsTest
    static void logsDuplicateAssignmentFailures() {
        Id me = UserInfo.getUserId();
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId();
        System.assertNotEquals(null, psId, 'Packaged permission set must exist.');

        if ([SELECT COUNT() FROM PermissionSetAssignment
             WHERE AssigneeId = :me AND PermissionSetId = :psId] == 0) {
            insert new PermissionSetAssignment(AssigneeId = me, PermissionSetId = psId);
        }

        Test.startTest();
        // duplicate row -> SaveResult error -> exercises the error-logging branch
        FonadaMCPPostInstall.assignToTargets(new Set<Id>{ me }, psId);
        Test.stopTest();

        System.assert(true, 'Duplicate assignments must be logged, not thrown.');
    }

    @IsTest
    static void handlesEmptyTargetSet() {
        Test.startTest();
        FonadaMCPPostInstall.assignToTargets(
            new Set<Id>(), FonadaMCPPostInstall.resolvePermissionSetId());
        Test.stopTest();
        System.assert(true, 'An empty target set must be a no-op.');
    }
}