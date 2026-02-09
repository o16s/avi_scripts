-- Camera controller for OpenWrt
module("luci.controller.camera", package.seeall)

function index()
    -- Main camera entry under Services
    entry({"admin", "services", "camera"}, template("camera"), _("Camera"), 60)
    
    -- Environment settings page
    entry({"admin", "services", "camera", "env"}, template("env"), _("Settings"), 61)
    
    -- Snapshot endpoint
    entry({"admin", "services", "camera", "snapshot"}, call("action_snapshot"))
    
    -- Camera setup endpoint
    entry({"admin", "services", "camera", "setup"}, call("action_setup"))

    -- Latest snapshot image
    entry({"admin", "services", "camera", "latest"}, call("action_latest"))

    -- Stream toggle (POST) and status (GET)
    local st = entry({"admin", "services", "camera", "stream_toggle"}, call("action_stream_toggle"))
    st.leaf = true
    entry({"admin", "services", "camera", "stream_status"}, call("action_stream_status"))
end

function action_snapshot()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local nixio = require "nixio"

    local tmp_file = "/tmp/luci_snapshot_" .. os.time() .. ".jpg"
    local snapshot_data = nil

    -- Check if mjpg-streamer is running
    local mjpg_running = (sys.exec("pgrep mjpg_streamer 2>/dev/null") or "") ~= ""

    local started_mjpg = false
    if not mjpg_running then
        -- Briefly start mjpg-streamer for a clean capture
        sys.exec("/etc/init.d/mjpg-streamer start 2>/dev/null")
        sys.exec("sleep 2")
        started_mjpg = true
    end

    snapshot_data = sys.exec("curl -s --max-time 5 'http://localhost:8080/?action=snapshot' 2>/dev/null")

    if started_mjpg then
        sys.exec("/etc/init.d/mjpg-streamer stop 2>/dev/null")
    end

    if snapshot_data and #snapshot_data > 1000 then
        http.header("Content-Type", "image/jpeg")
        http.header("Content-Disposition", "inline; filename=snapshot_" .. os.date("%Y%m%d_%H%M%S") .. ".jpg")
        http.write(snapshot_data)
    else
        http.status(404, "Not Found")
        http.header("Content-Type", "text/plain")
        http.write("Camera not available")
    end
end

function action_setup()
    local http = require "luci.http"
    local sys = require "luci.sys"

    -- Run camsetup.sh script
    local setup_output = sys.exec("/bin/camsetup.sh 2>&1")

    -- Return JSON response
    http.header("Content-Type", "application/json")

    if setup_output then
        http.write('{"success": true, "output": "' .. setup_output:gsub('"', '\\"'):gsub('\n', '\\n') .. '"}')
    else
        http.write('{"success": false, "output": "Failed to execute camera setup"}')
    end
end

function action_latest()
    local http = require "luci.http"
    local fs = require "nixio.fs"

    local path = "/tmp/latest_snapshot.jpg"
    local data = fs.readfile(path)

    if data and #data > 0 then
        http.header("Content-Type", "image/jpeg")
        http.header("Cache-Control", "no-cache")
        http.write(data)
    else
        http.status(404, "Not Found")
        http.header("Content-Type", "text/plain")
        http.write("No snapshot available yet")
    end
end

function action_stream_toggle()
    local http = require "luci.http"
    local sys = require "luci.sys"

    local streaming = (sys.exec("pgrep mjpg_streamer 2>/dev/null") or "") ~= ""

    if streaming then
        -- Stop streaming
        sys.exec("/etc/init.d/mjpg-streamer stop 2>/dev/null")
        -- Kill background timer if running
        local pid_data = sys.exec("cat /tmp/stream_timer.pid 2>/dev/null") or ""
        local timer_pid = pid_data:match("(%d+)")
        if timer_pid then
            sys.exec("kill " .. timer_pid .. " 2>/dev/null")
        end
        os.remove("/tmp/stream_expires")
        os.remove("/tmp/stream_timer.pid")

        http.header("Content-Type", "application/json")
        http.write('{"streaming":false}')
    else
        -- Start streaming
        sys.exec("/etc/init.d/mjpg-streamer start 2>/dev/null")
        local expires = os.time() + 300
        local ef = io.open("/tmp/stream_expires", "w")
        if ef then
            ef:write(tostring(expires))
            ef:close()
        end
        -- Spawn background timer to auto-stop after 5 minutes, save its PID
        -- Redirect subshell stdout/stderr so sys.exec (io.popen) doesn't block on the pipe
        sys.exec("( sleep 300; /etc/init.d/mjpg-streamer stop; rm -f /tmp/stream_expires /tmp/stream_timer.pid ) >/dev/null 2>&1 & echo $! > /tmp/stream_timer.pid")

        http.header("Content-Type", "application/json")
        http.write('{"streaming":true,"expires_in":300}')
    end
end

function action_stream_status()
    local http = require "luci.http"
    local sys = require "luci.sys"

    local streaming = (sys.exec("pgrep mjpg_streamer 2>/dev/null") or "") ~= ""
    local expires_in = 0

    if streaming then
        local ef = io.open("/tmp/stream_expires", "r")
        if ef then
            local ts = tonumber(ef:read("*a"))
            ef:close()
            if ts then
                expires_in = ts - os.time()
                if expires_in < 0 then expires_in = 0 end
            end
        end
    end

    http.header("Content-Type", "application/json")
    http.write('{"streaming":' .. tostring(streaming) .. ',"expires_in":' .. tostring(expires_in) .. '}')
end