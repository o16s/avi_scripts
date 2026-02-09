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

    # Gather system metrics
    file_size=$(wc -c < "$file_path" 2>/dev/null)
    load_avg=$(cut -d' ' -f1,2,3 /proc/loadavg 2>/dev/null)
    mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)
    uptime_sec=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
    flash_used=$(df /overlay 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    ip_addr=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)

    # Load version info
    avi_version="" avi_commit=""
    if [ -f /etc/avi_version.env ]; then
        . /etc/avi_version.env
        avi_version="$AVI_SCRIPTS_VERSION"
        avi_commit="$AVI_SCRIPTS_COMMIT"
    fi

    # Publish status JSON
    status_json="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"size\":${file_size:-0},\"interval\":${UPLOAD_INTERVAL}"
    status_json="${status_json},\"customer\":\"${CUSTOMER}\",\"camera\":\"${CAMNAME}\""
    status_json="${status_json},\"version\":\"${avi_version}\",\"commit\":\"${avi_commit}\""
    status_json="${status_json},\"brightness\":${CAM_BRIGHTNESS:-0},\"contrast\":${CAM_CONTRAST:-32},\"saturation\":${CAM_SATURATION:-64}"
    status_json="${status_json},\"gain\":${CAM_GAIN:-20},\"exposure_auto\":${CAM_EXPOSURE_AUTO:-3},\"wb_auto\":${CAM_AUTO_WB:-1}"
    status_json="${status_json},\"load\":\"${load_avg}\",\"mem_available_kb\":${mem_avail:-0},\"uptime_sec\":${uptime_sec:-0}"
    status_json="${status_json},\"flash_used_pct\":${flash_used:-0},\"ip\":\"${ip_addr}\""
    status_json="${status_json},\"img_r\":${IMG_R:-0},\"img_g\":${IMG_G:-0},\"img_b\":${IMG_B:-0}"
    status_json="${status_json},\"img_brightness\":${IMG_BRIGHTNESS:-0},\"img_green_pct\":${IMG_GREEN_PCT:-0}"
    status_json="${status_json},\"img_diff_pct\":${IMG_DIFF_PCT:-0}}"

    if mosquitto_pub $mqtt_args -t "${MQTT_TOPIC}/status" -m "$status_json" 2>/dev/null; then
        logger -p daemon.info -t "u3.sh" "MQTT status published to ${MQTT_TOPIC}/status"
    else
        logger -p daemon.warn -t "u3.sh" "MQTT status publish failed"
    fi
}

compute_image_metrics() {
    img="$1"
    prev="/tmp/latest_snapshot.jpg"

    IMG_R="" IMG_G="" IMG_B="" IMG_BRIGHTNESS="" IMG_GREEN_PCT="" IMG_DIFF_PCT=""

    if ! command -v convert >/dev/null 2>&1; then
        return 0
    fi

    # Mean RGB via 1x1 resize (one convert call)
    # Output: "0,0: (28,47,38)  #1C2F26  srgb(28,47,38)"
    rgb_line=$(convert "$img" -resize 1x1! txt:- 2>/dev/null | tail -1)
    if [ -n "$rgb_line" ]; then
        rgb=$(echo "$rgb_line" | grep -o '([0-9]*,[0-9]*,[0-9]*)' | head -1 | tr -d '()')
        IMG_R=$(echo "$rgb" | cut -d, -f1)
        IMG_G=$(echo "$rgb" | cut -d, -f2)
        IMG_B=$(echo "$rgb" | cut -d, -f3)

        # Brightness = standard luminance from RGB (integer math, no second convert call)
        IMG_BRIGHTNESS=$(( (IMG_R * 299 + IMG_G * 587 + IMG_B * 114) / 1000 ))

        # Green index = G% of total RGB
        total=$(( IMG_R + IMG_G + IMG_B ))
        if [ "$total" -gt 0 ]; then
            IMG_GREEN_PCT=$(( IMG_G * 100 / total ))
        else
            IMG_GREEN_PCT=0
        fi
    fi

    logger -p daemon.info -t "u3.sh" "Image metrics: R=${IMG_R} G=${IMG_G} B=${IMG_B} bright=${IMG_BRIGHTNESS} green=${IMG_GREEN_PCT}%"

    # Frame difference vs previous snapshot (one convert call)
    if [ -f "$prev" ]; then
        IMG_DIFF_PCT=$(convert "$img" "$prev" -compose difference -composite \
            -colorspace Gray -resize 1x1! -format "%[fx:mean*100]" info: 2>/dev/null)
        logger -p daemon.info -t "u3.sh" "Frame diff: ${IMG_DIFF_PCT}%"
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

    # Compute image metrics (before cp overwrites previous frame)
    if [ "${IMAGE_METRICS_ENABLED:-true}" = "true" ]; then
        compute_image_metrics "$SNAPSHOT_FILE"
    fi

    # Keep a persistent copy for the LuCI camera UI
    cp "$SNAPSHOT_FILE" /tmp/latest_snapshot.jpg

    # Only send heartbeat if capture succeeds
    logger -p daemon.debug -t "u3.sh" "Sending heartbeat ping"
    curl -s --max-time 5 "${UPTIME_PING}${FILE_SIZE}bytes" >/dev/null 2>&1

    # Upload to Azure (if enabled)
    if [ "${AZURE_ENABLED:-false}" = "true" ]; then
        logger -p daemon.info -t "u3.sh" "Starting Azure uploads"
        upload_to_azure "$SNAPSHOT_FILE" "$LATEST_NAME"
        upload_to_azure "$SNAPSHOT_FILE" "$BLOB_NAME"
    fi

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
