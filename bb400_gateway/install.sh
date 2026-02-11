#!/bin/sh
# BB-400 Gateway Installer - NanoMQ MQTT Broker
# Usage: curl -fsSL https://raw.githubusercontent.com/o16s/avi_scripts/main/bb400_gateway/install.sh | sh
set -eu

INSTALL_DIR="/opt/avi-gateway"
GITHUB_RAW="https://raw.githubusercontent.com/o16s/avi_scripts/main/bb400_gateway"
MQTT_USER="avi"

# -- Prerequisites --
echo "Checking prerequisites..."

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed." >&2
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "Error: docker compose (or docker-compose) is not available." >&2
    exit 1
fi

echo "Using: $COMPOSE"

# -- Install directory --
mkdir -p "$INSTALL_DIR"

# -- Credentials --
if [ -f "$INSTALL_DIR/.env" ]; then
    echo "Existing .env found, preserving credentials."
    . "$INSTALL_DIR/.env"
    MQTT_PASS="$MQTT_PASSWORD"
else
    echo "Generating MQTT credentials..."
    MQTT_PASS="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
    cat > "$INSTALL_DIR/.env" <<EOF
MQTT_USER=$MQTT_USER
MQTT_PASSWORD=$MQTT_PASS
EOF
    chmod 600 "$INSTALL_DIR/.env"
fi

# -- Download config files --
echo "Downloading configuration..."
curl -fsSL "$GITHUB_RAW/docker-compose.yml" -o "$INSTALL_DIR/docker-compose.yml"
curl -fsSL "$GITHUB_RAW/nanomq.conf" -o "$INSTALL_DIR/nanomq.conf"

# -- Substitute password into config --
sed -i.bak "s/__MQTT_PASSWORD__/$MQTT_PASS/" "$INSTALL_DIR/nanomq.conf"
rm -f "$INSTALL_DIR/nanomq.conf.bak"

# -- Start services --
echo "Starting NanoMQ broker..."
cd "$INSTALL_DIR"
$COMPOSE up -d

echo ""
echo "====================================="
echo " AVI Gateway - NanoMQ MQTT Broker"
echo "====================================="
echo ""
echo "MQTT Broker: localhost:1883"
echo "HTTP API:    localhost:8081"
echo "Username:    $MQTT_USER"
echo "Password:    $MQTT_PASS"
echo ""
echo "Camera configuration:"
echo "  MQTT_HOST=<this-device-ip>"
echo "  MQTT_PORT=1883"
echo "  MQTT_USER=$MQTT_USER"
echo "  MQTT_PASSWORD=$MQTT_PASS"
echo ""
echo "Credentials saved to: $INSTALL_DIR/.env"
