#!/usr/bin/env bash
# Läuft auf der VM: kompletter Lauf (Seed -> Bericht) in einer Instanz, direkt gegen deren Backend.
#   sudo bash smoke.sh <instanz> <seed> <requirement> <name> [runden]
# Fortschritt: sudo docker compose exec backend-<instanz> cat /tmp/smoke.log
set -euo pipefail
inst="$1"; seed="$2"; req="$3"; name="$4"; rounds="${5:-15}"
cd /opt/mirofish/deploy
svc="backend-$inst"
sed "s/f\"Lasttest {args.tag}\"/args.tag/" loadtest/run_pipeline.py > /tmp/run_pipeline.py
docker compose cp /tmp/run_pipeline.py "$svc":/tmp/run_pipeline.py
base=$(basename "$seed")
docker compose cp "$seed" "$svc":/tmp/"$base"
docker compose cp "$req" "$svc":/tmp/requirement.txt
docker compose exec -d "$svc" sh -c "cd /tmp && python run_pipeline.py --base http://localhost:5001 --seed '$base' --requirement-file requirement.txt --rounds $rounds --tag '$name' --out smoke.json > smoke.log 2>&1"
echo "Lauf gestartet in $svc"
