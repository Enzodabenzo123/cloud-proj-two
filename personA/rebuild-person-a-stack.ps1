<#
.SYNOPSIS
  Rebuilds Person A's data-cleaning + caching pipeline (their function_app.py,
  as originally written) in a fully separate resource group, under your own
  Azure subscription - because their original resource group was deleted.

.DESCRIPTION
  This is NOT a respin of Person A's original resource. It's a fresh copy
  of their code, deployed by you, under your own subscription, in its own
  resource group, kept deliberately isolated from your recipes API resource
  group. Disclose this plainly in your submission - see the disclosure note
  template printed at the end of this script and in DISCLOSURE_NOTE.md.

  Creates: resource group, storage account (with datasets/results/analysis
  containers), Redis Basic (C0), and a Python Function App on a Consumption
  plan running Person A's DietDataProcessor blob trigger + analyze endpoint.

.PREREQUISITES
  - Azure CLI, logged in ('az login')
  - Azure Functions Core Tools ('func')
  - A copy of the source dataset (All_Diets.csv) to upload and trigger the
    pipeline once it's live

.EXAMPLE
  ./rebuild-person-a-stack.ps1 -DietCsvPath "..\cloud-proj-two\data\All_Diets.csv"
#>

param(
    [string]$ResourceGroup = "diet-analysis-rebuild-personc-rg",
    [string]$Location = "canadacentral",
    [string]$StorageAccount = "dietrebuildst$(Get-Random -Maximum 9999)",
    [string]$RedisName = "diet-rebuild-redis-$(Get-Random -Maximum 9999)",
    [string]$FunctionAppName = "diet-analysis-rebuild-$(Get-Random -Maximum 9999)",

    [Parameter(Mandatory = $true)]
    [string]$DietCsvPath,

    [string]$FunctionsProjectPath = "."
)

$ErrorActionPreference = "Stop"

Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " This creates a NEW, separate resource - not a respin" -ForegroundColor Magenta
Write-Host " of Person A's original. Disclose this in your video." -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host ""

Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
az account show *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
}

Write-Host "Creating resource group '$ResourceGroup'..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

Write-Host "Creating storage account '$StorageAccount'..." -ForegroundColor Cyan
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --output none

$StorageConnStr = az storage account show-connection-string `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --output tsv

Write-Host "Creating blob containers (datasets, results)..." -ForegroundColor Cyan
az storage container create --name datasets --connection-string $StorageConnStr --output none
az storage container create --name results --connection-string $StorageConnStr --output none

Write-Host "Creating Redis cache '$RedisName' (Basic C0 - this step takes 10-20 min)..." -ForegroundColor Cyan
az redis create `
    --name $RedisName `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Basic `
    --vm-size c0 `
    --output none

Write-Host "Waiting for Redis to finish provisioning..." -ForegroundColor Cyan
do {
    Start-Sleep -Seconds 30
    $state = az redis show --name $RedisName --resource-group $ResourceGroup --query "provisioningState" --output tsv
    Write-Host "  Redis state: $state"
} while ($state -ne "Succeeded")

$RedisKey = az redis list-keys --name $RedisName --resource-group $ResourceGroup --query "primaryKey" --output tsv

Write-Host "Creating Function App '$FunctionAppName'..." -ForegroundColor Cyan
az functionapp create `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --storage-account $StorageAccount `
    --consumption-plan-location $Location `
    --runtime python `
    --runtime-version 3.11 `
    --os-type Linux `
    --functions-version 4 `
    --output none

Write-Host "Setting app configuration (STORAGE_CONNECTION_STRING, REDIS_HOST, REDIS_KEY)..." -ForegroundColor Cyan
az functionapp config appsettings set `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --settings `
        "STORAGE_CONNECTION_STRING=$StorageConnStr" `
        "REDIS_HOST=$RedisName.redis.cache.windows.net" `
        "REDIS_KEY=$RedisKey" `
    --output none

Write-Host "Enabling CORS for all origins..." -ForegroundColor Cyan
az functionapp cors add `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --allowed-origins "*" `
    --output none

Write-Host "Publishing function code from '$FunctionsProjectPath'..." -ForegroundColor Cyan
Push-Location $FunctionsProjectPath
try {
    func azure functionapp publish $FunctionAppName --python
}
finally {
    Pop-Location
}

Write-Host "Uploading $DietCsvPath to trigger the blob trigger..." -ForegroundColor Cyan
az storage blob upload `
    --connection-string $StorageConnStr `
    --container-name datasets `
    --name All_Diets.csv `
    --file $DietCsvPath `
    --overwrite `
    --output none

Write-Host "Waiting 20s for the blob trigger to fire and cache to populate..." -ForegroundColor Cyan
Start-Sleep -Seconds 20

$FunctionAppUrl = "https://$FunctionAppName.azurewebsites.net"
$NewConnStr = $StorageConnStr

Write-Host ""
Write-Host "Done. Rebuilt pipeline is live at:" -ForegroundColor Green
Write-Host "  $FunctionAppUrl/api/analyze" -ForegroundColor Green
Write-Host ""
Write-Host "Verify it worked:" -ForegroundColor Green
Write-Host "  curl.exe -s $FunctionAppUrl/api/analyze"
Write-Host ""
Write-Host "Connection string for YOUR recipes API to read results/All_Diets_clean.csv" -ForegroundColor Green
Write-Host "(pass this as -PersonAConnectionString to deploy-recipes-api.ps1):" -ForegroundColor Green
Write-Host "  $NewConnStr" -ForegroundColor Green
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " REMEMBER: disclose this rebuild in your video/writeup." -ForegroundColor Magenta
Write-Host " See DISCLOSURE_NOTE.md for suggested wording." -ForegroundColor Magenta
Write-Host "====================================================="  -ForegroundColor Magenta
