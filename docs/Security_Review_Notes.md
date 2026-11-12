# Security Review Notes - Fonada MCP (internal)

> Not customer-facing. Use these notes when preparing the Partner Security Portal /
> AgentExchange submission and the Security Review Requirements checklist.

## 1. Automatic access for the installer and Agentforce agent users

Three components grant access automatically:

- **`FonadaMCPPostInstall`** (InstallHandler)
  - On first install: assigns `FonadaMCP_Perm_Set` to the **installing administrator**.
  - On every install and upgrade: backfills existing **agent users** through `FonadaMCPAgentAccess`.
- **`FonadaMCPAgentUserTrigger`** (User, after insert/update)
  - Fires when a user is created, re-activated or has their profile changed.
  - Enqueues `FonadaMCPAgentAccess` for that user.
- **`FonadaMCPAgentAccess`** (Queueable, `without sharing`)
  - Acts **only** on active users whose profile license is Einstein Agent
    (`PID_DigitalAgent` / `PID_DigitalAgentExternal`) or whose profile is `Einstein Agent User`.
  - Assigns them two permission sets:
    1. **`FonadaMCP_Perm_Set`** (packaged): External Credential principal access to
       `FonadaAI__FonadaMCP-MCPAuthentication`.
    2. **`Fonada_MCP_Agent_Credential_Read`**: a subscriber-owned permission set the code creates
       once. It grants **only** `UserExternalCredential` Read.
       - **Why it's created at runtime:** managed packages strip this object permission on
         install. Without it, agent actions fail with `credential_access_denied`.

**Why this is intentional:**
- Agentforce runs agent actions as the agent's own user.
- These grants unlock only the org-level credential that holds the Fonada API key, which the admin
  installed the package to use.
- No other users, objects or fields are touched.
- No per-user secret is exposed.
- Admins can remove the assignments, or delete the runtime permission set, at any time.

**Why `without sharing`:** the code reads `User`, `PermissionSet` and `PermissionSetAssignment`
and inserts assignments. It runs from an install handler and a User trigger, which have no
meaningful sharing context. All queries are filtered to agent-licensed users.

**Hardening (released in Fonada MCP 1.0, build 1.2.0.13):**
- The packaged permission set is resolved by API name **and** the `FonadaAI` namespace (no label
  fallback), so a subscriber permission set with the same name or label is never assigned.
- `Fonada_MCP_Agent_Credential_Read` is only reused when it is subscriber-owned and grants nothing but
  `UserExternalCredential` Read (no other object permissions, no setup-entity access, no Modify/View All
  Data, Manage Users, Author Apex or Customize Application). Otherwise it is not assigned and an error
  is logged.
- Admins can switch the automatic grants off (Fonada Settings → *Disable automatic agent access*); the
  admin-only "Fix agent access" button in the Fonada Setup tab still works.
- "Prepare for uninstall" removes the assignments of both permission sets and deletes the runtime one.

**Limits:**
- The trigger first checks the changed users' profiles (one Profile query, skipped if the
  transaction has no query left) and queues a job only for agent users, so creating or editing
  ordinary users never uses a queueable slot.
- Each grant is capped by Queueable limits. The trigger skips the enqueue when queueable capacity
  is exhausted, and the next post-install backfill catches those users.
- Every failure is caught and logged with `System.debug`. Installs and user saves never fail
  because of this code.

## 2. CRM agent actions (FonadaFindRecord, FonadaGetCallList, FonadaStartCampaign, FonadaSendMessageCampaign)

- **Read-only** on Contact, Lead, Account, Campaign, CampaignMember. Fields read: Name, Phone,
  MobilePhone, Email, DoNotCall, Account.Name / Company. No DML on CRM data.
- **Access mode (`FonadaSettings.crmAccessLevel`)**:
  - Running user is an Agentforce agent user (Einstein Agent licence / profile): queries run in
    `SYSTEM_MODE`. Agent users have no CRM object access of their own; the admin chose to give the
    agent these actions by pasting the agent script. Only the fields above are returned.
  - Any other running user (employee agents, Flows, Apex): queries run in `USER_MODE`, so sharing,
    CRUD and FLS apply. Access errors are returned as a message, not thrown.
  - The classes are declared `without sharing` only so the agent-user path works; every query passes
    an explicit `AccessLevel`.
