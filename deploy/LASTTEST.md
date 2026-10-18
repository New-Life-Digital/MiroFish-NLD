# Lasttest 18.10.2026

**Ergebnis: 5 parallele Läufe in Klar-Größe laufen sauber durch. Vertex hält, CPU ist der Engpass. VM: e2-standard-16.**

## Aufbau

- Lokal (Windows, Ryzen 7 7800X3D, 16 Threads, 32 GB), Backend mit diesem Fork, Gemini 3.8 Flash über den Vertex-Proxy (`eu`-Multiregion, Projekt `ki-workspace-507114`).
- Seed `klar-public-beta.md`, Frage wie im Spike, `LLM_REASONING_EFFORT=low`, `MAX_ROUNDS_CAP=20`, Bericht auf Deutsch.
- Skripte: `loadtest/run_pipeline.py` (ein Lauf über die HTTP-API wie im Browser), `loadtest/run_parallel.sh` (N Läufe, 15 s versetzt, plus Ressourcen-Monitor).

## Einzellauf

| Phase | kumuliert |
|---|---|
| Ontologie | 14 s |
| Graph | 53 s |
| Agenten (13) | 1:58 min |
| Simulation 20 Runden, 71 Aktionen | 4:39 min |
| Bericht | 8:58 min |

163 LLM-Aufrufe, 1,03 Mio. Input, 66k Output, **0,71 $** (Spike über AI Studio: 1,63 $, 22 min). Die Ersparnis kommt aus dem Denkbudget in Simulation und Profilerzeugung.

## 5 parallel

| Gruppe | Agenten | Aktionen | Dauer |
|---|---|---|---|
| g1 | 8 | 50 | 9:48 min |
| g2 | 9 | 53 | 9:51 min |
| g3 | 9 | 70 | 10:40 min |
| g4 | 13 | 70 | 10:10 min |
| g5 | 6 | 50 | 9:49 min |

- **5 von 5 fertig**, alle mit 20 Runden ohne Rundenangabe: Die Obergrenze `MAX_ROUNDS_CAP` greift.
- **Vertex:** 756 Aufrufe, Spitze 136 Aufrufe und 0,92 Mio. Tokens pro Minute, **0 Wiederholungen, kein 429**. Latenz p50 3,9 s, p95 11 s. Gemini 3.x läuft über dynamisch geteilte Kapazität, ein festes Projekt-Quota gibt es nicht; der Proxy wiederholt bei 429 bis zu 6-mal.
- **Kosten:** 3,02 $ für 5 Läufe, also 0,60 $ je Lauf. Workshop mit 5 Gruppen x 4 Läufen: etwa 12 $ (ab 2027 doppelt). Preise im Proxy geschätzt mit 0,50 $ / 3,00 $ je Mio. Tokens, echte Zahl steht in der Abrechnung.
- **CPU:** Rechner lief ohne Test bei etwa 45 %, im Test im Mittel 78 %, Spitzen 100 %. Der Lasttest belegt also etwa 7 bis 9 Threads, vor allem in Simulation und Bericht (jede Simulation lädt ein BERT-Modell für den Feed).
- **RAM:** Python-Prozesse von 4 auf 14 GB (Summe RSS, zählt geteilte Seiten mehrfach), System nur +3 GB. Planwert: 2 GB je Simulation.

## Folgerung für die VM

- **e2-standard-16** (16 vCPU, 64 GB): eine e2-vCPU ist ein halber Kern, 8 vCPU hätten bei 5 Gruppen keine Reserve. Mehrkosten gegenüber e2-standard-8 etwa 7 $ für zwei Workshop-Tage.
- Eine VM reicht. Mehr als 5 gleichzeitige Läufe sind nicht getestet.

## Nicht getestet

- Docker-Stack selbst (kein Docker auf dem Testrechner), Caddy/HTTPS, Embeddings auf CPU (lokal lief Ollama auf der GPU). Erster echter Test: Probelauf nach `deploy.sh install`.
