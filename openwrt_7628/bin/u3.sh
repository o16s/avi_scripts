#!/bin/sh

# --- Load Environment Variables ---
# Load from .env file
if [ -f "/root/.env" ]; then
    . "/root/.env"
else
    echo "Error: No .env file found"
    exit 1
fi

# --- Safety Checks ---
LOCKFILE="/var/lock/u3.lock"
exec 200>"$LOCKFILE" || exit 1
flock -n 200 || exit 1
echo 0 > /sys/class/leds/green:wlan/brightness

# Turn on USB device load switch GPIO11, with OpenWrt 22.03.5, r20134-5f15225c1e
echo 491 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio491/direction
echo 1 > /sys/class/gpio/gpio491/value  # HIGH

# --- Functions ---
record_audio() {
    local output_file="$1"
    local duration="$2"
    
    # Use the already-running audio capture
    if [ -p "/tmp/audio_stream.fifo" ]; then
        # Capture from the named pipe and convert to WAV
        (
            # Add WAV header to raw audio
            (
                # Generate WAV header for 32000Hz, 16-bit, 2 channel audio
                printf "RIFF\x24\xf0\xff\x7f" # RIFF chunk
                printf "WAVE"                  # WAVE identifier
                printf "fmt \x10\x00\x00\x00"  # fmt chunk size = 16 bytes
                printf "\x01\x00"              # format = 1 (PCM)
                printf "\x02\x00"              # channels = 2
                printf "\x00\x7d\x00\x00"      # sample rate = 32000
                printf "\x00\xf4\x01\x00"      # byte rate = 32000*2*2 = 128000
                printf "\x04\x00"              # block align = 2*2 = 4
                printf "\x10\x00"              # bits per sample = 16
                printf "data\x00\xf0\xff\x7f"  # data chunk header
            )
            # Read from named pipe for specified duration
            dd bs=4 count=$((32000 * $duration)) if=/tmp/audio_stream.fifo 2>/dev/null
        ) > "$output_file"
        
        return 0
    else
        # Fallback to regular recording if pipe not available
        arecord -d "$duration" -f S16_LE -r 32000 -c 2 -D hw:0,0 "$output_file" >/dev/null 2>&1
        return $?
    fi
}

blacken_regions() {
    local input="$1"

    # Skip blackening if no polygon is defined
    if [ -z "$POLYGON" ]; then
        return 0
    fi

    # Check if ImageMagick is available
    if command -v convert >/dev/null 2>&1; then
        convert "$input" -fill black -draw "polygon $POLYGON" "$input" 2>/dev/null || return 0
        return 0
    else
        return 0
    fi
}

upload_to_azure() {
    local file_path="$1"
    local blob_name="$2"

    # Verify file exists and has content before trying to upload
    [ ! -s "$file_path" ] && return 1

    curl -i -X PUT \
        --max-time 15 \
        -H "x-ms-version: 2019-12-12" \
        -H "x-ms-date: $(date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
        -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Length: $(wc -c < "$file_path")" \
        --data-binary @"$file_path" \
        "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$blob_name$SAS_TOKEN"

    return $?
}

# --- Main ---
DATE=$(date -u +%d-%m-%Y)
TIME=$(date -u +%H_%M_%S)

# Process audio if enabled
if [ "$AUDIO_ENABLED" = "true" ]; then
    AUDIO_FILE="/tmp/audio_$TIME.wav"
    AUDIO_BLOB_NAME="$CUSTOMER/$DATE/$CAMNAME/audio_$TIME.wav"
    AUDIO_LATEST_NAME="$CUSTOMER/latest/$CAMNAME.wav"
    
    # Record audio for specified duration (default to 5 seconds if not set)
    AUDIO_DURATION="${AUDIO_DURATION:-5}"
    
    if record_audio "$AUDIO_FILE" "$AUDIO_DURATION"; then
        # Upload audio files
        upload_to_azure "$AUDIO_FILE" "$AUDIO_BLOB_NAME"
        upload_to_azure "$AUDIO_FILE" "$AUDIO_LATEST_NAME"
    fi
    
    # Clean up audio file
    rm -f "$AUDIO_FILE"
fi

# Process image
SNAPSHOT_FILE="/tmp/snapshot_$TIME.jpg"
BLOB_NAME="$CUSTOMER/$DATE/$CAMNAME/snapshot_$TIME.jpg"
LATEST_NAME="$CUSTOMER/latest/$CAMNAME.jpg"

# Try to capture snapshot
if curl -s --max-time 10 "http://localhost:8080/?action=snapshot" > "$SNAPSHOT_FILE" && [ -s "$SNAPSHOT_FILE" ]; then
    # Blacken regions (if polygon is defined)
    blacken_regions "$SNAPSHOT_FILE"

    # Only send heartbeat if capture succeeds
    FILE_SIZE=$(wc -c < "$SNAPSHOT_FILE" 2>/dev/null || echo "0")
    curl -s --max-time 5 "${UPTIME_PING}${FILE_SIZE}bytes" >/dev/null 2>&1

    # Upload to Azure
    upload_to_azure "$SNAPSHOT_FILE" "$LATEST_NAME"
    upload_to_azure "$SNAPSHOT_FILE" "$BLOB_NAME"
else
    # Restart mjpg-streamer if capture fails
    /etc/init.d/mjpg-streamer restart
    rm -f "$SNAPSHOT_FILE"
    exit 1
fi

# Cleanup
rm -f "$SNAPSHOT_FILE"
exec 200>&- # Explicitly close file descriptor
exit 0
