[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
$project=Get-ECProjects -DatabasePath $DatabasePath | Where-Object ProjectCode -eq 'ALPHA-001' | Select-Object -First 1
if(-not $project){throw 'ALPHA-001 not found.'}
$projectId=[int]$project.ProjectId
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-002' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100 -MeasuredIscA 13 -MeasuredIRMOhm 480 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-003' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100 -MeasuredIscA 13.2 -MeasuredIRMOhm 450 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-004' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100.1 -MeasuredIscA 13 -MeasuredIRMOhm 500 -Polarity 'PASS'
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId -CableCode 'DC-CAB-01' -BlockCode 'BLK-01' -FromAssetCode 'STR-001' -ToAssetCode 'INV-01' -ConductorMaterial CU -PhaseType DC -DesignSizeMm2 6 -InstalledSizeMm2 6 -LengthM 20 -DesignCurrentA 13 -SystemVoltageV 100 -MaxVoltageDropPct 2 -MeasuredIRMOhm 500
Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $projectId | Out-Null
Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId $projectId
Write-Host ''
Write-Host '=== V0.4 DIAGNOSTIC DEMO REMEDIATED ===' -ForegroundColor Green
Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
$remaining=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $projectId)
Write-Host "Remaining findings: $($remaining.Count)" -ForegroundColor Yellow
if($remaining.Count -eq 0){Write-Host 'ALL CURRENT ENGINEERING GATES PASSED. Historical finding cases remain available as CLOSED audit records.' -ForegroundColor Green}
