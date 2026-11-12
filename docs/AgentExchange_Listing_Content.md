# AgentExchange Listing — Content Pack for "Fonada MCP"

Copy and paste this into **Partner Console → Listings → New Listing → Listing Builder**.
None of this is code; it's the text and values the marketplace asks for.

> Customer-facing version: **"Fonada MCP 1.0"**. Don't show the internal build number (1.2.0.13) in listing text,
> screenshots or the video.

---

## 1. Listing type (cannot be changed later)

**Packaged Solution → Salesforce Platform Package → Agentforce Solution**

> Salesforce also announced a newer **"ISV MCP Tool Action"** listing type for off-platform MCP servers. If
> Partner Console offers it, it's the closest match to our use case, so choose it. Otherwise use
> **Agentforce Solution**.

---

## 2. Package (internal reference)

| Field | Value |
|---|---|
| Package | `Fonada MCP` |
| Package ID | `0HodN0000000bcHSAQ` |
| **Version to attach** | **Fonada MCP 1.0** (build 1.2.0.13, released 2026-11-12) |
| Subscriber Package Version Id | `04tdN000000TfMLQA0` |
| Install URL | `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tdN000000TfMLQA0` |
| Namespace | `FonadaAI` |

## 3. Basics

- **Listing name:** `Fonada MCP for Agentforce`
- **Tagline / brief description (≤ 255 chars):**
  > Let Agentforce call your Salesforce contacts and leads, run voice campaigns from Salesforce Campaigns and
  > Accounts, and send WhatsApp and RCS templates through the Fonada AI platform. Install, paste one key, copy a
  > ready-made agent.
- **Categories:** `AI`, `Sales`, `Customer Service`, `Marketing`, `Integrations`
- **Keywords:** `MCP`, `Agentforce`, `Voice`, `Outbound calling`, `Dialer`, `WhatsApp`, `RCS`, `Campaigns`, `Fonada`

### Agentforce capability details
- **Agentforce Capabilities Description (≤ 100 chars):**
  > Call contacts, run voice campaigns and send WhatsApp/RCS from Agentforce.
- **Number of Agents:** `1` (ready-made, delivered by the Fonada Setup tab)
- **Number of Topics (subagents):** `1` (Fonada)
- **Number of Actions:** `21` (17 Fonada MCP tools + 4 Salesforce actions)

---

## 4. What's included (long description)

> **Fonada MCP for Agentforce**
>
> Turn Agentforce into an outbound calling and messaging assistant for your Salesforce data. Fonada MCP
> connects your agents to the Fonada AI platform over the Model Context Protocol. There's no code to write and
> no credentials to set up by hand.
>
> **What your agent can do**
> - Find Salesforce **contacts and leads**, and **call** one person with a Fonada voice agent
> - **Start outbound voice campaigns** from a Salesforce **Campaign** or **Account**. The call list is built
>   from your Salesforce data and phone numbers are formatted automatically; no CSV is needed.
> - **Send WhatsApp and RCS templates** to one contact or lead, or to a whole Campaign or Account, with the
>   person's name filled into the template
> - **Pause, resume or stop** campaigns, and get **reports, KPIs and call records**
> - Search and update your Fonada **knowledge base**, and check **credits**
>
> **Set up in minutes**
> 1. Install the package and paste your Fonada API key (one field).
> 2. Create an agent in Agentforce Builder.
> 3. Open **Fonada Setup** (App Launcher → search *Fonada Setup*), click **Copy script**, paste it into the
>    agent's Script view, then commit and activate.
>
> Agent users get Fonada access automatically. The Fonada Setup tab also has the full usage guide, example
> requests and troubleshooting.
>
> **Example requests**
> - "call contact <name> using <Fonada agent>"
> - "start a campaign for <Salesforce campaign> with <Fonada agent>"
> - "send WhatsApp template <template> to campaign <Salesforce campaign>"
> - "how did campaign <name> go"
>
> **Safe by design**
> - Every call, message and campaign shows who will be contacted and asks for confirmation before it runs.
> - Records marked **Do Not Call** are skipped.
> - When a name matches several records, the agent asks which one you mean.
> - The same campaign can't accidentally be started twice within a few minutes.
> - The Salesforce actions only read data and never change your records.
> - Your Fonada key is stored encrypted in a Salesforce External Credential.
> - Admins can turn the Salesforce data actions or automatic access off in Fonada Settings.
>
> **Requirements**
> - A Salesforce org with **Einstein** and **Agentforce** enabled
> - A **Fonada API key** (`fsk_…`). Get one at https://fonada.ai
> - For messaging: an approved WhatsApp Business account or RCS bot in Fonada

