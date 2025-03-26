#!/bin/sh

# Load environment variables
. /root/.env

# Get the br-lan IP address
IP_ADDRESS=$(ip addr show br-lan | grep -w inet | awk '{print $2}' | cut -d/ -f1)

# Report the IP address to uptime monitoring
curl -s "${UPTIME_API_URL}?status=up&msg=IP_${IP_ADDRESS}"

# Get hostname
HOSTNAME=$(uname -n)

# Get basic system metrics
LOAD=$(cat /proc/loadavg | awk '{print $1}')
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
DISK_USAGE=$(df -h | grep -E '/overlay|/$' | head -1 | awk '{print $5}' | tr -d '%')
PING_MS=$(ping -c 1 8.8.8.8 | grep 'time=' | cut -d '=' -f 4 | cut -d ' ' -f 1 || echo "0")

# Check if mjpg-streamer is running
if ps | grep "mjpg_streamer" | grep -v grep >/dev/null; then
  MJPG_RUNNING=1
else
  MJPG_RUNNING=0
fi

# Check if u3_service is running
if ps | grep "/bin/u3.sh" | grep -v grep >/dev/null; then
  U3_RUNNING=1
else
  U3_RUNNING=0
fi

# Count video devices
VIDEO_DEVICES_COUNT=$(ls -1 /dev/video* 2>/dev/null | wc -l || echo "0")

# Create data point in line protocol format
DATA="openwrt_7628,host=$HOSTNAME,ip=$IP_ADDRESS load=$LOAD,mem_total=$MEM_TOTAL,mem_free=$MEM_FREE,disk_usage=$DISK_USAGE,ping_ms=$PING_MS,mjpg_running=$MJPG_RUNNING,u3_running=$U3_RUNNING,video_devices=$VIDEO_DEVICES_COUNT"

# Send to InfluxDB
curl -s -XPOST "https://${INFLUX_HOST}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}" \
  --header "Authorization: Token ${INFLUX_TOKEN}" \
  --data-binary "$DATA"
