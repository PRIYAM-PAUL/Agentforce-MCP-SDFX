> **⚠ Historical document (last updated 2026-11-02, package 1.1.0.1). Superseded.**
> Current state: **Fonada MCP 1.0 = build 1.2.0.13** (`04tdN000000TfMLQA0`), released 2026-11-12.
> For the current package see the repo `README.md`, `docs/Fonada_MCP_Agentforce_Install_Guide.md`,
> `docs/AgentExchange_Listing_Content.md` and `docs/Security_Review_Notes.md`.

# Fonada × Agentforce — Salesforce Implementation README

> **The single source of truth for this project.** Read this first on Monday — it contains the
> full journey, every decision, every command, every error we fixed, the current state, and
> the exact next steps. Written so **both** Priyam (Fonada) and the AI agent can resume with
> **full context** without re-explaining anything.

- **Owner:** Priyam (Fonada) — Fonada is the **ISV / vendor**, not the customer.
- **Project:** `fonada-agentforce-mcp-package` (a **new, separate** Salesforce DX project).
- **Status legend:** ✅ done · 🔄 in progress · ⛔ blocked · 🔮 future · 🧹 cleanup
- **Last updated:** 2026-10-30 (evening — logging off; resume Monday)
- **Companion docs in this folder:**
  - `Fonada_MCP_Agentforce_Install_Guide.md` — customer-facing install guide (shows **below the app** on the marketplace)
  - `AgentExchange_Listing_Content.md` — listing copy pack (paste into Listing Builder)
- **Full Day 1–2 history (source files, copied in):** `docs/source/`
  - `day1-2-complete-guide.md` — the original how-to guide
  - `day1-2-master-README.md` — the master doc from the first two days
  - `day1-raw-chat-transcript.md` — the raw session transcript

---

## 0. RESUME POINT (read this first)

**Where we are:** The package is **fixed, rebuilt, released and verified in a real org.**
Version **`1.1.0.1`** (`04tdN000000TSk5QAG`) ships the corrected ESR — **12 tools,
`status=Complete`**, descriptor `fonada 1.29.1`. It is ready to list.

**Verified on 2026-11-02:**
- PBO (`agentforce-org`) upgraded `1.0.0.4` → `1.1.0.1` ✅
- ESR `FonadaMCP` = `Complete`, schema contains the 12 tools ✅
- MCP server exposes **12 assets** ✅

**The very next action:**
1. In `partners.salesforce.com` → **Publishing → Solutions**, refresh and check whether package
   version **1.1.0.1** has synced. The Dev Hub (`agentforce-org`, org id `00DdN000013pPOnUAM`)
   was connected on 2026-10-30; the sync is **asynchronous** (minutes → ~a day).
2. When it appears → click **Register Package** → enter Dev Hub credentials → set license behavior → Save.
3. Then create the listing (see §9).

> ⚠️ **Scratch orgs cannot install this package.** `ExternalServiceRegistration` is rejected with
> *"Cannot install component of type:ExternalServiceRegistration … because it was used as a
> scratch org ancestor."* This affects **every** version (verified with `1.0.0.3`, `1.0.0.4` and
> `1.1.0.1`), so it is **not** caused by our ESR change — it is a platform restriction. Always
> install-test MCP packages in a **real org** (Developer Edition, sandbox, or production), never
> a scratch org.

**Released versions:** `1.1.0.1` (`04tdN000000TSk5QAG`) ← **use this**; `1.0.0.4`
(`04tdN000000TPRFQA4`) is superseded (empty tool schema).
---

## 1. The goal

Let a **normal Salesforce customer** get Fonada's tools into Agentforce in ~3 clicks — **without**
hand-building External Credential → Named Credential → Permission Set. Delivered as a
**Salesforce managed package** listed on **AgentExchange**, discoverable inside
**Agentforce Builder → Add from Asset Library → Browse AgentExchange**.

### Customer end-state (the "dream")
```
Browse AgentExchange → Install "Fonada MCP"
   → the MCP server registration + credential + named credential + permission set
     are created AUTOMATICALLY by the package
   → paste your Fonada fsk key (ONE field) → Activate
   → Tools tab → pick tools → they appear as agent actions
   → add the action to a subagent → done
```

---

