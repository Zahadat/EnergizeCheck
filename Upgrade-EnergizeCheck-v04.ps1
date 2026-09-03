[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force

if(-not (Test-Path -LiteralPath $DatabasePath)){throw "Database not found: $DatabasePath"}
$archive=Join-Path $PSScriptRoot 'data\archive'
New-Item -ItemType Directory -Path $archive -Force | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $archive "energizecheck-pre-v04-$stamp.db"
Copy-Item -LiteralPath $DatabasePath -Destination $backup -Force
Write-Host "Database backup: $backup" -ForegroundColor DarkGray

Initialize-ECV04Schema -DatabasePath $DatabasePath
Write-Host ''
Write-Host '=== ENERGIZECHECK V0.4 UPGRADE COMPLETE ===' -ForegroundColor Green
Write-Host 'Asset Explorer, diagnostic knowledge, finding lifecycle and readiness drill-down are ready.' -ForegroundColor Green
Write-Host ''
foreach($p in @(Get-ECProjects -DatabasePath $DatabasePath)){
    $k=Get-ECKPIs -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId)
    Write-Host ("{0}: Readiness {1}% | Blockers {2} | Warnings {3}" -f $p.ProjectCode,$k.ProjectReadiness,$k.Blockers,$k.Warnings) -ForegroundColor Cyan
}
