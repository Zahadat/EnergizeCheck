[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
$project=Get-ECProjects -DatabasePath $DatabasePath | Where-Object ProjectCode -eq 'ALPHA-001' | Select-Object -First 1
if(-not $project){throw 'ALPHA-001 not found.'}
$projectId=[int]$project.ProjectId

# Reintroduce five controlled defects only for demonstrating v0.4 diagnosis/workflow.
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-002' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 72 -MeasuredIscA 13 -MeasuredIRMOhm 480 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-003' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100 -MeasuredIscA 13.2 -MeasuredIRMOhm 40 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-004' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100.1 -MeasuredIscA 13 -MeasuredIRMOhm 500 -Polarity 'REVERSED'
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId -CableCode 'DC-CAB-01' -BlockCode 'BLK-01' -FromAssetCode 'STR-001' -ToAssetCode 'INV-01' -ConductorMaterial CU -PhaseType DC -DesignSizeMm2 6 -InstalledSizeMm2 4 -LengthM 100 -DesignCurrentA 13 -SystemVoltageV 100 -MaxVoltageDropPct 2 -MeasuredIRMOhm 500

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $projectId | Out-Null
Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId $projectId
Write-Host ''
Write-Host '=== V0.4 DIAGNOSTIC DEMO LOADED ===' -ForegroundColor Yellow
Get-ECKPIs -DatabasePath $DatabasePath -ProjectId $projectId | Format-List
Write-Host 'Current findings:' -ForegroundColor Yellow
Get-ECFindings -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize
Write-Host ''
Write-Host 'STR-002 diagnostic guidance:' -ForegroundColor Cyan
Get-ECDiagnosticsForAsset -DatabasePath $DatabasePath -ProjectId $projectId -AssetCode 'STR-002' | Format-Table Rule,Priority,PossibleCause,RecommendedAction -Wrap -AutoSize
