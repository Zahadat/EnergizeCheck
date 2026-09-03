# EnergizeCheck v0.5 - BESS Commissioning Intelligence

v0.5 extends the existing PV commissioning and QA/QC platform with battery energy storage system (BESS) engineering intelligence.

## Added BESS hierarchy
- BESS system
- PCS
- BESS transformer
- Battery container
- Battery racks
- BMS
- HVAC
- Fire system
- EMS/PPC

## Added calculated/validated checks
- Rack SOC imbalance
- Rack voltage deviation
- Cell-voltage spread
- Rack temperature spread
- PCS/BMS communication
- Emergency-stop chain
- HVAC functional commissioning
- Fire detection/suppression functional commissioning
- PCS firmware baseline
- EMS/PPC interface validation

## Configurable demo criteria
The values loaded by the ALPHA demonstration are project parameters for software demonstration only. They are not represented as universal manufacturer, IEC, NFPA, UL, or grid-code acceptance limits. Real projects must load approved project/manufacturer requirements.

## Demo workflow
```powershell
Set-Location C:\Projects\EnergizeCheck
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Upgrade-EnergizeCheck-v05.ps1
.\Load-ALPHA-BESSDemo.ps1
.\Start-EnergizeCheck.ps1 -Gui
```

After inspecting the ten intentional BESS findings:
```powershell
.\Repair-ALPHA-BESSDemo.ps1
```
