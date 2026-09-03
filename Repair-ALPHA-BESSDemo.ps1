[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
$p=Get-ECProjects -DatabasePath $DatabasePath|Where-Object ProjectCode -eq 'ALPHA-001'|Select-Object -First 1
if($null -eq $p){throw 'ALPHA-001 not found.'}
$ProjectId=[int]$p.ProjectId

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' BESS COMMISSIONING REMEDIATION' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan

Set-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -RackCode 'RACK-03' -SocPct 80.5 -RackVoltageV 815 -MinCellVoltageV 3.30 -MaxCellVoltageV 3.34 -MinTempC 25 -MaxTempC 30
Write-Host '[FIX] RACK-03 balanced: SOC, rack voltage, cell spread and thermal spread normalized.' -ForegroundColor Green

Set-ECBessPcsEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -PcsCode 'PCS-01' -RatedPowerMW 5 -DcVoltageV 820 -ApprovedFirmware 'PCS-FW-2.4.1' -InstalledFirmware 'PCS-FW-2.4.1'
Write-Host '[FIX] PCS firmware aligned with approved baseline.' -ForegroundColor Green

Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PCS-01' -CheckType 'PCS_BMS_COMMUNICATION' -Result 'PASS' -Details 'Stable end-to-end PCS/BMS communication verified with required status and control points.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'BESS-SYS-01' -CheckType 'EMERGENCY_STOP_CHAIN' -Result 'PASS' -Details 'All required local and remote E-stop initiation points verified through safe shutdown and reset.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'HVAC-01' -CheckType 'HVAC_FUNCTIONAL' -Result 'PASS' -Details 'Primary and redundant HVAC stages, alarms and control feedback verified.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'FIRE-01' -CheckType 'FIRE_SYSTEM_FUNCTIONAL' -Result 'PASS' -Details 'Approved fire detection and shutdown cause-and-effect sequence verified.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'EMS-PPC-01' -CheckType 'EMS_PPC_INTERFACE' -Result 'PASS' -Details 'Active/reactive power setpoints, scaling, feedback and response verified end-to-end.'
Write-Host '[FIX] Communications, E-stop, HVAC, fire-system and EMS/PPC commissioning checks passed.' -ForegroundColor Green

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId|Out-Null
$bess=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId|Where-Object {$_.Rule -like 'BESS-*'})
Write-Host ''
Write-Host "Remaining BESS findings: $($bess.Count)" -ForegroundColor Yellow
if($bess.Count -gt 0){$bess|Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize}else{Write-Host 'BESS COMMISSIONING GATES PASSED.' -ForegroundColor Green}
Write-Host ''
Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId|Format-Table -AutoSize
