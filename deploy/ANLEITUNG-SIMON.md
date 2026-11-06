# MiroFish-Workshop: Betrieb in Google Cloud

Stand 06.11.2026. Eine VM in Frankfurt (`mirofish-workshop`, e2-standard-16, IP `34.40.71.61`), Gemini über Vertex AI in der EU-Multiregion, Kosten über die Credits.

## Aufbau

- **Eine Instanz je Gruppe:** `gruppe1` bis `gruppe4.mirofish.newlifedigital.de`, je eigenes Backend und eigener Verlauf. Login: Gruppenname und Passwort. `leitung` kommt in jede Instanz.
- **Deine Demo-Instanz:** `leitung.mirofish.newlifedigital.de`
- **Ideathon-Seite ohne Login:** `mirofish.newlifedigital.de` mit Tagesplan, Gruppen-Links, MiroFish-Ablauf, Prototyp-Leitfaden, Prompt-Vorlagen zum Kopieren, Spickzettel-PDF und Hilfe (Englisch). Quelle: `deploy/info.template.html`, Dateien daneben in `deploy/info-assets/`; ausrollen mit `vm/info.sh` (kein Neustart nötig).
- **Limits:** höchstens 10 Runden je Lauf (`MAX_ROUNDS_CAP`), Bericht auf Englisch (`REPORT_LANGUAGE`), beides in `/opt/mirofish/deploy/.env`, danach `sudo docker compose up -d`.
- Geteilt: Neo4j, Ollama (Embeddings), Vertex-Proxy mit Kostenbremse bei 50 $.
- DNS bei IONOS: A-Records `mirofish` und `*.mirofish` (oder einzeln) auf `34.40.71.61`.
- Zugangskarten: `Obsidian Vault/Simon/01_Leads/MiroFish-Zugangskarten.pdf`

## Befehle (PowerShell im Repo-Ordner)

Git Bash funktioniert mit gcloud auf diesem Rechner nicht, deshalb PowerShell:

```
powershell -File deploy\install.ps1 status      # Container und bisherige LLM-Kosten
powershell -File deploy\install.ps1 passwords   # Zugänge
powershell -File deploy\install.ps1 stop        # VM anhalten (abends), Daten und IP bleiben
powershell -File deploy\install.ps1 start       # VM starten
powershell -File deploy\install.ps1 install     # Code/Konfig neu hochladen und neu bauen (Zugänge bleiben)
powershell -File deploy\install.ps1 log         # Fortschritt einer laufenden Installation
```

Gruppen ändern: `$TEAMS` in `deploy\install.ps1` anpassen, dann `install`. Für neue Gruppen auf der VM `/opt/mirofish/deploy/zugaenge.txt` löschen (erzeugt alle Passwörter neu) oder die Zeile von Hand ergänzen.

Notbremse anheben: auf der VM in `/opt/mirofish/deploy/.env` `MAX_USD` ändern, dann `sudo docker compose up -d vertex-proxy`.

## Nach dem Workshop

1. Berichte sichern: auf der VM liegen sie in den Volumes `mirofish_uploads_<gruppe>`.
2. Abbauen: VM `mirofish-workshop`, Adresse `mirofish-ip`, Firewall-Regel `mirofish-web`, Service-Account `mirofish-vm` löschen (Befehle in `deploy.sh destroy`), DNS-Einträge bei IONOS entfernen.
3. Solange die VM nur gestoppt ist, kosten nur Disk (80 GB) und feste IP, zusammen etwa 0,50 $ am Tag.

## Was du wissen musst

- **Kein Login im Produkt:** Schutz nur über Basic Auth je Subdomain. Löschen ist gesperrt.
- **AGPL:** Der geänderte Code ist öffentlich unter https://github.com/New-Life-Digital/MiroFish-NLD (Link auch unter `/quellcode`). Die Umstellung auf Gruppen-Instanzen betrifft nur `deploy/`; wer sie dauerhaft will, pusht sie dorthin.
- **Keine personenbezogenen Daten** in Seeds, das steht auch auf der Infoseite.
- **Bericht kommt auf Englisch** (`REPORT_LANGUAGE=English`). Für Deutsch `REPORT_LANGUAGE=German` setzen.
