#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploys Azure AI Foundry (Azure OpenAI) and GPT-4 model to Azure.

.DESCRIPTION
    This script automates the deployment of:
    - Azure OpenAI Service (part of Azure AI Foundry)
    - GPT-4 model deployment in a US region
    - Outputs endpoint and API key for application connection

.PARAMETER ResourceGroupName
    The name of the Azure resource group. Default: "rg-aifoundry-$(Get-Random -Maximum 9999)"

.PARAMETER Location
    The Azure region for deployment. Default: "eastus"
    Supported US regions: eastus, eastus2, westus, westus3, southcentralus

.PARAMETER OpenAIServiceName
    The name of the Azure OpenAI service. Default: "aoai-$(Get-Random -Maximum 99999)"

.PARAMETER DeploymentName
    The name for the GPT-4 model deployment. Default: "gpt4-deployment"

.PARAMETER ModelName
    The GPT-4 model to deploy. Default: "gpt-4"
    Options: "gpt-4", "gpt-4-32k", "gpt-4-turbo", "gpt-4o"

.PARAMETER ModelVersion
    The model version. Default: "1106-Preview" for gpt-4, "latest" for gpt-4o

.PARAMETER SkuName
    The SKU for the Azure OpenAI service. Default: "S0"

.EXAMPLE
    .\Deploy-AzureAIFoundry.ps1

.EXAMPLE
    .\Deploy-AzureAIFoundry.ps1 -ResourceGroupName "my-rg" -Location "eastus2" -ModelName "gpt-4o"

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-aifoundry-$(Get-Random -Maximum 9999)",

    [Parameter(Mandatory = $false)]
    [ValidateSet("eastus", "eastus2", "westus", "westus3", "southcentralus", "northcentralus")]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$OpenAIServiceName = "aoai-$(Get-Random -Maximum 99999)",

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "gpt4-deployment",

    [Parameter(Mandatory = $false)]
    [ValidateSet("gpt-4", "gpt-4-32k", "gpt-4-turbo", "gpt-4o", "gpt-4.1")]
    [string]$ModelName = "gpt-4.1",

    [Parameter(Mandatory = $false)]
    [string]$ModelVersion = "",

    [Parameter(Mandatory = $false)]
    [string]$SkuName = "S0"
)

# Set error action preference
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

