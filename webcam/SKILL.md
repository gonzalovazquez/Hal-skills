---
name: webcam
description: >
  Hal's eyes. Captures photos and short video clips from the USB webcam
  connected to the Mac Mini, sends them via WhatsApp, and optionally
  describes what the camera sees using the primary vision model.
metadata:
  openclaw:
    requires:
      bins: ["ffmpeg"]
      tools: ["exec", "message", "media"]
      os: ["darwin"]
---

# webcam

Hal can see. This skill captures images and short video clips from the
USB webcam on the Mac Mini, delivers them to WhatsApp, and uses the
vision model to describe what's in frame when asked.

---

## Device Configuration

| Setting | Value |
|---------|-------|
| Device index | `0` (USB Camera VID:1133 PID:2081) |
| Audio device | `1` (Unknown USB Audio Device) |
| Capture format | avfoundation (macOS native) |
| Default resolution | 1280x720 |
| Warmup delay | 1.5 seconds (camera needs time to adjust exposure) |

If the webcam is reconnected or a different camera is plugged in, run:
```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "video devices" -A 5
```
Update the device index in `scripts/capture.sh` if it changes.

---

## On-Demand Commands

Hal listens for these natural language triggers over WhatsApp:

| Say this | Hal does |
|----------|----------|
| "show me the webcam" / "take a photo" / "snap a pic" | Captures a single photo and sends it |
| "what do you see" / "describe the webcam" / "look around" | Captures a photo, analyzes it with vision model, sends photo + description |
| "record a clip" / "take a video" / "webcam video" | Records a 5-second video clip and sends it |
| "is anyone there" / "check the room" | Captures + vision analysis, focused on detecting people or activity |

---

## Step 0: Pre-flight

Before any capture, verify:

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "USB Camera"
```

If the webcam is not listed, respond:
```
⚠️ Webcam not detected. Check the USB connection on the Mac Mini.
```
and stop.

---

## Step 1: Capture Photo

Use the capture script:

```bash
bash ~/.openclaw/skills/webcam/scripts/capture.sh photo
```

This runs:
```bash
ffmpeg -f avfoundation -framerate 30 -video_size 1280x720 \
  -i "0:none" -frames:v 1 -y /tmp/hal-webcam-snap.jpg 2>/dev/null
```

**Important notes:**
- The `-y` flag overwrites any previous capture without prompting.
- `-i "0:none"` uses video device 0 with no audio.
- First frame may be dark. The script discards 30 frames (1 second warmup)
  before capturing the actual photo for proper exposure.
- Output is always JPEG for WhatsApp compatibility.

After capture, verify the file exists and is non-zero:
```bash
test -s /tmp/hal-webcam-snap.jpg && echo "ok" || echo "fail"
```

If capture fails, respond:
```
⚠️ Webcam capture failed. Camera may be in use by another app or disconnected.
```

---

## Step 2: Capture Video Clip

```bash
bash ~/.openclaw/skills/webcam/scripts/capture.sh video [seconds]
```

Default duration: 5 seconds. Maximum: 30 seconds.

This runs:
```bash
ffmpeg -f avfoundation -framerate 30 -video_size 1280x720 \
  -i "0:1" -t 5 -c:v libx264 -preset ultrafast -crf 23 \
  -c:a aac -b:a 128k -y /tmp/hal-webcam-clip.mp4 2>/dev/null
```

**Notes:**
- `-i "0:1"` uses video device 0 and audio device 1 (USB mic).
- `libx264` with `ultrafast` preset minimizes encoding time.
- `-crf 23` balances quality and file size for WhatsApp delivery.
- WhatsApp has a 16MB file limit for media. At these settings, 30 seconds
  is roughly 8-10MB, well within limits.

---

## Step 3: Send via WhatsApp

After capture, send the media file:

```
MEDIA:/tmp/hal-webcam-snap.jpg
```

or for video:

```
MEDIA:/tmp/hal-webcam-clip.mp4
```

Always include a brief text message with the media:
- Photo: "Here's what I see right now."
- Video: "5-second clip from the webcam."
- If the user asked "is anyone there": pair with vision analysis (Step 4).

---

## Step 4: Vision Analysis (optional)

When the user asks Hal to *describe* what the webcam sees, or asks
questions like "is anyone there" or "what's happening":

1. Capture a photo (Step 1)
2. Send the photo to the primary vision model with a prompt:
   - For general description: "Describe what you see in this image. Be concise."
   - For presence detection: "Is there anyone visible in this image? Describe any people, movement, or notable activity. If the room is empty, say so."
   - For security check: "Analyze this image for anything unusual or out of place. Be specific."
3. Send both the photo and the text description to WhatsApp.

The vision model receives the image as part of the message context.
Hal does not need to call an external API for this; the primary model
(Claude) supports vision natively.

---

## Error Handling

| Error | Response |
|-------|----------|
| Webcam not detected | `⚠️ Webcam not detected. Check USB connection.` |
| Capture produces 0-byte file | `⚠️ Capture failed. Camera may be in use or needs reconnecting.` |
| ffmpeg not installed | `⚠️ ffmpeg not found. Run: brew install ffmpeg` |
| Video too large for WhatsApp (>16MB) | Re-encode at lower quality or shorter duration |
| Permission denied on camera | `⚠️ Camera permission denied. Grant access in System Settings > Privacy > Camera for Terminal/OpenClaw.` |

---

## Privacy and Safety

- Hal never captures photos or video without an explicit command from Gonzalo.
- No scheduled captures unless Gonzalo explicitly enables them.
- Captured files are stored in `/tmp/` and overwritten on each new capture.
  They are not persisted or backed up.
- Hal never sends webcam images to anyone other than Gonzalo.
- If a group chat member asks Hal to "show the webcam," Hal declines:
  "Webcam access is restricted to direct messages with Gonzalo."

---

## Optimization Notes

1. **Camera warmup:** USB cameras need 1-2 seconds to adjust exposure after
   being activated. The capture script discards initial dark frames.

2. **macOS permissions:** The first time ffmpeg accesses the camera, macOS
   will prompt for permission. Grant it in System Settings > Privacy > Camera.
   If running via OpenClaw's gateway, the parent process (Terminal, iTerm,
   or the OpenClaw daemon) needs camera permission.

3. **File cleanup:** Captures overwrite the same filenames (`hal-webcam-snap.jpg`,
   `hal-webcam-clip.mp4`) to avoid filling `/tmp/`. No cleanup cron needed.

4. **Audio on video clips:** If the USB audio device causes issues, fall back
   to video-only by changing `-i "0:1"` to `-i "0:none"` in the video command.