## 2. The one key idea

The 4 manual Setup pieces are **packageable metadata** (officially, in Managed 2GP). Put them in a
managed package → they are **created automatically on install**. **The package IS the "bypass."**

| Feature | Metadata type |
|---|---|
| Auth (holds the `fsk` key) | `ExternalCredential` |
| Endpoint | `NamedCredential` |
| MCP registration | `ExternalServiceRegistration` (`schemaType = ModelContextProtocol`) |
| Access | `PermissionSet` |

Not packageable (per Salesforce): **MCP tool actions** and **Agentforce Gateway policies**.

---

## 3. Environment — orgs, IDs, and key facts

| Alias | Role | Login | Org ID | Edition | Dev Hub? | Namespace |
|---|---|---|---|---|---|---|
| **`agentforce-org`** | **Dev Hub + PBO** | `priyam@fonada.com` | `00DdN000013pPOnUAM` | Enterprise | ✅ Yes | linked `FonadaAI` |
| **`agentforce-dev`** | Dev / test org (has old manual setup) | `priyam.b190dbfb3954@agentforce.com` | `00Dbm000012mEgfEAE` | Developer | ❌ No | `FonadaAI` |
| **`fonada-mcp-test`** | Scratch org (test box, disposable) | `test-…@example.com` | (scratch) | Partner Developer | — | inherits `FonadaAI` |

- **Fonada MCP endpoint:** `https://mcp.fonada.ai/mcp`
- **Namespace:** `FonadaAI` (registered on a DE org, **linked to the Dev Hub** via Namespace Registries)
- **Partner Community org connected:** org id `00DdN000013pPOnUAM` (= `agentforce-org`), connected 2026-10-30

### Package IDs (the important ones)

```
Package            : "Fonada MCP"            id 0HodN0000000bcHSAQ
Version 1.0.0.2    : Subscriber id 04tdN000000TP6HQAW   (beta)
Version 1.0.0.3    : Subscriber id 04tdN000000TP7tQAG   (beta)
Version 1.0.0.4    : Subscriber id 04tdN000000TPRFQA4   (RELEASED ✅ — USE THIS)
Install URL        : https://login.salesforce.com/packaging/installPackage.apexp?p0=04tdN000000TPRFQA4
```

---

## 4. Journey — Day 1 (2026-10-28): register Fonada MCP in the dev org

(Full transcript: `../../fonada-mcp-agentforce-chat-2026-10-28.md` and `../../fonada-mcp-agentforce-complete-guide.md`)

1. Diagnosed the original failure: old credential `FonadaAI__fonadamcp` was `Oauth`, unauthenticated,
   with an orphan `Authorization` formula referencing a non-existent, **namespace-prefixed** parameter.
2. Rebuilt as External Credential `FonadaMCP`: protocol **`Custom`**, principal, header
   `Authorization = {!'Bearer ' & $Credential.FonadaMCP.FonadaApiKey}` (the **un-prefixed** form is the fix).
3. Created Named Credential `FonadaMCP` → `https://mcp.fonada.ai/mcp`.
4. Created + assigned Permission Set.
5. Registered the MCP server via the API Catalog API (`authType: EXISTING_EC`) → server id `0Lebm0000007Sij`, **CONNECTED**.
6. Discovery found 356 tools; tools are **inactive until allowlisted**.
7. Used a tool in an agent ("Test 3" → subagent "Fonada Voice Test") and verified in Preview.

### Key learning from Day 1
An action is only used if a **subagent whose Description matches the request** has it attached,
and the subagent's instructions don't steer the LLM elsewhere.

---

## 5. Journey — Day 2 (2026-10-29): cross-org problem + the packaging roadmap

- Problem: agent lives in `agentforce-dev`, real CRM data in `agentforce-org`.
- Enabled hosted `platform.sobject-reads` in the data org; created External Client App; planned
  cross-org OAuth client-credentials. (This thread is **paused** — not needed for the package.)
- Wrote the **roadmap**: package the MCP registration as a Managed 2GP and list it on AgentExchange.
- Decided the big constraint: Salesforce prefers **OAuth 2.0 Client Credentials**; Fonada only
  offers `authorization_code` + `refresh_token` + direct `fsk` bearer → chose the **`fsk` Custom credential** path.

