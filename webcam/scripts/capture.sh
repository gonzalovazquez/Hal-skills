#!/bin/bash
# capture.sh - Webcam capture for Hal
# Usage: capture.sh photo [output_path]
#        capture.sh video [duration_seconds] [output_path]

set -euo pipefail

# Device configuration
VIDEO_DEVICE="0"
AUDIO_DEVICE="1"
RESOLUTION="1280x720"
FRAMERATE="30"
WARMUP_FRAMES="30"

# Defaults
DEFAULT_PHOTO_PATH="/tmp/hal-webcam-snap.jpg"
DEFAULT_VIDEO_PATH="/tmp/hal-webcam-clip.mp4"
DEFAULT_VIDEO_DURATION="5"
MAX_VIDEO_DURATION="30"

# Check ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found. Run: brew install ffmpeg"
    exit 1
fi

# Check webcam is connected
if ! ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -q "USB Camera"; then
    echo "ERROR: Webcam not detected. Check USB connection."
    exit 1
fi

MODE="${1:-photo}"

case "$MODE" in
    photo)
        OUTPUT="${2:-$DEFAULT_PHOTO_PATH}"

        # Capture with warmup: grab extra frames and keep only the last one
        # This gives the camera time to adjust exposure
        ffmpeg -f avfoundation -framerate "$FRAMERATE" -video_size "$RESOLUTION" \
            -i "${VIDEO_DEVICE}:none" \
            -frames:v $((WARMUP_FRAMES + 1)) \
            -y -update 1 \
            "$OUTPUT" 2>/dev/null

        if [ -s "$OUTPUT" ]; then
            echo "OK: $OUTPUT"
        else
            echo "ERROR: Capture produced empty file"
            exit 1
        fi
        ;;

    video)
        DURATION="${2:-$DEFAULT_VIDEO_DURATION}"
        OUTPUT="${3:-$DEFAULT_VIDEO_PATH}"

        # Cap duration
        if [ "$DURATION" -gt "$MAX_VIDEO_DURATION" ]; then
            DURATION="$MAX_VIDEO_DURATION"
        fi

        # Record video with audio
        # Falls back to no audio if USB audio device fails
        ffmpeg -f avfoundation -framerate "$FRAMERATE" -video_size "$RESOLUTION" \
            -i "${VIDEO_DEVICE}:${AUDIO_DEVICE}" \
            -t "$DURATION" \
            -c:v libx264 -preset ultrafast -crf 23 \
            -c:a aac -b:a 128k \
            -y "$OUTPUT" 2>/dev/null

        # If video+audio failed, try video only
        if [ ! -s "$OUTPUT" ]; then
            ffmpeg -f avfoundation -framerate "$FRAMERATE" -video_size "$RESOLUTION" \
                -i "${VIDEO_DEVICE}:none" \
                -t "$DURATION" \
                -c:v libx264 -preset ultrafast -crf 23 \
                -y "$OUTPUT" 2>/dev/null
        fi

        if [ -s "$OUTPUT" ]; then
            SIZE=$(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT" 2>/dev/null)
            SIZE_MB=$((SIZE / 1048576))
            echo "OK: $OUTPUT (${SIZE_MB}MB, ${DURATION}s)"
        else
            echo "ERROR: Video capture failed"
            exit 1
        fi
        ;;

    devices)
        # List available video devices
        ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 10 "video devices"
        ;;

    test)
        # Quick connectivity test: capture one frame, report success/failure
        TEMP="/tmp/hal-webcam-test.jpg"
        ffmpeg -f avfoundation -framerate "$FRAMERATE" -video_size "640x480" \
            -i "${VIDEO_DEVICE}:none" \
            -frames:v 1 -y "$TEMP" 2>/dev/null

        if [ -s "$TEMP" ]; then
            echo "OK: Webcam is working"
            rm -f "$TEMP"
        else
            echo "ERROR: Webcam test failed"
            rm -f "$TEMP"
            exit 1
        fi
        ;;

    *)
        echo "Usage: capture.sh {photo|video|devices|test} [args]"
        echo "  photo [output_path]              Capture a single photo"
        echo "  video [duration] [output_path]   Record a video clip (max ${MAX_VIDEO_DURATION}s)"
        echo "  devices                          List available video devices"
        echo "  test                             Quick webcam connectivity test"
        exit 1
        ;;
esac
