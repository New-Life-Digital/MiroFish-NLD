#!/usr/bin/env bash
# Läuft auf der VM: schreibt deploy/Caddyfile aus Caddyfile.template und zugaenge.txt
# (eine Seite je Gruppe) und lädt Caddy neu, falls es schon läuft.
#   bash vm/caddy.sh <domain> <quellcode-url> "<gruppen>"
set -euo pipefail
DOMAIN="$1"; SOURCE_URL="$2"; TEAMS="$3"
cd /opt/mirofish/deploy

declare -A HASH
while read -r user pass _; do
  HASH[$user]=$(docker run --rm caddy:2.10-alpine caddy hash-password --plaintext "$pass")
done < <(tail -n +2 zugaenge.txt)

# Mit ">" schreiben, nicht sed -i: Caddyfile ist als einzelne Datei eingebunden, die Inode muss bleiben
{
  sed -e "s#__DOMAIN__#$DOMAIN#g" -e "s#__SOURCE_URL__#$SOURCE_URL#g" -e "s#__LEITUNG_HASH__#${HASH[leitung]}#g" Caddyfile.template
  for user in $TEAMS; do
    echo
    echo "$user.$DOMAIN {"
    echo "	basic_auth {"
    echo "		$user ${HASH[$user]}"
    if [ "$user" != leitung ] && [ -n "${HASH[leitung]:-}" ]; then
      echo "		leitung ${HASH[leitung]}"
    fi
    echo "	}"
    echo "	import instanz backend-$user"
    echo "}"
  done
} > Caddyfile

if docker compose ps --status running --services 2>/dev/null | grep -qx web; then
  docker compose exec -T web caddy reload --config /etc/caddy/Caddyfile
  echo "Caddy neu geladen"
fi
