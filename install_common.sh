#!/bin/sh
# install_common.sh - Shared install logic for AVI camera scripts.
# Called by install.sh (on-device) and deploy.sh (remote).
# Usage: sh install_common.sh <source_dir> <version> <commit> <date>
set -e

S="${1:?Usage: install_common.sh <source_dir> <version> <commit> <date>}"
VERSION="${2:?Missing version argument}"
COMMIT_HASH="${3:?Missing commit argument}"
UPDATE_DATE="${4:?Missing date argument}"

# -- Scripts --
echo "Installing scripts..."
mkdir -p /bin
if [ -d "$S/bin" ]; then
    for f in "$S"/bin/*.sh; do
        [ -f "$f" ] || continue
        cp "$f" /bin/
        chmod +x "/bin/$(basename "$f")"
        echo "  $(basename "$f")"
    done
fi

# -- Config files --
echo "Installing config files..."
mkdir -p /etc/config
if [ -d "$S/etc/config" ]; then
    for f in "$S"/etc/config/*; do
        [ -f "$f" ] || continue
        cp "$f" "/etc/config/$(basename "$f")"
        echo "  $(basename "$f")"
    done
fi

# -- Init scripts --
echo "Installing init scripts..."
if [ -d "$S/etc/init.d" ]; then
    for f in "$S"/etc/init.d/*; do
        [ -f "$f" ] || continue
        cp "$f" "/etc/init.d/$(basename "$f")"
        chmod +x "/etc/init.d/$(basename "$f")"
        echo "  $(basename "$f")"
    done
fi

# -- Crontab --
echo "Installing crontab..."
mkdir -p /etc/crontabs
[ -f /etc/crontabs/root ] && cp /etc/crontabs/root /etc/crontabs/root.backup
cp "$S/etc/crontabs/root" /etc/crontabs/root

# -- Environment file (preserve existing) --
if [ -f "$S/root/example.env" ]; then
    if [ ! -f /root/.env ]; then
        cp "$S/root/example.env" /root/.env
        echo "Created /root/.env from example -- edit with your settings!"
    else
        echo "Environment file /root/.env already exists, not overwriting."
        if ! diff -q "$S/root/example.env" /root/.env >/dev/null 2>&1; then
            echo "TIP: Check example.env for any new configuration variables"
        fi
    fi
fi

# -- Additional root files --
if [ -d "$S/root" ]; then
    for f in "$S"/root/*; do
        [ -f "$f" ] && [ "$(basename "$f")" != "example.env" ] || continue
        cp "$f" "/root/$(basename "$f")"
    done
fi

# -- Logo --
mkdir -p /www/luci-static
if [ -f "$S/docs/source/_static/avi_logo_w.png" ]; then
    cp "$S/docs/source/_static/avi_logo_w.png" /www/luci-static/avi_logo_w.png
    chmod 644 /www/luci-static/avi_logo_w.png
fi

# -- Custom LuCI header (with backup of original) --
_hdr="$S/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm"
_dest="/usr/lib/lua/luci/view/themes/bootstrap-dark/header.htm"
if [ -f "$_hdr" ]; then
    [ -f "$_dest" ] && [ ! -f "${_dest}.original" ] && cp "$_dest" "${_dest}.original"
    cp "$_hdr" "$_dest"
    chmod 644 "$_dest"
fi

# -- LuCI module files --
mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view /usr/lib/lua/luci/i18n
for d in controller view i18n; do
    [ -d "$S/usr/lib/lua/luci/$d" ] || continue
    for f in "$S/usr/lib/lua/luci/$d"/*; do
        [ -f "$f" ] || continue
        cp "$f" "/usr/lib/lua/luci/$d/$(basename "$f")"
        chmod 644 "/usr/lib/lua/luci/$d/$(basename "$f")"
    done
done

# -- Remove deprecated services --
if [ -f /etc/init.d/audio-capture ]; then
    /etc/init.d/audio-capture stop 2>/dev/null || true
    /etc/init.d/audio-capture disable 2>/dev/null || true
    rm -f /etc/init.d/audio-capture
    echo "Removed deprecated: audio-capture"
fi

# -- Enable & restart services --
echo "Enabling services..."
/etc/init.d/u3_service enable
/etc/init.d/cron enable

echo "Restarting services..."
/etc/init.d/cron restart
/etc/init.d/u3_service restart

rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart

# -- Version info --
cat > /etc/avi_version.env <<EOL
AVI_SCRIPTS_VERSION="${VERSION}"
AVI_SCRIPTS_UPDATED="${UPDATE_DATE}"
AVI_SCRIPTS_COMMIT="${COMMIT_HASH}"
AVI_SCRIPTS_MANUAL_URL="https://o16s.github.io/avi_scripts/"
EOL

echo ""
echo "Install complete!"
cat /etc/avi_version.env
