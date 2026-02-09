#!/usr/bin/env python3
"""MQTT snapshot viewer for AVI cameras.

Subscribes to an MQTT topic and displays received JPEG snapshots
in an OpenCV window. Also prints status JSON to the terminal.

Usage:
    uv run mqtt_viewer.py <broker> <topic> [--port 1883] [--username USER] [--password PASS]

Example:
    uv run mqtt_viewer.py mqtt.example.com cameras/site1/cam1
"""

import argparse
import json
import sys
import threading

import cv2
import numpy as np
import paho.mqtt.client as mqtt


latest_frame = None
frame_lock = threading.Lock()


def on_connect(client, userdata, flags, reason_code, properties=None):
    topic = userdata["topic"]
    if reason_code == 0:
        print(f"Connected to broker, subscribing to {topic}/snapshot and {topic}/status")
        client.subscribe(f"{topic}/snapshot")
        client.subscribe(f"{topic}/status")
    else:
        print(f"Connection failed: {reason_code}")


def on_disconnect(client, userdata, flags, reason_code, properties=None):
    if reason_code != 0:
        print(f"Disconnected (rc={reason_code}), will reconnect automatically")


def on_message(client, userdata, msg):
    global latest_frame
    topic = userdata["topic"]

    if msg.topic == f"{topic}/snapshot":
        buf = np.frombuffer(msg.payload, dtype=np.uint8)
        frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        if frame is not None:
            with frame_lock:
                latest_frame = frame
        else:
            print("Warning: failed to decode snapshot")

    elif msg.topic == f"{topic}/status":
        try:
            status = json.loads(msg.payload)
            parts = []
            for key in ("timestamp", "camera", "brightness", "gain",
                        "img_brightness", "img_green_pct", "img_diff_pct",
                        "load", "mem_available_kb"):
                if key in status:
                    parts.append(f"{key}={status[key]}")
            if parts:
                print("  ".join(parts))
        except json.JSONDecodeError:
            print(f"Status (raw): {msg.payload[:200]}")


def main():
    parser = argparse.ArgumentParser(description="MQTT snapshot viewer for AVI cameras")
    parser.add_argument("broker", help="MQTT broker hostname")
    parser.add_argument("topic", help="Base MQTT topic (e.g. cameras/site1/cam1)")
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port (default: 1883)")
    parser.add_argument("--username", help="MQTT username")
    parser.add_argument("--password", help="MQTT password")
    args = parser.parse_args()

    userdata = {"topic": args.topic}
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=userdata)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    if args.username:
        client.username_pw_set(args.username, args.password)

    print(f"Connecting to {args.broker}:{args.port} ...")
    client.connect(args.broker, args.port)
    client.loop_start()

    window_name = "MQTT Snapshot Viewer"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    print("Waiting for snapshots... press 'q' or ESC to quit")

    try:
        while True:
            with frame_lock:
                frame = latest_frame

            if frame is not None:
                cv2.imshow(window_name, frame)

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
