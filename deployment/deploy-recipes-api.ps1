<#
.SYNOPSIS
  Provisions and deploys the search/filter/pagination Function App.

.DESCRIPTION
  Creates a resource group, a storage account (required by the Functions
  runtime itself - separate from Person A's data storage), and a Python
  Function App on a Consumption plan, then publishes function_app.py to it.

.PREREQUISITES
  - Azure CLI installed and logged in (the script will call 'az login' for
    you if needed)
  - Azure Functions Core Tools installed (the 'func' command)
  - Person A's read connection string for the 'results' container
    (ask them for a SAS-scoped connection string, not their full account key)

.EXAMPLE
  ./deploy-recipes-api.ps1 -PersonAConnectionString "<connection string from Person A>"
#>

param(
    [string]$ResourceGroup = "diet-dashboard-personc-rg",
    [string]$Location = "canadacentral",
    [string]$StorageAccount = "dietpersoncstore$(Get-Random -Maximum 9999)",
    [string]$FunctionAppName = "diet-recipes-api-$(Get-Random -Maximum 9999)",

    [Parameter(Mandatory = $true)]
    [string]$PersonAConnectionString,

    [string]$FunctionsProjectPath = "Kaley"
)

$ErrorActionPreference = "Stop"

Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
az account show *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
}

Write-Host "Creating resource group '$ResourceGroup' in $Location..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

Write-Host "Creating storage account '$StorageAccount' (required by the Functions runtime, separate from Person A's data)..." -ForegroundColor Cyan
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --output none

# * DEMO: this call provisions the live Function App this whole API runs on
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

Write-Host "Setting PERSON_A_STORAGE_CONNECTION_STRING app setting..." -ForegroundColor Cyan
az functionapp config appsettings set `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --settings "PERSON_A_STORAGE_CONNECTION_STRING=$PersonAConnectionString" `
    --output none

Write-Host "Enabling CORS for all origins (matches Person A and B's setup)..." -ForegroundColor Cyan
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

$FunctionAppUrl = "https://$FunctionAppName.azurewebsites.net"
Write-Host ""
Write-Host "Done. Your Function App is live at:" -ForegroundColor Green
Write-Host "  $FunctionAppUrl" -ForegroundColor Green
Write-Host ""
Write-Host "Try it:" -ForegroundColor Green
Write-Host "  GET $FunctionAppUrl/api/recipes?diet_type=paleo&keyword=chicken&page=1&page_size=20"
Write-Host "  GET $FunctionAppUrl/api/diet-types"
Write-Host ""
Write-Host "Reminder: this is YOUR api url, not your dashboard's. You still owe" -ForegroundColor Yellow
Write-Host "Person B your DASHBOARD's url so they can set FRONTEND_URL." -ForegroundColor Yellow
