[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
$archive=Join-Path $PSScriptRoot 'data\archive';New-Item -ItemType Directory -Path $archive -Force|Out-Null
if(Test-Path $DatabasePath){$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';Copy-Item $DatabasePath (Join-Path $archive "energizecheck-before-v07-$stamp.db") -Force}
Initialize-ECV07Schema -DatabasePath $DatabasePath
Write-Host 'EnergizeCheck v0.7 dossier/document schema ready.' -ForegroundColor Green
Write-Host "Database: $DatabasePath" -ForegroundColor DarkGray
