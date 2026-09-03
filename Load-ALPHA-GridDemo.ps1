[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
Initialize-ECV06Schema -DatabasePath $DatabasePath
$p=Get-ECProjects -DatabasePath $DatabasePath|Where-Object ProjectCode -eq 'ALPHA-001'|Select-Object -First 1
if($null -eq $p){throw 'ALPHA-001 not found. Complete the prior demo stages first.'}
$ProjectId=[int]$p.ProjectId

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' GRID CONNECTION & PROTECTION DEMO' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$repairBess=Join-Path $PSScriptRoot 'Repair-ALPHA-BESSDemo.ps1';if(Test-Path $repairBess){& $repairBess -DatabasePath $DatabasePath | Out-Null}

$old=Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT block_id FROM blocks WHERE project_id=@p AND block_code='GRID-01';" -SqlParameters @{p=$ProjectId}
if($null -ne $old){Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM assets WHERE project_id=@p AND block_id=@b;' -SqlParameters @{p=$ProjectId;b=[int]$old.block_id}|Out-Null;Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM blocks WHERE block_id=@b;' -SqlParameters @{b=[int]$old.block_id}|Out-Null}
Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO blocks(project_id,block_code,block_name) VALUES(@p,'GRID-01','Grid Connection and Protection');" -SqlParameters @{p=$ProjectId}|Out-Null
$BlockId=[int](Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT block_id FROM blocks WHERE project_id=@p AND block_code='GRID-01';" -SqlParameters @{p=$ProjectId}).block_id
function Add-GridAsset([string]$Code,[string]$Type,[string]$Parent,[string]$Manufacturer,[string]$Model){$parentId=$null;if(-not [string]::IsNullOrWhiteSpace($Parent)){$parentId=(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$Parent}).asset_id};Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,status,source)
VALUES(@p,@b,@t,@c,@parent,@m,@model,'INSTALLED','GRID-DEMO');
'@ -SqlParameters @{p=$ProjectId;b=$BlockId;t=$Type;c=$Code;parent=$parentId;m=$Manufacturer;model=$Model}|Out-Null}
Add-GridAsset 'GRID-SYS-01' 'GRID_SYSTEM' '' 'DemoGrid' 'POI-System'
Add-GridAsset 'POI-01' 'POI' 'GRID-SYS-01' 'DemoGrid' '20kV-POI'
Add-GridAsset 'MV-SWG-01' 'MV_SWITCHGEAR' 'GRID-SYS-01' 'DemoSwitchgear' '20kV-AIS'
Add-GridAsset 'BREAKER-01' 'MV_BREAKER' 'MV-SWG-01' 'DemoBreaker' 'VCB-20kV'
Add-GridAsset 'CT-01' 'CT' 'MV-SWG-01' 'DemoCT' '800-1A'
Add-GridAsset 'VT-01' 'VT' 'MV-SWG-01' 'DemoVT' '20kV-100V'
Add-GridAsset 'RELAY-01' 'PROTECTION_RELAY' 'MV-SWG-01' 'DemoRelay' 'P546'
Add-GridAsset 'TRF-GRID-01' 'GRID_TRANSFORMER' 'GRID-SYS-01' 'DemoTransformer' '20-0.8kV-8MVA'
Add-GridAsset 'PPC-GRID-01' 'PPC' 'GRID-SYS-01' 'DemoControls' 'PlantController-A'
Add-GridAsset 'METER-01' 'REVENUE_METER' 'POI-01' 'DemoMeter' 'Class-0.2S'

Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_RELAY_SETTING_DEVIATION_PCT' -Value 2 -Unit '%' -Description 'Maximum allowed deviation between installed and approved relay setting values.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MIN_TRANSFORMER_IR_MOHM' -Value 500 -Unit 'MOhm' -Description 'Demo minimum transformer insulation resistance.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_TRANSFORMER_RATIO_ERROR_PCT' -Value 0.5 -Unit '%' -Description 'Demo maximum transformer ratio error.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_ACTIVE_POWER_TRACKING_ERROR_PCT' -Value 2 -Unit '%' -Description 'Maximum active-power setpoint tracking error.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_REACTIVE_POWER_TRACKING_ERROR_PCT' -Value 2 -Unit '%' -Description 'Maximum reactive-power setpoint tracking error.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_FREQUENCY_RESPONSE_ERROR_PCT' -Value 2 -Unit '%' -Description 'Demo maximum frequency-response error.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $ProjectId -Key 'GRID_MAX_VOLTAGE_RESPONSE_ERROR_PCT' -Value 2 -Unit '%' -Description 'Demo maximum voltage-response error.'
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'RELAY-01' -SettingKey 'OC_PICKUP_A' -ApprovedValue 620 -InstalledValue 700 -Unit 'A' -ApprovedRevision 'PROT-REV-C'
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'CT-01' -SettingKey 'CT_RATIO' -ApprovedValue 800 -InstalledValue 600 -Unit 'A/1A' -ApprovedRevision 'SLD-REV-D'
Set-ECGridSetting -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'VT-01' -SettingKey 'VT_RATIO' -ApprovedValue 200 -InstalledValue 190 -Unit 'V/V' -ApprovedRevision 'SLD-REV-D'
Set-ECGridTransformerTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'TRF-GRID-01' -TestType 'INSULATION_RESISTANCE' -MeasuredValue 300 -Unit 'MOhm' -Details 'Intentionally below demo acceptance limit.'
Set-ECGridTransformerTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'TRF-GRID-01' -TestType 'RATIO_ERROR_PCT' -MeasuredValue 1.2 -Unit '%' -Details 'Intentional ratio error.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'BREAKER-01' -CheckType 'BREAKER_FUNCTIONAL' -Result 'FAIL' -Details 'Remote trip did not operate breaker on first test.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'ANTI_ISLANDING' -Result 'FAIL' -Details 'Loss-of-grid simulation did not produce approved shutdown sequence.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'GRID_SYNCHRONIZATION' -Result 'FAIL' -Details 'Synch-check permissive not achieved.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'POI-01' -CheckType 'EXPORT_LIMITATION' -Result 'FAIL' -Details 'Plant exceeded configured export cap during step test.'
Set-ECGridCommissioningCheck -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -CheckType 'PPC_GRID_COMMUNICATION' -Result 'FAIL' -Details 'Mandatory grid-control feedback points remained stale.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'ACTIVE_POWER_TRACKING' -CommandedValue 4 -MeasuredValue 3.52 -Unit 'MW' -Details 'Intentional active-power tracking error.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'REACTIVE_POWER_TRACKING' -CommandedValue 2 -MeasuredValue 1.70 -Unit 'Mvar' -Details 'Intentional reactive-power tracking error.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'FREQUENCY_RESPONSE' -CommandedValue 100 -MeasuredValue 94 -Unit '% target' -Details 'Intentional frequency-response failure.'
Set-ECGridResponseTest -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode 'PPC-GRID-01' -ResponseType 'VOLTAGE_RESPONSE' -CommandedValue 100 -MeasuredValue 96 -Unit '% target' -Details 'Intentional voltage-control failure.'
Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId|Out-Null
$grid=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId|Where-Object {$_.Rule -like 'GRID-*'})
Write-Host '';Write-Host 'GRID DEMO LOADED' -ForegroundColor Green;Write-Host "Grid findings: $($grid.Count)" -ForegroundColor Yellow;$grid|Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize;Write-Host '';Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId|Format-Table -AutoSize
if($grid.Count -ne 14){Write-Warning "Expected 14 GRID findings but validation returned $($grid.Count)."}
