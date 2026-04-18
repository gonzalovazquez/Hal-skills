---
name: networking
description: >
  Gonzo's networking companion. Imports a LinkedIn Connections CSV into a Notion
  CRM, infers lead temperature with AI, drafts Gmail outreach, tracks replies,
  sends Calendly invites to responders, and schedules follow-ups. Designed to be
  run idempotently on a cron — state lives in Notion.
schedule: "0 9 * * *"            # cron: 9:00 AM daily run
timezone: America/Toronto
config:
  calendly_link: "https://calendly.com/gonzalovazquez010/30min"
  linkedin_csv_path: "~/.openclaw/networking/Connections.csv"
  notion_database_name: "Networking CRM"
  followup_wait_days: 7
  max_new_outreach_per_run: 10   # throttle to avoid Gmail spam flags
  max_followups_per_run: 20
  hot_titles: ["VP", "Head of", "Director", "Founder", "CEO", "CTO", "Partner"]
metadata:
  openclaw:
    requires:
      bins: ["python3"]
      tools: ["exec", "message"]
      mcp: ["notion", "gmail", "calendly"]
---

# networking

A networking CRM agent. On each run it:

1. Syncs new LinkedIn connections from a CSV export into a Notion database.
2. Uses AI to infer each lead's temperature (Hot / Warm / Cool / Cold) from
   their role and company.
3. Drafts personalized Gmail outreach for uncontacted leads.
4. Scans Gmail for replies on active threads.
5. On reply: sends a Calendly link and notifies Gonzo with a profile summary.
6. On silence past `followup_wait_days`: drafts a follow-up email.
7. Writes every state change back to Notion so the DB is the single source
   of truth.

Because the skill is idempotent and state lives in Notion, it is safe to run
repeatedly under cron. All timing decisions are made from Notion fields, not
from wall-clock sleeping.

---

## Notion Database Schema

The skill expects a Notion database named `Networking CRM` (configurable). On
first run, if the database does not exist, the skill creates it with the
following schema via the Notion MCP server.

| Property            | Type          | Purpose                                                              |
|---------------------|---------------|----------------------------------------------------------------------|
| `Name`              | title         | Full name from LinkedIn                                              |
| `Email`             | email         | Primary contact                                                      |
| `Company`           | rich_text     | Current company                                                      |
| `Position`          | rich_text     | Current title                                                        |
| `LinkedIn URL`      | url           | Profile URL                                                          |
| `Connected On`      | date          | LinkedIn connection date                                             |
| `Lead Temperature`  | select        | `Hot`, `Warm`, `Cool`, `Cold`                                        |
| `Outreach Stage`    | select        | `Not Contacted`, `Initial Sent`, `Follow-up Sent`, `Responded`, `Meeting Scheduled`, `Met`, `Declined`, `Do Not Contact` |
| `Last Interaction`  | date          | Last email sent or received                                          |
| `Next Action Date`  | date          | When the skill should act next (follow-up due date)                  |
| `Meeting Date`      | date          | Scheduled Calendly meeting                                           |
| `Calendly Sent`     | checkbox      | True once the Calendly link was delivered                            |
| `Gmail Thread ID`   | rich_text     | Gmail thread identifier — used to detect replies                     |
| `Profile Summary`   | rich_text     | AI-inferred one-paragraph summary                                    |
| `Notes`             | rich_text     | User-editable notes                                                  |
| `Tags`              | multi_select  | AI-inferred industry/role tags                                       |

Gonzo can freely add or edit `Notes`, `Meeting Date`, and `Tags` in Notion —
the skill never overwrites them.

---

## Step 0 — Pre-flight

Verify the three MCP servers are connected and responsive. If any fails,
log the failure and skip the steps that depend on it (do not abort the run).

- Notion MCP: list databases, confirm `Networking CRM` exists. If missing,
  create it with the schema above.
- Gmail MCP: confirm authenticated identity matches Gonzo's account.
- Calendly MCP: confirm the scheduling link
  `https://calendly.com/gonzalovazquez010/30min` is reachable.

If Notion is down: abort the entire run (no DB = no state = unsafe).
If Gmail is down: skip Steps 3, 4, 6.
If Calendly MCP is down: still send Calendly responses using the plain URL.

---

## Step 1 — Import LinkedIn CSV

Read the standard LinkedIn Connections export from `linkedin_csv_path`.
Expected columns: `First Name, Last Name, URL, Email Address, Company,
Position, Connected On`.

For each row:

1. Normalize: `Name = "First Name" + " " + "Last Name"`.
2. Dedupe against Notion by `LinkedIn URL` (primary) and `Email` (fallback).
3. If the lead already exists, skip (do not overwrite).
4. If new, create a Notion page with:
   - `Outreach Stage = Not Contacted`
   - `Lead Temperature` left blank (set in Step 2)
   - All other fields populated from the CSV row.

