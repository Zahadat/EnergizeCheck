# EnergizeCheck

**PV + BESS + Grid Commissioning Intelligence Platform**

EnergizeCheck is a Windows desktop engineering decision-support prototype for renewable-energy commissioning and handover. It combines PowerShell, WPF, and SQLite to model project assets, validate commissioning data, calculate engineering acceptance checks, diagnose failures, manage corrective-action workflows, and determine energization/handover readiness.

> Portfolio / R&D project. Acceptance thresholds in the included demo scenarios are configurable demonstration values and must not be treated as universal manufacturer, IEC, utility, or grid-code limits.

## Why I built it

Utility-scale PV and BESS projects generate large amounts of fragmented commissioning information: string tests, cable checks, BESS rack measurements, protection settings, transformer tests, NCRs, document revisions, approvals, and handover evidence.

The core problem is not simply storing the data. The challenge is determining:

- Is the installation technically ready?
- Which exact asset or subsystem is blocking energization?
- What engineering condition failed?
- What should the commissioning team investigate?
- Has the corrective action been retested?
- Is the documentation complete and on the correct revision?
- Is the project actually ready for handover?

EnergizeCheck was built as an offline prototype to explore that workflow.

## Technology

- **PowerShell** â€” application logic, engineering rules, automation and packaging
- **WPF / XAML** â€” Windows desktop UI
- **SQLite** â€” local relational engineering database
- **PSSQLite** â€” PowerShell/SQLite integration
- **HTML / CSV** â€” readiness reports and handover dossier output
- **SHA-256** â€” evidence-file integrity tracking

## Major capabilities

### 1. Project and asset modelling
Hierarchical asset model covering:

```text
PV
Project -> Block -> Inverter -> MPPT -> String -> Module

BESS
BESS Block -> BESS System -> Container -> Rack
                           -> PCS / BMS / HVAC / Fire / EMS-PPC

GRID
Grid Block -> POI
           -> MV Switchgear -> Breaker / CT / VT / Protection Relay
           -> Transformer
           -> PPC / Metering
```

### 2. Project data ingestion
- CSV import
- automatic column mapping
- pre-import validation
- row-level import errors
- import audit history

### 3. PV engineering intelligence
Examples include:
- temperature-corrected expected string Voc
- measured-vs-expected Voc deviation
- string insulation resistance
- polarity
- inverter maximum DC voltage
- MPPT operating limits
- strings-per-MPPT limits
- conductor-size checks
- calculated cable voltage drop
- cable insulation resistance

### 4. BESS commissioning intelligence
Examples include:
- rack SOC imbalance
- rack-voltage deviation
- cell-voltage spread
- thermal spread
- PCS/BMS communications
- emergency-stop chain
- HVAC functional test
- fire-system functional test
- PCS firmware baseline
- EMS/PPC interface validation

### 5. Grid and protection intelligence
Examples include:
- protection-relay settings vs approved baseline
- CT ratio
- VT ratio
- MV breaker functional testing
- transformer insulation resistance
- transformer ratio error
- anti-islanding
- grid synchronization
- active-power response
- reactive-power response
- frequency response
- voltage-control response
- export limitation
- PPC/grid communications

### 6. Diagnostic intelligence
Each engineering finding can map to:
- diagnosis
- possible causes
- investigation guidance
- recommended corrective actions
- priority

### 7. Persistent finding workflow
Engineering findings can move through:

```text
OPEN
-> ACKNOWLEDGED
-> UNDER INVESTIGATION
-> CORRECTIVE ACTION
-> READY FOR RETEST
-> CLOSED
```

The workflow stores assignment, root cause, corrective action, retest result, timestamps, and audit history.

### 8. Commissioning dossier and document intelligence
- document requirement matrix
- evidence registration
- revision control
- review state
- approval state
- controlled-document references
- SHA-256 evidence integrity
- dossier-section completeness
- handover readiness
- timestamped handover dossier generation

The platform deliberately distinguishes:

```text
TECHNICAL READINESS
+
QA / WORKFLOW CLOSURE
+
DOCUMENT COMPLETENESS
=
READY FOR ENERGIZATION / HANDOVER
```

## Demonstrated lifecycle

The synthetic demonstration project exercises the full flow:

```text
Load intentionally defective project data
            |
            v
Run engineering validation
            |
            v
Generate asset-level blockers
            |
            v
Provide diagnostic guidance
            |
            v
Assign / investigate / record root cause
            |
            v
Apply corrective action
            |
            v
Retest
            |
            v
Automatically revalidate
            |
            v
Close findings
            |
            v
Verify documentation and revisions
            |
            v
Generate handover dossier
```

The final synthetic scenario reaches:

- PV engineering checks: PASS
- BESS commissioning checks: PASS
- Grid/protection checks: PASS
- engineering findings: 0
- technical readiness: 100%
- document readiness: 100%
- handover status: READY FOR HANDOVER

## Repository structure

A typical local installation contains:

```text
EnergizeCheck/
|-- Modules/
|   `-- EnergizeCheck.psm1
|-- database/
|   |-- schema.sql
|   |-- rules.sql
|   `-- schema-v0*.sql
|-- templates/
|-- reports/
|-- data/
|-- Launch-EnergizeCheckGUI.ps1
|-- Start-EnergizeCheck.ps1
|-- Upgrade-EnergizeCheck-v0*.ps1
|-- Load-ALPHA-*.ps1
|-- Repair-ALPHA-*.ps1
`-- README.md
```

For a public repository, do **not** commit local SQLite databases, backups, real customer evidence, generated dossiers, or proprietary project data.

## Running locally

Requirements:

- Windows 10/11
- Windows PowerShell 5.1 or compatible PowerShell environment
- PSSQLite module

Typical launch:

```powershell
Set-Location "C:\Projects\EnergizeCheck"
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Start-EnergizeCheck.ps1 -Gui
```

## Demo progression

The project evolved through these milestones:

- **v0.1** â€” SQLite validation proof of concept
- **v0.2** â€” project management and CSV ingestion
- **v0.3** â€” PV engineering calculations
- **v0.4** â€” asset explorer, diagnostics and finding workflow
- **v0.5** â€” BESS commissioning intelligence
- **v0.6** â€” grid connection and protection intelligence
- **v0.7** â€” commissioning dossier and document intelligence

The portfolio release intentionally stops here and focuses on demonstrating the end-to-end engineering workflow.

## Important limitations

EnergizeCheck is a prototype / portfolio R&D project, not a certified commissioning product.

- Demo acceptance limits are synthetic/configurable.
- Real deployments would require approved project specifications, equipment manufacturer data, utility/grid-code requirements, cybersecurity controls, identity/RBAC, validation, testing, and formal engineering governance.
- Automated diagnostics are decision support; they do not replace qualified engineering judgment.
- No real customer, employer, or confidential project data should be included in the public repository.

## Future production directions

Potential future work:
- equipment-manufacturer rule packs
- configurable grid-code profiles
- user authentication and role-based access
- PostgreSQL / API backend
- web-based multi-user deployment
- automated document ingestion
- digital signatures
- time-series integration with SCADA/EMS
- formal test-procedure templates
- automated portfolio analytics

## Author

**Zahadat**  
AI Engineer / Renewable Energy Engineering Portfolio Project

Built as an engineering-software portfolio project combining software development, data modelling, automation, electrical commissioning logic, and renewable-energy domain knowledge.

