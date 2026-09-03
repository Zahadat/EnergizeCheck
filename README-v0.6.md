# EnergizeCheck v0.6 - Grid Connection & Protection Intelligence

Adds POI, MV switchgear, breaker, CT/VT, protection relay, grid transformer, PPC response and grid-code style commissioning checks to the existing PV + BESS platform.

Demo numeric thresholds are configurable project parameters for software demonstration only; they are not represented as universal IEC, EN, utility, manufacturer or grid-code limits.

```powershell
Set-Location C:\Projects\EnergizeCheck
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Upgrade-EnergizeCheck-v06.ps1
.\Load-ALPHA-GridDemo.ps1
.\Start-EnergizeCheck.ps1 -Gui
```

After inspection:
```powershell
.\Repair-ALPHA-GridDemo.ps1
```
