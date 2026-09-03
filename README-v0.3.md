# EnergizeCheck v0.3 - Engineering Intelligence Engine

Adds configurable project acceptance criteria and calculated engineering validation for PV strings, inverter limits and cables.

## v0.3 rules
- ENG-STR-001: measured string Voc outside configured tolerance
- ENG-STR-002: string insulation resistance below configured minimum
- ENG-STR-003: string polarity verification failed
- ENG-INV-001: cold-condition string Voc exceeds inverter maximum DC voltage
- ENG-INV-002: string STC voltage outside inverter MPPT window
- ENG-INV-003: strings per MPPT exceed inverter limit
- ENG-CAB-001: installed conductor size below design size
- ENG-CAB-002: calculated voltage drop above configured limit
- ENG-CAB-003: cable insulation resistance below configured minimum

The default values installed by the demo are synthetic project acceptance criteria and are not universal code or manufacturer limits. Real projects must use approved design criteria, manufacturer data and applicable standards.
