#!/bin/sh

# --- Load Environment Variables ---
logger -p daemon.info -t "u3.sh" "Starting camera capture cycle"

# Load from .env file
if [ -f "/root/.env" ]; then
    . "/root/.env"
    logger -p daemon.debug -t "u3.sh" "Loaded environment from /root/.env"
else
    logger -p daemon.err -t "u3.sh" "Error: No .env file found"
    echo "Error: No .env file found"
    exit 1
fi

# --- Safety Checks ---
LOCKFILE="/var/lock/u3.lock"
exec 200>"$LOCKFILE" || {
    logger -p daemon.err -t "u3.sh" "Failed to create lockfile"
    exit 1
}
flock -n 200 || {
    logger -p daemon.warn -t "u3.sh" "Another instance is running, exiting"
    exit 1
}
logger -p daemon.debug -t "u3.sh" "Acquired lock successfully"

# --- Functions ---
record_audio() {
    output_file="$1"
    duration="$2"
    
    logger -p daemon.debug -t "u3.sh" "Starting audio recording: ${duration}s to $output_file"
    
    # Use the already-running audio capture
    if [ -p "/tmp/audio_stream.fifo" ]; then
        logger -p daemon.debug -t "u3.sh" "Using audio stream from named pipe"
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
        logger -p daemon.warn -t "u3.sh" "Audio pipe not available, using fallback recording"
        arecord -d "$duration" -f S16_LE -r 32000 -c 2 -D hw:0,0 "$output_file" >/dev/null 2>&1
        return $?
    fi
}

blacken_regions() {
    input="$1"

    # Skip blackening if no polygon is defined
    if [ -z "$POLYGON" ]; then
        return 0
    fi

    logger -p daemon.debug -t "u3.sh" "Applying privacy polygon to image"
    
    # Check if ImageMagick is available
    if command -v convert >/dev/null 2>&1; then
        if convert "$input" -fill black -draw "polygon $POLYGON" "$input" 2>/dev/null; then
            logger -p daemon.info -t "u3.sh" "Privacy polygon applied successfully"
        else
            logger -p daemon.warn -t "u3.sh" "Failed to apply privacy polygon"
        fi
        return 0
    else
        logger -p daemon.warn -t "u3.sh" "ImageMagick not available, skipping privacy polygon"
        return 0
    fi
}

upload_to_azure() {
    file_path="$1"
    blob_name="$2"

    # Verify file exists and has content before trying to upload
    if [ ! -s "$file_path" ]; then
        logger -p daemon.err -t "u3.sh" "Upload failed: file does not exist or is empty: $file_path"
        return 1
    fi

    file_size=$(wc -c < "$file_path")
    logger -p daemon.debug -t "u3.sh" "Uploading to Azure: $blob_name (${file_size} bytes)"

    if curl -i -X PUT \
        --max-time 15 \
        -H "x-ms-version: 2019-12-12" \
        -H "x-ms-date: $(date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
        -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Length: $(wc -c < "$file_path")" \
        --data-binary @"$file_path" \
        "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$blob_name$SAS_TOKEN" >/dev/null 2>&1; then
        logger -p daemon.info -t "u3.sh" "Upload successful: $blob_name (${file_size} bytes)"
        return 0
    else
        logger -p daemon.err -t "u3.sh" "Upload failed: $blob_name"
        return 1
    fi
}

publish_to_mqtt() {
    file_path="$1"

    if [ "$MQTT_ENABLED" != "true" ]; then
        return 0
    fi

    if ! command -v mosquitto_pub >/dev/null 2>&1; then
        logger -p daemon.warn -t "u3.sh" "MQTT enabled but mosquitto_pub not found"
        return 1
    fi

    mqtt_args="-h $MQTT_BROKER -p ${MQTT_PORT:-1883} -q ${MQTT_QOS:-1}"
    if [ -n "$MQTT_USERNAME" ]; then
        mqtt_args="$mqtt_args -u $MQTT_USERNAME -P $MQTT_PASSWORD"
    fi
    if [ "${MQTT_RETAIN:-true}" = "true" ]; then
        mqtt_args="$mqtt_args -r"
    fi

    # Publish snapshot image
    if [ "${MQTT_UPLOAD_IMAGE:-true}" = "true" ]; then
        if mosquitto_pub $mqtt_args -t "${MQTT_TOPIC}/snapshot" -f "$file_path" 2>/dev/null; then
            logger -p daemon.info -t "u3.sh" "MQTT snapshot published to ${MQTT_TOPIC}/snapshot"
        else
            logger -p daemon.warn -t "u3.sh" "MQTT snapshot publish failed"
        fi
    fi

    # Publish status JSON
    file_size=$(wc -c < "$file_path")
    if mosquitto_pub $mqtt_args -t "${MQTT_TOPIC}/status" \
        -m "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"size\":${file_size},\"interval\":${UPLOAD_INTERVAL}}" 2>/dev/null; then
        logger -p daemon.info -t "u3.sh" "MQTT status published to ${MQTT_TOPIC}/status"
    else
        logger -p daemon.warn -t "u3.sh" "MQTT status publish failed"
    fi
}

