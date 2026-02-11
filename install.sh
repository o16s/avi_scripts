#!/bin/sh
# OpenWrt Camera System Installer
# Downloads latest AVI scripts from GitHub and installs on-device.

echo "Installing OpenWrt Camera System..."

# Check and install dependencies if needed
echo "Checking dependencies..."

if command -v v4l2-ctl >/dev/null 2>&1; then
    echo "v4l-utils already installed"
else
    echo "Installing v4l-utils..."
    opkg update && opkg install v4l-utils

    if command -v v4l2-ctl >/dev/null 2>&1; then
        echo "v4l-utils installed successfully"
    else
        echo "Failed to install v4l-utils"
        exit 1
    fi
fi

if command -v mosquitto_pub >/dev/null 2>&1; then
    echo "mosquitto-client already installed"
else
    echo "Installing mosquitto-client..."
    opkg update && opkg install mosquitto-client

    if command -v mosquitto_pub >/dev/null 2>&1; then
        echo "mosquitto-client installed successfully"
    else
        echo "Warning: Failed to install mosquitto-client (MQTT publishing will be unavailable)"
    fi
fi

# Download and extract repo tarball
cd /tmp || exit 1
rm -rf avi_scripts_temp install.tar.gz
mkdir -p avi_scripts_temp
cd avi_scripts_temp || exit 1

echo "Downloading configuration files..."
wget -O /tmp/install.tar.gz https://github.com/o16s/avi_scripts/archive/refs/heads/main.tar.gz
tar -xzf /tmp/install.tar.gz -C /tmp/avi_scripts_temp
mv avi_scripts-main/* ./
rm -rf avi_scripts-main

# Fetch version info from GitHub API
echo "Getting latest release information..."
RELEASE_JSON=$(wget -qO- "https://api.github.com/repos/o16s/avi_scripts/releases/latest" 2>/dev/null || echo "")

if [ -n "$RELEASE_JSON" ]; then
    VERSION=$(echo "$RELEASE_JSON" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$VERSION" ]; then
        VERSION=$(echo "$RELEASE_JSON" | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p')
    fi
    if [ -z "$VERSION" ]; then
        VERSION="main"
    fi
else
    VERSION="main"
fi

COMMIT_HASH=$(wget -qO- "https://api.github.com/repos/o16s/avi_scripts/git/refs/heads/main" 2>/dev/null \
    | grep -o '"sha":"[^"]*"' | cut -d'"' -f4 | cut -c1-7 2>/dev/null || echo "unknown")
UPDATE_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Run shared install logic
[ -f ./install_common.sh ] || { echo "Error: install_common.sh not found in downloaded archive"; exit 1; }
sh ./install_common.sh ./openwrt_7628 "$VERSION" "$COMMIT_HASH" "$UPDATE_DATE"

# Cleanup
cd /
rm -rf /tmp/avi_scripts_temp /tmp/install.tar.gz
