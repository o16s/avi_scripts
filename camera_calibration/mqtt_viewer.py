#!/usr/bin/env python3
"""MQTT snapshot viewer for AVI cameras.

Subscribes to one or more MQTT topics and displays received JPEG snapshots
side by side in an OpenCV window with overlaid stats, image age, and a
frame-diff history graph.

Usage:
    uv run mqtt_viewer.py <broker> <topic> [<topic> ...] [--port 1883] [--username USER] [--password PASS]

Example:
    uv run mqtt_viewer.py mqtt.example.com cameras/site1/cam1
    uv run mqtt_viewer.py mqtt.example.com cameras/site1/cam1 cameras/E438191F37F8
"""

import argparse
import json
import threading
import time
from collections import deque

import cv2
import numpy as np
import paho.mqtt.client as mqtt

DIFF_HISTORY_LEN = 60  # number of samples to keep per camera
GRAPH_H = 80           # graph height in pixels
GRAPH_W = 240          # graph width in pixels
STAT_KEYS = ("img_brightness", "img_green_pct", "img_diff_pct",
             "load", "mem_available_kb", "gain", "exposure_auto")

lock = threading.Lock()

# per-camera state, keyed by topic
cam_frames = {}       # {topic: np.ndarray}
cam_status = {}       # {topic: dict}
cam_frame_time = {}   # {topic: float} — time.time() when snapshot arrived
cam_diff_hist = {}    # {topic: deque of (time, diff_pct)}


def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code == 0:
        for topic in userdata["topics"]:
            client.subscribe(f"{topic}/snapshot")
            client.subscribe(f"{topic}/status")
            print(f"  subscribed to {topic}/#")
    else:
        print(f"Connection failed: {reason_code}")


def on_disconnect(client, userdata, flags, reason_code, properties=None):
    if reason_code != 0:
        print(f"Disconnected (rc={reason_code}), will reconnect automatically")


def on_message(client, userdata, msg):
    topics = userdata["topics"]

    for topic in topics:
        if msg.topic == f"{topic}/snapshot":
            buf = np.frombuffer(msg.payload, dtype=np.uint8)
            frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
            if frame is not None:
                with lock:
                    cam_frames[topic] = frame
                    cam_frame_time[topic] = time.time()
            return

        if msg.topic == f"{topic}/status":
            try:
                status = json.loads(msg.payload)
                with lock:
                    cam_status[topic] = status
                    # track diff history
                    if topic not in cam_diff_hist:
                        cam_diff_hist[topic] = deque(maxlen=DIFF_HISTORY_LEN)
                    diff = status.get("img_diff_pct")
                    if diff is not None:
                        try:
                            cam_diff_hist[topic].append((time.time(), float(diff)))
                        except (ValueError, TypeError):
                            pass
                # print summary
                cam = status.get("camera", topic.rsplit("/", 1)[-1])
                parts = [f"[{cam}]"]
                for key in ("timestamp", "img_brightness", "img_green_pct",
                            "img_diff_pct", "load"):
                    if key in status:
                        parts.append(f"{key}={status[key]}")
                print("  ".join(parts))
            except json.JSONDecodeError:
                print(f"Status (raw): {msg.payload[:200]}")
            return


