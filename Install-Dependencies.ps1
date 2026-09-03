$ErrorActionPreference = 'Stop'
Write-Host "=== EnergizeCheck dependency installer ===" -ForegroundColor Cyan

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
    Write-Host "PSSQLite not found. Installing for CurrentUser..." -ForegroundColor Yellow
    try {
        if (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    } catch {}
    Install-Module PSSQLite -Scope CurrentUser -Force -AllowClobber
} else {
    Write-Host "PSSQLite is already installed." -ForegroundColor Green
}

Import-Module PSSQLite -Force
Write-Host "PSSQLite version: $((Get-Module PSSQLite).Version)" -ForegroundColor Green
Write-Host "Dependencies are ready." -ForegroundColor Green
