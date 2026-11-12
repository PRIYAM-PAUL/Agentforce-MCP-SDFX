/**
 * Fonada MCP - automatic access for Agentforce agent users.
 *
 * Agentforce runs agent actions as the agent's own user (Einstein Agent license,
 * e.g. fonada_assistant@...ext). That user needs two things to call Fonada:
 *   1. the packaged permission set (External Credential principal access), and
 *   2. Read on UserExternalCredential. A managed package can't carry this, because
 *      it is stripped on install, so we create a small subscriber-owned permission
 *      set at runtime that grants only that read.
 *
 * Invoked by:
 *   - FonadaMCPAgentUserTrigger: each new or re-activated agent user (async; only
 *     agent users queue a job, see onUserChange)
 *   - FonadaMCPPostInstall: backfill on install and upgrade
 *   - Fonada Setup tab: "Fix agent access" button (admins only)
 * The automatic paths (trigger, install backfill) can be switched off with
 * "Disable automatic agent access" in Fonada Settings; the button always works.
 *
 * Safety: the credential-read permission set is only reused when it is
 * subscriber-owned and grants nothing except UserExternalCredential Read, so a
 * pre-created look-alike with broader permissions is never assigned to agents.
 */
public without sharing class FonadaMCPAgentAccess implements Queueable {

    public static final String CRED_READ_PS_NAME  = 'Fonada_MCP_Agent_Credential_Read';
    public static final String CRED_READ_PS_LABEL = 'Fonada MCP - Agent Credential Read';
    public static final Set<String> AGENT_LICENSE_KEYS =
        new Set<String>{ 'PID_DigitalAgent', 'PID_DigitalAgentExternal' };
    public static final String AGENT_PROFILE_NAME = 'Einstein Agent User';

    private final Set<Id> userIds;

    public FonadaMCPAgentAccess(Set<Id> userIds) {
        this.userIds = userIds;
    }

    /**
     * Trigger handler. Picks the users that became active agent users (new, re-activated or
     * moved to another profile) and queues a grant only for them, so creating or editing
     * ordinary users never uses one of the transaction's queueable slots (only one is allowed
     * when users are created from a batch, queueable or future job).
     */
    public static void onUserChange(List<User> users, Map<Id, User> oldMap) {
        if (users == null || users.isEmpty() || !FonadaSettings.autoAccessEnabled()) return;
        Map<Id, Id> profileByUser = new Map<Id, Id>();
        for (User u : users) {
            if (!u.IsActive || u.ProfileId == null) continue;
            User old = oldMap == null ? null : oldMap.get(u.Id);
            if (old == null || old.ProfileId != u.ProfileId || !old.IsActive) profileByUser.put(u.Id, u.ProfileId);
        }
        // Never use the customer's last query or fail their user save; the next install backfill
        // or the Fix agent access button covers a skipped user.
        if (profileByUser.isEmpty() || Limits.getQueries() >= Limits.getLimitQueries()) return;
        Set<Id> agentProfiles;
        try {
            agentProfiles = agentProfileIds(new Set<Id>(profileByUser.values()));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'FonadaMCP agent access: ' + e.getMessage());
            return;
        }
        if (agentProfiles.isEmpty()) return;
        Set<Id> ids = new Set<Id>();
        for (Id userId : profileByUser.keySet()) {
            if (agentProfiles.contains(profileByUser.get(userId))) ids.add(userId);
        }
        enqueue(ids);
    }

    /** The given profiles that belong to Agentforce agent users (Einstein Agent licence or profile). */
    public static Set<Id> agentProfileIds(Set<Id> profileIds) {
        if (profileIds == null || profileIds.isEmpty()) return new Set<Id>();
        return new Map<Id, Profile>([
            SELECT Id FROM Profile
            WHERE Id IN :profileIds
              AND (UserLicense.LicenseDefinitionKey IN :AGENT_LICENSE_KEYS OR Name = :AGENT_PROFILE_NAME)
        ]).keySet();
    }

    /**
     * Enqueue a grant for the given users (no-op when empty, out of queueable capacity,
     * or when automatic agent access is switched off in Fonada Settings).
     */
    public static void enqueue(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return;
        if (!FonadaSettings.autoAccessEnabled()) return;
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) return;
        System.enqueueJob(new FonadaMCPAgentAccess(userIds));
    }

    public void execute(QueueableContext ctx) {
        grant(userIds);
    }

    /** Grants both permission sets to every agent user in userIds. Never throws. */
    public static void grant(Set<Id> userIds) {
        try {
            Set<Id> agents = filterAgentUsers(userIds);
            if (agents.isEmpty()) return;
            Set<Id> psIds = new Set<Id>();
            Id pkgPs = FonadaMCPPostInstall.resolvePermissionSetId();
            if (pkgPs != null) psIds.add(pkgPs);
            Id credPs = ensureCredentialReadPermSet();
            if (credPs != null) psIds.add(credPs);
            for (Id psId : psIds) {
                FonadaMCPPostInstall.assignToTargets(missingAssignees(agents, psId), psId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'FonadaMCP agent access: ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
        }
    }

    /** All active agent users in the org (used for the post-install backfill). */
    public static Set<Id> allAgentUserIds() {
        return new Map<Id, User>([
            SELECT Id FROM User
            WHERE IsActive = true
              AND (Profile.UserLicense.LicenseDefinitionKey IN :AGENT_LICENSE_KEYS
                   OR Profile.Name = :AGENT_PROFILE_NAME)
            LIMIT 5000
        ]).keySet();
    }

    @TestVisible
    public static Set<Id> filterAgentUsers(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return new Set<Id>();
        return new Map<Id, User>([
            SELECT Id FROM User
            WHERE Id IN :userIds AND IsActive = true
              AND (Profile.UserLicense.LicenseDefinitionKey IN :AGENT_LICENSE_KEYS
                   OR Profile.Name = :AGENT_PROFILE_NAME)
        ]).keySet();
    }

    /**
     * Finds or creates the subscriber-owned permission set granting UserExternalCredential
     * read. Returns null (and logs) when a permission set with that name exists but grants
     * more than that read, so it is never assigned automatically.
     */
    @TestVisible
    private static Id ensureCredentialReadPermSet() {
        String orgNamespace = orgNamespace();
        List<PermissionSet> existing = [
            SELECT Id, PermissionsModifyAllData, PermissionsViewAllData, PermissionsManageUsers,
                   PermissionsAuthorApex, PermissionsCustomizeApplication
            FROM PermissionSet
            WHERE Name = :CRED_READ_PS_NAME AND NamespacePrefix = :orgNamespace AND IsOwnedByProfile = false
            LIMIT 1
        ];
        Id psId;
        if (!existing.isEmpty() && !isCredentialReadOnly(existing[0])) {
            System.debug(LoggingLevel.ERROR, 'FonadaMCP agent access: permission set ' + CRED_READ_PS_NAME
                + ' grants more than UserExternalCredential Read; not assigning it automatically.');
            return null;
        }
        if (existing.isEmpty()) {
            PermissionSet ps = new PermissionSet(
                Name = CRED_READ_PS_NAME,
                Label = CRED_READ_PS_LABEL,
                Description = 'Created by the Fonada MCP package. Grants Read on User External '
                    + 'Credentials so Agentforce agent users can use the Fonada MCP credential.');
            insert ps;
            psId = ps.Id;
        } else {
            psId = existing[0].Id;
        }
        if ([SELECT COUNT() FROM ObjectPermissions
             WHERE ParentId = :psId AND SobjectType = 'UserExternalCredential'
               AND PermissionsRead = true] == 0) {
            insert new ObjectPermissions(
                ParentId = psId, SobjectType = 'UserExternalCredential', PermissionsRead = true);
        }
        return psId;
    }

    private static String orgNamespaceCache;
    private static Boolean orgNamespaceLoaded = false;

    /**
     * Namespace that permission sets created by this code receive: none in customer
     * orgs, the org's own namespace in a namespaced (development / build) org.
     */
    public static String orgNamespace() {
        if (!orgNamespaceLoaded) {
            orgNamespaceCache = [SELECT NamespacePrefix FROM Organization LIMIT 1].NamespacePrefix;
            orgNamespaceLoaded = true;
        }
        return orgNamespaceCache;
    }

    /** True when the permission set grants nothing except (at most) UserExternalCredential Read. */
    @TestVisible
    private static Boolean isCredentialReadOnly(PermissionSet ps) {
        if (ps.PermissionsModifyAllData || ps.PermissionsViewAllData || ps.PermissionsManageUsers
                || ps.PermissionsAuthorApex || ps.PermissionsCustomizeApplication) {
            return false;
        }
        Integer otherObjects = [
            SELECT COUNT() FROM ObjectPermissions
            WHERE ParentId = :ps.Id AND SobjectType != 'UserExternalCredential'
        ];
        Integer setupAccess = [SELECT COUNT() FROM SetupEntityAccess WHERE ParentId = :ps.Id];
        return otherObjects == 0 && setupAccess == 0;
    }

    @TestVisible
    private static Set<Id> missingAssignees(Set<Id> userIds, Id psId) {
        Set<Id> missing = new Set<Id>(userIds);
        for (PermissionSetAssignment a : [
                SELECT AssigneeId FROM PermissionSetAssignment
                WHERE PermissionSetId = :psId AND AssigneeId IN :userIds]) {
            missing.remove(a.AssigneeId);
        }
        return missing;
    }
}
