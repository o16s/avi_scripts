#!/bin/bash

# Generate a unique identifier using system hardware information
generate_camera_id() {
    # Get the camera's LAN IP from function argument
    local LAN_IP="$1"
    
    # Exit with error if no LAN IP provided
    if [[ -z "$LAN_IP" ]]; then
        echo "Error: LAN IP must be provided as argument" >&2
        return 1
    fi
    
    echo "Collecting system identifiers..."
    
    # Get hostname - available on both Linux and macOS
    local HOSTNAME=$(hostname 2>/dev/null || echo "unknown-host")
    
    # Get MAC address of primary interface - works on both systems
    local MAC_ADDRESS=""
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS method
        MAC_ADDRESS=$(ifconfig en0 | grep ether | awk '{print $2}' 2>/dev/null)
    else
        # Linux method
        MAC_ADDRESS=$(ip link | grep "link/ether" | head -1 | awk '{print $2}' 2>/dev/null)
    fi
    
    # Fallback if MAC not found
    if [[ -z "$MAC_ADDRESS" ]]; then
        MAC_ADDRESS="no-mac"
    fi
    
    # Get Machine ID (stable system identifier)
    local MACHINE_ID=""
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS hardware UUID
        MACHINE_ID=$(ioreg -rd1 -c IOPlatformExpertDevice | grep -o '"IOPlatformUUID" = "[^"]*"' | awk -F '= ' '{print $2}' | tr -d '"' 2>/dev/null)
    else
        # Linux machine-id (persistent across boots)
        if [[ -f "/etc/machine-id" ]]; then
            MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
        elif [[ -f "/var/lib/dbus/machine-id" ]]; then
            MACHINE_ID=$(cat /var/lib/dbus/machine-id 2>/dev/null)
        fi
    fi
    
    # Fallback if machine ID not found
    if [[ -z "$MACHINE_ID" ]]; then
        MACHINE_ID="no-id"
    fi
    
    # Create a base identifier by combining static identifiers and camera IP
    local BASE_ID="${HOSTNAME}_${MAC_ADDRESS}_${MACHINE_ID}_${LAN_IP}"
    echo "Base identifier created: ${HOSTNAME}_${MAC_ADDRESS}_part-of-machine-id_${LAN_IP}"
    
    # Generate a unique hash
    local HASH_ID=""
    if command -v md5sum >/dev/null 2>&1; then
        HASH_ID=$(echo -n "$BASE_ID" | md5sum | cut -d' ' -f1)
    elif command -v md5 >/dev/null 2>&1; then
        # For macOS
        HASH_ID=$(echo -n "$BASE_ID" | md5)
    else
        # Fallback if no md5 tool available
        HASH_ID="nohash-${HOSTNAME}-${LAN_IP}"
    fi
    
    # Create human-readable identifier
    local READABLE_ID="${HOSTNAME}_${LAN_IP}"
    
    # Set variables
    CAMERA_HASH_ID="$HASH_ID"
    CAMERA_READABLE_ID="$READABLE_ID"
    CAMERA_HOST_ID="$HOSTNAME"
    CAMERA_LOCATION_ID="$LAN_IP"
    
    # Export variables to be used by the main script
    export CAMERA_HASH_ID
    export CAMERA_READABLE_ID
    export CAMERA_HOST_ID
    export CAMERA_LOCATION_ID
    
    # Return the hash ID
    echo "$HASH_ID"
}

# Only execute if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$1" ]]; then
        echo "Usage: $0 <camera_lan_ip>"
        echo "Example: $0 192.168.123.103"
        exit 1
    fi
    
    # Display info if run directly
    echo "Generating camera ID for IP: $1"
    generate_camera_id "$1"
    
    echo ""
    echo "Camera Hash ID: $CAMERA_HASH_ID"
    echo "Camera Readable ID: $CAMERA_READABLE_ID"
    echo "Camera Host: $CAMERA_HOST_ID"
    echo "Camera Location: $CAMERA_LOCATION_ID"
fi
