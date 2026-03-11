# openclaw-daily-briefing

A personal OpenClaw skill that delivers a concise morning briefing to your WhatsApp at 5:00 AM Toronto time every day.

## What It Does

Each morning the agent runs five steps in sequence and sends a single, readable WhatsApp message:

1. **Email highlights** — Summarizes all Gmail from the last 24 hours (max 30) into 3–5 bullets, flagging anything urgent
1. **Today’s meetings** — Lists every calendar event for the day with times and video call indicators
1. **Toronto weather** — Current conditions, feels-like, and high/low for the day via wttr.in (no API key needed)
1. **Portfolio summary** — Live USD prices converted to CAD for NVDA, QBTS, IONQ, and RGTI with P&L vs cost basis
1. **Quantum alert** — Prepends 🚨 ALERT to any quantum ticker (RGTI, IONQ, QBTS) that moves ±10% in a single day

-----

## Requirements

|Dependency                                                          |Purpose                                       |
|--------------------------------------------------------------------|----------------------------------------------|
|`gog`                                                               |Google Workspace CLI — Gmail + Calendar access|
|`wacli`                                                             |WhatsApp CLI — sends the briefing to self     |
|OpenClaw tools: `exec`, `web_search`, `web_fetch`, `message`, `cron`|Core runtime                                  |

-----

## Installation

### Option 1 — Via WhatsApp (recommended)

Once your OpenClaw instance is running, send it this message from WhatsApp:

```
Install the skill at https://github.com/YOUR_USERNAME/openclaw-daily-briefing
```

OpenClaw will fetch the repo, detect the skill folder, and install it automatically.

### Option 2 — Via ClawHub CLI

```bash
clawhub install https://github.com/YOUR_USERNAME/openclaw-daily-briefing
```

### Option 3 — Manual

```bash
cp -r daily-briefing ~/.openclaw/skills/
```

-----

## Activation

Add the following block to your `~/.openclaw/openclaw.json`:

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

Confirm it registered:

```bash
openclaw cron list
```

-----

## Configuration

All tunable options live at the top of `daily-briefing/SKILL.md`:

|Config key               |Default          |Description                                                                           |
|-------------------------|-----------------|--------------------------------------------------------------------------------------|
|`quantum_alert_threshold`|`10`             |% single-day move that triggers 🚨 ALERT on RGTI, IONQ, QBTS. Set to `null` to disable.|
|`schedule`               |`0 5 * * *`      |Cron expression — adjust if your server runs in UTC                                   |
|`timezone`               |`America/Toronto`|Delivery timezone                                                                     |

### Adjusting the alert threshold

Open `daily-briefing/SKILL.md` and change this line in the frontmatter:

```yaml
quantum_alert_threshold: 10    # change to 5 for tighter alerts, null to disable
```

### Adjusting for UTC servers (AWS / Azure VMs)

If your OpenClaw runs on a cloud VM, change the schedule to UTC equivalent:

```yaml
schedule: "0 10 * * *"    # EST (UTC-5, winter)
schedule: "0 9 * * *"     # EDT (UTC-4, summer)
```

-----

## Portfolio

The skill comes pre-loaded with the following cost basis. **Do not edit these unless your position changes.**

|Ticker|Name             |Qty      |Avg Cost (CAD)|
|------|-----------------|---------|--------------|
|NVDA  |Nvidia Corp      |137.00619|$102.0345     |
|QBTS  |D-Wave Quantum   |170      |$28.6677      |
|IONQ  |IonQ Inc         |84       |$58.6668      |
|RGTI  |Rigetti Computing|153      |$32.8623      |

To update a position, edit the portfolio table in `daily-briefing/SKILL.md` under **Step 4**.

-----

## Repo Structure

```
openclaw-daily-briefing/
├── README.md                  ← this file
└── daily-briefing/
    └── SKILL.md               ← the skill OpenClaw reads
```

-----

## Security Note

This skill sends messages to **yourself only** via `wacli --to=self`. It does not message any third parties. Review `daily-briefing/SKILL.md` before installing to verify all commands and permissions.

-----

## License

MIT — use freely, modify as needed.
