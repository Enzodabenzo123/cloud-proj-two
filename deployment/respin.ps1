# respin.ps1
#
# Recreates the full Azure backend + frontend for the Diet Analysis dashboard
# and deploys code to both. Safe to re-run any time the resource group gets
# deleted (e.g. end of a lab session to save cost).
#
# PORTABLE: all paths are resolved relative to this script's own location
# ($PSScriptRoot), so it works from any machine or folder as long as the repo
# structure is intact:
#
#   <repo root>\
#   |-- respin.ps1        (this file)
#   |-- projtwo\          (backend: function_app.py, host.json, requirements.txt)
#   |-- webapp\           (frontend: index.html)
#   \-- data\             (All_Diets.csv)
#
# PREREQUISITES (one-time setup on this machine):
#   az login                                          (log into Azure first)
#   npm install -g azure-functions-core-tools@4
#   npm install -g @azure/static-web-apps-cli
#
# USAGE:
#   cd to the repo root (the folder containing this script), then:  .\respin.ps1
#
# ---------------------------------------------------------------------------

# --- Azure resource names -------------------------------------------------
# NOTE: $STORAGE and $FUNCTIONAPP are GLOBALLY unique across all of Azure.
# If a respin fails at "name already taken", bump the suffix letter here.
$RG          = "diet-analysis-rg"
$LOCATION    = "centralus"
$STORAGE     = "dietanalysisst2026e"       # 3-24 chars, lowercase/numbers only
$FUNCTIONAPP = "diet-analysis-func-2026e"  # becomes <name>.azurewebsites.net
$STATICAPP   = "diet-dashboard-swa-e"

# --- Local paths (resolved from this script's location) -------------------
$BACKEND_DIR     = Join-Path $PSScriptRoot "projtwo"
$FRONTEND_PARENT = $PSScriptRoot
$FRONTEND_FOLDER = "webapp"
$CSV_PATH        = Join-Path $PSScriptRoot "data\All_Diets.csv"

