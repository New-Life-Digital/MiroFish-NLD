# PowerShell-Variante von "deploy.sh install" und den Betriebsbefehlen (Git Bash + gcloud vertragen sich unter Windows nicht).
#   powershell -File deploy\install.ps1 install     Code hochladen, Gruppen-Instanzen bauen und starten (läuft auf der VM im Hintergrund)
#   powershell -File deploy\install.ps1 log         Fortschritt der Installation
#   powershell -File deploy\install.ps1 passwords   Zugänge anzeigen
#   powershell -File deploy\install.ps1 status      Container und bisherige LLM-Kosten
#   powershell -File deploy\install.ps1 stop|start  VM anhalten / starten
param([string]$Cmd = 'install')
$ErrorActionPreference = 'Continue'
$P = 'ki-workspace-507114'; $ZONE = 'europe-west3-a'; $VM = 'mirofish-workshop'
$DOMAIN = 'mirofish.newlifedigital.de'
$SOURCE = 'https://github.com/New-Life-Digital/MiroFish-NLD'
$MAX_USD = '50'
$TEAMS = 'gruppe1 gruppe2 gruppe3 gruppe4 leitung'
$DEPLOY = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO = Split-Path -Parent $DEPLOY

function Remote([string]$c) { gcloud --project $P compute ssh $VM --zone $ZONE --quiet --strict-host-key-checking=no --command $c }

switch ($Cmd) {
  'install' {
    $tmp = Join-Path $env:TEMP 'mirofish-upload'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    git -C $REPO archive --format tar.gz -o "$tmp\code.tgz" HEAD
    Push-Location $REPO
    tar -czf "$tmp\deploy.tgz" --exclude=deploy/backups --exclude=*.tgz deploy
    Pop-Location
    Write-Output 'Warte auf Docker auf der VM ...'
    do { $ok = Remote 'command -v docker >/dev/null && docker compose version >/dev/null && echo READY'; if ($ok -notmatch 'READY') { Start-Sleep 10 } } until ($ok -match 'READY')
    gcloud --project $P compute scp "$tmp\code.tgz" "$tmp\deploy.tgz" "${VM}:/tmp/" --zone $ZONE --quiet --strict-host-key-checking=no
    $run = "sudo mkdir -p /opt/mirofish && sudo tar -xzf /tmp/code.tgz -C /opt/mirofish && sudo tar -xzf /tmp/deploy.tgz -C /opt/mirofish && " +
           "sudo find /opt/mirofish/deploy -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.template*' -o -name '*.py' -o -name 'Dockerfile*' -o -name '*.txt' \) -exec sed -i 's/\r$//' {} + && " +
           "sudo systemctl reset-failed mirofish-install 2>/dev/null; " +
           "sudo systemd-run --unit mirofish-install --collect bash /opt/mirofish/deploy/vm/install-remote.sh '$DOMAIN' '$P' '$MAX_USD' '$SOURCE' '$TEAMS' && echo GESTARTET"
    Remote $run
  }
  'log'       { Remote 'sudo journalctl -u mirofish-install --no-pager -n 40 -o cat; systemctl is-active mirofish-install' }
  'passwords' { Remote 'sudo cat /opt/mirofish/deploy/zugaenge.txt' }
  'status'    { Remote 'sudo bash /opt/mirofish/deploy/vm/check.sh' }
  'stop'      { gcloud --project $P compute instances stop $VM --zone $ZONE }
  'start'     { gcloud --project $P compute instances start $VM --zone $ZONE }
  default     { Get-Content $MyInvocation.MyCommand.Path -TotalCount 7 }
}
