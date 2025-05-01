#!/bin/bash

# --- Load Environment Variables ---
if [ -f ".env" ]; then
    source ".env"
else
    echo "Error: No camera.env file found"
    exit 1
fi

# --- Safety Checks ---
LOCKFILE="/tmp/rtsp_snapshot.lock"
exec 200>"$LOCKFILE" || exit 1
flock -n 200 || { echo "Another instance is already running"; exit 1; }
trap 'exec 200>&-' EXIT  # Ensure lock file is released on exit

# --- Source Camera ID Script (if available) ---
if [ -f "../camera_id.sh" ]; then
    source "../camera_id.sh"
    generate_camera_id "${CAMERA_IP}"
    echo "Camera ID: $CAMERA_READABLE_ID"
    
    # Use camera ID as part of naming if available
    CAMERA_NAME="${CAMERA_NAME:-$CAMERA_READABLE_ID}"
else
    echo "Warning: camera_id.sh not found, using default camera name"
    CAMERA_NAME="${CAMERA_NAME:-unknown_camera}"
fi

# --- Functions ---
upload_to_azure() {
    local file_path="$1"
    local blob_name="$2"

    # Verify file exists and has content before trying to upload
    [ ! -s "$file_path" ] && { echo "Error: File empty or not found: $file_path"; return 1; }

    echo "Uploading to Azure: $blob_name"
    
    # Original URL format with the SAS token at the end
    local response=$(curl -s -X PUT \
        --max-time 15 \
        -H "x-ms-version: 2023-01-03" \
        -H "x-ms-date: $(date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
        -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Length: $(wc -c < "$file_path")" \
        --data-binary @"$file_path" \
        "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$blob_name$SAS_TOKEN")

    # Check for error in response
    if echo "$response" | grep -q "<Error>"; then
        echo "Upload failed: $blob_name"
        echo "Error details: $response"
        return 1
    else
        echo "Upload successful: $blob_name"
        return 0
    fi
}

# --- Main Script ---
DATE=$(date -u +%Y-%m-%d)
TIME=$(date -u +%H_%M_%S)
SNAPSHOT_FILE="/tmp/snapshot_${CAMERA_NAME}_${TIME}.jpg"
BLOB_NAME="$CUSTOMER/$DATE/$CAMERA_NAME/snapshot_$TIME.jpg"
LATEST_NAME="$CUSTOMER/latest/$CAMERA_NAME.jpg"

# Construct the RTSP URL
RTSP_URL="rtsp://${CAMERA_USERNAME}:${CAMERA_PASSWORD}@${CAMERA_IP}:${CAMERA_PORT}/${CAMERA_STREAM}"

echo "Taking snapshot from camera $CAMERA_NAME..."
ffmpeg -loglevel error -rtsp_transport tcp -i "${RTSP_URL}" -frames:v 1 -q:v 2 "${SNAPSHOT_FILE}"

# Check if snapshot was captured successfully
if [ $? -eq 0 ] && [ -s "${SNAPSHOT_FILE}" ]; then
    # Report file size
    FILE_SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
    echo "Snapshot captured: $FILE_SIZE"
     
    # Upload to Azure
    upload_to_azure "$SNAPSHOT_FILE" "$LATEST_NAME"
    upload_to_azure "$SNAPSHOT_FILE" "$BLOB_NAME"
    
    echo "Snapshot processing complete"
else
    echo "Error: Failed to capture snapshot"
    rm -f "$SNAPSHOT_FILE"
    exit 1
fi

# Cleanup
rm -f "$SNAPSHOT_FILE"
exit 0
