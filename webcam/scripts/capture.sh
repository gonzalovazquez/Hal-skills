#!/bin/bash
set -euo pipefail

VIDEO_DEVICE="0"
RESOLUTION="1280x720"
FRAMERATE="10"
PIXEL_FORMAT="uyvy422"
DEFAULT_PHOTO="/tmp/hal-webcam-snap.jpg"
DEFAULT_VIDEO="/tmp/hal-webcam-clip.mp4"

if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found"
    exit 1
fi

MODE="${1:-photo}"

case "$MODE" in
    photo)
        OUTPUT="${2:-$DEFAULT_PHOTO}"
        ffmpeg -f avfoundation -pixel_format "$PIXEL_FORMAT" \
            -framerate "$FRAMERATE" -video_size "$RESOLUTION" \
            -i "${VIDEO_DEVICE}:none" \
            -frames:v 1 -update 1 -y "$OUTPUT" 2>/dev/null || true
        test -s "$OUTPUT" && echo "OK: $OUTPUT" || { echo "ERROR: Capture failed"; exit 1; }
        ;;
    video)
        DURATION="${2:-5}"
        OUTPUT="${3:-$DEFAULT_VIDEO}"
        [ "$DURATION" -gt 30 ] && DURATION=30
        ffmpeg -f avfoundation -pixel_format "$PIXEL_FORMAT" \
            -framerate "$FRAMERATE" -video_size "$RESOLUTION" \
            -i "${VIDEO_DEVICE}:none" \
            -t "$DURATION" -c:v libx264 -preset ultrafast -crf 23 \
            -y "$OUTPUT" 2>/dev/null || true
        test -s "$OUTPUT" && echo "OK: $OUTPUT" || { echo "ERROR: Video failed"; exit 1; }
        ;;
    test)
        TEMP="/tmp/hal-webcam-test.jpg"
        ffmpeg -f avfoundation -pixel_format "$PIXEL_FORMAT" \
            -framerate "$FRAMERATE" -video_size "640x480" \
            -i "${VIDEO_DEVICE}:none" \
            -frames:v 1 -update 1 -y "$TEMP" 2>/dev/null || true
        test -s "$TEMP" && { echo "OK: Webcam is working"; rm -f "$TEMP"; } || { echo "ERROR: Test failed"; rm -f "$TEMP"; exit 1; }
        ;;
    devices)
        ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true
        ;;
    *)
        echo "Usage: capture.sh {photo|video|devices|test} [duration] [output]"
        exit 1
        ;;
esac