---

## 6. Journey — Day 3 (2026-10-30): the package — built, released, install-tested

### 6.1 R&D findings (the important discoveries)

1. **Official model confirmed** (2GP Developer Guide): four packageable metadata types; full metadata
   template obtained; agent actions & gateway policies are **not** packageable.
2. **Real-world reference found in your own org:** the **Demandbase** managed package (`namespace DB_Agent`)
   already ships an MCP registration:
   - `DB_Agent__DemandbaseMCP` ExternalCredential, protocol **Oauth**, variant `ClientCredentialsClientSecret`,
     `AuthProviderUrl = https://uapi.demandbase.com/auth/v1/token/sf`, principal `MCPAuthentication`.
   - NamedCredential `DB_Agent__DemandbaseMCP` → their MCP endpoint.
   - ExternalServiceRegistration with **full tool schema** and **pre-activated tools** (`operations` active:true).
   - PermissionSet `DB_Agent__DemandbaseMCP_Perm_Set`.
   - **No agent actions packaged** (confirms actions aren't packageable).
   - **Lesson:** Demandbase puts the **reasoning guidance inside the tool descriptions** — that's how
     "reasoning is auto-filled". Pre-activating tools in the ESR gives the "no manual allowlist" experience.
3. **The `fsk` key belongs in the External Credential's Named Principal** — surfaced as one field.
4. **"Reasoning auto-fill":** tool `description` (from the MCP server) → ESR `schema` → agent action → LLM.
   The separate "Reasoning Instructions" field is **not** packageable.
5. **Security/gating:** the `fsk` key is the hard gate; LMA licensing is optional; server-side entitlements possible.

### 6.2 Blocker fixed: Dev Hub had no namespace
- `agentforce-org` was a Dev Hub but had **no namespace**; `agentforce-dev` had the namespace but wasn't a Dev Hub.
- **Fix:** in the Dev Hub → **App Launcher → Namespace Registries → Link Namespace** → log in to the
  Developer Edition org that owns the namespace (`priyam.b190dbfb3954@agentforce.com`) → Allow.
- Result: `FonadaAI` linked to the Dev Hub; `sf package create` then succeeded.

### 6.3 The new project

```
/home/priyam-paul/Downloads/fonada-agentforce-mcp-package/
├── sfdx-project.json          # namespace FonadaAI, sourceApiVersion 66.0, package "Fonada MCP"
├── config/project-scratch-def.json
├── force-app/main/default/
│   ├── externalCredentials/FonadaMCP.externalCredential-meta.xml
│   ├── namedCredentials/FonadaMCP.namedCredential-meta.xml
│   ├── externalServiceRegistrations/FonadaMCP.externalServiceRegistration-meta.xml
│   └── permissionsets/FonadaMCP_Perm_Set.permissionset-meta.xml
└── docs/  (this file + install guide + listing content)
```

### 6.4 The 4 metadata files (final, working)

**`externalCredentials/FonadaMCP.externalCredential-meta.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExternalCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <authenticationProtocol>Custom</authenticationProtocol>
    <externalCredentialParameters>
        <parameterGroup>MCPAuthentication</parameterGroup>
        <parameterName>MCPAuthentication</parameterName>
        <parameterType>NamedPrincipal</parameterType>
        <sequenceNumber>1</sequenceNumber>
    </externalCredentialParameters>
    <externalCredentialParameters>
        <parameterGroup>DefaultGroup</parameterGroup>
        <parameterName>Authorization</parameterName>
        <parameterType>AuthHeader</parameterType>
        <parameterValue>{!'Bearer ' &amp; $Credential.FonadaMCP.FonadaApiKey}</parameterValue>
        <sequenceNumber>1</sequenceNumber>
    </externalCredentialParameters>
    <label>Fonada MCP</label>
</ExternalCredential>
```
> ⚠️ The `Custom` protocol does **NOT** support the `AuthParameter` type and the `AuthProtocolVariant`
> value `Custom` is invalid. The `FonadaApiKey` value is set **after install** (not in metadata).

**`namedCredentials/FonadaMCP.namedCredential-meta.xml`**
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
        <externalCredential>FonadaAI__FonadaMCP</externalCredential>
        <parameterName>ExternalCredential</parameterName>
        <parameterType>Authentication</parameterType>
    </namedCredentialParameters>
    <namedCredentialType>SecuredEndpoint</namedCredentialType>
</NamedCredential>
```

**`externalServiceRegistrations/FonadaMCP.externalServiceRegistration-meta.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExternalServiceRegistration xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>FonadaMCP</label>
    <namedCredential>FonadaAI__FonadaMCP</namedCredential>
    <namedCredentialReference>FonadaMCP</namedCredentialReference>
    <registrationProviderType>ModelContextProtocol</registrationProviderType>
       <!-- schema is GENERATED from the live server; tools baked in. Never hand-edit. -->
    <schema>{"serverDescriptor":{"protocolVersion":"2025-11-25","serverInfo":{"name":"fonada","version":"1.29.1"}},"tools":[…12 curated tools…],"resources":[]}</schema>
    <schemaType>ModelContextProtocol</schemaType>
    <status>Complete</status>
    <systemVersion>8</systemVersion>
</ExternalServiceRegistration>
```

**`permissionsets/FonadaMCP_Perm_Set.permissionset-meta.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Access to the Fonada MCP server and its tools</description>
    <externalCredentialPrincipalAccesses>
        <enabled>true</enabled>
        <externalCredentialPrincipal>FonadaAI__FonadaMCP-MCPAuthentication</externalCredentialPrincipal>
    </externalCredentialPrincipalAccesses>
    <hasActivationRequired>false</hasActivationRequired>
    <label>Fonada MCP - Permission Set</label>
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>UserExternalCredential</object>
        <viewAllFields>false</viewAllFields>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
</PermissionSet>
```

### 6.5 Build commands used (in order)

```bash
# 0. point CLI at the Dev Hub
sf config set target-dev-hub=agentforce-org

# 1. scaffold
cd ~/Downloads && sf project generate --name fonada-agentforce-mcp-package --template empty
#   → edit sfdx-project.json (namespace FonadaAI, sourceApiVersion 66.0)
#   → edit config/project-scratch-def.json (see §6.7)

# 2. create the package container
sf package create --name "Fonada MCP" --package-type Managed --path force-app --target-dev-hub agentforce-org
#   → Package Id 0HodN0000000bcHSAQ

# 3. create package versions (1.0.0.2 → 1.0.0.3 → 1.0.0.4)
sf package version create --package "Fonada MCP" --path force-app --version-number 1.0.0.4 \
  --installation-key-bypass --code-coverage --wait 30 --target-dev-hub agentforce-org
#   → Subscriber id 04tdN000000TPRFQA4

# 4. promote (release) — REQUIRES --code-coverage at create time
sf package version promote --package 04tdN000000TPRFQA4 --target-dev-hub agentforce-org --no-prompt
#   → released = true

# 5. create scratch org + install + verify
sf org create scratch -f config/project-scratch-def.json -a fonada-mcp-test --target-dev-hub agentforce-org -d 30 -w 15
sf package install --package 04tdN000000TPRFQA4 --target-org fonada-mcp-test --wait 15 --no-prompt
sf agent mcp list --target-org fonada-mcp-test     # → FonadaMCP EXTERNAL appears ✅
```

### 6.6 Errors encountered and the fixes (IMPORTANT for future rebuilds)

| Error | Cause | Fix |
|---|---|---|
| `The ParameterValue for AuthProtocolVariant is invalid for the Custom authentication protocol` | We set `AuthProtocolVariant = Custom` | **Remove** the `AuthProtocolVariant` block entirely (matches the working dev-org credential) |
| `The authentication protocol "Custom" doesn't support ... AuthParameter` | `Custom` doesn't accept `AuthParameter` | **Remove** the `FonadaApiKey` `AuthParameter` block; the key is set post-install |
| `FonadaMCP_Perm_Set: The MCPAuthentication parameter value doesn't exist` | Cascade from the credential failing | Resolved automatically once the credential built |
| `Chatbot is not a valid Features value` (scratch org) | Dev Hub doesn't offer `Chatbot` | Remove `Chatbot`; keep `Einstein1AIPlatform` + `einsteinGptSettings` |
| `Bot : Legal Terms acceptance ...` (scratch org settings) | `botSettings` needs `Chatbot` | Remove `botSettings` |
| `Code coverage has not been run for this version` (promote) | Promotion of a managed package requires coverage | Rebuild with **`--code-coverage`** → new version 1.0.0.4 → promote |
| `sf package create --type` / `sf package install -p` flag errors | CLI flag names | Use `--package-type`, `--package`, etc. |
| VS Code XML errors on `externalCredentialPrincipalAccesses` | Stale VS Code schema | **False positive** — ignore; deploy validates |

### 6.7 `config/project-scratch-def.json` (final working)

```json
{
  "orgName": "Fonada MCP Dev",
  "edition": "Partner Developer",
  "features": ["Einstein1AIPlatform"],
  "settings": {
    "einsteinGptSettings": { "enableEinsteinGptPlatform": true }
  }
}
```

### 6.8 Proof it works

Installed the package into a **clean** scratch org → `sf agent mcp list` showed:

```
FonadaMCP | type = EXTERNAL | health = UNAVAILABLE
```

i.e. the package **auto-created the MCP server registration with zero manual Setup** — the milestone. 🎯

### 6.9 Manual (GUI) run — the recipe we validated

Steps: External Credential (Custom, `MCPAuthentication` principal, `FonadaApiKey` param, `Authorization` header)
→ Named Credential → Permission Set → Agentforce Registry → allowlist tools → add to agent.

**Scratch-org limitation discovered:** the new Agentforce Builder throws
`Cannot read properties of undefined (reading 'upsertContentFromAfscriptList')` when creating subagents /
adding tools. Fixes tried: enable Einstein + Agentforce, assign `Agentforce Default Admin`. If it persists,
it's a **scratch-org bug** — build agents in `agentforce-dev` (its Builder works) instead.

---

## 7. Business / GTM decisions made

| Question | Decision |
|---|---|
| Auth model | **`fsk` API key via a `Custom` External Credential** (no server change) |
| Distribution | **Private managed-package install-test first**, then AgentExchange |
| Tool surface | **All ~356 tools shipped inactive**; admin allowlists what they need |
| Pricing | **List FREE first** ($0 security review fee), convert to paid later |
| Repo | **New DX project**; the `fonada_mcp` repo is untouched |

### Pricing & revenue model (verified)
- **Salesforce takes 15%** of net revenue **only on AgentExchange Checkout transactions** (you keep 85%).
  Card payments add **$0.30/transaction**. No setup/monthly/card-storage fees. (OEM = 25%.)
- **Fonada platform usage** (voice, WhatsApp, RCS, credits) is billed by **Fonada directly** →
  **Salesforce takes $0** of it. It is a separate revenue stream.
- **Free-first is allowed**: free apps get the security review fee **waived** but must still **pass** review.
  You can later **convert the listing to paid** (Partner Console → make private → enable Checkout/Stripe →
  pricing plans → resubmit → republish). You'd pay the ~$999 review fee at that point.
- ⚠️ **No "freemium" under a *free* label** — the free version must be genuinely fully usable.
- Paid listings also carry **$150/yr**.

---

## 8. Current state (what exists right now)

### ✅ Done
- Namespace `FonadaAI` **linked to the Dev Hub** (`agentforce-org`).
- Managed package **`Fonada MCP`** created (`0HodN0000000bcHSAQ`).
- Package version **1.0.0.4 (`04tdN000000TPRFQA4`) RELEASED**.
- **Install-tested** in a clean scratch org → MCP server auto-created ✅.
- **Customer install guide** written (`docs/Fonada_MCP_Agentforce_Install_Guide.md`).
- **Listing content pack** written (`docs/AgentExchange_Listing_Content.md`).
- **Dev Hub connected** to the Partner Community (org id `00DdN000013pPOnUAM`, 2026-10-30)

### 🔄 In progress / pending
- **Partner Console → Solutions tab** is still **empty** → waiting for the async sync of the released
  version, then **Register Package**.
- **Dev Hub → Verified Org Status** was **Failed** → should now show linked after the Partner Console
  connection; **re-check on Monday**.
- **Security review** not started.
- **Listing** not created.

### 🧹 Cleanup / security (do regardless)
- 🔴 **Rotate the leaked `fsk_` key** found in plaintext in `agentforce-org` (unmanaged External
  Credential `fonada_mcp`, `Authorization` header literally contains `fsk_c73ce…`). Delete that credential after rotating.
- 🧹 Delete leftover `fonadamcp_Perm_Set` / `fonada_mcp` from earlier attempts.
- 🧹 (Optional) Delete beta versions `04tdN000000TP6HQAW`, `04tdN000000TP7tQAG`:
  `sf package version delete --package <id> --target-dev-hub agentforce-org --no-prompt`.
- ⚠️ `agentforce-dev` FonadaMCP risk score = **MEDIUM** — review tool descriptions before listing.

---

## 9. Monday plan — the exact next steps

### Step A — finish Partner Console registration
1. `partners.salesforce.com` → **Publishing → Solutions** → refresh.
2. If **1.0.0.4** appears → **Register Package** → enter Dev Hub credentials (`priyam@fonada.com`) →
   set default license behavior (trial length, seats) → **Save**.
3. If still empty → check **Setup → Dev Hub → Verified Org Status**; if still **Failed**, raise it with
   your **Partner Account Manager / partner support** (this blocks public installs).

### Step B — create the listing
1. **Partner Console → Listings → New Listing**
2. Type: **Packaged Solution → Salesforce Platform Package → Agentforce Solution**
   *(cannot be changed later)* — or the newer **"ISV MCP Tool Action"** type if offered.
3. Paste everything from `docs/AgentExchange_Listing_Content.md`.
4. Attach package version **`04tdN000000TPRFQA4`**.
5. **MCP Servers → List an MCP Server** → server name + description + **at least one tool**.
6. Upload the **install guide** + screenshots; set **pricing = Free**.

### Step C — security review & publish
1. Partner Security Portal → **Source Code Scanner (Checkmarx)** (our package has no Apex — confirm via
   the Security Review Requirements Checklist Builder) + **DAST of `https://mcp.fonada.ai`**.
2. Submit → **Business Plan Review** (~2–4 wk) → **Security Review** (~4–8 wk) → **sign PADA** → **Publish**.

### Step D — verify the one untested link
- Confirm a subscriber can actually **enter the `FonadaApiKey` value** in the External Credential UI
  (Step 4 of the install guide) and that `FonadaMCP` flips to **CONNECTED**. If not, adjust the credential design.

### 🔮 Future
- Add **OAuth 2.0 Client Credentials** to `mcp.fonada.ai` (Salesforce's preferred flow) as an optional upgrade.
- Optionally package an **Agent Template** (`sf agent generate template`) with a pre-built subagent.
- Resume the **cross-org** work from Day 2 if still needed.

---

## 10. Every prompt / request from the start (chronological)

> Captured so Monday's session starts with zero re-explaining. Paraphrased where long.

**Day 3 (2026-10-30) — this session:**
1. Read `fonada-mcp-agentforce-complete-guide.md` and `fonada-mcp-agentforce-chat-2026-10-28.md`; build a
   Salesforce marketplace (AgentExchange) MCP package that connects with Agentforce Builder, usable by normal
   users via Agentforce AI, appearing in AppExchange / Agent Builder → Browse AgentExchange → Fonada MCP.
2. Security: no one should be able to register the MCP without getting it. Minimize customer friction
   (no manual External Credential → Named Credential → Permission Set). Where does the `fsk` key go?
   Can reasoning be auto-filled for all tools? R&D how other MCPs register in Salesforce. Don't change the
   existing MCP repo; a new DX project is fine. Read the repo if needed; don't hallucinate; teach me.
3. How do I enable Dev Hub + 2GP in my PBO? Do I need CLI? (I log in as `priyam@fonada.com`.)
4. I'm on `partners.salesforce.com` and don't see Setup / Quick Find. (Clarified: that's the Partner Community, not an org.)
5. Confirmed the Dev Hub Package Manager page shows Namespace Settings (empty) + Verified Org Status: Failed.
6. Namespace not present on the Dev Hub → linked `FonadaAI` via Namespace Registries → **done** (`00000001 FonadaAI 30/10/2026 PPaul`).
7. Project scaffolded; set `sfdx-project.json` + scratch def; wrote the 4 metadata files.
8. Hit XML false positive on `externalCredentialPrincipalAccesses` (ignored).
9. `sf package create --type` flag error → fixed to `--package-type`; package created `0HodN0000000bcHSAQ`.
10. Version create failed twice (AuthProtocolVariant; AuthParameter) → fixed → versions 1.0.0.2 / 1.0.0.3 built.
11. "how this name generated and fetching from?" (explained `04t…` IDs).
12. "get this name in ui" (explained CLI is the source).
13. Created scratch org (fixed `Chatbot` / `botSettings` errors) → installed package → **`FonadaMCP` appeared** ✅.
14. "cant i do this via GUI?" / "which org" (scratch vs dev vs PBO).
15. "pause it — tell me how we manually added Fonada MCP in Agentforce Registry and used it in Agent Builder, all via GUI."
16. Scratch-org Builder error `upsertContentFromAfscriptList`; permission sets list; "how to delete scratch org".
17. "resume steps, I have complete code, next start from build."
18. "how this app will show in Agentforce marketplace now" (explained the two surfaces + remaining steps).
19. "create a docs how to establish Fonada MCP in Agentforce after purchase (shows on marketplace below my app) — Path B; and do Path A as well in CLI."
20. "if I make this paid, how much revenue does my company get? Is 15% from Salesforce only and my MCP revenue different?"
21. "how to publish this project" → "guide me from part 3" (Dev Hub ↔ Partner Console link).
22. Partner Community Orgs tab shows `00DdN000013pPOnUAM`; Solutions tab empty; "why 3 versions".
23. "document complete today convo, tomorrow, day after tomorrow, all prompts from the start and all README
    files in the current dir — complete journey document in docs; save it as the Salesforce implementation README."

**Day 1 & Day 2 prompts:** see `../../fonada-mcp-agentforce-complete-guide.md` §2–§6 and
`../../README.md` (master doc) for the full transcript of those sessions.

---

## 11. Glossary

- **MCP** — Model Context Protocol; the open standard Agentforce uses to call external tools.
- **Agentforce Registry / API Catalog** — where MCP servers are registered in an org.
- **External Credential** — holds the secret (our `fsk` key).
- **Named Credential** — holds the endpoint URL and links the external credential.
- **ESR** — `ExternalServiceRegistration`; the record backing an MCP registration (`schemaType = ModelContextProtocol`).
- **2GP** — second-generation managed packaging (the modern managed-package tech).
- **PBO** — Partner Business Org (where the namespace lives; the Dev Hub).
- **PNR** — Percentage Net Revenue (Salesforce's 15% cut of Checkout sales).
- **LMA** — License Management App (optional licensing).
- **fsk** — Fonada API key (`fsk_…`); the single credential a customer provides.
- **`04t…`** — Subscriber Package Version Id (the installable version).

---

## 12. References

- **MCP for Agentforce Metadata in Managed Packages** — 2GP Developer Guide
  `developer.salesforce.com/docs/platform/pkg2-dev/guide/dev2gp-package-mcp-agentforce.html`
- **Link a Namespace to a Dev Hub Org** — `.../pkg2-dev/guide/sfdx-dev-reg-namespace.html`
- **Publishing Your App on AgentExchange** — `.../pkg2-dev/guide/sfdx-dev-dev2gp-publish-appexchange.html`
- **Add MCP Servers to Your Agentforce Agents** — ISVforce Guide
  `.../isvforce/guide/appexchange-listing-builder-add-mcp-servers.html`
- **Register a Third-Party MCP Server in Agentforce Registry** — Salesforce Help
  `help.salesforce.com/s/articleArticleView?id=ai.agent_mcp_connect_register.htm`
- **AgentExchange Checkout Revenue Share** — `.../isvforce/guide/appexchange-checkout-rev-share.html`
- **Convert a Listing to Paid (Checkout)** — `.../isvforce/guide/appexchange-checkout-convert-listing.html`
- **Scratch Org Features** — `.../sfdx-dev/guide/sfdx-dev-scratch-orgs-def-file-config-values.html`
- **AgentExchange / Agentforce MCP** — `agentexchange.salesforce.com/collections/agentforce-mcp`

---

*End of document. Resume at §0. Questions → support@fonada.ai.*
