#!/bin/sh
# Camera setup script that reads settings from .env file
# for camera type: AS-2MUSB12J

VIDEO_DEVICE="/dev/video0"

# Load .env file
if [ -f "/root/.env" ]; then
    . "/root/.env"
else
    echo "Warning: No .env file found, using defaults"
fi

# Set defaults if variables don't exist
CAM_BRIGHTNESS="${CAM_BRIGHTNESS:-0}"
CAM_CONTRAST="${CAM_CONTRAST:-32}"
CAM_SATURATION="${CAM_SATURATION:-64}"
CAM_HUE="${CAM_HUE:-0}"
CAM_GAMMA="${CAM_GAMMA:-100}"
CAM_GAIN="${CAM_GAIN:-20}"
CAM_SHARPNESS="${CAM_SHARPNESS:-3}"
CAM_BACKLIGHT="${CAM_BACKLIGHT:-1}"
CAM_AUTO_WB="${CAM_AUTO_WB:-1}"
CAM_AUTO_EXP="${CAM_AUTO_EXP:-1}"

echo "Applying camera settings from .env file..."

# Basic settings
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=brightness=$CAM_BRIGHTNESS
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=contrast=$CAM_CONTRAST
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=saturation=$CAM_SATURATION
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=hue=$CAM_HUE

# White balance
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=white_balance_temperature_auto=$CAM_AUTO_WB

# Advanced settings
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=gamma=$CAM_GAMMA
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=gain=$CAM_GAIN
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=power_line_frequency=2
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=sharpness=$CAM_SHARPNESS
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=backlight_compensation=$CAM_BACKLIGHT

# Exposure settings
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=exposure_auto=3
v4l2-ctl -d $VIDEO_DEVICE --set-ctrl=exposure_auto_priority=$CAM_AUTO_EXP

echo "Camera settings applied successfully"
echo "  Brightness: $CAM_BRIGHTNESS, Contrast: $CAM_CONTRAST, Saturation: $CAM_SATURATION"
echo "  Gamma: $CAM_GAMMA, Gain: $CAM_GAIN, Sharpness: $CAM_SHARPNESS"
echo "  Auto WB: $CAM_AUTO_WB, Auto Exposure Priority: $CAM_AUTO_EXP"