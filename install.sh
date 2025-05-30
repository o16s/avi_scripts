#!/bin/sh

# OpenWrt Camera System Installer - Space-efficient version with overwrite support
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

# Step 3: Install/Update scripts in bin (with overwrite)
echo "Installing/updating scripts..."
mkdir -p /bin

# Copy all .sh files from bin directory (overwrites existing)
if [ -d "./openwrt_7628/bin" ]; then
    echo "Copying all scripts from bin directory..."
    for script in ./openwrt_7628/bin/*.sh; do
        if [ -f "$script" ]; then
            cp -v "$script" /bin/
            chmod +x "/bin/$(basename "$script")"
            echo "✅ Installed/Updated: $(basename "$script")"
        fi
    done
else
    # Fallback to individual files if directory structure is different
    cp -v ./openwrt_7628/bin/report_ip.sh /bin/report_ip.sh
    cp -v ./openwrt_7628/bin/u3.sh /bin/u3.sh
    cp -v ./openwrt_7628/bin/camsetup.sh /bin/camsetup.sh 2>/dev/null || echo "camsetup.sh not found, skipping"
    chmod +x /bin/report_ip.sh /bin/u3.sh
    chmod +x /bin/camsetup.sh 2>/dev/null || true
fi

# Step 4: Install/Update config files (with overwrite detection)
echo "Installing/updating configuration files..."
mkdir -p /etc/config

# Copy all config files and detect new ones
if [ -d "./openwrt_7628/etc/config" ]; then
    for config_file in ./openwrt_7628/etc/config/*; do
        if [ -f "$config_file" ]; then
            config_name=$(basename "$config_file")
            if [ -f "/etc/config/$config_name" ]; then
                echo "🔄 Updating existing config: $config_name"
            else
                echo "🆕 Installing new config: $config_name"
            fi
            cp -v "$config_file" "/etc/config/$config_name"
        fi
    done
else
    # Fallback to known files
    cp -v ./openwrt_7628/etc/config/mjpg-streamer /etc/config/mjpg-streamer
    cp -v ./openwrt_7628/etc/config/camera /etc/config/camera
fi

# Step 5: Install/Update init scripts (with overwrite)
echo "Installing/updating service init scripts..."
if [ -d "./openwrt_7628/etc/init.d" ]; then
    for init_script in ./openwrt_7628/etc/init.d/*; do
        if [ -f "$init_script" ]; then
            script_name=$(basename "$init_script")
            if [ -f "/etc/init.d/$script_name" ]; then
                echo "🔄 Updating existing init script: $script_name"
            else
                echo "🆕 Installing new init script: $script_name"
            fi
            cp -v "$init_script" "/etc/init.d/$script_name"
            chmod +x "/etc/init.d/$script_name"
        fi
    done
else
    # Fallback
    cp -v ./openwrt_7628/etc/init.d/u3_service /etc/init.d/u3_service
    chmod +x /etc/init.d/u3_service
fi

# Step 6: Install/Update crontab (with backup)
echo "Installing/updating crontab..."
mkdir -p /etc/crontabs
if [ -f "/etc/crontabs/root" ]; then
    echo "🔄 Backing up existing crontab to /etc/crontabs/root.backup"
    cp /etc/crontabs/root /etc/crontabs/root.backup
fi
cp -v ./openwrt_7628/etc/crontabs/root /etc/crontabs/root

# Step 7: Handle environment file (preserve existing)
echo "Checking environment file..."
if [ -f "./openwrt_7628/root/example.env" ]; then
    if [ ! -f "/root/.env" ]; then
        cp -v ./openwrt_7628/root/example.env /root/.env
        echo "🆕 Created new environment file from example"
        echo "⚠️ IMPORTANT: Edit /root/.env with your actual configuration values!"
    else
        echo "✅ Environment file already exists at /root/.env. Not overwriting."
        # Optional: show if example.env has new variables
        if ! diff -q ./openwrt_7628/root/example.env /root/.env >/dev/null 2>&1; then
            echo "💡 TIP: Check example.env for any new configuration variables"
        fi
    fi
fi

# Step 8: Copy any additional files that might have been added
echo "Checking for additional files..."
if [ -d "./openwrt_7628/root" ]; then
    for file in ./openwrt_7628/root/*; do
        if [ -f "$file" ] && [ "$(basename "$file")" != "example.env" ]; then
            filename=$(basename "$file")
            echo "🆕 Found additional file: $filename"
            cp -v "$file" "/root/$filename"
        fi
    done
fi

# Step 9: Enable services
echo "Enabling services..."
/etc/init.d/u3_service enable
/etc/init.d/cron enable
/etc/init.d/mjpg-streamer enable

# Step 10: Restart services
echo "Restarting services..."
/etc/init.d/mjpg-streamer restart
/etc/init.d/cron restart
/etc/init.d/u3_service restart

# Step 11: Cleanup
cd /
rm -rf /tmp/avi_scripts_temp /tmp/install.tar.gz

echo ""
echo "✅ Installation/Update complete!"
echo ""
echo "📋 Summary of changes:"
echo "  - All .sh scripts updated/installed in /bin/"
echo "  - Configuration files updated/added in /etc/config/"
echo "  - Init scripts updated/added in /etc/init.d/"
echo "  - Services restarted with new configurations"
echo ""
echo "🔍 To verify installation:"
echo "1. Check scripts: ls -la /bin/*.sh"
echo "2. Verify crontab: cat /etc/crontabs/root"
echo "3. Check service status: /etc/init.d/u3_service status"
echo "4. Test camera: curl http://localhost:8080/?action=snapshot > /tmp/test.jpg"
echo ""
echo "📝 If you need to modify environment variables:"
echo "   vi /root/.env"