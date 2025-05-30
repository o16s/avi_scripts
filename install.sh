#!/bin/sh

# OpenWrt Camera System Installer - Space-efficient version
echo "Installing OpenWrt Camera System..."

# install dependencies not in image
opkg update && opkg install v4l-utils

# Step 1: Create temp directory and prepare environment
cd /tmp
rm -rf avi_scripts_temp install.tar.gz
mkdir -p avi_scripts_temp
cd avi_scripts_temp

# Step 2: Download repository as tarball (no git required)
echo "Downloading configuration files..."
wget -O /tmp/install.tar.gz https://github.com/o16s/avi_scripts/archive/refs/heads/main.tar.gz
tar -xzf /tmp/install.tar.gz -C /tmp/avi_scripts_temp
mv avi_scripts-main/* ./
rm -rf avi_scripts-main

# Step 3: Install scripts in bin
echo "Installing scripts..."
mkdir -p /bin
cp -v ./openwrt_7628/bin/report_ip.sh /bin/report_ip.sh
cp -v ./openwrt_7628/bin/u3.sh /bin/u3.sh
chmod +x /bin/report_ip.sh /bin/u3.sh

# Step 4: Install config files
echo "Installing configuration files..."
mkdir -p /etc/config
cp -v ./openwrt_7628/etc/config/mjpg-streamer /etc/config/mjpg-streamer
cp -v ./openwrt_7628/etc/config/camera /etc/config/camera

# Step 5: Install init scripts
echo "Installing service init scripts..."
cp -v ./openwrt_7628/etc/init.d/u3_service /etc/init.d/u3_service
chmod +x /etc/init.d/u3_service

# Step 6: Install crontab
echo "Installing crontab..."
mkdir -p /etc/crontabs
cp -v ./openwrt_7628/etc/crontabs/root /etc/crontabs/root

# Step 7: Install environment file
echo "Installing environment file..."
if [ -f "./openwrt_7628/root/example.env" ]; then
    if [ ! -f "/root/.env" ]; then
        cp -v ./openwrt_7628/root/example.env /root/.env
        echo "⚠️ IMPORTANT: Edit /root/.env with your actual configuration values!"
    else
        echo "Environment file already exists at /root/.env. Not overwriting."
    fi
fi

# Step 8: Enable services
echo "Enabling services..."
/etc/init.d/u3_service enable
/etc/init.d/cron enable
/etc/init.d/mjpg-streamer enable

# Step 9: Restart services
echo "Starting services..."
/etc/init.d/mjpg-streamer restart
/etc/init.d/cron restart
/etc/init.d/u3_service restart

# Step 10: Cleanup
cd /
rm -rf /tmp/avi_scripts_temp /tmp/install.tar.gz

echo ""
echo "✅ Installation complete!"
echo ""
echo "To check if everything is working:"
echo "1. Verify crontab: cat /etc/crontabs/root"
echo "2. Check service status: /etc/init.d/u3_service status"
echo "3. Make sure camera is working: curl http://localhost:8080/?action=snapshot > /tmp/test.jpg"
echo ""
echo "If you need to modify the environment variables:"
echo "   vi /root/.env"
