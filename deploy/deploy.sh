#!/usr/bin/env bash
# MiroFish-Workshop auf einer Compute-Engine-VM in europe-west3.
# Läuft lokal in Git Bash mit eingeloggtem gcloud (gcloud auth login).
#
#   bash deploy/deploy.sh create      VM, statische IP, Firewall, Service-Account anlegen
#   bash deploy/deploy.sh install     Code auf die VM kopieren, Zugänge erzeugen, Container starten
#   bash deploy/deploy.sh passwords   Zugänge der Gruppen anzeigen
#   bash deploy/deploy.sh status      Container und bisherige LLM-Kosten anzeigen
#   bash deploy/deploy.sh budget      Budget-Alarm anlegen (zählt Kosten vor Credits)
#   bash deploy/deploy.sh stop|start  VM anhalten / wieder starten (Daten und IP bleiben)
#   bash deploy/deploy.sh backup      Berichte, Simulationen und Kostenlog nach deploy/backups/ holen
#   bash deploy/deploy.sh destroy     alles wieder löschen (fragt nach)
set -euo pipefail

PROJECT="${GCP_PROJECT:-ki-workspace-507114}"
REGION="europe-west3"
ZONE="${ZONE:-europe-west3-a}"
VM="${VM:-mirofish-workshop}"
MACHINE="${MACHINE:-e2-standard-16}"
DOMAIN="${DOMAIN:-mirofish.newlifedigital.de}"
SOURCE_URL="${SOURCE_URL:-https://github.com/New-Life-Digital/MiroFish-NLD}"
BUDGET="${BUDGET:-100}"
MAX_USD="${MAX_USD:-50}"
TEAMS="${TEAMS:-gruppe1 gruppe2 gruppe3 gruppe4 gruppe5 leitung}"
SA="mirofish-vm@${PROJECT}.iam.gserviceaccount.com"
# Git Bash: Windows-Pfade an gcloud geben, keine automatische Pfadumschreibung
export MSYS_NO_PATHCONV=1
DEPLOY_DIR="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))"
REPO_DIR="$(dirname "$DEPLOY_DIR")"

g() { gcloud --project "$PROJECT" "$@"; }
remote() { g compute ssh "$VM" --zone "$ZONE" --command "$1"; }

cmd_create() {
  g services enable compute.googleapis.com aiplatform.googleapis.com

  if ! g iam service-accounts describe "$SA" >/dev/null 2>&1; then
    g iam service-accounts create mirofish-vm --display-name "MiroFish-Workshop-VM"
  fi
  # Nur Gemini aufrufen und Logs schreiben, sonst nichts
  for role in roles/aiplatform.user roles/logging.logWriter; do
    g projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$role" --condition None >/dev/null
  done

  g compute addresses describe mirofish-ip --region "$REGION" >/dev/null 2>&1 \
    || g compute addresses create mirofish-ip --region "$REGION"
  IP=$(g compute addresses describe mirofish-ip --region "$REGION" --format 'value(address)')

  g compute firewall-rules describe mirofish-web >/dev/null 2>&1 \
    || g compute firewall-rules create mirofish-web --allow tcp:80,tcp:443 --target-tags mirofish

  g compute instances create "$VM" --zone "$ZONE" --machine-type "$MACHINE" \
    --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud \
    --boot-disk-size 50GB --boot-disk-type pd-balanced \
    --address "$IP" --tags mirofish --labels workshop=mirofish \
    --service-account "$SA" --scopes cloud-platform \
    --metadata-from-file startup-script="$DEPLOY_DIR/vm/startup.sh"

  echo
  echo "VM läuft. Jetzt DNS setzen:  A-Record  ${DOMAIN}  ->  ${IP}"
  echo "Danach:  bash deploy/deploy.sh install"
}

