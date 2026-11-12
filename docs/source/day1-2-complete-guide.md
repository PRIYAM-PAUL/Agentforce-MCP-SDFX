# Fonada MCP → Agentforce: Complete Guide

**Scope:** everything about connecting the Fonada MCP server to Salesforce Agentforce —
what we already did, how to do it from scratch, and the roadmap to distribute it on
AgentExchange (AppExchange).

- **Org used:** `agentforce-dev` → `priyam.b190dbfb3954@agentforce.com` (Developer Edition, namespace `FonadaAI`, API 68.0)
- **Instance:** `https://orgfarm-7dc2c56568-dev-ed.develop.my.salesforce.com`
- **MCP endpoint:** `https://mcp.fonada.ai/mcp`
- **Partner org (PBO):** `agentforce-org` → `priyam@fonada.com` (`fonada.my.salesforce.com`)
- **Last updated:** 2026-10-29

> ⚠️ **Secret hygiene:** the Fonada API key (`fsk_…`) was shared in plaintext during setup.
> Rotate it in Fonada and update the credential. Never commit it to a repo or paste it into a shell history.

---

## 0. TL;DR

Adding an external MCP server to Agentforce = **4 Salesforce components + 1 registration**:

```
ExternalCredential  →  NamedCredential  →  PermissionSet  →  (MCP registration)  →  allowlist tools  →  add action to agent
        (auth)              (endpoint)         (access)        API Catalog / Registry      Tools tab        Agent Builder
```

- Auth = **External Credential** (here: `Custom` protocol, `Authorization: Bearer <Fonada key>`)
- Endpoint = **Named Credential** (`https://mcp.fonada.ai/mcp`)
- Access = **Permission Set** granting the external-credential principal + `User External Credential` read
- Registration = **Agentforce Registry / API Catalog MCP server** (discovers the tools)
- Tools are **inactive until allowlisted**, then they appear in the Agent Builder action library.

---

## 1. Components (what each thing is)

| Component | API name (this org) | Purpose |
|---|---|---|
| External Credential | `FonadaMCP` (ns `FonadaAI`) | Holds auth: principal + `FonadaApiKey` + `Authorization` header formula |
| Named Credential | `FonadaMCP` | Callout endpoint + links the external credential |
| Permission Set | `Fonada_MCP_Access` (label "FonadaMCP Registry Access") | Grants users access to the credential principal |
| MCP Server (API Catalog) | `FonadaMCP`, id `0Lebm0000007Sij` | The registered MCP server; holds the tool allowlist |
| External Service Registration | `FonadaMCP` | The metadata record backing the MCP registration (`schemaType = ModelContextProtocol`) |
| Agent Action | `GenAiFunctionDefinition` per tool, e.g. `voice_campaigns_test_single_call - FonadaMCP` | The callable action exposed to agents |

---

## 2. What we did (chronological log)

1. **Diagnosed the original failure.** The pre-existing external credential `FonadaAI__fonadamcp`
   was saved with `authenticationProtocol = Oauth`, was **not authenticated**, and carried an orphan
   `Authorization` header formula referencing a **non-existent** principal parameter `FonadaApiKey`.
   The Agentforce Registry discovery therefore failed with *"The external credential isn't fully configured."*
   - Root cause of the formula problem: the reference was **namespace-prefixed**
     (`$Credential.FonadaAI__fonadamcp.FonadaApiKey`), which does not resolve.
     The correct form is **`$Credential.FonadaMCP.FonadaApiKey`**.

2. **Rebuilt the credential correctly** as an External Credential `FonadaMCP`:
   - `authenticationProtocol = Custom`
   - Named principal `FonadaMCPPrincipal` (sequence 1)
   - Header parameter `Authorization = {!'Bearer ' & $Credential.FonadaMCP.FonadaApiKey}`
   - The `FonadaApiKey` value was set (the secret cannot be deployed via metadata for a Custom principal).

