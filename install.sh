#!/bin/sh

# OpenWrt Camera System Installer - Space-efficient version with overwrite support
echo "Installing OpenWrt Camera System..."

# Check and install dependencies if needed
echo "Checking dependencies..."

if command -v v4l2-ctl >/dev/null 2>&1; then
    echo "✅ v4l-utils already installed"
else
    echo "Installing v4l-utils..."
    opkg update && opkg install v4l-utils
    
    if command -v v4l2-ctl >/dev/null 2>&1; then
        echo "✅ v4l-utils installed successfully"
    else
        echo "❌ Failed to install v4l-utils"
        exit 1
    fi
fi

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

# Step 9a: Install logo and header template
echo "Installing logo and custom header..."

# Create static directory for logo
mkdir -p /www/luci-static

# Copy logo file if it exists
if [ -f "./openwrt_7628/docs/source/_static/avi_logo_w.png" ]; then
    echo "📷 Installing AVI logo..."
    cp -v "./openwrt_7628/docs/source/_static/avi_logo_w.png" "/www/luci-static/avi_logo_w.png"
    chmod 644 "/www/luci-static/avi_logo_w.png"
    echo "✅ Logo installed at /www/luci-static/avi_logo_w.png"
else
    echo "⚠️ Logo file not found: ./openwrt_7628/docs/source/_static/avi_logo_w.png"
fi

# Install custom header template
if [ -f "./openwrt_7628/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm" ]; then
    echo "🎨 Installing custom LuCI header..."
    
    # Backup original header if not already backed up
    if [ -f "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm" ] && [ ! -f "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm.original" ]; then
        cp "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm" "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm.original"
        echo "🔄 Backed up original header"
    fi
    
    # Copy new header
    cp -v "./openwrt_7628/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm" "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm"
    chmod 644 "/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm"
    echo "✅ Custom header installed"
else
    echo "⚠️ Custom header file not found: ./openwrt_7628/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm"
fi

# Step 9b: Install/Update LuCI Camera Module
echo "Installing/updating LuCI Camera module..."

# Create LuCI module directories
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/view
mkdir -p /usr/lib/lua/luci/i18n

# Copy LuCI controller files
if [ -d "./openwrt_7628/usr/lib/lua/luci/controller" ]; then
    echo "Copying LuCI controller files..."
    for controller_file in ./openwrt_7628/usr/lib/lua/luci/controller/*; do
        if [ -f "$controller_file" ]; then
            controller_name=$(basename "$controller_file")
            if [ -f "/usr/lib/lua/luci/controller/$controller_name" ]; then
                echo "🔄 Updating existing controller: $controller_name"
            else
                echo "🆕 Installing new controller: $controller_name"
            fi
            cp -v "$controller_file" "/usr/lib/lua/luci/controller/$controller_name"
            chmod 644 "/usr/lib/lua/luci/controller/$controller_name"
        fi
    done
fi

# Copy LuCI view files
if [ -d "./openwrt_7628/usr/lib/lua/luci/view" ]; then
    echo "Copying LuCI view files..."
    for view_file in ./openwrt_7628/usr/lib/lua/luci/view/*; do
        if [ -f "$view_file" ]; then
            view_name=$(basename "$view_file")
            if [ -f "/usr/lib/lua/luci/view/$view_name" ]; then
                echo "🔄 Updating existing view: $view_name"
            else
                echo "🆕 Installing new view: $view_name"
            fi
            cp -v "$view_file" "/usr/lib/lua/luci/view/$view_name"
            chmod 644 "/usr/lib/lua/luci/view/$view_name"
        fi
    done
fi

# Copy LuCI translation files
if [ -d "./openwrt_7628/usr/lib/lua/luci/i18n" ]; then
    echo "Copying LuCI translation files..."
    for i18n_file in ./openwrt_7628/usr/lib/lua/luci/i18n/*; do
        if [ -f "$i18n_file" ]; then
            i18n_name=$(basename "$i18n_file")
            if [ -f "/usr/lib/lua/luci/i18n/$i18n_name" ]; then
                echo "🔄 Updating existing translation: $i18n_name"
            else
                echo "🆕 Installing new translation: $i18n_name"
            fi
            cp -v "$i18n_file" "/usr/lib/lua/luci/i18n/$i18n_name"
            chmod 644 "/usr/lib/lua/luci/i18n/$i18n_name"
        fi
    done
fi

# Step 10: Enable services
echo "Enabling services..."
/etc/init.d/u3_service enable
/etc/init.d/cron enable
/etc/init.d/mjpg-streamer enable

# Step 11: Restart services
echo "Restarting services..."
/etc/init.d/mjpg-streamer restart
/etc/init.d/cron restart
/etc/init.d/u3_service restart

# Step 12: Clear LuCI cache and restart web server
echo "Clearing LuCI cache and restarting web server..."
rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart

# Step 13: Update version information with improved parsing
echo "Getting version information..."

# Get latest release info with better JSON parsing
RELEASE_JSON=$(wget -qO- "https://api.github.com/repos/o16s/avi_scripts/releases/latest" 2>/dev/null || echo "")

if [ -n "$RELEASE_JSON" ]; then
    # Parse version using multiple methods for reliability
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

# Get commit hash using git ls-remote (more reliable than API)
COMMIT_HASH=$(wget -qO- "https://api.github.com/repos/o16s/avi_scripts/git/refs/heads/main" 2>/dev/null | grep -o '"sha":"[^"]*"' | cut -d'"' -f4 | cut -c1-7 2>/dev/null || echo "unknown")

# Alternative method if API fails - try git ls-remote
if [ "$COMMIT_HASH" = "unknown" ] || [ -z "$COMMIT_HASH" ]; then
    # This requires git command, but fallback gracefully
    COMMIT_HASH=$(git ls-remote https://github.com/o16s/avi_scripts.git HEAD 2>/dev/null | cut -c1-7 || echo "unknown")
fi

UPDATE_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Create or update version env vars
cat > /etc/avi_version.env << EOL
AVI_SCRIPTS_VERSION="${VERSION}"
AVI_SCRIPTS_UPDATED="${UPDATE_DATE}"
AVI_SCRIPTS_COMMIT="${COMMIT_HASH}"
AVI_SCRIPTS_MANUAL_URL="https://o16s.github.io/avi_scripts/"
EOL

# Step 14: Cleanup
cd /
rm -rf /tmp/avi_scripts_temp /tmp/install.tar.gz

echo ""
echo "✅ Installation/Update complete!"
echo ""
echo "📋 Summary of changes:"
echo "  - All .sh scripts updated/installed in /bin/"
echo "  - Configuration files updated/added in /etc/config/"
echo "  - Init scripts updated/added in /etc/init.d/"
echo "  - LuCI Camera module updated/installed"
echo "  - Services restarted with new configurations"
echo ""
echo "📦 Version Information:"
echo "  - AVI Scripts Version: ${VERSION}"
echo "  - Commit: ${COMMIT_HASH}"
echo "  - Updated: ${UPDATE_DATE}"
echo ""
echo "🔍 To verify installation:"
echo "1. Check scripts: ls -la /bin/*.sh"
echo "2. Verify crontab: cat /etc/crontabs/root"
echo "3. Check service status: /etc/init.d/u3_service status"
echo "4. Test camera: curl http://localhost:8080/?action=snapshot > /tmp/test.jpg"
echo "5. Access LuCI camera: Services → Camera"
echo ""
echo "📝 If you need to modify environment variables:"
echo "   vi /root/.env"