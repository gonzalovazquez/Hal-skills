-----

## name: daily-briefing
description: >
Sends a personalized morning briefing to the user via WhatsApp every day at 5:00 AM ET.
Covers emails from the last 24 hours, today’s calendar meetings, current Toronto weather,
and a portfolio summary for RGTI, IONQ, QBTS, and NVDA.
schedule: “0 5 * * *”        # cron: 5:00 AM daily (server must be in ET or adjust to UTC-5)
timezone: America/Toronto
config:
quantum_alert_threshold: 10    # 🚨 Alert if RGTI, IONQ, or QBTS moves ±this% in a single day. Set to null to disable.
metadata:
openclaw:
requires:
bins: [“gog”, “wacli”]
tools: [“exec”, “web_search”, “web_fetch”, “message”, “cron”]

## Purpose

Run every morning at 5:00 AM Toronto time. Fetch context from email, calendar, weather,
and live stock data. Compose a concise WhatsApp briefing and send it to the user.
The message must be readable in under 60 seconds — no walls of text.

-----

## Step 1 — Fetch Emails (Last 24 Hours)

Use the `gog` skill to retrieve all emails received in the past 24 hours from Gmail.

```
gog gmail list --after="-24h" --max=30
```

- Summarize into **3–5 bullet points** covering the most actionable or notable threads.
- Flag anything that looks urgent (words like “urgent”, “action required”, “deadline”, “ASAP”).
- If there are no emails, output: `📭 No new emails in the last 24h.`
- Do NOT reproduce full email bodies — summarize only.

**Output format:**

```
📧 *Email Highlights*
• [Sender] — [One-line summary]
• [Sender] — [One-line summary]
⚠️ Urgent: [Sender] — [Subject] (if applicable)
```

-----

## Step 2 — Fetch Today’s Calendar

Use the `gog` skill to retrieve all calendar events for today.

```
gog calendar list --date=today
```

- Include **all events** regardless of size, attendee count, or tag.
- Show event name, time, and duration.
- If a meeting has a video link (Google Meet, Zoom, Teams), append 📹 to that line.
- If there are no meetings, output: `📅 No meetings scheduled today.`

**Output format:**

```
📅 *Today's Meetings*
• 09:00–09:30 — [Meeting Name] 📹
• 14:00–15:00 — [Meeting Name]
```

-----

## Step 3 — Fetch Toronto Weather

Use `web_search` or `web_fetch` to retrieve the current weather and today’s forecast
for **Toronto, Ontario, Canada**.

Preferred source: `wttr.in/Toronto?format=j1` (JSON, no API key needed)

Extract:

- Current temperature (°C)
- Feels like (°C)
- Condition (e.g., Cloudy, Rain, Clear)
- High / Low for the day
- Any precipitation warnings if present

**Output format:**

```
🌤 *Toronto Weather*
Now: 4°C (Feels like -1°C) — Partly Cloudy
Today: High 8°C / Low -2°C
```

-----

## Step 4 — Portfolio Summary

Fetch live USD prices for the four tickers below using `web_search` or `web_fetch`.
Also fetch the current USD/CAD exchange rate.

**Portfolio (do not change these values — these are the user’s cost basis):**

|Ticker|Name             |Qty      |Avg Cost (CAD)|
|------|-----------------|---------|--------------|
|RGTI  |Rigetti Computing|153      |$32.8623      |
|IONQ  |IonQ Inc         |84       |$58.6668      |
|QBTS  |D-Wave Quantum   |170      |$28.6677      |
|NVDA  |Nvidia Corp      |137.00619|$102.0345     |

**Calculation logic per ticker:**

1. Fetch live USD price
1. Convert to CAD: `USD price × current USD/CAD rate`
1. Market Value (CAD) = `CAD price × quantity`
1. P&L (CAD) = `Market Value − (avg cost × quantity)`
1. P&L % = `(P&L / (avg cost × quantity)) × 100`

**Output format:**

