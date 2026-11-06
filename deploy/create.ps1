# PowerShell-Variante von "deploy.sh create" (Git Bash + gcloud vertragen sich unter Windows nicht).
$ErrorActionPreference = 'Continue'
$P = 'ki-workspace-507114'; $REGION = 'europe-west3'; $ZONE = 'europe-west3-a'
$VM = 'mirofish-workshop'; $MACHINE = if ($env:MACHINE) { $env:MACHINE } else { 'e2-standard-16' }
$SA = "mirofish-vm@$P.iam.gserviceaccount.com"
$DEPLOY = Split-Path -Parent $MyInvocation.MyCommand.Path

gcloud --project $P services enable compute.googleapis.com aiplatform.googleapis.com
gcloud --project $P iam service-accounts describe $SA *> $null
if ($LASTEXITCODE -ne 0) { gcloud --project $P iam service-accounts create mirofish-vm --display-name "MiroFish-Workshop-VM" }
foreach ($role in 'roles/aiplatform.user','roles/logging.logWriter') {
  gcloud projects add-iam-policy-binding $P --member "serviceAccount:$SA" --role $role --condition None --quiet *> $null
  "IAM $role -> $LASTEXITCODE"
}
gcloud --project $P compute addresses describe mirofish-ip --region $REGION *> $null
if ($LASTEXITCODE -ne 0) { gcloud --project $P compute addresses create mirofish-ip --region $REGION }
$IP = gcloud --project $P compute addresses describe mirofish-ip --region $REGION --format 'value(address)'
gcloud --project $P compute firewall-rules describe mirofish-web *> $null
if ($LASTEXITCODE -ne 0) { gcloud --project $P compute firewall-rules create mirofish-web --allow tcp:80,tcp:443 --target-tags mirofish }
gcloud --project $P compute instances create $VM --zone $ZONE --machine-type $MACHINE `
  --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud `
  --boot-disk-size 80GB --boot-disk-type pd-balanced `
  --address $IP --tags mirofish --labels workshop=mirofish `
  --service-account $SA --scopes cloud-platform `
  --metadata-from-file "startup-script=$DEPLOY\vm\startup.sh"
"IP=$IP"