- **All SOQL uses bind variables** (`Database.queryWithBinds`); object names are fixed literals.
  LIKE input is escaped (`%`, `_`, `\`), so wildcards cannot enumerate records.
- **No silent record choice**: a name is matched exactly first; a partial name must match exactly one
  record, otherwise the candidates are returned and nothing is started. `start_fonada_campaign`
  accepts the `sourceId` from the preview so the confirmed list is the one launched.
- **Compliance**: records with `DoNotCall = true` are skipped and get no dial number (admin override
  in Fonada Settings, off by default).
- **Messaging** (`FonadaSendMessageCampaign`): builds the recipient list with the same
  `FonadaGetCallList.collect` (same access mode, Do Not Call skip, ambiguity rules) and sends it as
  `contacts` rows to `whatsapp_send_campaign` or `rcs_run_campaign`. Only phone, name and the
  template variables the user names are sent. RCS template names are resolved with
  `rcs_list_bots` / `rcs_list_templates`. Variable names are validated; values are cleaned.
- **Repeat-launch guard**: `FonadaStartCampaign` and `FonadaSendMessageCampaign` (shared `FonadaLaunchGuard`) refuse to
  start the same Salesforce source with the same Fonada agent or template again within Fonada Settings → *Repeat launch guard (minutes)* (default 10, 0 = off)
  unless the user explicitly confirms (`allowRepeat`). Starts are logged in the package-owned object
  `Fonada_Campaign_Launch__c` (source Id/name, Fonada agent, Fonada campaign id/name, schedule, count;
  no contact data). The log is read and written in `SYSTEM_MODE` because it is the package's own
  operational record, not customer data, and agent users have no object access of their own; the
  insert happens after all callouts, and a logging failure never blocks or fails a launch.
- **Admin kill switch**: Fonada Settings → *Disable CRM actions* turns all four actions off (org,
  profile or user level).
- **Deployment guidance** (Setup tab + install guide): the agent is meant for internal users; do not
  expose it on public channels.
- **MCP protocol**: each Apex tool call performs the MCP handshake (`initialize`,
  `notifications/initialized`) and sends the negotiated `MCP-Protocol-Version` and any `Mcp-Session-Id`
  on `tools/call`. If the handshake fails (other than 401/403), the call is sent without those headers.
  All callouts in a transaction share the 120-second budget.
- **Callout** (`FonadaMcpClient`): only to `callout:FonadaAI__FonadaMCP`; the key is added by the
  External Credential, never handled in Apex. The serialised body has `{!` neutralised, so merge
  fields can never be evaluated inside user or CRM text. CRM/user text is also stripped of control
  characters and capped (`FonadaSettings.cleanText`), which limits prompt injection through record data.

**Code Analyzer note — `FonadaSetupController` ApexCRUDViolation:** these queries/DML touch only
`PermissionSet`, `PermissionSetAssignment`, `User` and the package's own `StaticResource`. Every
`@AuraEnabled` method first calls `requireAdmin()` (the running user must hold *Assign Permission Sets*
or *Manage Users*), so only administrators reach them. The agent-user list query itself runs in
`USER_MODE`.

**Code Analyzer report** (`docs/security-review/code-analyzer-report.html` / `.csv`, Recommended rules,
run 2026-11-11): 0 critical; the only High findings are the 7 `ApexCRUDViolation`s in
`FonadaSetupController` explained above. `OperationWithLimitsInLoop` at `FonadaMCPPostInstall.cls:66` is
the chunked insert of permission-set assignments (200 per DML), bounded by the number of agent users.
The rest are style rules (braces, complexity, field order) with no security impact.

## 3. Tool metadata / prompt-injection review

- `serverDescriptor.instructions` is sanitized: plain product description, no
  LLM-directed "working rules" and no developer transport details (stdio,
  FONADA_API_KEY, header names).
- Tool descriptions intentionally keep their safety guardrails
  ("Side effect: ... spends credits", "Selection guard: do not guess ...").

## 4. Code coverage

- Released build 1.2.0.13 (`04tdN000000TfMLQA0`): package coverage **94 %** (Coverage Met: true).
- Check-only validation in a namespaced scratch org: **92/92 tests pass**, 95.1 % org-wide
  (`FonadaSendMessageCampaign` 97.8 %).
- Test classes: `FonadaMCPPostInstallTest`, `FonadaMCPAgentAccessTest`, `FonadaCrmActionsTest`,
  `FonadaStartCampaignTest`, `FonadaSendMessageCampaignTest`, `FonadaSetupControllerTest`. HTTP callouts
  are mocked with the exact prod response shapes (e.g. RCS `template_name`).
- Managed 2GP promotion requires at least 75 % Apex coverage.

## 5. Pre-submission checklist

- [x] Code Analyzer report (`docs/security-review/`, 2026-11-11). Re-run on the released source just before
  submitting: `sf code-analyzer run --workspace force-app --output-file docs/security-review/code-analyzer-report.html`
- [x] Package version promoted: Fonada MCP 1.0 / 1.2.0.13 (`04tdN000000TfMLQA0`), 2026-11-12
- [ ] Checkmarx source scan (runs automatically on submission)
- [ ] `mcp.fonada.ai` nginx: add `Strict-Transport-Security` and `server_tokens off`. As of 2026-11-12 the
  server still sends `server: nginx/1.20.1` and no HSTS header; it already sends `x-frame-options`,
  `x-content-type-options` and `referrer-policy`.
- [ ] DAST of `https://mcp.fonada.ai` (OWASP ZAP or Chimera; the endpoint needs Bearer auth, so use a low-credit
  test key) + a fix or justification for each High/Medium finding
- [ ] Reviewer test org (Developer Edition) with the package installed, the agent committed and a working
  low-credit Fonada key, plus a short how-to-test sheet
