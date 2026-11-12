/**
 * Fonada MCP - post-install script.
 * Runs on every install and upgrade:
 *   - first install: grants the packaged permission set to the installing admin
 *   - every install/upgrade: backfills Fonada MCP access for existing Agentforce
 *     agent users (FonadaMCPAgentAccess), unless an admin ticked "Disable automatic
 *     agent access" in Fonada Settings. Agent users created later are handled by
 *     FonadaMCPAgentUserTrigger.
 *
 * onInstall() itself can't be exercised from Apex tests (InstallContext has no
 * public constructor), so all logic lives in @TestVisible helpers.
 */
global class FonadaMCPPostInstall implements InstallHandler {

    global void onInstall(InstallContext context) {
        backfillAgentUsers();
        if (context.previousVersion() != null) return;   // installer: first install only
        assignPermissionSet(context.installerId());
    }

    /** Grants Fonada access to existing agent users when automatic access is on. Never throws. */
    @TestVisible
    private static void backfillAgentUsers() {
        try {
            if (FonadaSettings.autoAccessEnabled()) {
                FonadaMCPAgentAccess.grant(FonadaMCPAgentAccess.allAgentUserIds());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'FonadaMCP post-install backfill: ' + e.getMessage());
        }
    }

    @TestVisible
    private static void assignPermissionSet(Id userId) {
        try {
            assignPermissionSet(userId, resolvePermissionSetId());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'FonadaMCP post-install: ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
        }
    }

    @TestVisible
    private static void assignPermissionSet(Id userId, Id psId) {
        if (userId == null || psId == null) return;
        assignToTargets(new Set<Id>{ userId }, psId);
    }

    /**
     * Inserts in small batches so one bad row cannot block the rest, and logs
     * partial failures instead of failing the whole installation.
     */
    @TestVisible
    public static void assignToTargets(Set<Id> targets, Id psId) {
        if (targets == null || targets.isEmpty() || psId == null) return;
        List<PermissionSetAssignment> inserts = new List<PermissionSetAssignment>();
        for (Id uid : targets) {
            inserts.add(new PermissionSetAssignment(AssigneeId = uid, PermissionSetId = psId));
        }

        for (Integer i = 0; i < inserts.size(); i += 200) {
            List<PermissionSetAssignment> chunk = new List<PermissionSetAssignment>();
            for (Integer j = i; j < Math.min(i + 200, inserts.size()); j++) {
                chunk.add(inserts[j]);
            }
            for (Database.SaveResult sr : Database.insert(chunk, false)) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'FonadaMCP post-install assignment failed: ' + err.getMessage());
                    }
                }
            }
        }
    }

    public static final String PKG_PS_NAME = 'FonadaMCP_Perm_Set';

    /**
     * The packaged permission set, matched by API name AND this package's namespace,
     * so a subscriber's own permission set with the same name or label is never used.
     */
    @TestVisible
    public static Id resolvePermissionSetId() {
        return resolvePermissionSetId(PKG_PS_NAME, namespacePrefix());
    }

    @TestVisible
    private static Id resolvePermissionSetId(String name, String namespacePrefix) {
        List<PermissionSet> rows = [
            SELECT Id FROM PermissionSet
            WHERE Name = :name AND NamespacePrefix = :namespacePrefix AND IsOwnedByProfile = false
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    /** 'FonadaAI' inside the managed package, null in an unmanaged deploy. */
    @TestVisible
    private static String namespacePrefix() {
        String cls = FonadaMCPPostInstall.class.getName();
        return cls.contains('.') ? cls.substringBefore('.') : null;
    }
}