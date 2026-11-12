# Fonada × Agentforce — Master README

> **One file that holds everything.** The completed journey (what we already did), the current
> state (what is live right now), and the **future work** we still have to do — including
> packaging the Fonada MCP and listing it on AgentExchange.
>
> Written so that **both of us can read it** — you (Priyam / Fonada) and the AI agent (me) — and
> pick up work without re-explaining the whole story.

- **Owner:** Priyam (Fonada) — Fonada is the ISV/vendor, not the customer.
- **Created:** 2026-10-29
- **Supersedes / combines:**
  - `fonada-mcp-agentforce-complete-guide.md` (the how-to guide)
  - `fonada-mcp-agentforce-chat-2026-10-28.md` (the raw session transcript — kept as an appendix)
- **Status legend:** ✅ done · 🔄 in progress · ⛔ blocked · 🔮 future · 🧹 cleanup

---

## 0. Read me first — how we work together

Rules we agreed on (so future sessions stay on track):

1. **Always name the org.** We work across *two* Salesforce orgs. Every step says which one.
2. **One step at a time.** Short answers. No 10-step dumps unless asked.
3. **Don't spend credits / don't activate hundreds of tools.** MCP tool activation costs money.
4. **Secrets:** the Fonada `fsk_…` key was shared in plaintext once. Treat it as burned → **rotate it**.
   Never commit keys to a repo or paste them into shell history.
5. **Don't guess entities.** List candidates (agents, campaigns, tools, numbers) and let the user choose.
6. **Read-only diagnosis is fine; destructive/paid actions need confirmation.**

### The two orgs (memorise this)

| Alias | Role | Login | Instance |
|---|---|---|---|
| **`agentforce-dev`** | Where the **agent** lives (`Test 3`) | `priyam.b190dbfb3954@agentforce.com` | `orgfarm-7dc2c56568-dev-ed.develop.my.salesforce.com` |
| **`agentforce-org`** | Where the **data** lives (real CRM records) | `priyam@fonada.com` | `fonada.my.salesforce.com` |

> ⚠️ **`fonada.lightning.force.com` = the DATA org (`agentforce-org`), NOT the dev org.**
> This tripped us up before. Always double-check which one the browser tab is on.

Other key facts:

- Dev org: Developer Edition, namespace **`FonadaAI`**, API **68.0**, org id `00Dbm000012mEgfEAE`.
- Data org: org id `00DdN000013pPOnUAM`.
- Fonada MCP endpoint: **`https://mcp.fonada.ai/mcp`**

---

## 1. TL;DR — where we are

```
DONE  ──►  Fonada MCP registered in the DEV org and used by an agent (Test 3).  ✅
NOW   ──►  Trying to read DATA-ORG CRM records from the DEV-org agent, over MCP. 🔄
FUTURE ─►  Package Fonada MCP (2GP) + list it on AgentExchange.                 🔮
```

**The big idea for "future":** a customer should install **Fonada MCP** from AgentExchange in one
step, authenticate to Fonada, allowlist tools, and see them in the Agentforce action library —
exactly like the Trailhead MCP. That needs a managed package + an AgentExchange listing + an
OAuth change on Fonada's side.

---

## 2. The journey — what we already did ✅

### Day 1 — 2026-10-28: register the Fonada MCP and use it

1. **Diagnosed the original failure.** The old external credential `FonadaAI__fonadamcp` was saved
   with `authenticationProtocol = Oauth`, was not authenticated, and had an `Authorization` header
   formula pointing at a **non-existent** parameter. Registry discovery failed with
   *"The external credential isn't fully configured."*
   - **Root cause:** the formula used a **namespace-prefixed** reference
     (`$Credential.FonadaAI__fonadamcp.FonadaApiKey`) which does not resolve.
   - **Correct form:** `$Credential.FonadaMCP.FonadaApiKey` (no namespace prefix).