---

## 5. MCP Servers section (Listing Builder → **MCP Servers → List an MCP Server**)

- **Server name:** `Fonada MCP`
- **Server description:**
  > Fonada AI for Agentforce: call Salesforce contacts and leads, run outbound voice campaigns from
  > Salesforce Campaigns or Accounts, send WhatsApp and RCS, search the knowledge base and check credits.
  > Setup guide: App Launcher → search **Fonada Setup**.
- **Endpoint:** `https://mcp.fonada.ai/mcp`
- **Tools the ready-made agent uses** (17):

| Tool name | Description |
|---|---|
| `voice_list_agents` | List your Fonada telephony (voice) agents. |
| `voice_campaigns_pause` / `_resume` / `_stop` | Pause, resume or stop a voice campaign. |
| `voice_campaigns_list_leads` | List a campaign's leads with their call status. |
| `voice_campaigns_get_lead_summary` | Lead and disposition summary for a campaign. |
| `voice_campaigns_get_cdr_report` | Call detail records of a campaign. |
| `orchestrator_campaign_report` | Campaign report: dispositions, latest summary and KPIs. |
| `voice_upload_leads` | Upload a leads CSV to the dialer. |
| `whatsapp_send_template_message` | Send one approved WhatsApp template to one number. |
| `whatsapp_send_text` | Reply with WhatsApp text inside the 24-hour customer window. |
| `whatsapp_list_templates` | List WhatsApp templates. |
| `rcs_send_test_message` | Send one RCS test message. |
| `knowledge_base_search` | Semantic search over an agent's knowledge base. |
| `knowledge_base_add_text` | Add text to an agent's knowledge base. |
| `analytics_list_kpis` | List an agent's KPI definitions. |
| `credits_get_balance` | Fonada credit balance. |

**Salesforce actions shipped in the package (4):**

| Action | What it does |
|---|---|
| **Fonada: Find Contact or Lead** | Finds a Contact or Lead by name and returns company, phone, Fonada dial number, email and Do Not Call |
| **Fonada: Get Call List** | Previews the people in a Salesforce Campaign or Account: count, skipped records and the first names |
| **Fonada: Start Campaign** | Calls one Contact or Lead, a typed number, or a whole Campaign or Account (Fonada `voice_campaigns_create_outbound`) |
| **Fonada: Send Message Campaign** | Sends a WhatsApp or RCS template to the same recipients (Fonada `whatsapp_send_campaign` / `rcs_run_campaign`) |

---

## 6. Documentation

Attach the install guide as the listing's documentation: **`docs/Fonada_MCP_Agentforce_Install_Guide.md`**.
Convert it to PDF or HTML if the listing form requires it. This is what appears **below the app** on the
marketplace page.

Screenshots to upload:
1. The Fonada Setup tab (agent user, model picker, Copy script)
2. Preview finding a contact and calling it
3. Preview launching a campaign from a Salesforce Campaign (count, preview, confirmation, result)
4. Preview sending a WhatsApp template to a campaign
5. The FonadaMCP server in the Agentforce Registry

---

## 7. Support & links

- **Support email:** `support@fonada.ai`
- **Support URL:** `https://fonada.ai`
- **Endpoint:** `https://mcp.fonada.ai/mcp`

---

## 8. Remaining steps after this content is pasted (Partner Console UI)

1. **Partner Console → Listings → New Listing**, with type *Agentforce Solution*.
2. Fill in **Basics** (§3) and **Details** (§4), and attach the released version **Fonada MCP 1.0** (§2).
3. **MCP Servers** → *List an MCP Server* → fill in §5.
4. Upload the **screenshots / demo video** and the **install guide** (§6).
5. Set **pricing** (free or paid).
6. **Submit for Security Review** with the Code Analyzer report, `docs/Security_Review_Notes.md`, the DAST report
   for `https://mcp.fonada.ai`, a reviewer test org and a low-credit Fonada key.
7. After the review passes, **sign the PADA** and **Publish**.

> **Fees (current; verify at submission):** free apps have a **$0** review fee; paid apps are about **$999** per
> review attempt; the ISVforce revenue share is **15%**.
