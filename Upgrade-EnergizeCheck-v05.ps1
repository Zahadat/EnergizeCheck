[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force

if(-not (Test-Path -LiteralPath $DatabasePath)){throw "Database not found: $DatabasePath"}
$archive=Join-Path $PSScriptRoot 'data\archive'
New-Item -ItemType Directory -Path $archive -Force|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $archive ("energizecheck-before-v05-$stamp.db")
Copy-Item $DatabasePath $backup -Force
Write-Host "Database backup: $backup" -ForegroundColor DarkGray

Initialize-ECV05Schema -DatabasePath $DatabasePath
$integrity=(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'PRAGMA integrity_check;').'integrity_check'
if($integrity -ne 'ok'){throw "SQLite integrity check failed: $integrity"}
Write-Host 'EnergizeCheck v0.5 BESS schema installed.' -ForegroundColor Green
Write-Host 'Existing PV project data and finding workflow are preserved.' -ForegroundColor Green
