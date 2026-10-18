"""
Misst während eines Lasttests alle 5 s CPU, belegten RAM und den Speicher der Python-Prozesse (Backend + Simulationen).
Beenden mit Strg+C oder über eine Stopp-Datei: python monitor.py out.jsonl stop.flag
"""

import json
import os
import sys
import time

import psutil

out, stop_flag = sys.argv[1], sys.argv[2]
with open(out, "a", encoding="utf-8") as f:
    while not os.path.exists(stop_flag):
        cpu = psutil.cpu_percent(interval=5)
        mem = psutil.virtual_memory()
        py_rss, py_count = 0, 0
        for p in psutil.process_iter(["name", "memory_info"]):
            if (p.info["name"] or "").lower().startswith("python") and p.info["memory_info"]:
                py_rss += p.info["memory_info"].rss
                py_count += 1
        f.write(json.dumps({
            "t": round(time.time()), "cpu": cpu, "ram_used_gb": round(mem.used / 2**30, 2),
            "py_rss_gb": round(py_rss / 2**30, 2), "py_procs": py_count,
        }) + "\n")
        f.flush()
