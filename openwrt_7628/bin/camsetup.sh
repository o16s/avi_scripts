#!/bin/sh
# opkg update && opkg install v4l-utils
# for camera type: AS-2MUSB12J
# readout settings with: v4l2-ctl --list-ctrls-menus
#!/bin/sh

VIDEO_DEVICE="/dev/video0"

# Basic settings
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=brightness=0
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=contrast=32
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=saturation=64
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=hue=0

# Re-enable auto white balance (this should fix the green tint)
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=white_balance_temperature_auto=1

# Note: white_balance_temperature becomes inactive when auto is enabled

v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=gamma=100
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=gain=20
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=power_line_frequency=2
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=sharpness=3
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=backlight_compensation=1

# Use aperture priority mode for automatic brightness response
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=exposure_auto=3
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=exposure_auto_priority=1
