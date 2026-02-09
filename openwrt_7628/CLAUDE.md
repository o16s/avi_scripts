# openwrt_7628 — Anisca Vision AVI-1-1 Camera System

On-device software for the **AVI-1-1** OpenWrt camera (MediaTek MT7628AN, MIPS).

## Platform constraints

- **OpenWrt 22.03.5** (r20134-5f15225c1e) — BusyBox ash, NOT bash
- **POSIX sh only** — no arrays, no `[[ ]]`, no `${var//pat/rep}`, no `local -a`, no process substitution `<()`
- ~128 MB RAM, limited flash — no Node, no Python, no heavy runtimes
- Camera: USB UVC (AS-2MUSB12J) via mjpg-streamer (used for both snapshots and live streaming)
- GPIO 491 controls USB load switch (must be toggled before camera access)

## File layout

```
openwrt_7628/
├── bin/
│   ├── u3.sh              # Main capture loop: snapshot → privacy mask → image metrics → Azure upload (optional) → MQTT
│   ├── camsetup.sh         # Applies v4l2 camera hardware settings from .env
│   └── report_ip.sh        # Sends system metrics to InfluxDB (runs every minute via cron)
├── etc/
│   ├── config/camera        # UCI config (currently just capture interval)
│   ├── crontabs/root        # Cron: report_ip every min, daily 3:30am restart, u3 watchdog every 5min
│   └── init.d/
│       └── u3_service       # procd service: loops u3.sh with UPLOAD_INTERVAL sleep
├── root/
│   └── example.env          # Template for /root/.env (all runtime config lives here)
├── usr/lib/lua/luci/
│   ├── controller/camera.lua  # LuCI routes: camera page, env settings, snapshot endpoint, setup endpoint
│   ├── view/
│   │   ├── camera.htm         # Snapshot-first camera page with click-to-stream, version info, update checker
│   │   └── env.htm            # Settings form — writes /root/.env and UCI mjpg-streamer config
│   ├── view/themes/bootstrap-dark/
│   │   └── header.htm         # Custom LuCI header with AVI branding
│   └── i8n/camera.en.lua      # English translation strings
└── docs/                      # Sphinx documentation (build artifacts, not deployed to device)
```

## How configuration works

All runtime config is in `/root/.env` — a flat file of `KEY="value"` pairs, sourced by shell scripts with `. /root/.env`. The LuCI env.htm page reads/writes this file directly.

Key variables (see `root/example.env` for full list):
- `AZURE_ENABLED` — toggle Azure Blob uploads (default OFF)
- `STORAGE_ACCOUNT_NAME`, `CONTAINER_NAME`, `SAS_TOKEN` — Azure Blob Storage
- `CUSTOMER`, `CAMNAME` — blob path prefix: `CUSTOMER/DATE/CAMNAME/snapshot_TIME.jpg`
- `UPLOAD_INTERVAL` — seconds between capture cycles (30–3600)
- `POLYGON` — ImageMagick privacy mask coordinates ("x1,y1 x2,y2 ...")
- `CAM_*` — v4l2 hardware controls (brightness, contrast, gain, WB temp, exposure mode/value, power line freq, etc.)
- `UPTIME_PING` — heartbeat URL pinged on successful capture
- `INFLUX_*` — InfluxDB v2 credentials for metrics reporting
- `IMAGE_METRICS_ENABLED` — toggle for RGB/brightness/GCC/frame-diff computation (~6s per cycle on MIPS)
- `MQTT_ENABLED`, `MQTT_BROKER`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD` — MQTT broker connection
- `MQTT_TOPIC`, `MQTT_QOS`, `MQTT_RETAIN`, `MQTT_UPLOAD_IMAGE` — MQTT publishing options

**UCI** is only used for mjpg-streamer settings (`/etc/config/mjpg-streamer`), managed via `uci` commands in `env.htm`.

## Data flow

```
u3_service start_service():
  GPIO 491 HIGH + sleep 10       (one-time per service start)
  camsetup.sh                     (one-time per service start)
  launch loop → u3.sh + sleep (min 30s, max 3600s)