capture_snapshot() {
    output_file="$1"
    if pgrep mjpg_streamer >/dev/null 2>&1; then
        # mjpg-streamer already running, grab snapshot via HTTP
        logger -p daemon.info -t "u3.sh" "mjpg-streamer active, using HTTP snapshot"
        curl -s --max-time 10 "http://localhost:8080/?action=snapshot" > "$output_file" && [ -s "$output_file" ]
        return $?
    fi
    # Briefly start mjpg-streamer for a clean capture
    logger -p daemon.info -t "u3.sh" "Starting mjpg-streamer for snapshot capture"
    /etc/init.d/mjpg-streamer start 2>/dev/null
    sleep 1
    /bin/camsetup.sh 2>/dev/null
    curl -s --max-time 10 "http://localhost:8080/?action=snapshot" > "$output_file"
    /etc/init.d/mjpg-streamer stop 2>/dev/null
    [ -s "$output_file" ]
}

# --- Main ---
DATE=$(date -u +%d-%m-%Y)
TIME=$(date -u +%H_%M_%S)
UPLOAD_INTERVAL="${UPLOAD_INTERVAL:-60}"

logger -p daemon.info -t "u3.sh" "Processing cycle for $CUSTOMER/$CAMNAME (interval: ${UPLOAD_INTERVAL}s)"

# Process audio if enabled
if [ "$AUDIO_ENABLED" = "true" ]; then
    AUDIO_FILE="/tmp/audio_$TIME.wav"
    AUDIO_BLOB_NAME="$CUSTOMER/$DATE/$CAMNAME/audio_$TIME.wav"
    AUDIO_LATEST_NAME="$CUSTOMER/latest/$CAMNAME.wav"
    
    # Record audio for specified duration (default to 5 seconds if not set)
    AUDIO_DURATION="${AUDIO_DURATION:-5}"
    
    logger -p daemon.info -t "u3.sh" "Recording audio: ${AUDIO_DURATION} seconds"
    
    if record_audio "$AUDIO_FILE" "$AUDIO_DURATION"; then
        audio_size=$(wc -c < "$AUDIO_FILE" 2>/dev/null || echo "0")
        logger -p daemon.info -t "u3.sh" "Audio recording completed: ${audio_size} bytes"
        
        # Upload audio files
        upload_to_azure "$AUDIO_FILE" "$AUDIO_BLOB_NAME"
        upload_to_azure "$AUDIO_FILE" "$AUDIO_LATEST_NAME"
    else
        logger -p daemon.err -t "u3.sh" "Audio recording failed"
    fi
    
    # Clean up audio file
    rm -f "$AUDIO_FILE"
else
    logger -p daemon.debug -t "u3.sh" "Audio recording disabled"
fi

# Process image
SNAPSHOT_FILE="/tmp/snapshot_$TIME.jpg"
BLOB_NAME="$CUSTOMER/$DATE/$CAMNAME/snapshot_$TIME.jpg"
LATEST_NAME="$CUSTOMER/latest/$CAMNAME.jpg"

logger -p daemon.info -t "u3.sh" "Capturing snapshot"

if capture_snapshot "$SNAPSHOT_FILE"; then
    FILE_SIZE=$(wc -c < "$SNAPSHOT_FILE" 2>/dev/null || echo "0")
    logger -p daemon.info -t "u3.sh" "Snapshot captured successfully: ${FILE_SIZE} bytes"

    # Blacken regions (if polygon is defined)
    blacken_regions "$SNAPSHOT_FILE"

    # Keep a persistent copy for the LuCI camera UI
    cp "$SNAPSHOT_FILE" /tmp/latest_snapshot.jpg

    # Only send heartbeat if capture succeeds
    logger -p daemon.debug -t "u3.sh" "Sending heartbeat ping"
    curl -s --max-time 5 "${UPTIME_PING}${FILE_SIZE}bytes" >/dev/null 2>&1

    # Upload to Azure
    logger -p daemon.info -t "u3.sh" "Starting Azure uploads"
    upload_to_azure "$SNAPSHOT_FILE" "$LATEST_NAME"
    upload_to_azure "$SNAPSHOT_FILE" "$BLOB_NAME"

    # Publish to MQTT (if enabled)
    publish_to_mqtt "$SNAPSHOT_FILE"

    logger -p daemon.info -t "u3.sh" "Camera capture cycle completed successfully"
else
    logger -p daemon.err -t "u3.sh" "Snapshot capture failed"
    rm -f "$SNAPSHOT_FILE"
    exit 1
fi

# Cleanup
rm -f "$SNAPSHOT_FILE"
logger -p daemon.debug -t "u3.sh" "Cleanup completed"
exec 200>&- # Explicitly close file descriptor
exit 0