3. **Created the Named Credential** `FonadaMCP` → `https://mcp.fonada.ai/mcp`
   (`SecuredEndpoint`, `Enabled`, references `FonadaAI__FonadaMCP`).

4. **Created + assigned the permission set** `Fonada_MCP_Access` (principal access).

5. **Registered the MCP server in the API Catalog** (the supported programmatic path):
   `POST /services/data/v68.0/api-catalog/mcp-servers` with
   `authorization.authType = EXISTING_EC` → server id `0Lebm0000007Sij`, `CONNECTED`.
   - Earlier a hand-built `ExternalServiceRegistration` was also deployed; the API route is the
     supported one because it also creates the proper internal linkage (service binding, per-tool records).

6. **Discovery found 356 tools.** Tools are **inactive until allowlisted**. ~107 were turned on as
   agent actions (`GenAiFunctionDefinition`).

7. **Used a tool in an agent.** Added `voice_campaigns_test_single_call - FonadaMCP` to a dedicated
   subagent ("Fonada Voice Test") in the `Test 3` agent, with a reasoning instruction, and verified it
   fires from the agent preview.
   - **Lesson:** an action is only used if a subagent whose **Description** matches the request has it
     attached, and that subagent's **instructions** don't steer the LLM to a different action.

---

## 3. Add Fonada MCP to Agentforce from scratch

### 3A. UI route (recommended, one-time per org)

1. **Setup → Quick Find `Agentforce` → Agentforce Registry → New MCP Server.**
2. **Name:** `FonadaMCP` · **Server URL:** `https://mcp.fonada.ai/mcp` · **Authentication Method:** **Use External Credential**.
3. Click **New External Credential** (opens Named Credentials). Create one:
   - **Authentication Protocol:** `Custom`
   - **Principal:** `FonadaMCPPrincipal` (Named Principal, sequence 1)
   - **Parameter:** name `FonadaApiKey`, value = your Fonada `fsk_…` key
   - **Header parameter:** name `Authorization`, value
     `{!'Bearer ' & $Credential.<YourCredentialName>.FonadaApiKey}`
     → for this org: `{!'Bearer ' & $Credential.FonadaMCP.FonadaApiKey}`
   - Save.
4. Back on the registry form: **refresh** the External Credential picker → select `FonadaMCP`.
   Confirm the **Authentication Status** shows **Configured**.
5. **Save** the MCP server. Salesforce creates the Named Credential + permission set and runs discovery.
6. **Assign the permission set** (Setup → Permission Sets → *FonadaMCP Registry Access* → Manage Assignments)
   to the users who will run the agent, **and** to the agent's **agent user** (Einstein Agent User, `…@….ext`).
7. **Allowlist tools:** MCP server → **Tools** tab → select the tools you want → Activate.
8. **Use in an agent** (see section 4).

### 3B. CLI / metadata route (what we effectively did)

```bash
ORG=agentforce-dev
ID=0Lebm0000007Sij            # MCP server id (after registration)
ENDPOINT=https://mcp.fonada.ai/mcp
```

**Step 1 — External Credential (deploy structure only; secret set separately).**

`force-app/main/default/externalCredentials/FonadaMCP.externalCredential-meta.xml`
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

Deploy it:
```bash
sf project deploy start --metadata ExternalCredential:FonadaMCP --target-org $ORG
```

**Step 2 — Set the secret value.**
A `Custom` principal's parameter value **cannot** be deployed via metadata. Set it either:
- in the UI: **Setup → Named Credentials → External Credentials → FonadaMCP → Edit → `FonadaApiKey`**, or
- via the Named Credentials credentials API:
  ```bash
  # verify the exact payload shape for your API version before running
  sf api request rest "/services/data/v68.0/named-credentials/credential/" -X POST \
    -H "Content-Type: application/json" \
    --body '{"externalCredential":"FonadaMCP","principalType":"NamedPrincipal","principalName":"FonadaMCPPrincipal","authenticationProtocol":"Custom","credentials":[{"name":"FonadaApiKey","value":"fsk_YOUR_KEY"}]}' \
    --target-org $ORG
  ```

