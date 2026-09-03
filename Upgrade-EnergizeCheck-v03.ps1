[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
if(-not (Test-Path -LiteralPath $DatabasePath)){throw "Database not found: $DatabasePath"}
$archive=Join-Path $PSScriptRoot 'data\archive';New-Item -ItemType Directory -Path $archive -Force|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';Copy-Item $DatabasePath (Join-Path $archive "energizecheck-before-v03-$stamp.db") -Force
Initialize-ECEngineeringSchema -DatabasePath $DatabasePath
$projects=@(Get-ECProjects -DatabasePath $DatabasePath)
foreach($p in $projects){
 Set-ECParameter -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId) -Key 'STRING_VOC_TOLERANCE_PCT' -Value 5 -Unit '%' -Description 'Default demo tolerance; configure per project.'
 Set-ECParameter -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId) -Key 'MIN_STRING_IR_MOHM' -Value 100 -Unit 'MOhm' -Description 'Default demo threshold; configure per project.'
 Set-ECParameter -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId) -Key 'DESIGN_MIN_TEMP_C' -Value -10 -Unit 'C' -Description 'Design minimum temperature for cold Voc calculation.'
 Set-ECParameter -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId) -Key 'MAX_CABLE_VDROP_PCT' -Value 2 -Unit '%' -Description 'Default demo voltage-drop limit; configure per project.'
 Set-ECParameter -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId) -Key 'MIN_CABLE_IR_MOHM' -Value 100 -Unit 'MOhm' -Description 'Default demo threshold; configure per project.'
}
Write-Host 'EnergizeCheck v0.3 schema and configurable engineering criteria are ready.' -ForegroundColor Green
Write-Host "Database backup: $archive" -ForegroundColor DarkGray