u3.sh (each cycle):
       1. Source /root/.env
       2. Acquire flock /var/lock/u3.lock
       3. capture_snapshot() → /tmp/snapshot_TIME.jpg
          - mjpg-streamer running? → curl localhost:8080 snapshot
          - otherwise → briefly start mjpg-streamer, grab snapshot, stop it
       4. blacken_regions (ImageMagick polygon if POLYGON set)
       5. If IMAGE_METRICS_ENABLED: compute_image_metrics (RGB, brightness, GCC, frame diff)
       6. cp snapshot → /tmp/latest_snapshot.jpg (for LuCI camera UI)
       7. Heartbeat ping to UPTIME_PING
       8. If AZURE_ENABLED: upload snapshot to Azure (latest + timestamped)
       9. If MQTT_ENABLED: publish_to_mqtt (snapshot image + status JSON with metrics)
      10. Cleanup temp files

Camera UI (camera.htm):
  - Default: shows /tmp/latest_snapshot.jpg, auto-refreshes every 30s
  - Click image → starts mjpg-streamer for 5min live stream with countdown timer
  - Stream auto-stops after timeout, falls back to snapshot view

On failure: exit 1 → procd respawn → start_service() re-runs GPIO + camsetup
Watchdog cron: only starts service if enabled in rc.d AND not running
```

## install.sh deployment

`install.sh` (repo root) runs on-device and:
1. Downloads the repo tarball from GitHub
2. Copies `openwrt_7628/bin/*.sh` → `/bin/`
3. Copies `openwrt_7628/etc/config/*` → `/etc/config/`
4. Copies `openwrt_7628/etc/init.d/*` → `/etc/init.d/` (chmod +x)
5. Installs crontab (backs up existing)
6. Copies `example.env` → `/root/.env` only if `.env` doesn't exist
7. Installs LuCI files (controller, views, i18n, header, logo)
8. Installs `mosquitto-client` package (for MQTT publishing)
9. Enables and restarts services (u3_service, cron, uhttpd — mjpg-streamer is opt-in)
10. Writes `/etc/avi_version.env` with version/commit info

The repo tree mirrors the device filesystem: `openwrt_7628/bin/u3.sh` → `/bin/u3.sh`.

## Conventions

- **Shell**: `#!/bin/sh` — POSIX-compliant, no bashisms. Test with `shellcheck -s sh`.
- **Logging**: Use `logger -p daemon.{info,warn,err,debug} -t "scriptname"` (goes to syslog/logread).
- **Error handling**: Check command exit codes. Use `|| exit 1` or `|| return 1` for critical failures.
- **Temp files**: Write to `/tmp/`, clean up with `rm -f` after use.
- **Locking**: Use `flock` to prevent concurrent instances of u3.sh.
- **LuCI views**: HTM templates with `<%lua%>` blocks. Use `luci.xml.pcdata()` for escaping user content. No emojis — use plain ASCII text for all UI labels and messages.
- **LuCI controller**: Lua module using `luci.dispatcher` entry points. Key endpoints: `camera` (main page), `camera/env` (settings), `camera/snapshot` (live capture), `camera/latest` (cached snapshot via `nixio.fs.readfile`), `camera/stream_toggle` / `camera/stream_status` (on-demand streaming).
- **Config values**: Always provide defaults with `${VAR:-default}` pattern.
- **Quoting**: Always quote `"$variables"` in shell scripts — unquoted expansion breaks on spaces.
- **No new dependencies**: The device has limited flash. Don't add packages without confirming they're available in OpenWrt 22.03.
- **Feature toggles**: Boolean features in `.env` use `"true"`/`"false"` strings. In shell: `if [ "${VAR:-true}" = "true" ]`. In env.htm: checkbox with `value="1"`, read as `http.formvalue("name") and "true" or "false"`, default to `"true"` when missing from `.env`.

## Verifying changes

- **Syntax check shell scripts**: `shellcheck -s sh bin/*.sh` (catches bashisms and common bugs)
- **Read-through LuCI Lua**: No local test harness — verify Lua syntax with `luac -p file.lua`
- **On-device testing**: SSH to device, run `install.sh`, then:
  - `logread -f` — watch syslog for u3.sh / u3_service messages
  - `/etc/init.d/u3_service restart` — restart capture loop
  - `curl http://localhost:8080/?action=snapshot > /tmp/test.jpg` — test camera
  - `cat /root/.env` — verify config
  - LuCI: Services > Camera — verify web UI
