#!/usr/bin/env bash
# Läuft auf der VM: Container, Backends je Gruppe, Zertifikate und LLM-Kosten auf einen Blick.
cd /opt/mirofish/deploy
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
echo "--- Backends"
for c in $(docker compose ps --services | grep '^backend-'); do
  code=$(docker compose exec -T "$c" curl -s -o /dev/null -w '%{http_code}' http://localhost:5001/api/graph/project/list || echo down)
  echo "$c: $code"
done
echo "--- Kosten (Vertex-Proxy)"
docker compose exec -T vertex-proxy python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8080/health').read().decode())" || true
echo "--- Zertifikate"
docker compose exec -T web sh -c 'ls /data/caddy/certificates/*/ 2>/dev/null' || true
docker compose logs web --since 15m 2>/dev/null | grep -o '"msg":"[^"]*","identifier":"[^"]*"' | sort | uniq -c | tail -12
