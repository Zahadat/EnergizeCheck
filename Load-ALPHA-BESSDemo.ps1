[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
Initialize-ECV05Schema -DatabasePath $DatabasePath

$p=Get-ECProjects -DatabasePath $DatabasePath|Where-Object ProjectCode -eq 'ALPHA-001'|Select-Object -First 1
if($null -eq $p){throw 'ALPHA-001 does not exist. Complete the earlier EnergizeCheck demo first.'}
$ProjectId=[int]$p.ProjectId

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' ENERGIZECHECK v0.5 - BESS DEMO LOADER' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan

# Normalize the PV side to a healthy baseline so this demonstration isolates BESS findings.
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -StringCode 'STR-002' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100 -MeasuredIscA 13 -MeasuredIRMOhm 480 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -StringCode 'STR-003' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100 -MeasuredIscA 13 -MeasuredIRMOhm 450 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -StringCode 'STR-004' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100.1 -MeasuredIscA 13 -MeasuredIRMOhm 500 -Polarity 'PASS'
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -CableCode 'DC-CAB-01' -BlockCode 'BLK-01' -ConductorMaterial CU -PhaseType DC -DesignSizeMm2 6 -InstalledSizeMm2 6 -LengthM 20 -DesignCurrentA 13 -SystemVoltageV 100 -MaxVoltageDropPct 2 -MeasuredIRMOhm 500

Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE projects SET project_type='HYBRID',bess_capacity_mwh=10,status='COMMISSIONING',updated_at=datetime('now') WHERE project_id=@p;" -SqlParameters @{p=$ProjectId}|Out-Null

# Remove the prior synthetic BESS hierarchy/data if this loader is re-run. Finding cases are intentionally preserved.
$oldBlock=Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT block_id FROM blocks WHERE project_id=@p AND block_code='BESS-01';" -SqlParameters @{p=$ProjectId}
if($null -ne $oldBlock){
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM assets WHERE project_id=@p AND block_id=@b;' -SqlParameters @{p=$ProjectId;b=[int]$oldBlock.block_id}|Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM blocks WHERE block_id=@b;' -SqlParameters @{b=[int]$oldBlock.block_id}|Out-Null
}

Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO blocks(project_id,block_code,block_name) VALUES(@p,'BESS-01','Battery Energy Storage System 01');" -SqlParameters @{p=$ProjectId}|Out-Null
$BlockId=[int](Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT block_id FROM blocks WHERE project_id=@p AND block_code='BESS-01';" -SqlParameters @{p=$ProjectId}).block_id

function Add-BessAsset([string]$Code,[string]$Type,[string]$Parent,[string]$Manufacturer,[string]$Model){
    $parentId=$null
    if(-not [string]::IsNullOrWhiteSpace($Parent)){$parentId=(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$Parent}).asset_id}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,status,source)
VALUES(@p,@b,@t,@c,@parent,@m,@model,'INSTALLED','BESS-DEMO');
'@ -SqlParameters @{p=$ProjectId;b=$BlockId;t=$Type;c=$Code;parent=$parentId;m=$Manufacturer;model=$Model}|Out-Null
}

