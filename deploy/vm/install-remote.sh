#!/usr/bin/env bash
# Läuft auf der VM (aufgerufen von deploy.sh install). Erzeugt beim ersten Mal Secrets und
# Gruppen-Zugänge, schreibt Caddyfile und startet alle Container. Wiederholbar: vorhandene
# Zugänge bleiben, nur der Code wird neu gebaut.
set -euo pipefail
DOMAIN="$1"; PROJECT="$2"; MAX_USD="$3"; SOURCE_URL="$4"; TEAMS="$5"
cd /opt/mirofish/deploy

# Zufallsstring aus Zeichensatz $1 mit Länge $2 (|| true: head beendet die Pipe absichtlich früh)
rand() { LC_ALL=C tr -dc "$1" < /dev/urandom | head -c "$2" || true; }

if [ ! -f .env ]; then
  cat > .env <<EOF
GCP_PROJECT=$PROJECT
VERTEX_LOCATION=eu
MAX_USD=$MAX_USD
PROXY_TOKEN=$(rand 'A-Za-z0-9' 32)
NEO4J_PASSWORD=$(rand 'A-Za-z0-9' 24)
FLASK_SECRET_KEY=$(rand 'A-Za-z0-9' 32)
EOF
  chmod 600 .env
fi

if [ ! -f zugaenge.txt ]; then
  {
    echo "MiroFish-Workshop  https://$DOMAIN"
    for user in $TEAMS; do
      # Lesbare Passwörter für Beamer und Zettel: ohne 0/O/1/l
      echo "$user  $(rand 'abcdefghjkmnpqrstuvwxyz23456789' 12)"
    done
  } > zugaenge.txt
  chmod 600 zugaenge.txt
fi

users=""
while read -r user pass; do
  hash=$(docker run --rm caddy:2.10-alpine caddy hash-password --plaintext "$pass")
  users+=$'\t\t'"$user $hash"$'\n'
done < <(tail -n +2 zugaenge.txt)

awk -v domain="$DOMAIN" -v users="$users" -v src="$SOURCE_URL" '
  /__USERS__/ { printf "%s", users; next }
  { gsub("__DOMAIN__", domain); gsub("__SOURCE_URL__", src); print }
' Caddyfile.template > Caddyfile

docker compose up -d --build
docker compose ps
