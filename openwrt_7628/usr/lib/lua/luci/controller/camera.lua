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
end

function action_snapshot()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    -- Get snapshot from mjpg-streamer
    local snapshot_data = sys.exec("curl -s --max-time 5 'http://localhost:8080/?action=snapshot' 2>/dev/null")
    
    if snapshot_data and #snapshot_data > 1000 then  -- Basic size check
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