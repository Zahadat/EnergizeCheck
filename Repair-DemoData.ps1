[CmdletBinding()]
param(
    [switch]$OpenReport,
    [int]$ProjectId=1,
    [string]$DatabasePath = (Join-Path $PSScriptRoot 'data\energizecheck.db')
)
$ErrorActionPreference = 'Stop'
Import-Module PSSQLite -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
Repair-ECDemoData -DatabasePath $DatabasePath -ProjectId $ProjectId
Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId | Out-Null
Show-ECSummary -DatabasePath $DatabasePath -ProjectId $ProjectId
$report = Export-ECReport -DatabasePath $DatabasePath -ProjectId $ProjectId
if ($OpenReport) { Start-Process $report }