try {
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║   Azure AI Foundry & GPT-4 Deployment Script            ║" -ForegroundColor Magenta
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

    # Check if Azure CLI is installed
    Write-Step "Checking prerequisites..."
    $azVersion = az version --query '\"azure-cli\"' -o tsv 2>$null
    if (-not $azVersion) {
        Write-Error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
        exit 1
    }
    Write-Success "Azure CLI version $azVersion detected"

    # Check if logged in to Azure
    Write-Step "Checking Azure login status..."
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Host "Not logged in to Azure. Initiating login..." -ForegroundColor Yellow
        az login
        $account = az account show | ConvertFrom-Json
    }
    Write-Success "Logged in as: $($account.user.name)"
    Write-Success "Subscription: $($account.name) ($($account.id))"

    # Create Resource Group
    Write-Step "Creating resource group '$ResourceGroupName' in '$Location'..."
    $rgExists = az group exists --name $ResourceGroupName
    if ($rgExists -eq "true") {
        Write-Host "Resource group already exists. Using existing resource group." -ForegroundColor Yellow
    } else {
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Success "Resource group created successfully"
    }

    # Create Azure OpenAI Service
    Write-Step "Creating Azure OpenAI service '$OpenAIServiceName'..."
    
    # Determine model version if not specified
    if ([string]::IsNullOrWhiteSpace($ModelVersion)) {
        switch ($ModelName) {
            "gpt-4" { $ModelVersion = "0613" }
            "gpt-4-32k" { $ModelVersion = "0613" }
            "gpt-4-turbo" { $ModelVersion = "2024-04-09" }
            "gpt-4o" { $ModelVersion = "2024-05-13" }
            "gpt-4.1" { $ModelVersion = "2025-04-14" }
            default { $ModelVersion = "2025-04-14" }
        }
    }

    # Get the path to the Bicep template
    $bicepTemplate = Join-Path $PSScriptRoot "azuredeploy.bicep"
    
    if (-not (Test-Path $bicepTemplate)) {
        Write-Error "Bicep template not found at: $bicepTemplate"
        exit 1
    }

    # Deploy using Bicep
    Write-Host "Deploying Azure OpenAI service and model using Bicep..." -ForegroundColor Yellow
    $deploymentName = "aoai-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    $deployment = az deployment group create `
        --name $deploymentName `
        --resource-group $ResourceGroupName `
        --template-file $bicepTemplate `
        --parameters openAIServiceName=$OpenAIServiceName `
                     location=$Location `
                     skuName=$SkuName `
                     deploymentName=$DeploymentName `
                     modelName=$ModelName `
                     modelVersion=$ModelVersion `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bicep deployment failed"
        exit 1
    }

    Write-Success "Azure OpenAI service created successfully"
    Write-Success "Model deployment created successfully"

    # Verify and ensure API key authentication is enabled
    Write-Step "Verifying API key authentication is enabled..."
    
    # Wait a bit for the deployment to fully complete
    Start-Sleep -Seconds 5
    
    $disableLocalAuth = az cognitiveservices account show `
        --name $OpenAIServiceName `
        --resource-group $ResourceGroupName `
        --query "properties.disableLocalAuth" `
        --output tsv

    if ($disableLocalAuth -eq "true") {
        Write-Host "API key authentication is disabled. Applying fix..." -ForegroundColor Yellow
        
        # Use multiple methods to ensure it gets enabled
        $resourceId = "/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$OpenAIServiceName"
        
        # Method 1: Using az resource update
        Write-Host "Method 1: Using az resource update..." -ForegroundColor Yellow
        az resource update `
            --ids $resourceId `
            --set properties.disableLocalAuth=false `
            --api-version 2024-04-01-preview `
            --output none 2>$null
        
        Start-Sleep -Seconds 5
        
        # Method 2: Using az cognitiveservices account update (if supported)
        Write-Host "Method 2: Using direct account update..." -ForegroundColor Yellow
        az cognitiveservices account update `
            --name $OpenAIServiceName `
            --resource-group $ResourceGroupName `
            --output none 2>$null
        
        Start-Sleep -Seconds 10
        
        # Verify it's now enabled
        $disableLocalAuth = az cognitiveservices account show `
            --name $OpenAIServiceName `
            --resource-group $ResourceGroupName `
            --query "properties.disableLocalAuth" `
            --output tsv
        
        if ($disableLocalAuth -eq "true") {
            Write-Host "`nManual action required:" -ForegroundColor Red
            Write-Host "Please run this command manually to enable API key authentication:" -ForegroundColor Yellow
            Write-Host "az resource update --ids $resourceId --set properties.disableLocalAuth=false --api-version 2024-04-01-preview`n" -ForegroundColor Cyan
        } else {
            Write-Success "API key authentication is now enabled"
        }
    } else {
        Write-Success "API key authentication is enabled"
    }

    # Get outputs from Bicep deployment
    Write-Step "Retrieving connection details..."
    $endpoint = $deployment.properties.outputs.endpoint.value

    # Retrieve API key directly using Azure CLI (secure outputs are masked in Bicep)
    $apiKey = az cognitiveservices account keys list `
        --name $OpenAIServiceName `
        --resource-group $ResourceGroupName `
        --query "key1" `
        --output tsv

    # Display results
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                 DEPLOYMENT SUCCESSFUL                     ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green

    Write-Host "`nAzure OpenAI Details:" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "Resource Group:     " -NoNewline -ForegroundColor White
    Write-Host $ResourceGroupName -ForegroundColor Yellow
    Write-Host "Service Name:       " -NoNewline -ForegroundColor White
    Write-Host $OpenAIServiceName -ForegroundColor Yellow
    Write-Host "Location:           " -NoNewline -ForegroundColor White
    Write-Host $Location -ForegroundColor Yellow
    Write-Host "Model:              " -NoNewline -ForegroundColor White
    Write-Host "$ModelName ($ModelVersion)" -ForegroundColor Yellow
    Write-Host "Deployment Name:    " -NoNewline -ForegroundColor White
    Write-Host $DeploymentName -ForegroundColor Yellow
    Write-Host "`nConnection Information:" -ForegroundColor Cyan
    Write-Host "Endpoint:           " -NoNewline -ForegroundColor White
    Write-Host $endpoint -ForegroundColor Green
    Write-Host "API Key:            " -NoNewline -ForegroundColor White
    Write-Host $apiKey -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    # Output connection information to file
    $outputFile = Join-Path $PSScriptRoot "azure-openai-connection.txt"
    $connectionInfo = @"
Azure OpenAI Connection Information
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

=== Azure OpenAI Details ===
Resource Group: $ResourceGroupName
Service Name: $OpenAIServiceName
Location: $Location
Model: $ModelName ($ModelVersion)
Deployment Name: $DeploymentName

ENDPOINT=$endpoint
API_KEY=$apiKey

Example Usage (cURL):
curl $endpoint/openai/deployments/$DeploymentName/chat/completions?api-version=2024-02-15-preview \
  -H "Content-Type: application/json" \
  -H "api-key: $apiKey" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

Environment Variables (PowerShell):
`$env:AZURE_OPENAI_ENDPOINT = "$endpoint"
`$env:AZURE_OPENAI_API_KEY = "$apiKey"
`$env:AZURE_OPENAI_DEPLOYMENT_NAME = "$DeploymentName"

Environment Variables (Bash):
export AZURE_OPENAI_ENDPOINT="$endpoint"
export AZURE_OPENAI_API_KEY="$apiKey"
export AZURE_OPENAI_DEPLOYMENT_NAME="$DeploymentName"
"@

    $connectionInfo | Out-File -FilePath $outputFile -Encoding utf8
    Write-Host "`nConnection details saved to: " -NoNewline -ForegroundColor White
    Write-Host $outputFile -ForegroundColor Cyan

    # Create .env file
    $envFile = Join-Path $PSScriptRoot ".env"
    @"
AZURE_OPENAI_ENDPOINT=$endpoint
AZURE_OPENAI_API_KEY=$apiKey
AZURE_OPENAI_DEPLOYMENT_NAME=$DeploymentName
"@ | Out-File -FilePath $envFile -Encoding utf8
    Write-Host "Environment file created: " -NoNewline -ForegroundColor White
    Write-Host $envFile -ForegroundColor Cyan

    Write-Host "`n✓ Deployment completed successfully!`n" -ForegroundColor Green

} catch {
    Write-Error "`nDeployment failed: $_"
    Write-Host "`nError Details:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nStack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