```
📈 *Portfolio Summary*
Total Value: CAD $XX,XXX.XX

• NVDA  — $XXX.XX USD | CAD $XX,XXX | +$XX,XXX (+XX%)
• QBTS  — $XX.XX USD  | CAD $X,XXX  | -$XXX (-XX%)
• IONQ  — $XX.XX USD  | CAD $X,XXX  | -$XXX (-XX%)
• RGTI  — $XX.XX USD  | CAD $X,XXX  | -$XXX (-XX%)

💱 USD/CAD: X.XXXX
```

Note: Always show NVDA first (largest position at ~74% weight).
Gains are shown in green emoji context (✅), losses in red (🔴) — but do not send
color-coded HTML; WhatsApp only supports plain text and basic emoji.

**Quantum Alert Rule (`quantum_alert_threshold: 10`):**
After calculating each ticker’s single-day price change (today’s price vs. prior close),
apply the following logic to RGTI, IONQ, and QBTS only:

```
if abs(day_change_pct) >= quantum_alert_threshold:
    prepend "🚨 ALERT" to that ticker's line in the output
```

Example triggered output:

```
🚨 ALERT  RGTI  — $19.80 USD | CAD $X,XXX | -$XXX (-XX%) | Today: +12.3%
```

If no tickers breach the threshold, no alert line is added — output remains clean.
To disable alerts entirely, set `quantum_alert_threshold: null` in the config.

-----

## Step 5 — Compose & Send via WhatsApp

Assemble all four sections into a single WhatsApp message.
Use `wacli` to send the message to the user’s own number (self-message only).

```
wacli send --to=self --message="[assembled briefing]"
```

**Full message template:**

```
🌅 *Good morning, Gonzo!*
Here's your 5 AM briefing for [Day, Month Date].

━━━━━━━━━━━━━━━━━
[Step 1 email output]

━━━━━━━━━━━━━━━━━
[Step 2 calendar output]

━━━━━━━━━━━━━━━━━
[Step 3 weather output]

━━━━━━━━━━━━━━━━━
[Step 4 portfolio output]

━━━━━━━━━━━━━━━━━
_Briefing generated by OpenClaw at 05:00 ET_
```

-----

## Error Handling

- If any single step fails (e.g., gog auth expires, weather API is down), insert a one-line
  placeholder for that section and continue with the rest. Never abort the full briefing.
- Example: `⚠️ Weather data unavailable — check manually.`
- If WhatsApp send fails, log the error to `~/.openclaw/logs/daily-briefing.log` with timestamp.

-----

## Cron Registration

Add this to your `openclaw.json` to activate:

```json
{
  "cron": {
    "daily-briefing": {
      "skill": "daily-briefing",
      "schedule": "0 5 * * *",
      "timezone": "America/Toronto",
      "enabled": true
    }
  }
}
```

Verify it is active with:

```
openclaw cron list
```

-----

## Optimization Notes

1. **FX Rate freshness** — The USD/CAD rate is fetched live each morning, so portfolio
   values reflect the real CAD equivalent at time of delivery.
1. **Quantum stock volatility** — RGTI, IONQ, and QBTS are monitored with a ±10% single-day
   alert threshold (active). To adjust the sensitivity, change `quantum_alert_threshold` in
   the config frontmatter. Set to `null` to revert to summary-only.
1. **NVDA concentration risk** — At 74% portfolio weight, NVDA dominates the total.
   A future enhancement could flag when NVDA’s weight drifts above 80% as a rebalancing cue.
1. **Email volume** — “All emails from last 24h” with a cap of 30 means on heavy inbox
   days some emails will be cut. Consider adding a VIP sender list to `gog` filters later.
1. **WhatsApp auth persistence** — `wacli` sessions can expire. Run
   `wacli check-auth` as a pre-flight step before the send, and log a warning if the
   session needs to be re-authenticated.
1. **Timezone on server** — If your OpenClaw runs on a cloud VM (Azure, AWS),
   confirm the system timezone is set to `America/Toronto` or adjust the cron expression
   to UTC-5 (winter) / UTC-4 (summer): `0 10 * * *` (winter EST).
