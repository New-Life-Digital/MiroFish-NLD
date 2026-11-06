#!/usr/bin/env bash
# Läuft auf der VM (aufgerufen von deploy/install.ps1 bzw. deploy.sh install). Erzeugt beim ersten Mal
# Secrets und Zugänge, schreibt Caddyfile, Gruppen-Compose und Infoseite und startet alle Container.
#
# Jede Gruppe bekommt eine eigene Instanz: eigenes Backend, eigener Verlauf (Volume), eigene Subdomain
# <gruppe>.<DOMAIN> mit eigenem Login (leitung kommt überall rein). Neo4j, Ollama und der
# Vertex-Proxy samt Kostenbremse sind geteilt. Die Infoseite liegt ohne Login auf <DOMAIN>.
# Wiederholbar: vorhandene Zugänge bleiben, nur Code und Konfiguration werden neu gebaut.
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
# Basis plus generierte Gruppen-Dienste, damit "docker compose ..." ohne -f alles sieht
grep -q '^COMPOSE_FILE=' .env || echo 'COMPOSE_FILE=docker-compose.yml:docker-compose.teams.yml' >> .env

if [ ! -f zugaenge.txt ]; then
  {
    echo "MiroFish-Workshop  Infoseite: https://$DOMAIN"
    for user in $TEAMS; do
      # Lesbare Passwörter für Beamer und Zettel: ohne 0/O/1/l
      echo "$user  $(rand 'abcdefghjkmnpqrstuvwxyz23456789' 12)  https://$user.$DOMAIN"
    done
  } > zugaenge.txt
  chmod 600 zugaenge.txt
fi

# --- Caddyfile: Vorlage plus eine Seite je Gruppe (lädt Caddy neu, falls es läuft)
bash vm/caddy.sh "$DOMAIN" "$SOURCE_URL" "$TEAMS"

# --- Ein Backend je Gruppe, alle aus demselben Image
{
  cat <<'EOF'
# Generiert von vm/install-remote.sh. Ein Backend je Gruppe mit eigenem Verlauf.
x-backend: &backend
  image: mirofish-backend:local
  pull_policy: never
  environment:
    LLM_API_KEY: ${PROXY_TOKEN}
    LLM_BASE_URL: http://vertex-proxy:8080/v1
    LLM_MODEL_NAME: ${LLM_MODEL_NAME:-gemini-3.8-flash}
    LLM_REASONING_EFFORT: ${LLM_REASONING_EFFORT:-low}
    REPORT_LANGUAGE: ${REPORT_LANGUAGE:-English}
    MAX_ROUNDS_CAP: ${MAX_ROUNDS_CAP:-10}
    NEO4J_URI: bolt://neo4j:7687
    NEO4J_USER: neo4j
    NEO4J_PASSWORD: ${NEO4J_PASSWORD}
    EMBEDDING_MODEL: nomic-embed-text
    EMBEDDING_BASE_URL: http://ollama:11434
    SECRET_KEY: ${FLASK_SECRET_KEY}
    FLASK_DEBUG: "False"
  depends_on:
    neo4j:
      condition: service_healthy
    ollama-pull:
      condition: service_completed_successfully
    vertex-proxy:
      condition: service_started
  restart: unless-stopped

services:
EOF
  for user in $TEAMS; do
    cat <<EOF
  backend-$user:
    <<: *backend
    volumes:
      - uploads_$user:/app/backend/uploads
      # OASIS lädt beim ersten Lauf ein BERT-Modell von Hugging Face; Cache geteilt
      - hf_cache:/root/.cache/huggingface
EOF
  done
  echo
  echo "volumes:"
  for user in $TEAMS; do echo "  uploads_$user:"; done
} > docker-compose.teams.yml

# --- Infoseite: Gruppenliste einsetzen
bash vm/info.sh "$DOMAIN" "$TEAMS"

docker build -t mirofish-backend:local -f Dockerfile.backend ..
docker compose up -d --build --remove-orphans
docker compose ps
