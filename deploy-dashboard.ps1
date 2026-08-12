<#
.SYNOPSIS
  Deploys Person C's dashboard (webapp/) as its own Azure Static Web App.

.DESCRIPTION
  Deliberately scoped to just the frontend — does NOT touch projtwo/ (the old
  Phase 2 backend, now superseded by Person A's live /api/analyze). This is
  separate infra from deploy-recipes-api.ps1, under your own subscription,
  matching the "own Function App, own deployment" pattern from the Phase 3
  context doc. No connection strings or secrets needed for this piece.

  Safe to re-run any time (e.g. after the resource group gets deleted between
  sessions to save cost).

.PREREQUISITES
  - Azure CLI installed and you're logged in (the script will call
    'az login' for you if needed)
  - Static Web Apps CLI installed: npm install -g @azure/static-web-apps-cli

.EXAMPLE
  ./deploy-dashboard.ps1
#>

param(
    [string]$ResourceGroup = "diet-dashboard-personc-rg",
    [string]$Location = "centralus",
    [string]$StaticAppName = "diet-dashboard-personc-swa",
    [string]$FrontendParent = ".",
    [string]$FrontendFolder = "webapp",

    # Pass -Teardown to delete everything this script created instead of
    # deploying (handy for saving cost between work sessions).
    [switch]$Teardown
)

$ErrorActionPreference = "Stop"

if ($Teardown) {
    Write-Host "Deleting resource group '$ResourceGroup'..." -ForegroundColor Yellow
    az group delete --name $ResourceGroup --yes --no-wait
    Write-Host "Deletion started (running in background). Note: this only removes the dashboard's Static Web App. If you also deployed the recipes API into the same resource group, that goes with it too - re-run deploy-recipes-api.ps1 afterward if you still need it." -ForegroundColor Yellow
    return
}

Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
az account show *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
}

Write-Host "Creating resource group '$ResourceGroup' in $Location (no-op if it already exists)..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

Write-Host "Creating Static Web App '$StaticAppName'..." -ForegroundColor Cyan
az staticwebapp create --name $StaticAppName --resource-group $ResourceGroup --location $Location --sku Free --output none

Write-Host "Fetching deployment token..." -ForegroundColor Cyan
$SWA_TOKEN = az staticwebapp secrets list --name $StaticAppName --resource-group $ResourceGroup --query "properties.apiKey" -o tsv

# Important: run this from the PARENT directory, pointing at the folder name -
# not from inside the folder itself pointing at "." - the deploy binary
# rejects the case where the working directory equals the artifact directory.
Write-Host "Deploying '$FrontendFolder'..." -ForegroundColor Cyan
Push-Location $FrontendParent
try {
    swa deploy $FrontendFolder --deployment-token $SWA_TOKEN --env production
}
finally {
    Pop-Location
}

$SWA_HOST = az staticwebapp show --name $StaticAppName --resource-group $ResourceGroup --query "defaultHostname" -o tsv

Write-Host ""
Write-Host "Done. Your dashboard is live at:" -ForegroundColor Green
Write-Host "  https://$SWA_HOST" -ForegroundColor Green
Write-Host ""
Write-Host "Reminders:" -ForegroundColor Yellow
Write-Host "  - Send Enzo this URL as your real FRONTEND_URL (replaces the localhost one)."
Write-Host "  - The recipe search card won't work until you deploy the recipes API"
Write-Host "    separately with deploy-recipes-api.ps1 and paste that URL into the dashboard."
