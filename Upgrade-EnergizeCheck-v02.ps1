[CmdletBinding()]
param(
    [switch]$NoDemo,
    [string]$DatabasePath = (Join-Path $PSScriptRoot 'data\energizecheck.db')
)
$ErrorActionPreference = 'Stop'

Write-Host '=== EnergizeCheck v0.2 Database Upgrade ===' -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name PSSQLite)) { throw "PSSQLite is not installed. Run .\Install-Dependencies.ps1 first." }
Import-Module PSSQLite -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force

if (Test-Path $DatabasePath) {
    $archive = Join-Path $PSScriptRoot 'data\archive'
    New-Item -ItemType Directory -Path $archive -Force | Out-Null
    $backup = Join-Path $archive ("energizecheck-v01-{0}.db" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $DatabasePath -Destination $backup -Force
    Write-Host "Existing v0.1 database backed up to: $backup" -ForegroundColor Yellow
}

Initialize-ECDatabase -DatabasePath $DatabasePath -Reset
if (-not $NoDemo) {
    Add-ECDemoData -DatabasePath $DatabasePath
    Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId 1 | Out-Null
    Show-ECSummary -DatabasePath $DatabasePath -ProjectId 1
}
Write-Host ''
Write-Host 'EnergizeCheck v0.2 database is ready.' -ForegroundColor Green
Write-Host 'Launch with: .\Start-EnergizeCheck.ps1 -Gui' -ForegroundColor Green
