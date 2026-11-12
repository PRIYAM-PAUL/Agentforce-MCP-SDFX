/**
 * Fonada MCP - controller for the "Fonada Setup" tab (LWC fonadaSetup).
 *
 * Lists the org's Agentforce agent users, shows whether each one already has
 * Fonada access, and returns the ready-to-paste Agent Script with
 * default_agent_user filled in. All methods are for administrators (users who can
 * assign permission sets or manage users). Only the two admin buttons change data:
 * "Fix agent access" (grant) and "Prepare for uninstall" (remove assignments).
 */
public with sharing class FonadaSetupController {

    public static final String TEMPLATE_NAME = 'FonadaAgentTemplate';
    public static final String PLACEHOLDER   = 'UPDATE_WITH_YOUR_DEFAULT_AGENT_USER';
    public static final String PKG_PS_NAME   = 'FonadaMCP_Perm_Set';
    public static final String CRED_PS_NAME  = 'Fonada_MCP_Agent_Credential_Read';
    private static final Set<String> AGENT_LICENSE_KEYS =
        new Set<String>{ 'PID_DigitalAgent', 'PID_DigitalAgentExternal' };
    private static final String AGENT_PROFILE_NAME = 'Einstein Agent User';

    public class AgentUser {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean hasFonadaAccess;
        @AuraEnabled public Boolean hasCredentialRead;
    }

    /** Active agent users, newest first, with their Fonada access status. */
    @AuraEnabled
    public static List<AgentUser> getAgentUsers() {
        requireAdmin();
        List<User> users = queryAgentUsers(null);
        Id pkgPs = FonadaMCPPostInstall.resolvePermissionSetId();
        Id credPs = credentialReadPermSetId();
        Map<Id, Set<String>> psByUser = new Map<Id, Set<String>>();
        for (PermissionSetAssignment a : [
                SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment
                WHERE AssigneeId IN :users AND PermissionSetId IN (:pkgPs, :credPs)]) {
            if (!psByUser.containsKey(a.AssigneeId)) psByUser.put(a.AssigneeId, new Set<String>());
            psByUser.get(a.AssigneeId).add(a.PermissionSetId == pkgPs ? PKG_PS_NAME : CRED_PS_NAME);
        }
        List<AgentUser> result = new List<AgentUser>();
        for (User u : users) {
            Set<String> ps = psByUser.containsKey(u.Id) ? psByUser.get(u.Id) : new Set<String>();
            AgentUser au = new AgentUser();
            au.userId = u.Id;
            au.name = u.Name;
            au.username = u.Username;
            au.createdDate = u.CreatedDate;
            au.hasFonadaAccess = ps.contains(PKG_PS_NAME);
            au.hasCredentialRead = ps.contains(CRED_PS_NAME);
            result.add(au);
        }
        return result;
    }

    /** Model the Fonada subagent reasons with. The template ships with TEMPLATE_MODEL. */
    public static final String TEMPLATE_MODEL = 'sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet';
    public static final String MODEL_ORG_DEFAULT = 'default';
    private static final Map<String, String> MODELS = new Map<String, String>{
        'claude-sonnet-4-5' => 'sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet',
        'gpt-4-1'           => 'sfdc_ai__DefaultOpenAIGPT41',
        'gpt-4o-mini'       => 'sfdc_ai__DefaultOpenAIGPT4OmniMini'
    };

    /** The Agent Script with default_agent_user set to the chosen agent user (recommended model). */
    @AuraEnabled
    public static String buildScript(String username) {
        return buildScriptWithModel(username, null);
    }

    /**
     * Same as buildScript, with the AI model for the Fonada subagent:
     * claude-sonnet-4-5 (default), gpt-4-1, gpt-4o-mini, or "default" for the org's default model.
     */
    @AuraEnabled
    public static String buildScriptWithModel(String username, String modelKey) {
        requireAdmin();
        if (String.isBlank(username) || queryAgentUsers(username).isEmpty()) {
            throw new AuraHandledException('Pick an active Agentforce agent user.');
        }
        return render(username, modelKey);
    }

    /**
     * "Fix agent access": grants both Fonada permission sets to every active agent
     * user right now (same logic as the install script and the User trigger).
     * Returns how many agent users exist.
     */
    @AuraEnabled
    public static Integer grantAgentAccess() {
        requireAdmin();
        Set<Id> agents = FonadaMCPAgentAccess.allAgentUserIds();
        FonadaMCPAgentAccess.grant(agents);
        return agents.size();
    }

    /**
     * "Prepare for uninstall": removes every assignment of the packaged
     * permission set, which otherwise blocks the uninstall
     * ("This permission set is assigned to one or more users"), and removes the
     * runtime "Fonada MCP - Agent Credential Read" permission set the package
     * created, so nothing is left behind.
     * Returns the number of assignments removed.
     */
    @AuraEnabled
    public static Integer prepareUninstall() {
        requireAdmin();
        Id pkgPs = FonadaMCPPostInstall.resolvePermissionSetId();
        Id credPs = credentialReadPermSetId();
        List<PermissionSetAssignment> rows = [
            SELECT Id FROM PermissionSetAssignment
            WHERE PermissionSetId IN (:pkgPs, :credPs)
        ];
        if (!rows.isEmpty()) delete rows;
        if (credPs != null) {
            Database.delete(credPs, false);   // best effort; Fix agent access recreates it
        }
        return rows.size();
    }

    /** The subscriber-owned credential-read permission set created by the package, or null. */
    private static Id credentialReadPermSetId() {
        String orgNamespace = FonadaMCPAgentAccess.orgNamespace();
        List<PermissionSet> ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = :CRED_PS_NAME AND NamespacePrefix = :orgNamespace AND IsOwnedByProfile = false
            LIMIT 1
        ];
        return ps.isEmpty() ? null : ps[0].Id;
    }

    /** Only users who may assign permission sets can run the admin buttons. */
    @TestVisible
    private static void requireAdmin() {
        // Profiles are permission sets too (IsOwnedByProfile), so this covers both.
        Integer allowed = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND (PermissionSet.PermissionsAssignPermissionSets = true
                   OR PermissionSet.PermissionsManageUsers = true)
        ];
        if (allowed == 0) {
            throw new AuraHandledException('Only an administrator who can assign permission sets can do this.');
        }
    }

    @TestVisible
    private static String render(String username) {
        return render(username, null);
    }

    @TestVisible
    private static String render(String username, String modelKey) {
        String script = loadTemplate().replace('\r\n', '\n').replace(PLACEHOLDER, username);
        String key = String.isBlank(modelKey) ? 'claude-sonnet-4-5' : modelKey.trim().toLowerCase();
        String modelLine = '        model: "model://' + TEMPLATE_MODEL + '"';
        String modelBlock = '    model_config:\n' + modelLine + '\n';
        if (key != MODEL_ORG_DEFAULT && !MODELS.containsKey(key)) {
            throw new AuraHandledException('Unknown model option: ' + modelKey);
        }
        // The model choice must really be applied; never return a script that silently ignores it.
        if (!script.contains(modelBlock)) {
            throw new AuraHandledException('The Fonada agent template has an unexpected format. Reinstall the package.');
        }
        if (key == MODEL_ORG_DEFAULT) {
            return script.replace(modelBlock, '');
        }
        return script.replace(modelLine, '        model: "model://' + MODELS.get(key) + '"');
    }

    @TestVisible
    private static String loadTemplate() {
        List<StaticResource> sr = [
            SELECT Body FROM StaticResource
            WHERE Name = :TEMPLATE_NAME AND NamespacePrefix = :namespacePrefix()
            LIMIT 1
        ];
        if (sr.isEmpty()) {
            throw new AuraHandledException('The Fonada agent template is missing. Reinstall the package.');
        }
        return sr[0].Body.toString();
    }

    /** 'FonadaAI' when running inside the managed package, null in an unmanaged deploy. */
    @TestVisible
    private static String namespacePrefix() {
        String cls = FonadaSetupController.class.getName();
        return cls.contains('.') ? cls.substringBefore('.') : null;
    }

    private static List<User> queryAgentUsers(String username) {
        String q = 'SELECT Id, Name, Username, CreatedDate FROM User'
            + ' WHERE IsActive = true'
            + ' AND (Profile.UserLicense.LicenseDefinitionKey IN :AGENT_LICENSE_KEYS'
            + '      OR Profile.Name = :AGENT_PROFILE_NAME)'
            + ' AND (NOT Username LIKE \'automatedclean%\')'
            + (username == null ? '' : ' AND Username = :username')
            + ' ORDER BY CreatedDate DESC LIMIT 200';
        return Database.queryWithBinds(q, new Map<String, Object>{
            'AGENT_LICENSE_KEYS' => AGENT_LICENSE_KEYS,
            'AGENT_PROFILE_NAME' => AGENT_PROFILE_NAME,
            'username' => username
        }, AccessLevel.USER_MODE);
    }
}
