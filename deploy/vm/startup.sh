#!/usr/bin/env bash
# Startskript der VM (läuft bei jedem Boot als root). Installiert einmalig Docker.
# Die Container starten danach von selbst (restart: unless-stopped).
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker.io docker-compose-v2
  systemctl enable --now docker
fi
