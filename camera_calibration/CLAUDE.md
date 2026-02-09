# camera_calibration — Calibration tools and MQTT viewer

Desktop Python tools for AVI camera calibration and remote monitoring.

## Setup

Uses `uv` for dependency management. No conda, no pip.

```
cd camera_calibration
uv sync
```

## File layout

```
camera_calibration/
├── pyproject.toml              # uv project config (numpy, opencv-python, paho-mqtt, pyusb)
├── calibrate.py                # Fisheye camera calibration with live checkerboard detection
├── diag.py                     # USB/UVC device diagnostic (lists cameras, reads/tests controls)
├── mqtt_viewer.py              # MQTT subscriber that displays camera snapshots in an OpenCV window
├── calibration_images/         # Captured checkerboard images for calibration
├── camera_calibration.npz      # Saved calibration matrices (K, D, rvecs, tvecs)
└── camera_calibration.txt      # Human-readable calibration results
```

## Scripts

### calibrate.py

Interactive fisheye calibration via local USB camera. Opens a live OpenCV window with checkerboard corner detection and sharpness metering. Keys: `c` capture, `k` calibrate, `r` reset, `q` quit. Outputs `fisheye_calibration.npz` and `fisheye_calibration.txt`.

### diag.py

Enumerates all USB devices via pyusb, identifies UVC cameras, and probes standard UVC controls (brightness, contrast, exposure, focus, etc.) via USB control transfers. May need `sudo` on macOS.

### mqtt_viewer.py

Subscribes to an AVI camera's MQTT topics and displays snapshots in real time.

```
uv run mqtt_viewer.py <broker> <topic> [--port 1883] [--username USER] [--password PASS]
```

The camera publishes:
- `{topic}/snapshot` — raw JPEG binary (via `mosquitto_pub -f`)
- `{topic}/status` — JSON with timestamp, camera settings, image metrics, system stats

The viewer decodes JPEGs with `cv2.imdecode` and prints status fields to the terminal. Press `q` or ESC to quit.

## Conventions

- **Dependencies**: Add to `pyproject.toml` `[project.dependencies]`, then `uv sync`. No requirements.txt.
- **Python**: Requires >=3.10. Use argparse for CLI scripts.
- **OpenCV GUI**: Always run `imshow`/`waitKey` in the main thread. Use background threads for I/O (MQTT, network).
- **paho-mqtt**: Use v2 callback API (`CallbackAPIVersion.VERSION2`).