Rows missing both `Email Address` and `URL` are skipped and logged — they
cannot be contacted or deduped.

Report: `📥 Imported N new leads, skipped M duplicates, dropped K unusable rows.`

---

## Step 2 — Infer Lead Temperature

For every lead in Notion where `Lead Temperature` is empty, infer a value
using the lead's `Position` and `Company` fields. Use Claude's reasoning
directly — no external API call needed.

Inference rubric (tune as Gonzo learns what converts):

- **Hot**: Title matches `hot_titles` config AND company is a plausible
  customer/partner/investor for Gonzo's current focus (quantum computing,
  AI infrastructure, fintech).
- **Warm**: Senior IC or manager at a relevant company, OR decision-maker
  at an adjacent company.
- **Cool**: Relevant industry but junior, OR senior but adjacent industry.
- **Cold**: No clear signal of relevance.

Also generate a one-paragraph `Profile Summary` (≤ 3 sentences) covering
who they are, why they matter, and a suggested angle for outreach.
Generate 1–3 `Tags` (e.g., `quantum`, `fintech`, `investor`, `founder`).

Write `Lead Temperature`, `Profile Summary`, and `Tags` back to Notion.

---

## Step 3 — Draft Initial Outreach

Query Notion for leads where:

- `Outreach Stage = Not Contacted`
- `Email` is non-empty
- `Lead Temperature` is `Hot` or `Warm` (skip Cool/Cold unless Gonzo
  manually promotes them)

Order by `Lead Temperature` (Hot first), then `Connected On` descending.
Cap at `max_new_outreach_per_run`.

For each lead, draft a personalized email using the Gmail MCP. The email
must:

- Reference something specific from `Profile Summary` (not a generic blast).
- Be under 120 words.
- Ask one concrete question — either a 30-minute call, advice on a specific
  topic, or a warm intro ask.
- End with Gonzo's signature.

**Template:**

```
Subject: Quick hello from a fellow [tag]

Hi [First Name],

[One sentence referencing their Profile Summary — e.g., "Saw you're leading
quantum infra at IBM — congrats on the latest Heron launch."]

I'm working on [one-line context about Gonzo — pulled from notes config].
I'd love to compare notes on [specific topic tied to their role]. Would a
30-minute call next week work?

Thanks,
Gonzo
```

**Do not auto-send.** Save as a Gmail draft only. Gonzo reviews and sends
manually from his inbox.

After drafting, update Notion:

- `Outreach Stage = Initial Sent` (set when Gonzo actually sends —
  detected in Step 4; keep as `Not Contacted` until then, or use an
  intermediate `Draft Ready` stage if preferred)
- Store the Gmail draft ID in `Gmail Thread ID` so Step 4 can poll it.

Report: `✉️  Drafted N outreach emails (review in Gmail drafts).`

---

## Step 4 — Detect Sends & Replies

For every lead where `Gmail Thread ID` is set:

1. Query the thread via Gmail MCP.
2. If the draft has been **sent** (thread now has an outbound message) and
   Notion still shows `Not Contacted`, promote stage to `Initial Sent`,
   set `Last Interaction = today`, and set
   `Next Action Date = today + followup_wait_days`.
3. If the thread contains an **inbound reply** newer than `Last Interaction`:
   - Set `Outreach Stage = Responded`.
   - Set `Last Interaction = reply date`.
   - Clear `Next Action Date`.
   - Queue for Step 5.

---

## Step 5 — Calendly Reply + User Notification

For every lead newly moved to `Responded` in this run:

