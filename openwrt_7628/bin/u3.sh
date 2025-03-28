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

# --- Functions ---
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
