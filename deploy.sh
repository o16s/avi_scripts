#!/bin/sh
# deploy.sh - Deploy AVI camera scripts to OpenWrt cameras over SSH.
# Runs on the local machine (macOS/Linux) which has internet access.
# Target cameras do NOT need internet connectivity.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$SCRIPT_DIR/packages/mips_24kc"
OPENWRT_VERSION="22.03.5"
ARCH="mips_24kc"
FEEDS_URL="https://downloads.openwrt.org/releases/$OPENWRT_VERSION/packages/$ARCH"
TARGET_URL="https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/ramips/mt76x8/packages"
REPO="o16s/avi_scripts"
REQUIRED_PKGS="v4l-utils mosquitto-client-nossl"
# Packages always present on OpenWrt — skip during dependency resolution
SKIP_PKGS="libc libgcc1 libpthread librt kernel"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [user@host ...]

Deploy AVI camera scripts to OpenWrt cameras over SSH.

Options:
  --fetch-packages  Download .ipk packages only (no deploy)
  -h, --help        Show this help

Examples:
  $(basename "$0") root@192.168.1.100
  $(basename "$0") root@192.168.1.100 root@192.168.1.101
  $(basename "$0") --fetch-packages
EOF
    exit 0
}

die() { printf "Error: %s\n" "$1" >&2; exit 1; }

# Download a URL to stdout. Works with curl or wget.
http_get() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

# Download a URL to a file. Returns 0 on success.
http_download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1" 2>/dev/null
    else
        wget -qO "$2" "$1" 2>/dev/null
    fi
}

# ---- Package resolution ----

fetch_package_indices() {
    printf "Fetching OpenWrt %s package indices for %s...\n" "$OPENWRT_VERSION" "$ARCH"
    mkdir -p "$PKG_DIR"
    _idx="$PKG_DIR/.Packages"
    : > "$_idx"

    for feed in base packages; do
        _url="$FEEDS_URL/$feed/Packages.gz"
        printf "  %s feed..." "$feed"
        http_get "$_url" | gunzip >> "$_idx"
        printf " ok\n"
        printf "\n" >> "$_idx"
    done

    printf "  target feed..."
    http_get "$TARGET_URL/Packages.gz" | gunzip >> "$_idx"
    printf " ok\n"
    printf "\n" >> "$_idx"

    printf "  %s packages indexed\n" "$(grep -c '^Package:' "$_idx")"
}

resolve_dependencies() {
    _idx="$PKG_DIR/.Packages"

    awk -v "roots=$REQUIRED_PKGS" -v "skip=$SKIP_PKGS" '
    BEGIN {
        n = split(skip, a); for (i = 1; i <= n; i++) skipset[a[i]] = 1
    }
    /^Package:/ { pkg = $2; deps[pkg] = ""; fname[pkg] = "" }
    /^Depends:/ { sub(/^Depends: /, ""); deps[pkg] = $0 }
    /^Filename:/ { fname[pkg] = $2 }
    END {
        n = split(roots, a)
        for (i = 1; i <= n; i++) { need[a[i]] = 1; queue[a[i]] = 1 }

        go = 1
        while (go) {
            go = 0
            for (p in queue) {
                if (seen[p]) continue; seen[p] = 1; go = 1
                if (deps[p] == "") continue
                tmp = deps[p]; gsub(/\([^)]*\)/, "", tmp)
                m = split(tmp, darr, ",")
                for (j = 1; j <= m; j++) {
                    split(darr[j], alts, "[|]"); d = alts[1]
                    gsub(/^[ \t]+|[ \t]+$/, "", d)
                    if (d == "" || d in skipset) continue
                    if (!(d in need)) { need[d] = 1; queue[d] = 1 }
                }
            }
        }
        for (p in need) {
            if (fname[p] != "") print fname[p]
            else print "MISSING:" p > "/dev/stderr"
        }
    }' "$_idx"
}