**Step 3 — Named Credential.**

`force-app/main/default/namedCredentials/FonadaMCP.namedCredential-meta.xml`
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
```

**Step 4 — Permission Set** granting the external-credential principal access, then assign it:
```bash
sf project deploy start --metadata "PermissionSet:Fonada_MCP_Access" --target-org $ORG
# assign to your user + the agent user
sf org assign permset --name Fonada_MCP_Access --target-org $ORG
```

**Step 5 — Register the MCP server (API Catalog).**
The CLI `sf agent mcp create` only supports `OAUTH | NO_AUTH`; for **Use External Credential** call the API directly:
```bash
sf api request rest "/services/data/v68.0/api-catalog/mcp-servers" -X POST \
  -H "Content-Type: application/json" \
  --body '{"name":"FonadaMCP","type":"EXTERNAL","serverUrl":"https://mcp.fonada.ai/mcp","authorization":{"authType":"EXISTING_EC","externalCredentialName":"FonadaMCP"}}' \
  --target-org $ORG
```
→ returns the server + discovered assets. Note the server `id`.

**Step 6 — Allowlist tools.**
```bash
# live assets + fingerprint
sf api request rest "/services/data/v68.0/api-catalog/mcp-servers/$ID/fetch" -X POST --body '{}' --target-org $ORG > /tmp/fetch.json

# mark the ones you want active (example: just the voice_campaigns_test_single_call)
jq --arg t "McpTool__voice_campaigns_test_single_call" '{
  serverFingerprint: .serverFingerprint,
  assets: [ .assets[] | {id,name,label,description,kind,
            active: ((.active==true) or (.name==$t))} ] }' /tmp/fetch.json > /tmp/allowlist.json

sf api request rest "/services/data/v68.0/api-catalog/mcp-servers/$ID/assets" -X PUT \
  -H "Content-Type: application/json" --body @/tmp/allowlist.json --target-org $ORG