Add-BessAsset 'BESS-SYS-01' 'BESS_SYSTEM' '' 'DemoBESS' '10MWh-System'
Add-BessAsset 'PCS-01' 'PCS' 'BESS-SYS-01' 'DemoPCS' 'PCS-5MW'
Add-BessAsset 'BESS-TRF-01' 'BESS_TRANSFORMER' 'BESS-SYS-01' 'DemoTransformer' '5MVA'
Add-BessAsset 'CONT-01' 'BESS_CONTAINER' 'BESS-SYS-01' 'DemoBattery' 'Container-A'
Add-BessAsset 'RACK-01' 'BESS_RACK' 'CONT-01' 'DemoBattery' 'Rack-Model-A'
Add-BessAsset 'RACK-02' 'BESS_RACK' 'CONT-01' 'DemoBattery' 'Rack-Model-A'
Add-BessAsset 'RACK-03' 'BESS_RACK' 'CONT-01' 'DemoBattery' 'Rack-Model-A'
Add-BessAsset 'RACK-04' 'BESS_RACK' 'CONT-01' 'DemoBattery' 'Rack-Model-A'
Add-BessAsset 'BMS-01' 'BMS' 'CONT-01' 'DemoBMS' 'BMS-A'
Add-BessAsset 'HVAC-01' 'HVAC' 'CONT-01' 'DemoHVAC' 'HVAC-A'
Add-BessAsset 'FIRE-01' 'FIRE_SYSTEM' 'CONT-01' 'DemoFire' 'FSS-A'
Add-BessAsset 'EMS-PPC-01' 'EMS_PPC' 'BESS-SYS-01' 'DemoControls' 'EMS-PPC-A'

Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'BESS_MAX_RACK_SOC_DEVIATION_PCT' -Value 3 -Unit '%' -Description 'Maximum allowed SOC deviation from peer-rack average during commissioning.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'BESS_MAX_RACK_VOLTAGE_DEVIATION_PCT' -Value 2 -Unit '%' -Description 'Maximum allowed rack-voltage deviation from peer-rack average.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'BESS_MAX_CELL_VOLTAGE_SPREAD_MV' -Value 50 -Unit 'mV' -Description 'Maximum allowed cell-voltage spread within a rack.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'BESS_MAX_RACK_TEMP_SPREAD_C' -Value 8 -Unit 'C' -Description 'Maximum allowed temperature spread within a rack.'

Set-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -RackCode 'RACK-01' -SocPct 82 -RackVoltageV 820 -MinCellVoltageV 3.30 -MaxCellVoltageV 3.34 -MinTempC 25 -MaxTempC 29
Set-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -RackCode 'RACK-02' -SocPct 81 -RackVoltageV 818 -MinCellVoltageV 3.29 -MaxCellVoltageV 3.33 -MinTempC 24 -MaxTempC 30
Set-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -RackCode 'RACK-03' -SocPct 73 -RackVoltageV 780 -MinCellVoltageV 3.18 -MaxCellVoltageV 3.36 -MinTempC 22 -MaxTempC 38
Set-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -RackCode 'RACK-04' -SocPct 82.5 -RackVoltageV 821 -MinCellVoltageV 3.30 -MaxCellVoltageV 3.335 -MinTempC 25 -MaxTempC 30

Set-ECBessPcsEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId -PcsCode 'PCS-01' -RatedPowerMW 5 -DcVoltageV 820 -ApprovedFirmware 'PCS-FW-2.4.1' -InstalledFirmware 'PCS-FW-2.3.7'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PCS-01' -CheckType 'PCS_BMS_COMMUNICATION' -Result 'FAIL' -Details 'PCS receives intermittent BMS heartbeat and invalid rack availability status.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'BESS-SYS-01' -CheckType 'EMERGENCY_STOP_CHAIN' -Result 'FAIL' -Details 'Remote E-stop input did not trip the full commanded shutdown chain.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'HVAC-01' -CheckType 'HVAC_FUNCTIONAL' -Result 'FAIL' -Details 'Container temperature command did not start redundant HVAC stage.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'FIRE-01' -CheckType 'FIRE_SYSTEM_FUNCTIONAL' -Result 'FAIL' -Details 'Fire panel shutdown interface to BESS controls not proven.'
Set-ECBessCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'EMS-PPC-01' -CheckType 'EMS_PPC_INTERFACE' -Result 'FAIL' -Details 'Reactive-power setpoint scaling mismatch during interface test.'

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId|Out-Null
$findings=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
$bess=@($findings|Where-Object {$_.Rule -like 'BESS-*'})

Write-Host ''
Write-Host 'BESS DEMO LOADED' -ForegroundColor Green
Write-Host "BESS findings: $($bess.Count)" -ForegroundColor Yellow
$bess|Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize
Write-Host ''
Write-Host 'BESS readiness:' -ForegroundColor Cyan
Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId|Format-Table -AutoSize
if($bess.Count -ne 10){Write-Warning "Expected 10 BESS findings but validation returned $($bess.Count). Review the displayed rules before continuing."}