def draw_graph(hist, width=GRAPH_W, height=GRAPH_H):
    """Draw a diff_pct sparkline graph. Returns a BGR image."""
    canvas = np.zeros((height, width, 3), dtype=np.uint8)

    if len(hist) < 2:
        cv2.putText(canvas, "diff %", (4, 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (100, 100, 100), 1)
        return canvas

    values = [v for _, v in hist]
    max_val = max(max(values), 1.0)

    # grid lines at 25% and 50%
    for pct in (25, 50):
        if pct <= max_val:
            y = height - 1 - int((pct / max_val) * (height - 20))
            cv2.line(canvas, (0, y), (width, y), (40, 40, 40), 1)
            cv2.putText(canvas, f"{pct}%", (2, y - 2),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.3, (80, 80, 80), 1)

    # plot line
    n = len(values)
    step = (width - 1) / max(n - 1, 1)
    pts = []
    for i, v in enumerate(values):
        x = int(i * step)
        y = height - 1 - int((v / max_val) * (height - 20))
        pts.append((x, y))

    for i in range(len(pts) - 1):
        # color: green < 5%, yellow 5-20%, red > 20%
        v = values[i + 1]
        if v < 5:
            color = (0, 180, 0)
        elif v < 20:
            color = (0, 180, 220)
        else:
            color = (0, 0, 220)
        cv2.line(canvas, pts[i], pts[i + 1], color, 2)

    # latest value label
    latest = values[-1]
    cv2.putText(canvas, f"diff: {latest:.1f}%", (4, 14),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)

    return canvas


def draw_stats_overlay(panel, topic, now):
    """Draw stats text and diff graph on the panel in-place."""
    h, w = panel.shape[:2]

    # camera label
    label = topic.rsplit("/", 1)[-1]
    cv2.putText(panel, label, (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)

    # image age
    with lock:
        ft = cam_frame_time.get(topic)
        status = cam_status.get(topic, {})
        hist = list(cam_diff_hist.get(topic, []))

    if ft is not None:
        age = now - ft
        if age < 60:
            age_str = f"{age:.0f}s ago"
        else:
            age_str = f"{age / 60:.1f}m ago"
        cv2.putText(panel, age_str, (10, 58),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 200, 255), 1)

    # stats text — right-aligned column
    y = 30
    line_h = 22
    stat_lines = []
    for key in STAT_KEYS:
        val = status.get(key)
        if val is not None:
            short = key.replace("img_", "").replace("_pct", "%").replace("_kb", "KB")
            stat_lines.append(f"{short}: {val}")

    for line in stat_lines:
        text_size = cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)[0]
        x = w - text_size[0] - 10
        # background for readability
        cv2.rectangle(panel, (x - 4, y - 14), (w - 4, y + 4), (0, 0, 0), -1)
        cv2.putText(panel, line, (x, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
        y += line_h

    # diff graph — bottom-left
    if hist:
        graph = draw_graph(hist)
        gh, gw = graph.shape[:2]
        gy = h - gh - 8
        gx = 8
        if gy > 0 and gx + gw <= w and gy + gh <= h:
            # semi-transparent background
            roi = panel[gy:gy + gh, gx:gx + gw]
            cv2.addWeighted(roi, 0.3, np.zeros_like(roi), 0.7, 0, roi)
            # overlay graph (non-black pixels only)
            mask = np.any(graph > 0, axis=2)
            roi[mask] = graph[mask]


def build_canvas(topics, target_height=720):
    """Stitch frames side by side, resizing to equal height."""
    panels = []
    now = time.time()

    with lock:
        frame_copy = {t: f.copy() for t, f in cam_frames.items()}

    for topic in topics:
        frame = frame_copy.get(topic)
        if frame is not None:
            h, w = frame.shape[:2]
            scale = target_height / h
            panel = cv2.resize(frame, (int(w * scale), target_height))
        else:
            panel = np.full((target_height, int(target_height * 4 / 3), 3),
                            40, dtype=np.uint8)
            label = topic.rsplit("/", 1)[-1]
            cv2.putText(panel, f"waiting: {label}", (10, target_height // 2),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (128, 128, 128), 2)

        draw_stats_overlay(panel, topic, now)
        panels.append(panel)

    if not panels:
        return None
    return np.hstack(panels)


def main():
    parser = argparse.ArgumentParser(description="MQTT snapshot viewer for AVI cameras")
    parser.add_argument("broker", help="MQTT broker hostname")
    parser.add_argument("topics", nargs="+", metavar="topic",
                        help="Base MQTT topic(s) (e.g. cameras/site1/cam1)")
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port (default: 1883)")
    parser.add_argument("--username", help="MQTT username")
    parser.add_argument("--password", help="MQTT password")
    args = parser.parse_args()

    userdata = {"topics": args.topics}
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=userdata)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    if args.username:
        client.username_pw_set(args.username, args.password)

    print(f"Connecting to {args.broker}:{args.port} ({len(args.topics)} camera(s))...")
    client.connect(args.broker, args.port)
    client.loop_start()

    window_name = "MQTT Snapshot Viewer"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    print("Waiting for snapshots... press 'q' or ESC to quit")

    try:
        while True:
            canvas = build_canvas(args.topics)
            if canvas is not None:
                cv2.imshow(window_name, canvas)

            key = cv2.waitKey(100) & 0xFF
            if key == ord("q") or key == 27:
                break

            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                break
    except KeyboardInterrupt:
        pass
    finally:
        print("Shutting down...")
        client.loop_stop()
        client.disconnect()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
