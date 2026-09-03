# EnergizeCheck Architecture

## Logical architecture

```text
                   +----------------------+
                   |      WPF / XAML      |
                   |     Desktop UI       |
                   +----------+-----------+
                              |
                              v
                   +----------------------+
                   |    PowerShell Core   |
                   | Application Services |
                   +----------+-----------+
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
+------------------+ +------------------+ +------------------+
| Engineering Rule | | Finding Workflow | | Dossier / Docs   |
| Engine            | | & Diagnostics    | | Intelligence     |
+--------+---------+ +--------+---------+ +--------+---------+
         |                    |                    |
         +--------------------+--------------------+
                              |
                              v
                   +----------------------+
                   |       SQLite         |
                   | Relational Data Model|
                   +----------+-----------+
                              |
        +---------------------+----------------------+
        |                     |                      |
        v                     v                      v
  CSV Imports          HTML Reports          Handover Dossier
                                          + SHA-256 Manifest
```

## Engineering domains

```text
PV                     BESS                    GRID
--                     ----                    ----
Strings                Racks                   POI
Inverters              PCS / BMS              Protection relay
MPPT                   HVAC / Fire            CT / VT
DC / AC cable          EMS / PPC              Transformer
IR / Voc / polarity    SOC / voltage / temp   MV breaker
Voltage drop           Functional tests       PPC response
```

All domains feed a common finding model and readiness engine.

## Core design principles

1. **Traceability**
   Every finding is tied to a project/block/asset/rule.

2. **Configurable acceptance criteria**
   Project-specific thresholds are stored as data rather than assumed to be universal.

3. **Persistent lifecycle**
   Findings are not merely displayed; investigation, corrective action, retest and closure are retained.

4. **Evidence-based handover**
   Technical readiness is separated from documentary readiness.

5. **Offline-first prototype**
   SQLite and PowerShell keep the demonstration self-contained and easy to inspect.

## Production evolution

A production implementation could retain the engineering domain model while replacing the local architecture with:

```text
Web / Desktop Clients
        |
        v
 REST / GraphQL API
        |
        v
 Application Services
        |
        +--> Rule Engine
        +--> Workflow Service
        +--> Document Service
        +--> Identity / RBAC
        |
        v
 PostgreSQL + Object Storage
```
