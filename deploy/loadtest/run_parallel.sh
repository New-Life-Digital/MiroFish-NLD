#!/usr/bin/env bash
# Lasttest: N komplette Läufe gleichzeitig (wie N Gruppen), dazu Ressourcen-Monitor.
#   bash run_parallel.sh <base-url> <seed> <requirement-file> <n> <outdir> [rounds] [user:pass]
# rounds=0 lässt die Rundenzahl weg, dann greift die Server-Obergrenze MAX_ROUNDS_CAP.
set -uo pipefail
BASE="$1"; SEED="$2"; REQ="$3"; N="$4"; OUT="$5"; ROUNDS="${6:-20}"; AUTH="${7:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python}"
mkdir -p "$OUT"; rm -f "$OUT/stop.flag"
"$PY" "$HERE/monitor.py" "$OUT/monitor.jsonl" "$OUT/stop.flag" &
pids=()
for i in $(seq 1 "$N"); do
  "$PY" "$HERE/run_pipeline.py" --base "$BASE" --seed "$SEED" --requirement-file "$REQ" \
    --rounds "$ROUNDS" --tag "g$i" --out "$OUT/g$i.json" ${AUTH:+--auth "$AUTH"} > "$OUT/g$i.log" 2>&1 &
  pids+=($!)
  sleep 15  # Gruppen starten nie exakt gleichzeitig
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=$((fail + 1)); done
touch "$OUT/stop.flag"; wait
echo "Fertig, fehlgeschlagen: $fail von $N"
