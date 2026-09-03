[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
Initialize-ECEngineeringSchema -DatabasePath $DatabasePath
$project=Get-ECProjects -DatabasePath $DatabasePath | Where-Object ProjectCode -eq 'ALPHA-001' | Select-Object -First 1
if(-not $project){throw 'ALPHA-001 was not found. Complete the v0.2 ALPHA import first.'}
$projectId=[int]$project.ProjectId
Clear-ECEngineeringData -DatabasePath $DatabasePath -ProjectId $projectId

# Project acceptance criteria. These are synthetic demonstration thresholds, not universal code limits.
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $projectId -Key 'STRING_VOC_TOLERANCE_PCT' -Value 5 -Unit '%' -Description 'Allowed deviation between measured and temperature-corrected expected string Voc.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $projectId -Key 'MIN_STRING_IR_MOHM' -Value 100 -Unit 'MOhm' -Description 'Demo minimum string insulation resistance.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $projectId -Key 'DESIGN_MIN_TEMP_C' -Value -10 -Unit 'C' -Description 'Design minimum temperature for cold Voc check.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $projectId -Key 'MAX_CABLE_VDROP_PCT' -Value 2 -Unit '%' -Description 'Demo project voltage-drop limit.'
Set-ECParameter -DatabasePath $DatabasePath -ProjectId $projectId -Key 'MIN_CABLE_IR_MOHM' -Value 100 -Unit 'MOhm' -Description 'Demo minimum cable insulation resistance.'

# String measurements. ALPHA uses two modules/string only to keep the synthetic dataset small.
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-001' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 99.7 -MeasuredIscA 13.1 -MeasuredIRMOhm 520 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-002' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 72.0 -MeasuredIscA 13.0 -MeasuredIRMOhm 480 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-003' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100.0 -MeasuredIscA 13.2 -MeasuredIRMOhm 40 -Polarity 'PASS'
Set-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId -StringCode 'STR-004' -ModuleVocStcV 50.1 -VocTempCoeffPctC -0.25 -MeasurementTempC 25 -MeasuredVocV 100.1 -MeasuredIscA 13.0 -MeasuredIRMOhm 500 -Polarity 'REVERSED'

# Inverter electrical limits.
Set-ECInverterEngineering -DatabasePath $DatabasePath -ProjectId $projectId -InverterCode 'INV-01' -MaxDcVoltageV 120 -MpptMinVoltageV 80 -MpptMaxVoltageV 115 -MaxStringsPerMppt 1
Set-ECInverterEngineering -DatabasePath $DatabasePath -ProjectId $projectId -InverterCode 'INV-02' -MaxDcVoltageV 105 -MpptMinVoltageV 80 -MpptMaxVoltageV 115 -MaxStringsPerMppt 2

# Cable records: one undersized/high-drop DC cable, one healthy cable, one cable with low IR.
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId -CableCode 'DC-CAB-01' -BlockCode 'BLK-01' -FromAssetCode 'STR-001' -ToAssetCode 'INV-01' -ConductorMaterial CU -PhaseType DC -DesignSizeMm2 6 -InstalledSizeMm2 4 -LengthM 100 -DesignCurrentA 13 -SystemVoltageV 100 -MaxVoltageDropPct 2 -MeasuredIRMOhm 500
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId -CableCode 'DC-CAB-02' -BlockCode 'BLK-02' -FromAssetCode 'STR-003' -ToAssetCode 'INV-02' -ConductorMaterial CU -PhaseType DC -DesignSizeMm2 6 -InstalledSizeMm2 6 -LengthM 20 -DesignCurrentA 13 -SystemVoltageV 100 -MaxVoltageDropPct 2 -MeasuredIRMOhm 500
Set-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId -CableCode 'AC-CAB-01' -BlockCode 'BLK-02' -FromAssetCode 'INV-02' -ConductorMaterial CU -PhaseType AC3 -DesignSizeMm2 35 -InstalledSizeMm2 35 -LengthM 80 -DesignCurrentA 80 -SystemVoltageV 400 -MaxVoltageDropPct 2 -MeasuredIRMOhm 80

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $projectId | Out-Null
Write-Host ''
Write-Host '=== V0.3 ACCEPTANCE CRITERIA ===' -ForegroundColor Cyan
Get-ECParameters -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
Write-Host '=== STRING ENGINEERING ===' -ForegroundColor Cyan
Get-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
Write-Host '=== INVERTER LIMITS ===' -ForegroundColor Cyan
Get-ECInverterEngineering -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
Write-Host '=== CABLE ENGINEERING ===' -ForegroundColor Cyan
Get-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
Write-Host '=== READINESS AFTER ENGINEERING CHECKS ===' -ForegroundColor Yellow
Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $projectId | Format-Table -AutoSize
$findings=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $projectId)
Write-Host "Engineering/data findings: $($findings.Count)" -ForegroundColor Yellow
$findings | Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize
$report=Export-ECReport -DatabasePath $DatabasePath -ProjectId $projectId
Write-Host "Report: $report" -ForegroundColor Green