fetch_packages() {
    if [ -d "$PKG_DIR" ] && ls "$PKG_DIR"/*.ipk >/dev/null 2>&1; then
        # shellcheck disable=SC2012
        _n=$(ls "$PKG_DIR"/*.ipk | wc -l | tr -d ' ')
        printf "Using cached packages (%s .ipk files in %s)\n" "$_n" "$PKG_DIR"
        return 0
    fi

    fetch_package_indices

    printf "Resolving dependencies for: %s\n" "$REQUIRED_PKGS"
    _files=$(resolve_dependencies)
    [ -n "$_files" ] || die "No packages resolved — check package names"

    printf "Downloading .ipk files...\n"
    echo "$_files" | while IFS= read -r _f; do
        case "$_f" in MISSING:*) continue ;; esac
        _base=$(basename "$_f")
        if [ -f "$PKG_DIR/$_base" ]; then
            printf "  [cached]     %s\n" "$_base"
            continue
        fi
        _got=false
        for _url in "$FEEDS_URL/base/$_base" "$FEEDS_URL/packages/$_base" "$TARGET_URL/$_base"; do
            if http_download "$_url" "$PKG_DIR/$_base"; then
                _got=true
                break
            fi
        done
        if [ "$_got" = true ]; then
            printf "  [downloaded] %s\n" "$_base"
        else
            printf "  [FAILED]     %s\n" "$_base" >&2
            rm -f "$PKG_DIR/$_base"
        fi
    done

    # shellcheck disable=SC2012
    _n=$(ls "$PKG_DIR"/*.ipk 2>/dev/null | wc -l | tr -d ' ')
    printf "Package cache: %s files in %s\n" "$_n" "$PKG_DIR"
}

# ---- Version info ----

fetch_version_info() {
    printf "Fetching version info from GitHub...\n"
    VERSION="main"
    COMMIT_HASH="unknown"

    command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq / apt install jq)"

    _v=$(http_get "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null || true)
    [ -n "$_v" ] && VERSION="$_v"

    _c=$(http_get "https://api.github.com/repos/$REPO/git/refs/heads/main" 2>/dev/null \
        | jq -r '.object.sha // empty' 2>/dev/null | cut -c1-7 || true)
    [ -n "$_c" ] && COMMIT_HASH="$_c"

    UPDATE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    printf "  Version: %s  Commit: %s\n" "$VERSION" "$COMMIT_HASH"
}

# ---- Bundle creation ----

create_bundle() {
    printf "Creating deploy bundle...\n"
    BUNDLE="/tmp/avi_deploy_bundle.tar.gz"
    tar -czf "$BUNDLE" -C "$SCRIPT_DIR" openwrt_7628 packages/mips_24kc install_common.sh
    _kb=$(( $(wc -c < "$BUNDLE") / 1024 ))
    printf "  Bundle: %s (%s KB)\n" "$BUNDLE" "$_kb"
}

# ---- Remote deploy ----

deploy_to_camera() {
    _target="$1"

    printf "\n========== Deploying to %s ==========\n" "$_target"

    printf "  Uploading bundle...\n"
    if ! scp -O -o ConnectTimeout=10 "$BUNDLE" "${_target}:/tmp/avi_deploy.tar.gz"; then
        printf "  FAILED: scp upload to %s\n" "$_target" >&2
        return 1
    fi

    printf "  Running install...\n"
    # Variables are passed via exported env vars; the heredoc is quoted so
    # all $ references inside are expanded by the remote shell, not locally.
    # shellcheck disable=SC2029
    ssh -o ConnectTimeout=10 "$_target" \
        "export AVI_V='$VERSION' AVI_C='$COMMIT_HASH' AVI_D='$UPDATE_DATE'; sh" <<'DEPLOY_EOF'
set -e

echo "Extracting bundle..."
rm -rf /tmp/avi_deploy
mkdir -p /tmp/avi_deploy
tar -xzf /tmp/avi_deploy.tar.gz -C /tmp/avi_deploy

# -- Install packages --
echo "Checking dependencies..."
_need=false
command -v v4l2-ctl >/dev/null 2>&1 || _need=true
command -v mosquitto_pub >/dev/null 2>&1 || _need=true

if [ "$_need" = true ] && ls /tmp/avi_deploy/packages/mips_24kc/*.ipk >/dev/null 2>&1; then
    echo "Installing packages..."
    opkg install /tmp/avi_deploy/packages/mips_24kc/*.ipk 2>&1 || \
        echo "Warning: some packages may have failed to install"
else
    echo "Dependencies already installed"
fi

# -- Run shared install logic --
sh /tmp/avi_deploy/install_common.sh /tmp/avi_deploy/openwrt_7628 "$AVI_V" "$AVI_C" "$AVI_D"

# -- Cleanup --
rm -rf /tmp/avi_deploy /tmp/avi_deploy.tar.gz
DEPLOY_EOF
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        printf "  FAILED: remote install on %s\n" "$_target" >&2
        return 1
    fi

    printf "  Done: %s\n" "$_target"
}

# ---- Main ----

FETCH_ONLY=false
TARGETS=""
for arg in "$@"; do
    case "$arg" in
        --fetch-packages) FETCH_ONLY=true ;;
        -h|--help) usage ;;
        -*) die "Unknown option: $arg" ;;
        *) TARGETS="$TARGETS $arg" ;;
    esac
done

if [ "$FETCH_ONLY" = false ] && [ -z "$TARGETS" ]; then
    usage
fi

fetch_packages

if [ "$FETCH_ONLY" = true ]; then
    exit 0
fi

fetch_version_info
create_bundle

_failed=0
for _t in $TARGETS; do
    if deploy_to_camera "$_t"; then
        :
    else
        printf "FAILED: %s\n" "$_t" >&2
        _failed=$((_failed + 1))
    fi
done

rm -f "$BUNDLE"

if [ "$_failed" -gt 0 ]; then
    printf "\n%s deployment(s) failed.\n" "$_failed" >&2
    exit 1
fi

printf "\nAll deployments successful.\n"
