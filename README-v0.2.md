# EnergizeCheck v0.2

PowerShell + WPF + SQLite desktop application for PV/BESS project integrity and commissioning readiness.

## v0.2 capabilities

- Multi-project Project Manager
- New project creation with PV/BESS metadata
- Real CSV import workflow
- Automatic header matching plus user-adjustable column mapping
- CSV preview and pre-import validation
- Eight import types: Plant Structure, String Schedule, Documents, Installed Equipment, Delivery Register, Materials, Tests, NCR / Punch List
- Import audit log and row-level error capture
- Project-scoped SQLite asset model
- Engineering rules engine and block readiness scoring
- Project-specific HTML readiness reports
- Existing v0.1 database is backed up by Upgrade-EnergizeCheck-v02.ps1 before the v0.2 demo database is initialized

## Recommended import order

1. Plant Structure
2. String Schedule
3. Documents
4. Installed Equipment
5. Delivery Register
6. Materials
7. Tests
8. NCR / Punch List

## Launch

```powershell
Set-Location C:\Projects\EnergizeCheck
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Start-EnergizeCheck.ps1 -Gui
```

## Reset the synthetic demo

```powershell
.\Upgrade-EnergizeCheck-v02.ps1
```

## Templates

Sample CSV templates are in the `templates` folder. These are deliberately small and use synthetic values.
