# MiroFish-Workshop: Betrieb in Google Cloud

Alles läuft auf einer VM in Frankfurt (`europe-west3`), Gemini über Vertex AI in der EU-Multiregion. Kosten laufen über die Credits. Alle Befehle in Git Bash im Repo-Ordner.

## Einmalig vorbereiten (ca. 10 Minuten)

1. `gcloud auth login` (dein gcloud-Login ist abgelaufen)
2. Prüfen, dass `ki-workspace-507114` am Rechnungskonto mit den Credits hängt. Sonst Projekt setzen: `export GCP_PROJECT=<projekt-id>`
3. `bash deploy/deploy.sh budget` legt den Budget-Alarm an (100 in der Kontowährung, Mails bei 25/50/90/100 %). Er zählt Kosten **vor** Credits, sonst würde er nie auslösen.

## Aufbauen (eine Woche vorher, ca. 20 Minuten)

1. Repo öffentlich auf GitHub (AGPL-Pflicht, siehe unten), falls noch nicht geschehen.
2. `bash deploy/deploy.sh create` erstellt VM (e2-standard-16, 16 vCPU, 64 GB), feste IP, Firewall, Service-Account. Am Ende steht die IP.
3. DNS: A-Record `mirofish.newlifedigital.de` auf diese IP.
4. `bash deploy/deploy.sh install` kopiert den Code, erzeugt Passwörter und startet alles. Das HTTPS-Zertifikat holt Caddy selbst, sobald DNS stimmt.
5. `bash deploy/deploy.sh passwords` zeigt die Logins `gruppe1` bis `gruppe5` und `leitung`. Auf Zettel drucken.
6. Probelauf als `leitung` mit dem Klar-Seed, dann VM bis zum Workshop anhalten.

## Am Workshop

- Morgens `bash deploy/deploy.sh start`, abends `bash deploy/deploy.sh stop`. Daten, IP und Zertifikat bleiben.
- `bash deploy/deploy.sh status` zeigt Container und bisher verbrauchte LLM-Kosten.
- Notbremse: Der Proxy lehnt ab 50 $ geschätzten LLM-Kosten (erwartet: ca. 15 $) neue Aufrufe ab. Anheben: auf der VM in `/opt/mirofish/deploy/.env` `MAX_USD` ändern, dann `sudo docker compose up -d vertex-proxy`.

## Kosten (Schätzung)

| Posten | Betrag |
|---|---|
| Ein Lauf in Klar-Größe (bis 13 Agenten, 20 Runden, Bericht) | 0,60 bis 0,70 $ (gemessen) |
| 5 Gruppen x 4 Läufe | ca. 15 $ |
| VM e2-standard-16, nur an Workshop-Tagen an (2 x 10 h) | ca. 14 $ |
| Disk + feste IP für 3 Wochen | ca. 10 $ |

## Nach dem Workshop

1. `bash deploy/deploy.sh backup` holt Berichte, Simulationen und Kostenlog nach `deploy/backups/`.
2. `bash deploy/deploy.sh destroy` löscht VM, Disk, IP, Firewall-Regel und Service-Account (fragt nach).
3. DNS-Eintrag entfernen.

## Was du wissen musst

- **Kein Login im Produkt:** Schutz nur über Basic Auth je Gruppe. Alle Gruppen sehen alle Läufe, Löschen ist gesperrt.
- **AGPL:** Weil Dritte die geänderte Fassung nutzen, muss der Code öffentlich sein: https://github.com/New-Life-Digital/MiroFish-NLD (Link auch unter `/quellcode`).
- **Keine personenbezogenen Daten** in Seeds, das steht auch in der Teilnehmer-Anleitung.
