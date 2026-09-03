# EnergizeCheck v0.7 - Commissioning Dossier & Document Intelligence

Adds document requirements, evidence/version tracking, approval and review history, controlled-reference checks, SHA-256 evidence integrity, dossier completeness, handover readiness and automated dossier packaging.

The synthetic scenario deliberately creates eight document/handover findings while all PV, BESS and grid engineering gates are healthy.

```powershell
Set-Location C:\Projects\EnergizeCheck
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Upgrade-EnergizeCheck-v07.ps1
.\Load-ALPHA-DossierDemo.ps1
.\Start-EnergizeCheck.ps1 -Gui
```

After inspection:
```powershell
.\Repair-ALPHA-DossierDemo.ps1
```
