#!/usr/bin/env bash
# Läuft auf der VM: erzeugt die Infoseite (deploy/info/index.html) aus info.template.html.
# Caddy liefert den Ordner direkt aus, ein Neustart ist nicht nötig.
#   bash vm/info.sh <domain> "<gruppen>"
set -euo pipefail
DOMAIN="$1"; TEAMS="$2"
cd /opt/mirofish/deploy
mkdir -p info
links=""
for user in $TEAMS; do
  [ "$user" = leitung ] && continue
  label="Group ${user#gruppe}"
  links+="<li><a class=\"team\" href=\"https://$user.$DOMAIN\"><span class=\"team-name\">$label</span><span class=\"team-url\">$user.$DOMAIN</span></a></li>"
done
awk -v links="$links" -v domain="$DOMAIN" '
  /<!--TEAMS-->/ { print links; next }
  { gsub("__DOMAIN__", domain); print }
' info.template.html > info/index.html
# Zusätzliche Dateien der Infoseite (z. B. Spickzettel-PDF)
[ -d info-assets ] && cp -rf info-assets/. info/ 2>/dev/null || true
echo "Infoseite geschrieben: $(wc -c < info/index.html) Bytes"
