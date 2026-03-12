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
bins: [“gog”, “wacli”, “python3”, “pip”]
tools: [“exec”, “web_search”, “web_fetch”, “message”, “cron”]
setup: |
pip install yfinance –quiet –break-system-packages
gog auth status || echo “⚠️  gog not authenticated — run: gog auth login”

## Purpose

Run every morning at 5:00 AM Toronto time. Fetch context from email, calendar, weather,
and live stock data. Compose a concise WhatsApp briefing and send it to the user.
The message must be readable in under 60 seconds — no walls of text.

-----

## Step 0 — Pre-flight Auth Check

Before running any steps, verify `gog` is authenticated. If not, skip Steps 1 and 2
gracefully rather than failing silently.

```
gog auth status
```

- If output is `authenticated`: proceed to Step 1.
- If output is `unauthenticated` or errors: skip Steps 1 and 2, insert this placeholder
  in the briefing:
  
  ```
  ⚠️ Google auth expired — run: gog auth login
  ```
  
  Then continue with Steps 3, 4, and 5 as normal.

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

Fetch live USD prices using `yfinance` (Python) and the USD/CAD rate from the free
Open Exchange Rates API. No API keys required for either.

**Step 4a — Fetch stock prices and day change via yfinance:**

```python
import yfinance as yf
import json

tickers = ["RGTI", "IONQ", "QBTS", "NVDA"]
results = {}

for symbol in tickers:
    t = yf.Ticker(symbol)
    hist = t.history(period="2d")
    if len(hist) >= 2:
        prev_close = hist["Close"].iloc[-2]
        current    = hist["Close"].iloc[-1]
        day_change_pct = ((current - prev_close) / prev_close) * 100
    else:
        current = hist["Close"].iloc[-1]
        day_change_pct = 0.0
    results[symbol] = {
        "price_usd": round(float(current), 4),
        "day_change_pct": round(float(day_change_pct), 2)
    }

print(json.dumps(results))
```

Run with: `python3 fetch_prices.py`

**Step 4b — Fetch USD/CAD exchange rate (no API key):**

```
web_fetch: https://open.er-api.com/v6/latest/USD
```

Extract: `response.rates.CAD` — this is the live USD/CAD multiplier.

**Portfolio (do not change these values — these are the user’s cost basis):**

|Ticker|Name             |Qty      |Avg Cost (CAD)|
|------|-----------------|---------|--------------|
|RGTI  |Rigetti Computing|153      |$32.8623      |
|IONQ  |IonQ Inc         |84       |$58.6668      |
|QBTS  |D-Wave Quantum   |170      |$28.6677      |
|NVDA  |Nvidia Corp      |137.00619|$102.0345     |

**Calculation logic per ticker:**

1. `price_usd` from yfinance
1. `price_cad = price_usd × rates.CAD`
1. `market_value_cad = price_cad × qty`
1. `cost_basis_cad = avg_cost_cad × qty`
1. `pnl_cad = market_value_cad − cost_basis_cad`
1. `pnl_pct = (pnl_cad / cost_basis_cad) × 100`

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

1. **FX Rate freshness** — USD/CAD is fetched live from `open.er-api.com/v6/latest/USD`
   each morning (free, no API key, updates hourly). Portfolio CAD values reflect the
   real exchange rate at time of delivery.
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