# ---------------------------------------------------------------------------
# Retry wrapper. Azure CLI calls occasionally fail with a mid-request SSL
# connection reset (seen repeatedly during initial setup) - this is a
# transient network issue, not a config problem, so retrying is the correct
# fix rather than debugging it fresh each time.
# ---------------------------------------------------------------------------
function Invoke-AzWithRetry {
    param(
        [string]$Description,
        [scriptblock]$Command,
        [int]$MaxAttempts = 3
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Host "-> $Description (attempt $i of $MaxAttempts)" -ForegroundColor DarkGray
        & $Command
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Write-Host "   Failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
        if ($i -lt $MaxAttempts) {
            Write-Host "   Retrying in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
    Write-Host "   $Description failed after $MaxAttempts attempts. Check manually before continuing." -ForegroundColor Red
}

# Sanity check: make sure the repo structure is intact before doing anything.
foreach ($p in @($BACKEND_DIR, (Join-Path $FRONTEND_PARENT $FRONTEND_FOLDER), $CSV_PATH)) {
    if (-not (Test-Path $p)) {
        Write-Host "ERROR: expected path not found: $p" -ForegroundColor Red
        Write-Host "Run this script from the repo root with projtwo\, webapp\, and data\ in place." -ForegroundColor Red
        exit 1
    }
}

Write-Host "== 1. Resource group ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Create resource group" -Command {
    az group create --name $RG --location $LOCATION
}

Write-Host "== 2. Storage account ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Create storage account" -Command {
    az storage account create --name $STORAGE --resource-group $RG --location $LOCATION --sku Standard_LRS --kind StorageV2
}

$CONN_STR = az storage account show-connection-string --name $STORAGE --resource-group $RG --query connectionString -o tsv

Write-Host "== 3. Datasets container ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Create datasets container" -Command {
    az storage container create --name datasets --connection-string $CONN_STR
}

Write-Host "== 4. Upload CSV ==" -ForegroundColor Cyan
if (Test-Path $CSV_PATH) {
    Invoke-AzWithRetry -Description "Upload CSV" -Command {
        az storage blob upload --connection-string $CONN_STR --container-name datasets --name All_Diets.csv --file $CSV_PATH --overwrite
    }
}
else {
    Write-Host "WARNING: CSV not found at $CSV_PATH - skipping upload. The function will error until this is uploaded manually." -ForegroundColor Red
}

Write-Host "== 5. Function App ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Create Function App" -Command {
    az functionapp create --name $FUNCTIONAPP --resource-group $RG --storage-account $STORAGE --consumption-plan-location $LOCATION --runtime python --runtime-version 3.11 --functions-version 4 --os-type Linux
}

Write-Host "== 6. Set connection string app setting ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Set STORAGE_CONNECTION_STRING" -Command {
    az functionapp config appsettings set --name $FUNCTIONAPP --resource-group $RG --settings "STORAGE_CONNECTION_STRING=$CONN_STR"
}
# Note: this command no longer echoes the value back (Azure redacts it for security).
# To verify it actually took, run:
#   az functionapp config appsettings list --name $FUNCTIONAPP --resource-group $RG --query "[?name=='STORAGE_CONNECTION_STRING']"

Write-Host "== 7. Deploy function code ==" -ForegroundColor Cyan
Push-Location $BACKEND_DIR
func azure functionapp publish $FUNCTIONAPP --python
Pop-Location

Write-Host "== 8. Test endpoint ==" -ForegroundColor Cyan
$FUNC_URL = "https://$FUNCTIONAPP.azurewebsites.net/api/analyze"
Write-Host "Function URL: $FUNC_URL" -ForegroundColor Green
# A freshly published consumption-plan Python app cold-starts; the first call
# can take 20-40s or briefly 500 while the worker spins up. Give it a moment,
# then retry a couple of times before deciding something is actually wrong.
Start-Sleep -Seconds 20
for ($t = 1; $t -le 3; $t++) {
    try {
        $resp = Invoke-RestMethod -Uri $FUNC_URL -TimeoutSec 60
        Write-Host "Endpoint returned $($resp.total_recipes) recipes in $($resp.execution_time_seconds)s." -ForegroundColor Green
        break
    }
    catch {
        Write-Host "   Endpoint not ready yet (attempt $t of 3): $($_.Exception.Message)" -ForegroundColor Yellow
        if ($t -lt 3) { Start-Sleep -Seconds 15 }
        else { Write-Host "   Still not responding - open $FUNC_URL in a browser in a minute; cold start can be slow." -ForegroundColor Yellow }
    }
}

Write-Host "== 9. Static Web App ==" -ForegroundColor Cyan
Invoke-AzWithRetry -Description "Create Static Web App" -Command {
    az staticwebapp create --name $STATICAPP --resource-group $RG --location $LOCATION --sku Free
}

Write-Host "== 10. Prepare frontend files ==" -ForegroundColor Cyan
# Azure Static Web Apps requires the entry file to be named index.html specifically.
# If the dashboard file exists under a different name, rename it automatically.
$frontendPath = Join-Path $FRONTEND_PARENT $FRONTEND_FOLDER
$indexPath = Join-Path $frontendPath "index.html"
if (-not (Test-Path $indexPath)) {
    $otherHtml = Get-ChildItem -Path $frontendPath -Filter "*.html" | Select-Object -First 1
    if ($otherHtml) {
        Write-Host "Renaming $($otherHtml.Name) to index.html" -ForegroundColor Yellow
        Rename-Item -Path $otherHtml.FullName -NewName "index.html"
    }
    else {
        Write-Host "WARNING: No .html file found in $frontendPath - nothing to deploy." -ForegroundColor Red
    }
}

Write-Host "== 11. Deploy dashboard ==" -ForegroundColor Cyan
$SWA_TOKEN = az staticwebapp secrets list --name $STATICAPP --resource-group $RG --query "properties.apiKey" -o tsv

# Important: run this from the PARENT directory, pointing at the folder name -
# not from inside the folder itself pointing at "." - the deploy binary
# rejects the case where the working directory equals the artifact directory.
Push-Location $FRONTEND_PARENT
swa deploy $FRONTEND_FOLDER --deployment-token $SWA_TOKEN --env production
Pop-Location

$SWA_HOST = az staticwebapp show --name $STATICAPP --resource-group $RG --query "defaultHostname" -o tsv

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "Done. Live URLs:" -ForegroundColor Green
Write-Host "  Function:  $FUNC_URL" -ForegroundColor Green
Write-Host "  Dashboard: https://$SWA_HOST" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host "Open the dashboard URL, paste the function URL into the endpoint field, click Connect."
