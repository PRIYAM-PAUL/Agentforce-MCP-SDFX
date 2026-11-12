/**
 * Fonada MCP - settings and shared safety helpers.
 *
 * Settings come from the hierarchy custom setting Fonada_Settings__c (Setup →
 * Custom Settings → Fonada Settings → Manage). Every field is optional and the
 * defaults keep the standard behaviour, so the package works with no record.
 *
 * CRM access mode:
 *   - Agentforce agent users (Einstein Agent licence) have no CRM object access of
 *     their own, so the CRM agent actions read in SYSTEM mode for them, returning
 *     only name, company, phone, email and Do Not Call.
 *   - Any other running user (employee agents, Flows, Apex) is a real person, so
 *     the reads run in USER mode: sharing, object and field security apply.
 */
public with sharing class FonadaSettings {

    public static final String DEFAULT_COUNTRY_CODE = '91';

    @TestVisible private static Fonada_Settings__c testOverride;
    @TestVisible private static Boolean agentUserOverride;
    private static Boolean isAgentUserCache;

    private static Fonada_Settings__c current() {
        if (testOverride != null) return testOverride;
        Fonada_Settings__c s = Fonada_Settings__c.getInstance();
        return s == null ? new Fonada_Settings__c() : s;
    }

    /** False when an admin ticked "Disable CRM actions". */
    public static Boolean crmActionsEnabled() {
        return current().Disable_CRM_Actions__c != true;
    }

    /** True only when an admin explicitly allows calling Do Not Call records. */
    public static Boolean includeDoNotCall() {
        return current().Include_Do_Not_Call__c == true;
    }

    /** False when an admin ticked "Disable automatic agent access". */
    public static Boolean autoAccessEnabled() {
        return current().Disable_Auto_Access__c != true;
    }

    /** Digits-only country calling code, default 91. */
    public static String countryCode() {
        String raw = current().Default_Country_Code__c;
        String digits = raw == null ? '' : raw.replaceAll('[^0-9]', '');
        return String.isBlank(digits) ? DEFAULT_COUNTRY_CODE : digits;
    }

    public static final Integer DEFAULT_REPEAT_GUARD_MINUTES = 10;

    /** Minutes the same source + Fonada agent cannot be started again; blank = 10, 0 = off. */
    public static Integer repeatGuardMinutes() {
        Decimal v = current().Repeat_Launch_Guard_Minutes__c;
        if (v == null) return DEFAULT_REPEAT_GUARD_MINUTES;
        return v <= 0 ? 0 : v.intValue();
    }

    public static final String CRM_DISABLED_MESSAGE =
        'Salesforce CRM actions are turned off by your admin (Setup → Custom Settings → Fonada Settings).';

    /** SYSTEM_MODE for Agentforce agent users, USER_MODE for everyone else. */
    public static AccessLevel crmAccessLevel() {
        return isAgentUser() ? AccessLevel.SYSTEM_MODE : AccessLevel.USER_MODE;
    }

    private static Boolean isAgentUser() {
        if (agentUserOverride != null) return agentUserOverride;
        if (isAgentUserCache == null) {
            isAgentUserCache = !FonadaMCPAgentAccess.filterAgentUsers(
                new Set<Id>{ UserInfo.getUserId() }).isEmpty();
        }
        return isAgentUserCache;
    }

    /**
     * Cleans text that came from users or CRM records before it is shown to the LLM
     * or sent to Fonada: removes control characters, neutralises Salesforce merge
     * syntax ("{!") and caps the length.
     */
    public static String cleanText(String value, Integer maxLength) {
        if (value == null) return null;
        String s = value.replaceAll('[\\x00-\\x1F\\x7F]', ' ').replace('{!', '{ !').normalizeSpace();
        return s.length() > maxLength ? s.left(maxLength) : s;
    }

    /**
     * True when a field can be queried in the given mode: it must exist in this org, and
     * in USER_MODE the running person must be able to read it (field-level security).
     * Used for optional fields such as DoNotCall, which some orgs hide or do not have.
     */
    public static Boolean fieldUsable(Schema.SObjectType objectType, String fieldName, AccessLevel mode) {
        Schema.SObjectField f = objectType.getDescribe().fields.getMap().get(fieldName.toLowerCase());
        if (f == null) return false;
        return mode == AccessLevel.SYSTEM_MODE || f.getDescribe().isAccessible();
    }

    /** Escapes LIKE wildcards so user input such as "%" or "_" matches literally. */
    public static String escapeLike(String value) {
        return value == null ? null
            : value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
