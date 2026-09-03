[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
$p=Get-ECProjects -DatabasePath $DatabasePath|Where-Object ProjectCode -eq 'ALPHA-001'|Select-Object -First 1;if($null -eq $p){throw 'ALPHA-001 not found.'};$ProjectId=[int]$p.ProjectId
Write-Host '';Write-Host '=============================================' -ForegroundColor Cyan;Write-Host ' GRID & PROTECTION COMMISSIONING REMEDIATION' -ForegroundColor Cyan;Write-Host '=============================================' -ForegroundColor Cyan
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'RELAY-01' -SettingKey 'OC_PICKUP_A' -ApprovedValue 620 -InstalledValue 620 -Unit 'A' -ApprovedRevision 'PROT-REV-C'
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'CT-01' -SettingKey 'CT_RATIO' -ApprovedValue 800 -InstalledValue 800 -Unit 'A/1A' -ApprovedRevision 'SLD-REV-D'
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'VT-01' -SettingKey 'VT_RATIO' -ApprovedValue 200 -InstalledValue 200 -Unit 'V/V' -ApprovedRevision 'SLD-REV-D'
Write-Host '[FIX] Relay, CT and VT aligned with approved baseline.' -ForegroundColor Green
Set-ECGridTransformerTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'TRF-GRID-01' -TestType 'INSULATION_RESISTANCE' -MeasuredValue 850 -Unit 'MOhm' -Details 'Corrective retest passed.'
Set-ECGridTransformerTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'TRF-GRID-01' -TestType 'RATIO_ERROR_PCT' -MeasuredValue 0.2 -Unit '%' -Details 'Corrective ratio retest passed.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'BREAKER-01' -CheckType 'BREAKER_FUNCTIONAL' -Result 'PASS' -Details 'Local/remote close-trip, interlocks and trip path verified.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'ANTI_ISLANDING' -Result 'PASS' -Details 'Approved loss-of-grid shutdown sequence verified.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'GRID_SYNCHRONIZATION' -Result 'PASS' -Details 'Synchronization permissive verified.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'EXPORT_LIMITATION' -Result 'PASS' -Details 'Export cap and curtailment response verified.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -CheckType 'PPC_GRID_COMMUNICATION' -Result 'PASS' -Details 'Mandatory grid-control points verified end-to-end.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'ACTIVE_POWER_TRACKING' -CommandedValue 4 -MeasuredValue 3.96 -Unit 'MW' -Details 'Corrective response within tolerance.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'REACTIVE_POWER_TRACKING' -CommandedValue 2 -MeasuredValue 1.98 -Unit 'Mvar' -Details 'Corrective response within tolerance.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'FREQUENCY_RESPONSE' -CommandedValue 100 -MeasuredValue 99 -Unit '% target' -Details 'Retest within envelope.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'VOLTAGE_RESPONSE' -CommandedValue 100 -MeasuredValue 99 -Unit '% target' -Details 'Retest within envelope.'
Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId|Out-Null
$grid=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId|Where-Object {$_.Rule -like 'GRID-*'})
Write-Host '';Write-Host "Remaining GRID findings: $($grid.Count)" -ForegroundColor Yellow;if($grid.Count -gt 0){$grid|Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize}else{Write-Host 'GRID CONNECTION & PROTECTION GATES PASSED.' -ForegroundColor Green};Write-Host '';Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId|Format-Table -AutoSize