cmd_install() {
  local archive
  archive="$DEPLOY_DIR/mirofish-upload.tar.gz"
  git -C "$REPO_DIR" archive --format tar.gz -o "$archive" HEAD
  echo "Warte, bis Docker auf der VM bereit ist ..."
  until remote "command -v docker >/dev/null && docker compose version >/dev/null" 2>/dev/null; do sleep 10; done
  g compute scp "$archive" "$VM:/tmp/mirofish.tar.gz" --zone "$ZONE"
  rm -f "$archive"
  remote "sudo mkdir -p /opt/mirofish && sudo tar -xzf /tmp/mirofish.tar.gz -C /opt/mirofish && \
    sudo bash /opt/mirofish/deploy/vm/install-remote.sh '$DOMAIN' '$PROJECT' '$MAX_USD' '$SOURCE_URL' '$TEAMS'"
  echo
  echo "Fertig. Aufruf: https://${DOMAIN}  (Zugänge: bash deploy/deploy.sh passwords)"
}

cmd_passwords() { remote "sudo cat /opt/mirofish/deploy/zugaenge.txt"; }

cmd_status() {
  remote "cd /opt/mirofish/deploy && sudo docker compose ps --format 'table {{.Service}}\t{{.Status}}' && \
    sudo docker compose exec -T vertex-proxy python -c \"import urllib.request;print(urllib.request.urlopen('http://localhost:8080/health').read().decode())\""
}

cmd_budget() {
  g services enable billingbudgets.googleapis.com cloudbilling.googleapis.com
  local account
  account=$(g billing projects describe "$PROJECT" --format 'value(billingAccountName)' | sed 's#billingAccounts/##')
  # exclude-all-credits: sonst zählt der Alarm die Kosten nach Credits, also 0, und meldet sich nie
  gcloud billing budgets create --billing-account "$account" \
    --display-name "MiroFish-Workshop" --budget-amount "$BUDGET" \
    --filter-projects "projects/$PROJECT" --credit-types-treatment exclude-all-credits \
    --threshold-rule percent=0.25 --threshold-rule percent=0.5 \
    --threshold-rule percent=0.9 --threshold-rule percent=1.0
  echo "Budget-Alarm über ${BUDGET} (Währung des Rechnungskontos) angelegt. Mails gehen an die Abrechnungs-Admins."
}

cmd_stop() { g compute instances stop "$VM" --zone "$ZONE"; }
cmd_start() { g compute instances start "$VM" --zone "$ZONE"; }

cmd_backup() {
  local stamp
  stamp=$(date +%Y%m%d-%H%M)
  remote "sudo docker run --rm -v mirofish_uploads:/data/uploads:ro -v mirofish_proxy_data:/data/proxy:ro \
    alpine tar -czf - -C /data . > /tmp/mirofish-backup.tgz"
  mkdir -p "$DEPLOY_DIR/backups"
  g compute scp "$VM:/tmp/mirofish-backup.tgz" "$DEPLOY_DIR/backups/mirofish-$stamp.tgz" --zone "$ZONE"
  echo "Gesichert: deploy/backups/mirofish-$stamp.tgz"
}

cmd_destroy() {
  read -r -p "VM, Daten, IP, Firewall-Regel und Service-Account löschen? Zum Bestätigen LOESCHEN tippen: " answer
  [ "$answer" = "LOESCHEN" ] || { echo "Abgebrochen."; exit 1; }
  g compute instances delete "$VM" --zone "$ZONE" --quiet || true
  g compute addresses delete mirofish-ip --region "$REGION" --quiet || true
  g compute firewall-rules delete mirofish-web --quiet || true
  for role in roles/aiplatform.user roles/logging.logWriter; do
    g projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$role" --condition None >/dev/null || true
  done
  g iam service-accounts delete "$SA" --quiet || true
  echo "Abgebaut. DNS-Eintrag ${DOMAIN} jetzt entfernen. Budget-Alarm bleibt bestehen (kostet nichts)."
}

case "${1:-}" in
  create|install|passwords|status|budget|stop|start|backup|destroy) "cmd_$1" ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
