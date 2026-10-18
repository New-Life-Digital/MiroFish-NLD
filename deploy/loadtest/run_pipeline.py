"""
Fährt einen kompletten MiroFish-Lauf über die HTTP-API, wie ihn eine Workshop-Gruppe im Browser macht:
Seed hochladen -> Ontologie -> Graph -> Simulation anlegen -> Agenten vorbereiten -> simulieren -> Bericht.

Beispiel:
  python run_pipeline.py --base http://localhost:5002 --seed klar-public-beta.md \
      --requirement-file requirement.txt --rounds 20 --tag g1 --out results/g1.json
"""

import argparse
import json
import sys
import time

import requests


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--seed", required=True)
    ap.add_argument("--requirement-file", required=True)
    ap.add_argument("--rounds", type=int, default=20, help="0 = keine Angabe, Server-Obergrenze MAX_ROUNDS_CAP greift")
    ap.add_argument("--tag", default="run")
    ap.add_argument("--out", required=True)
    ap.add_argument("--auth", help="user:pass für Basic Auth (Caddy)")
    ap.add_argument("--skip-report", action="store_true")
    args = ap.parse_args()

    s = requests.Session()
    if args.auth:
        s.auth = tuple(args.auth.split(":", 1))
    api = args.base.rstrip("/") + "/api"
    t0 = time.time()
    phases = {}
    result = {"tag": args.tag, "phases": phases, "ok": False}

    def log(msg):
        print(f"[{args.tag} {time.time() - t0:7.1f}s] {msg}", flush=True)

    def mark(name):
        phases[name] = round(time.time() - t0, 1)
        log(f"Phase fertig: {name}")
        save()

    def save():
        result["elapsed_s"] = round(time.time() - t0, 1)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

    def ok(resp):
        resp.raise_for_status()
        data = resp.json()
        if not data.get("success", True):
            raise RuntimeError(data.get("error"))
        return data.get("data", data)

    def wait(fn, done, label, every=5, limit=3600):
        start = time.time()
        while time.time() - start < limit:
            data = fn()
            status = done(data)
            if status == "done":
                return data
            if status == "failed":
                raise RuntimeError(f"{label} fehlgeschlagen: {json.dumps(data, ensure_ascii=False)[:500]}")
            time.sleep(every)
        raise TimeoutError(label)

    try:
        requirement = open(args.requirement_file, encoding="utf-8").read().strip()
        with open(args.seed, "rb") as f:
            d = ok(s.post(f"{api}/graph/ontology/generate", timeout=600,
                          data={"simulation_requirement": requirement, "project_name": f"Lasttest {args.tag}"},
                          files={"files": (args.seed.replace("\\", "/").split("/")[-1], f, "text/markdown")}))
        project_id = d["project_id"]
        result["project_id"] = project_id
        mark("ontologie")

        task_id = ok(s.post(f"{api}/graph/build", json={"project_id": project_id}, timeout=60))["task_id"]
        wait(lambda: ok(s.get(f"{api}/graph/task/{task_id}", timeout=30)),
             lambda t: {"completed": "done", "failed": "failed"}.get(t.get("status")), "Graph")
        mark("graph")

        sim = ok(s.post(f"{api}/simulation/create", json={"project_id": project_id}, timeout=60))
        sim_id = sim["simulation_id"]
        result["simulation_id"] = sim_id
        prep = ok(s.post(f"{api}/simulation/prepare", json={"simulation_id": sim_id}, timeout=120))
        prep_task = prep.get("task_id")
        wait(lambda: ok(s.post(f"{api}/simulation/prepare/status",
                                json={"task_id": prep_task, "simulation_id": sim_id}, timeout=30)),
             lambda t: "done" if t.get("status") in ("completed", "ready") else
             ("failed" if t.get("status") == "failed" else None), "Vorbereitung")
        state = ok(s.get(f"{api}/simulation/{sim_id}", timeout=30))
        result["agents"] = state.get("profiles_count")
        mark("agenten")

        start = {"simulation_id": sim_id, "platform": "parallel"}
        if args.rounds:
            start["max_rounds"] = args.rounds
        ok(s.post(f"{api}/simulation/start", json=start, timeout=120))
        run = wait(lambda: ok(s.get(f"{api}/simulation/{sim_id}/run-status", timeout=30)),
                   lambda r: {"completed": "done", "stopped": "done", "failed": "failed"}.get(r.get("runner_status")),
                   "Simulation", every=10)
        result["actions"] = run.get("total_actions_count")
        result["rounds"] = run.get("current_round")
        mark("simulation")

        if not args.skip_report:
            rep = ok(s.post(f"{api}/report/generate", json={"simulation_id": sim_id}, timeout=120))
            rep_task = rep.get("task_id")
            wait(lambda: ok(s.post(f"{api}/report/generate/status",
                                    json={"task_id": rep_task, "simulation_id": sim_id}, timeout=30)),
                 lambda t: {"completed": "done", "failed": "failed"}.get(t.get("status")), "Bericht", every=10)
            result["report_id"] = ok(s.get(f"{api}/report/by-simulation/{sim_id}", timeout=30)).get("report_id")
            mark("bericht")

        result["ok"] = True
    except Exception as e:
        result["error"] = f"{type(e).__name__}: {e}"
        log(result["error"])
    save()
    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