```
> `PUT …/assets` is a **full replace** — the payload becomes the entire allowlist.
> The CLI wrapper `sf agent mcp asset replace --assets-file` drops `serverFingerprint`, so it requires
> exact descriptions; the direct PUT above is more reliable.

### 3C. Verification

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
Success = server `CONNECTED`, tool `active=true action=true`, and the action appears in the count.

---

## 4. Use the tools in an Agentforce agent (UI)

The permission set is only half of it — the action must be attached to a **subagent** in the agent.

1. **App Launcher → Agentforce Studio** → open an **Employee Agent** (External-Credential MCP tools are Employee-only).
2. Open a subagent (or create one dedicated to the domain, e.g. **"Fonada Voice Test"**).
3. **Actions Available For Reasoning → Add action → search the tool name → add**
   (`voice_campaigns_test_single_call - FonadaMCP`). Leave **Set output = Not assigned** (optional).
4. **Reasoning Instructions** — add a line telling the LLM when to call it, e.g.:
   > *When the user asks to place a test call, call `voice_campaigns_test_single_call` with the Fonada
   > agent name and the phone number. If either is missing, ask the user for it.*
5. Make the **subagent Description** match the intent (the Agent Router uses it to route), e.g.
   > *Use when the user asks to place a test call or make a voice call using Fonada voice.*
6. **Save → Activate → Preview.**
7. (Optional) Turn on **Require user confirmation** on the action for anything that places calls/sends messages.
8. Per-user auth: the user may need to authorize at **My Personal Information → External Credentials → FonadaMCP → Allow Access**.

---

## 5. Troubleshooting / gotchas (learned the hard way)

| Symptom | Cause | Fix |
|---|---|---|
| *"The external credential isn't fully configured."* | Formula references a missing/namespace-prefixed parameter, or protocol is `Oauth` and unauthenticated | Use `$Credential.<Name>.<Param>` (no namespace prefix); set protocol `Custom`; set the secret value |
| Formula error `Field FonadaAI__….FonadaApiKey does not exist` | Namespace-prefixed reference | Use the un-prefixed credential name |
| `Custom` secret won't deploy | Custom principal values aren't deployable via metadata | Set via UI or the credentials API |
| Tool not in the agent action picker | Not allowlisted (`active:false`) | Allowlist via Tools tab / `PUT …/assets` |
| `sf agent mcp create` rejects your auth | CLI supports only `OAUTH|NO_AUTH` | Use the API with `authType: EXISTING_EC` |
| `asset replace` → *"description doesn't match remote state"* | CLI drops `serverFingerprint` | Use the direct `PUT …/assets` with the fingerprint |
| Allowlist PUT → `INTERNAL_SERVER_ERROR` / `ERROR_DEACTIVATING_OPERATION` | Hand-built registration record with broken linkage | Re-register the server through the Registry (or the API), then allowlist |
| Agent ignores the tool | Action attached to the wrong subagent, or subagent instructions steer elsewhere | Put the action on a subagent whose **Description** matches the request; add a matching instruction |
| Tool call unauthorized | Missing permission set on the running user / agent user | Assign the MCP permission set to both |

---

## 6. Roadmap — distribute Fonada MCP on AgentExchange (AppExchange)

> **Goal:** a customer installs **Fonada MCP** from AgentExchange in one step, authenticates to Fonada,
> allowlists tools, and sees them in the Agentforce action library — like the Trailhead MCP.

### The two things to ship (complementary)

1. **Managed package (2GP)** containing the MCP registration metadata.
2. **AgentExchange listing** (with the MCP Server / "ISV MCP Tool Action" listing type).

The MCP registration comprises **four packageable metadata types**:

| Feature | Metadata type | Notes |
|---|---|---|
| External Credential | `ExternalCredential` | Named principal + auth parameters |
| External Service Registration | `ExternalServiceRegistration` | `registrationProviderType`/`schemaType = ModelContextProtocol` |
| Named Credential | `NamedCredential` | Callout endpoint |
| Permission Set | `PermissionSet` | Grants External Credential Principal access + Read on `User External Credential` |

### ⚠️ The one hard constraint to decide first — authentication

- Salesforce's MCP packaging/registry flow **defaults to and favors OAuth 2.0 Client Credentials Flow**;
  the ISV guidance describes MCP connections as a **shared OAuth client credential** (not per-user sign-in).
- Fonada's current OAuth server supports only `authorization_code` + `refresh_token` — **no `client_credentials`**.
- **Therefore: Fonada must add an OAuth 2.0 Client Credentials flow** to `mcp.fonada.ai` (issue a
  client_id/client_secret per customer/tenant). That is the biggest product change.
- Alternative (non-standard): hand-write metadata for a **Custom/API-key** credential, where each
  subscriber enters their own key. The docs explicitly allow manually generating metadata for a
  non-Client-Credentials auth type.

### Phase 0 — Prerequisites
1. **PBO** + **AgentExchange ISV Program** enrollment (Partner Community / Partner Console).
2. **Namespace** registered for the package on the PBO.
3. Decide **free vs paid** listing (affects fees).
4. Get a **Partner Account Manager** contact for MCP-listing specifics.

### Phase 1 — Productize the MCP server (Fonada side)
1. Keep the server MCP-spec compliant (`initialize`, `tools/list`, `tools/call`) — already done.
2. **Add OAuth 2.0 Client Credentials** (or commit to the API-key path).
3. Decide the **tool surface per customer** — don't ship all 356 by default; group into sensible sets.
4. Decide tenancy/authorization for a subscriber's credential.

### Phase 2 — Build the 2GP managed package
1. New DX project; `sfdx-project.json` **API version 66.0+**; set the namespace.
2. Scratch org def with features **`Chatbot`** and **`Einstein1AIPlatform`**.
3. In that org, **register the MCP server in Agentforce Registry**, then **retrieve** the metadata
   (the four types). For a non-Client-Credentials auth type, hand-write the metadata instead.
4. Create + version the package:
   ```bash
   sf package create --type Managed --name "Fonada MCP" --path force-app
   sf package version create --package "Fonada MCP" --installation-key-bypass --wait 30
   ```
5. **Install-test** into a fresh subscriber/scratch org; confirm registration + tools appear.

### Phase 3 — Listing & review on AgentExchange
1. In **Partner Console**, create the listing (Agentforce/MCP type).
2. Per the ISVforce guide: **listing → MCP Servers → List an MCP Server → name/description → Add**.
3. **Business Plan Review** (~2–4 weeks).
4. Set up **LMA** (License Management App) if licensing.
5. **Security Review** — **2GP required for new listings**; budget **2–3 cycles** (~4–8 weeks).
   Indicative fees: ~**$2,700** security review for paid apps (free apps typically no review fee) +
   ~**$150/yr** listing fee *(verify current numbers)*.
6. Publish.

### Phase 4 — Customer experience ("easy install")
1. Find **Fonada MCP** on AgentExchange (also discoverable inside Agentforce Builder).
2. **Install** (package install / one-click connect).
3. Registration appears in their **Agentforce Registry**; admin enters Fonada client id/secret (or key).
4. Admin **allowlists** tools (inactive until selected).
5. Tools appear in the **Agent Builder** action library → add to a subagent + instruction.

### Phase 5 — Maintain
- New package versions on every tool change; re-run security review per policy; keep the listing current.

### Timeline & cost (rough)
| Stage | Time |
|---|---|
| Productize auth + tool surface | weeks (depends on client-credentials work) |
| Package build + test | 1–3 weeks |
| Business Plan Review | 2–4 weeks |
| Security Review | 4–8 weeks (often 2–3 cycles) |
| **Total** | **~3–6 months** realistically |

### Immediate next steps
1. Decide the auth model — can Fonada implement **OAuth 2.0 Client Credentials** on `mcp.fonada.ai`?
2. Enroll in the **AgentExchange ISV Program**; get a Partner Account Manager.
3. Register the **namespace** on the PBO.
4. Build the **2GP** with the four metadata types; install-test.
5. Create the **listing** and add the MCP server to it.

---

## 7. References

- **MCP for Agentforce Metadata in Managed Packages** — 2GP Developer Guide
  `developer.salesforce.com/docs/platform/pkg2-dev/guide/dev2gp-package-mcp-agentforce.html`
- **Add MCP Servers to Your Agentforce Agents** — ISVforce Guide
  `developer.salesforce.com/docs/platform/isvforce/guide/appexchange-listing-builder-add-mcp-servers.html`
- **Register a Third-Party MCP Server in Agentforce Registry** — Salesforce Help
  `help.salesforce.com/s/articleView?id=ai.agent_mcp_connect_register.htm`
- **Partner Program FAQ: AgentExchange ISV** — Salesforce Help (`id=000394757`)
- **AgentExchange / Agentforce MCP** — `agentexchange.salesforce.com/collections/agentforce-mcp`

---

### Key identifiers (this org, for reference)

```
org alias        : agentforce-dev
username         : priyam.b190dbfb3954@agentforce.com
namespace        : FonadaAI
External Credential : FonadaMCP   (protocol Custom)
Named Credential    : FonadaMCP   → https://mcp.fonada.ai/mcp
Permission Set      : Fonada_MCP_Access  ("FonadaMCP Registry Access")
MCP server id       : 0Lebm0000007Sij  (FonadaMCP, CONNECTED)
Example tool asset  : 1XObm0000008Dzg  (McpTool__voice_campaigns_test_single_call)
```
