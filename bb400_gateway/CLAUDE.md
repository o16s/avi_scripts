# bb400_gateway — NanoMQ MQTT Broker for BB-400 Gateways

Local MQTT broker for AVI camera networks, deployed via Docker on BB-400 industrial gateways.

## Install

```
curl -fsSL https://raw.githubusercontent.com/o16s/avi_scripts/main/bb400_gateway/install.sh | sh
```

Installs to `/opt/avi-gateway/`. Idempotent — re-running updates config while preserving credentials.

## File layout

```
bb400_gateway/
├── install.sh           # Curl-able installer (checks docker, generates creds, starts containers)
├── docker-compose.yml   # NanoMQ service (ports 1883 MQTT, 8081 HTTP API)
└── nanomq.conf          # Broker config template (placeholders replaced at install time)
```

## How it works

`install.sh` flow:
1. Checks for `docker` and `docker compose` (or `docker-compose`)
2. Creates `/opt/avi-gateway/`
3. Generates two separate 16-char alphanumeric passwords (MQTT + HTTP API), or reads existing from `.env`
4. Downloads `docker-compose.yml` and `nanomq.conf` from GitHub
5. Substitutes `__MQTT_PASSWORD__` and `__HTTP_API_PASSWORD__` placeholders via sed
6. Runs `docker compose up -d`

## Credentials

Stored in `/opt/avi-gateway/.env` (chmod 600):
- `MQTT_USER` — always `avi`
- `MQTT_PASSWORD` — for MQTT broker (port 1883), used by cameras
- `HTTP_API_PASSWORD` — for NanoMQ HTTP API (port 8081), used for management

Username is `avi` for both services. Passwords are independent.

## Config placeholders

`nanomq.conf` is a template. Never hardcode passwords in it — use placeholders:
- `__MQTT_PASSWORD__` — replaced with `MQTT_PASSWORD` from `.env`
- `__HTTP_API_PASSWORD__` — replaced with `HTTP_API_PASSWORD` from `.env`

## Conventions

- **Shell**: `#!/bin/sh` with `set -eu`. POSIX-compliant, no bashisms. Validate with `shellcheck -s sh`.
- **Idempotency**: `.env` is created once and preserved. Config files are re-downloaded and re-templated on every run (allows updates without losing credentials).
- **Passwords**: Generated from `/dev/urandom`, base64-encoded, filtered to `A-Za-z0-9` only. This keeps them safe for sed substitution and URL-safe for HTTP basic auth.
- **GitHub raw URLs**: All downloads use `https://raw.githubusercontent.com/o16s/avi_scripts/main/bb400_gateway/`.

## Verifying changes

- `shellcheck -s sh bb400_gateway/install.sh`
- On a machine with Docker: `sh bb400_gateway/install.sh`
- `docker ps` — nanomq container running
- `mosquitto_pub -h localhost -p 1883 -u avi -P <mqtt_password> -t test -m hello`
- `curl -u avi:<http_api_password> http://localhost:8081/api/v4/clients`