2. **Rebuilt the credential** as External Credential **`FonadaMCP`**:
   - `authenticationProtocol = Custom`
   - Named principal `FonadaMCPPrincipal` (sequence 1)
   - Header parameter `Authorization = {!'Bearer ' & $Credential.FonadaMCP.FonadaApiKey}`
   - Secret value set manually (a `Custom` principal's value **cannot** be deployed via metadata).
3. **Created Named Credential `FonadaMCP`** → `https://mcp.fonada.ai/mcp`.
4. **Created + assigned permission set** `Fonada_MCP_Access` ("FonadaMCP Registry Access").
5. **Registered the MCP server** via the API Catalog API
   (`POST /services/data/v68.0/api-catalog/mcp-servers`, `authType: EXISTING_EC`).
   → server id **`0Lebm0000007Sij`**, status **CONNECTED**.
6. **Discovery found 356 tools.** Tools are **inactive until allowlisted**. ~107 were turned on.
   - ⚠️ This triggered a **cost scare** → we stopped bulk activation.
7. **Used a tool in an agent.** Added `voice_campaigns_test_single_call - FonadaMCP` to a dedicated
   subagent ("Fonada Voice Test") in agent **`Test 3`** and verified it fires from Preview.
   - **Lesson:** an action is only used if a **subagent whose Description matches the request** has
     it attached, and that subagent's instructions don't steer the LLM elsewhere.
8. **Cost guardrail:** user told us to stop — "I will get the bill if I use too many MCP tools."
   → we stopped activating tools and switched to UI-guided, manual steps.

### Day 2 — 2026-10-29: the cross-org problem (this is the "future" work)

**Problem:** the agent lives in `agentforce-dev`, but the real CRM data (accounts/contacts) lives in
`agentforce-org`. The dev org has **no records**. The user does **not** want to just rebuild the
agent inside the data org — they want the **two orgs connected over MCP**.

What we established:

- ✅ **Hosted Salesforce MCP servers** are enabled per-org via **Setup → Quick Find `MCP Servers`**
  (under API Catalog), or via **Agentforce Registry → New → Add Salesforce Server**. There is **no
  CLI activate flag**. Until enabled, the registry shows *"No Salesforce servers found."*
- ✅ **Activated `platform.sobject-reads` in the data org** (`agentforce-org`) — the read-only
  SObject server.
  - URL: `https://api.salesforce.com/platform/mcp/v1/d/fonada/platform/sobject-reads`
  - Tools: `soqlQuery`, `find`, `getObjectSchema`, `getRelatedRecords`, `getUserInfo`,
    `listRecentSobjectRecords`.
- ✅ **Created an External Client App** in the data org: **`Agentforce Cross Org Integration`**
  (`0xIdN0000008nun`), Status **Enabled**, Type **Local**, App Authorization =
  *All users can self-authorize*.
- ✅ **Decision:** cross-org auth will use the registry's built-in **OAuth 2.0 Client Credentials**
  option — this works because the identity provider is **Salesforce**, which supports client
  credentials (unlike Fonada's own server).
- ⛔ **Blocked at:** enabling the client-credentials flow + scopes on that External Client App, and
  getting its Consumer Key/Secret.
- ❌ **Abandoned route:** a Lightning-app / Home-page Agent component (no "Agent" component exists in
  the dev org palette — searching returned nothing).

---

## 3. Current live state (what exists right now)

### Dev org (`agentforce-dev`)

| Component | API name | Status |
|---|---|---|
| External Credential | `FonadaMCP` (protocol `Custom`) | ✅ working |
| Named Credential | `FonadaMCP` → `https://mcp.fonada.ai/mcp` | ✅ |
| Permission Set | `Fonada_MCP_Access` | ✅ assigned |
| MCP Server (API Catalog) | `FonadaMCP`, id `0Lebm0000007Sij` | ✅ CONNECTED |
| Other connected servers | `trailbrazer` | ✅ CONNECTED |
| Agent Actions | ~107 `GenAiFunctionDefinition` ending `- FonadaMCP` | ✅ created |
| Agent | `Test 3` (Employee Agent) | ✅ activated |
| Subagent | "Fonada Voice Test" → action `voice_campaigns_test_single_call - FonadaMCP` | ✅ verified in Preview |
| Hosted servers present | `platform.sobject-reads`, `platform.sobject-all`, `platform.headless-360`, `platform.agentforce-grid` | all `active=false` |

### Data org (`agentforce-org`)

| Component | Value | Status |
|---|---|---|
| Hosted MCP server | `platform.sobject-reads` | ✅ activated |
| External Client App | `Agentforce Cross Org Integration` (`0xIdN0000008nun`) | 🔄 OAuth not finished |
| External MCP servers | `DemandbaseMCP` (Disconnected), `testtrailehad` (Active) | — |

> **Where the agent can be used in the dev org:** only **Agentforce Studio → Preview**
> (there is no usable Agent surface elsewhere in a Dev Edition org).

---

## 4. 🔄 In progress / blocked — finish the cross-org connection

**Goal:** the `Test 3` agent in `agentforce-dev` reads accounts/contacts that live in `agentforce-org`.

**Next steps (resume here):**

1. **Data org** (`agentforce-org`) → External Client App **Agentforce Cross Org Integration** →
   **Settings** tab → enable **OAuth Settings** → check **Enable Client Credentials Flow** →
   set **OAuth Scopes** = `mcp_api` (add `refresh_token` if listed) → **Save**.
2. Copy the **Consumer Key** and **Consumer Secret**.
3. **Dev org** (`agentforce-dev`) → **Agentforce Registry → New → Register MCP Server**:
   - URL: `https://api.salesforce.com/platform/mcp/v1/d/fonada/platform/sobject-reads`
   - Auth: **OAuth 2.0**
   - Identity Provider URL: `https://fonada.my.salesforce.com/services/oauth2/token`
   - Client ID / Secret: from step 2
   - Scope: `mcp_api`
4. **Allowlist** the SObject tools (`soqlQuery`, `find`, …) — *only the few needed* (cost!).
5. **Attach** them to `Test 3` (a subagent whose Description matches "read CRM data") and verify in
   **Preview**.

**Watch-outs:**
- Salesforce-hosted MCP servers consume **Flex Credits** (Developer Edition/sandbox are exempt from
  HPI metering; Fonada still bills its own usage).
- Client-credentials = **one shared app identity**, not per-user sign-in. Fine for a service agent.
- Keep the External Client App **Type = Local** (not the retired user-agent/hybrid flows).

---

## 5. 🔮 FUTURE WORK — the future tab

Everything we still plan to do, in priority order.

### F1. Finish cross-org MCP (see §4) — *next up*
Unblocked once the External Client App has client-credentials + `mcp_api` scope.

### F2. Productize the Fonada MCP server (Fonada side)
- [ ] Keep the server MCP-spec compliant (`initialize`, `tools/list`, `tools/call`) — already done.
- [ ] **Add OAuth 2.0 Client Credentials** to `mcp.fonada.ai` (issue per-customer
      client_id/client_secret). **This is the single biggest product change** — Salesforce's
      MCP packaging flow defaults to and favors client credentials, and Fonada currently supports
      only `authorization_code` + `refresh_token`.
- [ ] Decide the **tool surface per customer** — do **not** ship all 356 by default; group into
      sensible sets.
- [ ] Decide tenancy/authorization for a subscriber's credential.
- [ ] Rotate the leaked `fsk_` key.

### F3. Package Fonada MCP as a 2GP managed package
The MCP registration = **four packageable metadata types**:

| Feature | Metadata type | Notes |
|---|---|---|
| External Credential | `ExternalCredential` | Named principal + auth parameters |
| External Service Registration | `ExternalServiceRegistration` | `schemaType = ModelContextProtocol` |
| Named Credential | `NamedCredential` | Callout endpoint |
| Permission Set | `PermissionSet` | External Credential Principal access + Read on `User External Credential` |

Build steps:
1. New DX project; `sfdx-project.json` **API version 66.0+**; set the namespace.
2. Scratch org def with features **`Chatbot`** + **`Einstein1AIPlatform`**.
3. Register the MCP server in that org's Agentforce Registry, then **retrieve** the four metadata
   types. (For a non-client-credentials auth type, hand-write the metadata.)
4. Create + version the package:
   ```bash
   sf package create --type Managed --name "Fonada MCP" --path force-app
   sf package version create --package "Fonada MCP" --installation-key-bypass --wait 30
   ```
5. **Install-test** into a fresh subscriber/scratch org; confirm registration + tools appear.

### F4. List it on AgentExchange (AppExchange)
1. **Prerequisites:** PBO + AgentExchange ISV Program enrollment; namespace registered on the PBO;
   decide free vs paid; get a Partner Account Manager.
2. In **Partner Console**, create the listing (Agentforce/MCP type):
   *listing → MCP Servers → List an MCP Server → name/description → Add*.
3. **Business Plan Review** (~2–4 weeks).
4. Set up **LMA** (License Management App) if licensing.
5. **Security Review** — **2GP is required for new listings**; budget **2–3 cycles** (~4–8 weeks).
   Indicative fees: ~**$2,700** security review for paid apps + ~**$150/yr** listing fee
   *(verify current numbers)*.
6. Publish.

### F5. 🧹 Cleanup / hygiene (leftovers)
- [ ] Delete leftover permission sets: `fonada`, `fonda`, `foanda`, `fonadaMCP`, `FonadaMCPProbe`.
- [ ] Delete the empty Lightning app `Fonada Agent` (`Fonada_Agent`).
- [ ] Trim the ~94 unnecessary tools off the over-loaded subagent.
- [ ] Rotate the Fonada API key and update the credential.

### F6. Customer "easy install" experience (end state)
1. Find **Fonada MCP** on AgentExchange (also discoverable inside Agentforce Builder).
2. **Install** (package install / one-click connect).
3. Registration appears in their **Agentforce Registry**; admin enters the Fonada client id/secret.
4. Admin **allowlists** tools (inactive until selected).
5. Tools appear in the **Agent Builder** action library → add to a subagent + instruction.

### Rough timeline & cost

| Stage | Time |
|---|---|
| Productize auth + tool surface | weeks (depends on client-credentials work) |
| Package build + test | 1–3 weeks |
| Business Plan Review | 2–4 weeks |
| Security Review | 4–8 weeks (often 2–3 cycles) |
| **Total** | **~3–6 months** realistically |

---

## 6. From-scratch setup reference (condensed)

### 6A. UI route (recommended, one-time per org)

1. **Setup → Quick Find `Agentforce` → Agentforce Registry → New MCP Server.**
2. **Name:** `FonadaMCP` · **Server URL:** `https://mcp.fonada.ai/mcp` · **Auth:** *Use External Credential*.
3. **New External Credential:**
   - Protocol **`Custom`**; Principal `FonadaMCPPrincipal` (Named, seq 1)
   - Parameter `FonadaApiKey` = your `fsk_…` key
   - Header `Authorization` = `{!'Bearer ' & $Credential.<CredName>.FonadaApiKey}`
     → this org: `{!'Bearer ' & $Credential.FonadaMCP.FonadaApiKey}`
4. Back on the registry form: refresh the picker → select `FonadaMCP`; **Authentication Status = Configured**.
5. **Save** (Salesforce creates the Named Credential + permission set and runs discovery).
6. **Assign the permission set** to the running users **and** to the agent's **agent user**
   (`…@….ext`).
7. **Allowlist tools** (Tools tab → select → Activate) — only what you need.
8. Use in an agent (see §7).

### 6B. CLI / metadata route

```bash
ORG=agentforce-dev
ID=0Lebm0000007Sij            # MCP server id (after registration)
```

**External Credential** (`force-app/main/default/externalCredentials/FonadaMCP.externalCredential-meta.xml`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExternalCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <authenticationProtocol>Custom</authenticationProtocol>
    <externalCredentialParameters>
        <parameterGroup>DefaultGroup</parameterGroup>
        <parameterName>Custom</parameterName>
        <parameterType>AuthProtocolVariant</parameterType>
        <parameterValue>Custom</parameterValue>
    </externalCredentialParameters>
    <externalCredentialParameters>
        <parameterGroup>FonadaMCPPrincipal</parameterGroup>
        <parameterName>FonadaMCPPrincipal</parameterName>
        <parameterType>NamedPrincipal</parameterType>
        <sequenceNumber>1</sequenceNumber>
    </externalCredentialParameters>
    <externalCredentialParameters>
        <parameterGroup>FonadaMCPPrincipal</parameterGroup>
        <parameterName>FonadaApiKey</parameterName>
        <parameterType>AuthParameter</parameterType>
    </externalCredentialParameters>
    <externalCredentialParameters>
        <parameterGroup>DefaultGroup</parameterGroup>
        <parameterName>Authorization</parameterName>
        <parameterType>AuthHeader</parameterType>
        <parameterValue>{!'Bearer ' &amp; $Credential.FonadaMCP.FonadaApiKey}</parameterValue>
    </externalCredentialParameters>
    <label>FonadaMCP</label>
</ExternalCredential>
```

```bash
sf project deploy start --metadata ExternalCredential:FonadaMCP --target-org $ORG
```

**Set the secret** (a `Custom` principal's value can't be deployed via metadata):

```bash
sf api request rest "/services/data/v68.0/named-credentials/credential/" -X POST \
  -H "Content-Type: application/json" \
  --body '{"externalCredential":"FonadaMCP","principalType":"NamedPrincipal","principalName":"FonadaMCPPrincipal","authenticationProtocol":"Custom","credentials":[{"name":"FonadaApiKey","value":"fsk_YOUR_KEY"}]}' \
  --target-org $ORG
```

**Named Credential** (`…/namedCredentials/FonadaMCP.namedCredential-meta.xml`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <allowMergeFieldsInBody>true</allowMergeFieldsInBody>
    <allowMergeFieldsInHeader>true</allowMergeFieldsInHeader>
    <calloutStatus>Enabled</calloutStatus>
    <generateAuthorizationHeader>false</generateAuthorizationHeader>
    <label>FonadaMCP</label>
    <namedCredentialParameters>
        <parameterName>Url</parameterName>
        <parameterType>Url</parameterType>
        <parameterValue>https://mcp.fonada.ai/mcp</parameterValue>
    </namedCredentialParameters>
    <namedCredentialParameters>
        <externalCredential>FonadaMCP</externalCredential>
        <parameterName>ExternalCredential</parameterName>
        <parameterType>Authentication</parameterType>
    </namedCredentialParameters>
    <namedCredentialType>SecuredEndpoint</namedCredentialType>
</NamedCredential>
```

```bash
sf project deploy start --metadata NamedCredential:FonadaMCP --target-org $ORG
sf project deploy start --metadata "PermissionSet:Fonada_MCP_Access" --target-org $ORG
sf org assign permset --name Fonada_MCP_Access --target-org $ORG
```

**Register the MCP server** (CLI `sf agent mcp create` supports only `OAUTH | NO_AUTH`, so use the API):

```bash
sf api request rest "/services/data/v68.0/api-catalog/mcp-servers" -X POST \
  -H "Content-Type: application/json" \
  --body '{"name":"FonadaMCP","type":"EXTERNAL","serverUrl":"https://mcp.fonada.ai/mcp","authorization":{"authType":"EXISTING_EC","externalCredentialName":"FonadaMCP"}}' \
  --target-org $ORG
```

**Allowlist tools:**

```bash
sf api request rest "/services/data/v68.0/api-catalog/mcp-servers/$ID/fetch" -X POST --body '{}' --target-org $ORG > /tmp/fetch.json

jq --arg t "McpTool__voice_campaigns_test_single_call" '{
  serverFingerprint: .serverFingerprint,
  assets: [ .assets[] | {id,name,label,description,kind,
            active: ((.active==true) or (.name==$t))} ] }' /tmp/fetch.json > /tmp/allowlist.json

sf api request rest "/services/data/v68.0/api-catalog/mcp-servers/$ID/assets" -X PUT \
  -H "Content-Type: application/json" --body @/tmp/allowlist.json --target-org $ORG
```

> `PUT …/assets` is a **full replace**. The CLI wrapper `sf agent mcp asset replace --assets-file`
> drops `serverFingerprint` → the direct PUT above is more reliable.

### 6C. Verification

```bash
# server health
sf agent mcp list --target-org $ORG --json | jq -r '.result.mcpServers[]?|select(.type=="EXTERNAL")|"\(.id) \(.name) \(.connectionHealth) active=\(.active)"'

# a specific tool's state
sf api request rest "/services/data/v68.0/api-catalog/mcp-servers/$ID/fetch" -X POST --body '{}' --target-org $ORG \
 | jq -r '.assets[]|select(.name=="McpTool__voice_campaigns_test_single_call")|"\(.name) active=\(.active) action=\(.availableAsAgentAction)"'

# agent actions created
sf api request rest "services/data/v68.0/tooling/query?q=SELECT+MasterLabel+FROM+GenAiFunctionDefinition" --target-org $ORG \
 | jq -r '[.records[].MasterLabel|select(endswith("- FonadaMCP"))]|length'
```

**Success =** server `CONNECTED`, tool `active=true action=true`, and the action appears in the count.

---

## 7. Use the tools in an Agentforce agent (UI)

The permission set is only half of it — the action must be attached to a **subagent**.

1. **App Launcher → Agentforce Studio** → open an **Employee Agent** (External-Credential MCP tools
   are Employee-only).
2. Open (or create) a subagent dedicated to the domain, e.g. **"Fonada Voice Test"**.
3. **Actions Available For Reasoning → Add action → search the tool name → add**
   (`voice_campaigns_test_single_call - FonadaMCP`). Leave *Set output = Not assigned*.
4. **Reasoning Instructions** — tell the LLM when to call it:
   > *When the user asks to place a test call, call `voice_campaigns_test_single_call` with the Fonada
   > agent name and the phone number. If either is missing, ask the user for it.*
5. Make the **subagent Description** match the intent (the Agent Router uses it):
   > *Use when the user asks to place a test call or make a voice call using Fonada voice.*
6. **Save → Activate → Preview.**
7. (Optional) Turn on **Require user confirmation** for anything that places calls/sends messages.
8. Per-user auth: the user may need to authorize at
   **My Personal Information → External Credentials → FonadaMCP → Allow Access**.

---

## 8. Troubleshooting / gotchas (learned the hard way)

| Symptom | Cause | Fix |
|---|---|---|
| *"The external credential isn't fully configured."* | Formula references a missing/namespace-prefixed parameter, or protocol is `Oauth` and unauthenticated | Use `$Credential.<Name>.<Param>` (no namespace prefix); set protocol `Custom`; set the secret |
| `Field FonadaAI__….FonadaApiKey does not exist` | Namespace-prefixed reference | Use the un-prefixed credential name |
| `Custom` secret won't deploy | Custom principal values aren't deployable via metadata | Set via UI or the credentials API |
| Tool not in the agent action picker | Not allowlisted (`active:false`) | Allowlist via Tools tab / `PUT …/assets` |
| `sf agent mcp create` rejects your auth | CLI supports only `OAUTH\|NO_AUTH` | Use the API with `authType: EXISTING_EC` |
| `asset replace` → *"description doesn't match remote state"* | CLI drops `serverFingerprint` | Use the direct `PUT …/assets` with the fingerprint |
| Allowlist PUT → `INTERNAL_SERVER_ERROR` / `ERROR_DEACTIVATING_OPERATION` | Hand-built registration with broken linkage | Re-register through the Registry/API, then allowlist |
| Agent ignores the tool | Action on the wrong subagent, or instructions steer elsewhere | Put the action on a subagent whose **Description** matches; add a matching instruction |
| Tool call unauthorized | Missing permission set on the running user / agent user | Assign the MCP permission set to both |
| Registry shows *"No Salesforce servers found"* | Hosted servers not enabled in that org | **Setup → Quick Find `MCP Servers`** → enable (no CLI flag) |
| Tools all appear already checked | Bulk-activated earlier | Only the needed ones; deactivate the rest (cost) |

---

## 9. Key identifiers (this setup)

```
DEV ORG (agentforce-dev)
  org id              : 00Dbm000012mEgfEAE
  username            : priyam.b190dbfb3954@agentforce.com
  instance            : https://orgfarm-7dc2c56568-dev-ed.develop.my.salesforce.com
  namespace           : FonadaAI
  External Credential : FonadaMCP   (protocol Custom)
  Named Credential    : FonadaMCP   -> https://mcp.fonada.ai/mcp
  Permission Set      : Fonada_MCP_Access  ("FonadaMCP Registry Access")
  MCP server id       : 0Lebm0000007Sij  (FonadaMCP, CONNECTED)
  Example tool asset  : 1XObm0000008Dzg  (McpTool__voice_campaigns_test_single_call)
  Agent               : Test 3  (subagent "Fonada Voice Test")

DATA ORG (agentforce-org)
  org id              : 00DdN000013pPOnUAM
  username            : priyam@fonada.com
  instance            : https://fonada.my.salesforce.com
  Hosted MCP server   : platform.sobject-reads   (ACTIVATED)
  Hosted MCP URL      : https://api.salesforce.com/platform/mcp/v1/d/fonada/platform/sobject-reads
  External Client App : Agentforce Cross Org Integration  (0xIdN0000008nun, Enabled, Local)
```

---

## 10. References

- **MCP for Agentforce Metadata in Managed Packages** — 2GP Developer Guide
  `developer.salesforce.com/docs/platform/pkg2-dev/guide/dev2gp-package-mcp-agentforce.html`
- **Add MCP Servers to Your Agentforce Agents** — ISVforce Guide
  `developer.salesforce.com/docs/platform/isvforce/guide/appexchange-listing-builder-add-mcp-servers.html`
- **Register a Third-Party MCP Server in Agentforce Registry** — Salesforce Help
  `help.salesforce.com/s/articleView?id=ai.agent_mcp_connect_register.htm`
- **Set Up Your Org | Hosted MCP Servers** — Salesforce Developers
  `developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/setup-overview.html`
- **Partner Program FAQ: AgentExchange ISV** — Salesforce Help (`id=000394757`)
- **AgentExchange / Agentforce MCP** — `agentexchange.salesforce.com/collections/agentforce-mcp`

---

## 11. Appendix — source documents

| File | What it is |
|---|---|
| `README.md` (this file) | The master doc — read this first. |
| `fonada-mcp-agentforce-complete-guide.md` | The original how-to guide (setup + roadmap). |
| `fonada-mcp-agentforce-chat-2026-10-28.md` | Raw session transcript of Day 1 (diagnosis → working agent). |

> **Resume point:** §4, step 1 — open the data org's External Client App **Settings** tab and enable
> the client-credentials flow + `mcp_api` scope.