1. Draft a reply in the same Gmail thread:

   ```
   Thanks [First Name] — great to hear back. Here's my Calendly so you can
   grab any 30-minute slot that works:

   https://calendly.com/gonzalovazquez010/30min

   Looking forward to it.

   Gonzo
   ```

   Save as a draft (do not auto-send). Mark `Calendly Sent = true` once
   Gonzo sends it (detected on the next run via Step 4's send-detection).

2. Send Gonzo a notification via the `message` tool with a profile summary:

   ```
   🤝 *Reply from [Name]*
   [Company] · [Position]
   LinkedIn: [URL]

   *Who they are:* [Profile Summary]

   *Their reply:* [≤2-sentence summary of their message]

   Calendly draft is in Gmail — review and send.
   ```

3. If Calendly MCP supports booking webhooks, subscribe to the link so
   confirmed bookings update `Meeting Date` automatically in Step 7.

---

## Step 6 — Follow-up on Silent Threads

Query Notion for leads where:

- `Outreach Stage = Initial Sent`
- `Next Action Date <= today`
- No inbound reply in the thread (confirmed in Step 4)

Cap at `max_followups_per_run`.

Draft a short follow-up in the same Gmail thread:

```
Hi [First Name],

Floating this back up in case it got buried. No pressure — happy to reconnect
whenever timing is better.

Thanks,
Gonzo
```

Update Notion:

- `Outreach Stage = Follow-up Sent`
- `Next Action Date = cleared` (one follow-up only; after that the lead
  sits until Gonzo manually bumps them)

Report: `🔁 Drafted N follow-ups.`

---

## Step 7 — Sync Calendly Bookings

For every lead with `Calendly Sent = true` and no `Meeting Date` yet:

1. Query the Calendly MCP for bookings on the `gonzalovazquez010/30min`
   link in the last 30 days.
2. Match bookings to leads by email.
3. On match, set `Outreach Stage = Meeting Scheduled` and
   `Meeting Date = booking start time`.
4. Send Gonzo a message: `📅 Meeting booked with [Name] on [date].`

After the meeting date passes, the next run moves the stage to `Met`
automatically.

---

## Step 8 — Daily Summary

At the end of every run, send Gonzo a single digest via the `message`
tool:

```
🧭 *Networking Digest — [date]*

📥 Imported: N new leads
✉️  Outreach drafts ready: N
🔁 Follow-up drafts ready: N
💬 New replies: N
📅 Meetings booked: N

Active pipeline:
• Hot: X  Warm: Y  Cool: Z  Cold: W
• Awaiting reply: N  |  Responded: N  |  Scheduled: N
```

If nothing happened in any category, show `— none —` on that line
rather than omitting it (consistent layout helps Gonzo scan fast).

---

## Error Handling

- **CSV missing**: skip Step 1, continue. Notify Gonzo once per week if
  the file is still missing (avoid daily nagging).
- **Notion write fails on a single lead**: log and continue with the rest.
  Never abort the full run for one bad record.
- **Gmail draft creation fails**: mark the lead with a `Notes` entry
  `⚠️ outreach draft failed [date]` and move on.
- **Calendly booking fetch fails**: skip Step 7, retry next run.
- **MCP server disconnects mid-run**: log and continue with the MCPs
  still available.

All errors are appended to `~/.openclaw/logs/networking.log` with
timestamps for debugging.

---

## Cron Registration

Add this to your `~/.openclaw/openclaw.json` to activate:

```json
{
  "cron": {
    "networking": {
      "skill": "networking",
      "schedule": "0 9 * * *",
      "timezone": "America/Toronto",
      "enabled": true
    }
  }
}
```

Verify with: `openclaw cron list`.

Recommended cadence: once per day at 9 AM. Running more often risks
drafting duplicate outreach if Gmail send-detection lags.

---

## First-time Setup Checklist

1. Install and authenticate the Notion, Gmail, and Calendly MCP servers
   in the OpenClaw MCP config. The skill will not run until all three
   are reachable (Notion is hard-required).
2. Place the LinkedIn Connections CSV at
   `~/.openclaw/networking/Connections.csv`. Re-export and replace it
   whenever you want to sync new connections.
3. Run the skill once manually to create the Notion database:
   `openclaw run networking`.
4. Open the Notion DB and add/edit `Notes` or promote any Cool/Cold
   leads to Warm before the next scheduled run.
5. Register the cron block above.

---

## Privacy & Safety

- Outreach and follow-up emails are **always saved as drafts**, never
  auto-sent. Gonzo is the send button.
- Calendly reply drafts are also manual-send only.
- The skill never emails anyone not imported from Gonzo's own LinkedIn
  export.
- Leads with `Outreach Stage = Do Not Contact` are skipped in every
  step, permanently. Setting this flag in Notion is the unsubscribe.
- No lead data leaves the Notion/Gmail/Calendly boundary — the skill
  does not post to third-party services.

---

## Optimization Notes

1. **Send detection latency** — Step 4 infers sends by polling Gmail
   threads. If Gonzo sends an outreach email within minutes of the cron
   run, the state transition lands on the next run. This is fine for
   a daily cadence; tighten the cron to hourly if you want faster
   state sync.
2. **Throttle knobs** — `max_new_outreach_per_run: 10` keeps Gmail
   happy. LinkedIn-sourced cold outreach above ~20/day tends to trip
   spam heuristics.
3. **Temperature drift** — Re-run Step 2 on all leads quarterly
   (`Lead Temperature` can be cleared in bulk from Notion). Titles
   change, companies pivot — Hot today is Cold next year.
4. **One follow-up only** — The skill deliberately does not chain
   multiple follow-ups. Two unanswered emails is enough signal; more
   feels pushy. Gonzo can manually bump a lead by clearing
   `Outreach Stage` and `Last Interaction`.
5. **Meeting post-mortem** — After `Meeting Date` passes, Gonzo is
   expected to add `Notes` manually. A future enhancement could prompt
   for a post-meeting note via WhatsApp the evening of the meeting.
