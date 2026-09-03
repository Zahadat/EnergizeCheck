-- RULE:SER-001|BLOCKER|Asset Traceability|Duplicate installed serial number
SELECT b.block_code, a.asset_code,
       'Serial ' || a.serial_number || ' appears on more than one installed asset.' AS message
FROM assets a
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE a.project_id=@projectId
  AND a.serial_number IS NOT NULL
  AND TRIM(a.serial_number)<>''
  AND UPPER(a.status)='INSTALLED'
  AND a.serial_number IN (
      SELECT serial_number FROM assets
      WHERE project_id=@projectId AND serial_number IS NOT NULL AND TRIM(serial_number)<>'' AND UPPER(status)='INSTALLED'
      GROUP BY serial_number HAVING COUNT(*)>1
  );

-- RULE:DOC-001|BLOCKER|Revision Integrity|Superseded drawing used for installation
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Installed using superseded revision ' || d.revision || ' of ' || d.document_code || '.' AS message
FROM installation_records i
JOIN assets a ON a.asset_id=i.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
JOIN document_revisions d ON d.revision_id=i.document_revision_id
WHERE a.project_id=@projectId AND d.is_current=0;

-- RULE:TST-001|BLOCKER|Commissioning Tests|Missing passing insulation-resistance test
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Installed string has no passing insulation-resistance test.' AS message
FROM assets a
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE a.project_id=@projectId
  AND UPPER(a.asset_type)='STRING'
  AND UPPER(a.status)='INSTALLED'
  AND NOT EXISTS(
      SELECT 1 FROM test_results t
      WHERE t.project_id=@projectId AND t.asset_id=a.asset_id
        AND UPPER(t.test_type) IN ('IR','INSULATION RESISTANCE','INSULATION-RESISTANCE')
        AND UPPER(t.result)='PASS'
  );

-- RULE:DES-001|BLOCKER|Design Integrity|Installed module count does not match baseline
SELECT COALESCE(b.block_code,'') AS block_code, s.asset_code,
       'Expected ' || dr.requirement_value || ' modules but found ' || COUNT(m.asset_id) || '.' AS message
FROM assets s
LEFT JOIN blocks b ON b.block_id=s.block_id
JOIN design_requirements dr ON dr.asset_id=s.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
LEFT JOIN assets m ON m.parent_asset_id=s.asset_id AND UPPER(m.asset_type)='PV_MODULE' AND UPPER(m.status)='INSTALLED'
WHERE s.project_id=@projectId AND UPPER(s.asset_type)='STRING'
GROUP BY s.asset_id
HAVING COUNT(m.asset_id) <> CAST(dr.requirement_value AS INTEGER);

-- RULE:NCR-001|BLOCKER|Quality|Open energization-critical issue
SELECT COALESCE(b.block_code,'') AS block_code, COALESCE(a.asset_code,i.issue_code) AS asset_code,
       'Open critical issue ' || i.issue_code || ': ' || i.description AS message
FROM issues i
LEFT JOIN assets a ON a.asset_id=i.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE i.project_id=@projectId
  AND UPPER(i.status) NOT IN ('CLOSED','RESOLVED')
  AND UPPER(i.severity)='BLOCKER';

-- RULE:SER-002|WARNING|Asset Traceability|Installed serial absent from delivery register
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Installed serial ' || a.serial_number || ' is absent from delivery register.' AS message
FROM assets a
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE a.project_id=@projectId
  AND UPPER(a.status)='INSTALLED'
  AND a.serial_number IS NOT NULL AND TRIM(a.serial_number)<>''
  AND NOT EXISTS(
      SELECT 1 FROM delivered_serials d
      WHERE d.project_id=@projectId AND d.serial_number=a.serial_number
  );

-- RULE:TST-002|WARNING|Commissioning Tests|Test predates installation
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Test date ' || t.test_date || ' predates installation date ' || ir.installed_at || '.' AS message
FROM test_results t
JOIN assets a ON a.asset_id=t.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
JOIN installation_records ir ON ir.asset_id=a.asset_id
WHERE t.project_id=@projectId AND date(t.test_date) < date(ir.installed_at);

-- RULE:TST-003|BLOCKER|Commissioning Tests|Failed commissioning test
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Failed ' || t.test_type || ' test dated ' || t.test_date || '.' AS message
FROM test_results t
JOIN assets a ON a.asset_id=t.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE t.project_id=@projectId AND UPPER(t.result) IN ('FAIL','FAILED','NOK');

-- RULE:MAT-001|WARNING|Materials|Physical stock does not reconcile
SELECT COALESCE(b.block_code,'') AS block_code, m.material_code AS asset_code,
       'Physical remaining=' || m.physical_remaining || ', expected=' || m.expected_remaining || '.' AS message
FROM material_balances m
LEFT JOIN blocks b ON b.block_id=m.block_id
WHERE m.project_id=@projectId AND ABS(m.physical_remaining-m.expected_remaining)>0.001;

-- RULE:DOC-002|WARNING|Revision Integrity|Installed asset has no drawing revision reference
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Installed asset has no approved drawing revision linked to its installation record.' AS message
FROM installation_records i
JOIN assets a ON a.asset_id=i.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE a.project_id=@projectId AND i.document_revision_id IS NULL;

-- RULE:AST-001|BLOCKER|Asset Hierarchy|Installed module or string has no parent asset
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Installed ' || a.asset_type || ' has no parent asset in the electrical hierarchy.' AS message
FROM assets a
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE a.project_id=@projectId
  AND UPPER(a.status)='INSTALLED'
  AND UPPER(a.asset_type) IN ('PV_MODULE','STRING','MPPT')
  AND a.parent_asset_id IS NULL;

-- V0.3 ENGINEERING INTELLIGENCE

-- RULE:ENG-STR-001|BLOCKER|Engineering - Strings|Measured string Voc outside configured tolerance
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='STRING_VOC_TOLERANCE_PCT'),5.0) AS tol
), q AS (
    SELECT b.block_code, s.asset_code,
           CAST(dr.requirement_value AS REAL) * se.module_voc_stc_v *
             (1.0 + (se.voc_temp_coeff_pct_c / 100.0) * (COALESCE(se.measurement_temp_c,25.0)-25.0)) AS expected_voc,
           se.measured_voc_v AS measured_voc,
           cfg.tol AS tol
    FROM assets s
    JOIN design_requirements dr ON dr.asset_id=s.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
    JOIN string_engineering se ON se.asset_id=s.asset_id
    LEFT JOIN blocks b ON b.block_id=s.block_id
    CROSS JOIN cfg
    WHERE s.project_id=@projectId AND UPPER(s.asset_type)='STRING' AND se.measured_voc_v IS NOT NULL
)
SELECT block_code, asset_code,
       'Measured Voc=' || ROUND(measured_voc,2) || ' V, expected=' || ROUND(expected_voc,2) ||
       ' V, deviation=' || ROUND(ABS(measured_voc-expected_voc)/NULLIF(expected_voc,0)*100.0,2) ||
       '%, allowed=' || ROUND(tol,2) || '%.' AS message
FROM q
WHERE expected_voc > 0
  AND ABS(measured_voc-expected_voc)/expected_voc*100.0 > tol;

-- RULE:ENG-STR-002|BLOCKER|Engineering - Strings|String insulation resistance below configured minimum
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='MIN_STRING_IR_MOHM'),100.0) AS minimum_ir
)
SELECT COALESCE(b.block_code,'') AS block_code, s.asset_code,
       'Measured string IR=' || ROUND(se.measured_ir_mohm,2) || ' MOhm, configured minimum=' || ROUND(cfg.minimum_ir,2) || ' MOhm.' AS message
FROM string_engineering se
JOIN assets s ON s.asset_id=se.asset_id
LEFT JOIN blocks b ON b.block_id=s.block_id
CROSS JOIN cfg
WHERE s.project_id=@projectId
  AND se.measured_ir_mohm IS NOT NULL
  AND se.measured_ir_mohm < cfg.minimum_ir;

-- RULE:ENG-STR-003|BLOCKER|Engineering - Strings|String polarity verification failed
SELECT COALESCE(b.block_code,'') AS block_code, s.asset_code,
       'String polarity status is ' || COALESCE(se.polarity,'NOT RECORDED') || '.' AS message
FROM string_engineering se
JOIN assets s ON s.asset_id=se.asset_id
LEFT JOIN blocks b ON b.block_id=s.block_id
WHERE s.project_id=@projectId
  AND se.polarity IS NOT NULL
  AND UPPER(TRIM(se.polarity)) NOT IN ('PASS','POSITIVE','CORRECT','OK');

-- RULE:ENG-INV-001|BLOCKER|Engineering - Inverters|Cold-condition string Voc exceeds inverter maximum DC voltage
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='DESIGN_MIN_TEMP_C'),-10.0) AS tmin
), q AS (
    SELECT b.block_code, inv.asset_code AS inverter_code, s.asset_code AS string_code,
           ie.max_dc_voltage_v AS max_dc,
           CAST(dr.requirement_value AS REAL) * se.module_voc_stc_v *
             (1.0 + (se.voc_temp_coeff_pct_c / 100.0) * (cfg.tmin-25.0)) AS cold_voc
    FROM assets s
    JOIN assets mppt ON mppt.asset_id=s.parent_asset_id
    JOIN assets inv ON inv.asset_id=mppt.parent_asset_id
    JOIN inverter_engineering ie ON ie.asset_id=inv.asset_id
    JOIN design_requirements dr ON dr.asset_id=s.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
    JOIN string_engineering se ON se.asset_id=s.asset_id
    LEFT JOIN blocks b ON b.block_id=s.block_id
    CROSS JOIN cfg
    WHERE s.project_id=@projectId AND UPPER(s.asset_type)='STRING' AND ie.max_dc_voltage_v IS NOT NULL
)
SELECT block_code, string_code AS asset_code,
       'Cold-condition expected Voc=' || ROUND(cold_voc,2) || ' V exceeds inverter maximum DC voltage=' || ROUND(max_dc,2) || ' V on ' || inverter_code || '.' AS message
FROM q
WHERE cold_voc > max_dc;

-- RULE:ENG-INV-002|BLOCKER|Engineering - Inverters|String operating voltage outside inverter MPPT window
WITH q AS (
    SELECT b.block_code, inv.asset_code AS inverter_code, s.asset_code AS string_code,
           ie.mppt_min_voltage_v AS mppt_min, ie.mppt_max_voltage_v AS mppt_max,
           CAST(dr.requirement_value AS REAL) * se.module_voc_stc_v AS stc_voc
    FROM assets s
    JOIN assets mppt ON mppt.asset_id=s.parent_asset_id
    JOIN assets inv ON inv.asset_id=mppt.parent_asset_id
    JOIN inverter_engineering ie ON ie.asset_id=inv.asset_id
    JOIN design_requirements dr ON dr.asset_id=s.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
    JOIN string_engineering se ON se.asset_id=s.asset_id
    LEFT JOIN blocks b ON b.block_id=s.block_id
    WHERE s.project_id=@projectId AND UPPER(s.asset_type)='STRING'
      AND ie.mppt_min_voltage_v IS NOT NULL AND ie.mppt_max_voltage_v IS NOT NULL
)
SELECT block_code, string_code AS asset_code,
       'String STC Voc=' || ROUND(stc_voc,2) || ' V is outside inverter MPPT window ' || ROUND(mppt_min,2) || '-' || ROUND(mppt_max,2) || ' V on ' || inverter_code || '.' AS message
FROM q
WHERE stc_voc < mppt_min OR stc_voc > mppt_max;

-- RULE:ENG-INV-003|BLOCKER|Engineering - Inverters|MPPT has more strings than configured inverter limit
SELECT COALESCE(b.block_code,'') AS block_code, mppt.asset_code AS asset_code,
       'MPPT has ' || COUNT(s.asset_id) || ' strings; configured maximum is ' || ie.max_strings_per_mppt || ' for inverter ' || inv.asset_code || '.' AS message
FROM assets mppt
JOIN assets inv ON inv.asset_id=mppt.parent_asset_id
JOIN inverter_engineering ie ON ie.asset_id=inv.asset_id
LEFT JOIN assets s ON s.parent_asset_id=mppt.asset_id AND UPPER(s.asset_type)='STRING'
LEFT JOIN blocks b ON b.block_id=mppt.block_id
WHERE mppt.project_id=@projectId AND UPPER(mppt.asset_type)='MPPT' AND ie.max_strings_per_mppt IS NOT NULL
GROUP BY mppt.asset_id
HAVING COUNT(s.asset_id) > ie.max_strings_per_mppt;

-- RULE:ENG-CAB-001|BLOCKER|Engineering - Cables|Installed conductor size below design size
SELECT COALESCE(b.block_code,'') AS block_code, c.cable_code AS asset_code,
       'Installed conductor=' || ROUND(c.installed_size_mm2,2) || ' mm2 is below design size=' || ROUND(c.design_size_mm2,2) || ' mm2.' AS message
FROM cable_engineering c
LEFT JOIN blocks b ON b.block_id=c.block_id
WHERE c.project_id=@projectId
  AND c.installed_size_mm2 < c.design_size_mm2;

-- RULE:ENG-CAB-002|BLOCKER|Engineering - Cables|Calculated cable voltage drop exceeds configured limit
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='MAX_CABLE_VDROP_PCT'),2.0) AS project_limit
), q AS (
    SELECT c.*, COALESCE(b.block_code,'') AS block_code,
           CASE UPPER(c.conductor_material) WHEN 'AL' THEN 0.0282 ELSE 0.0175 END AS rho,
           CASE UPPER(c.phase_type) WHEN 'AC3' THEN 1.7320508075688772 ELSE 2.0 END AS factor,
           COALESCE(c.max_voltage_drop_pct,cfg.project_limit) AS allowed_drop
    FROM cable_engineering c
    LEFT JOIN blocks b ON b.block_id=c.block_id
    CROSS JOIN cfg
    WHERE c.project_id=@projectId
), calc AS (
    SELECT *, factor * length_m * design_current_a * rho / NULLIF(installed_size_mm2,0) / NULLIF(system_voltage_v,0) * 100.0 AS drop_pct
    FROM q
)
SELECT block_code, cable_code AS asset_code,
       'Calculated voltage drop=' || ROUND(drop_pct,2) || '%, configured maximum=' || ROUND(allowed_drop,2) || '%.' AS message
FROM calc
WHERE drop_pct IS NOT NULL AND drop_pct > allowed_drop;

-- RULE:ENG-CAB-003|BLOCKER|Engineering - Cables|Cable insulation resistance below configured minimum
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='MIN_CABLE_IR_MOHM'),100.0) AS minimum_ir
)
SELECT COALESCE(b.block_code,'') AS block_code, c.cable_code AS asset_code,
       'Measured cable IR=' || ROUND(c.measured_ir_mohm,2) || ' MOhm, configured minimum=' || ROUND(cfg.minimum_ir,2) || ' MOhm.' AS message
FROM cable_engineering c
LEFT JOIN blocks b ON b.block_id=c.block_id
CROSS JOIN cfg
WHERE c.project_id=@projectId
  AND c.measured_ir_mohm IS NOT NULL
  AND c.measured_ir_mohm < cfg.minimum_ir;

-- V0.5 BESS COMMISSIONING INTELLIGENCE

-- RULE:BESS-001|BLOCKER|BESS - Battery Racks|Rack SOC imbalance exceeds configured limit
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='BESS_MAX_RACK_SOC_DEVIATION_PCT'),3.0) AS lim
), avgq AS (
    SELECT a.parent_asset_id, AVG(br.soc_pct) AS avg_soc
    FROM assets a JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
    WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK' AND br.soc_pct IS NOT NULL
    GROUP BY a.parent_asset_id
)
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Rack SOC=' || ROUND(br.soc_pct,2) || '%, peer average=' || ROUND(avgq.avg_soc,2) ||
       '%, deviation=' || ROUND(ABS(br.soc_pct-avgq.avg_soc),2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM assets a
JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
JOIN avgq ON avgq.parent_asset_id=a.parent_asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
CROSS JOIN cfg
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK'
  AND br.soc_pct IS NOT NULL
  AND ABS(br.soc_pct-avgq.avg_soc) > cfg.lim;

-- RULE:BESS-002|BLOCKER|BESS - Battery Racks|Rack voltage deviation exceeds configured limit
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='BESS_MAX_RACK_VOLTAGE_DEVIATION_PCT'),2.0) AS lim
), avgq AS (
    SELECT a.parent_asset_id, AVG(br.rack_voltage_v) AS avg_v
    FROM assets a JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
    WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK' AND br.rack_voltage_v IS NOT NULL
    GROUP BY a.parent_asset_id
)
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Rack voltage=' || ROUND(br.rack_voltage_v,2) || ' V, peer average=' || ROUND(avgq.avg_v,2) ||
       ' V, deviation=' || ROUND(ABS(br.rack_voltage_v-avgq.avg_v)/NULLIF(avgq.avg_v,0)*100.0,2) ||
       '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM assets a
JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
JOIN avgq ON avgq.parent_asset_id=a.parent_asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
CROSS JOIN cfg
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK'
  AND br.rack_voltage_v IS NOT NULL AND avgq.avg_v<>0
  AND ABS(br.rack_voltage_v-avgq.avg_v)/avgq.avg_v*100.0 > cfg.lim;

-- RULE:BESS-003|BLOCKER|BESS - Battery Racks|Cell voltage spread exceeds configured limit
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='BESS_MAX_CELL_VOLTAGE_SPREAD_MV'),50.0) AS lim
)
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Cell voltage spread=' || ROUND((br.max_cell_voltage_v-br.min_cell_voltage_v)*1000.0,1) ||
       ' mV, configured maximum=' || ROUND(cfg.lim,1) || ' mV.' AS message
FROM assets a
JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
CROSS JOIN cfg
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK'
  AND br.min_cell_voltage_v IS NOT NULL AND br.max_cell_voltage_v IS NOT NULL
  AND (br.max_cell_voltage_v-br.min_cell_voltage_v)*1000.0 > cfg.lim;

-- RULE:BESS-004|BLOCKER|BESS - Thermal|Battery rack temperature spread exceeds configured limit
WITH cfg AS (
    SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='BESS_MAX_RACK_TEMP_SPREAD_C'),8.0) AS lim
)
SELECT COALESCE(b.block_code,'') AS block_code, a.asset_code,
       'Rack temperature spread=' || ROUND(br.max_temp_c-br.min_temp_c,2) ||
       ' C, configured maximum=' || ROUND(cfg.lim,2) || ' C.' AS message
FROM assets a
JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
CROSS JOIN cfg
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='BESS_RACK'
  AND br.min_temp_c IS NOT NULL AND br.max_temp_c IS NOT NULL
  AND (br.max_temp_c-br.min_temp_c) > cfg.lim;

-- RULE:BESS-005|BLOCKER|BESS - Communications|PCS/BMS communication test incomplete or failed
SELECT COALESCE(b.block_code,'') AS block_code, pcs.asset_code,
       'PCS/BMS communication check is ' || COALESCE(c.result,'NOT RECORDED') || '.' AS message
FROM assets pcs
LEFT JOIN blocks b ON b.block_id=pcs.block_id
LEFT JOIN bess_commissioning_checks c
  ON c.project_id=pcs.project_id AND c.asset_id=pcs.asset_id AND c.check_type='PCS_BMS_COMMUNICATION'
WHERE pcs.project_id=@projectId AND UPPER(pcs.asset_type)='PCS'
  AND COALESCE(UPPER(c.result),'NOT RECORDED') NOT IN ('PASS','PASSED','OK');

-- RULE:BESS-006|BLOCKER|BESS - Safety|Emergency-stop chain not proven
SELECT COALESCE(b.block_code,'') AS block_code, sys.asset_code,
       'Emergency-stop chain check is ' || COALESCE(c.result,'NOT RECORDED') || '.' AS message
FROM assets sys
LEFT JOIN blocks b ON b.block_id=sys.block_id
LEFT JOIN bess_commissioning_checks c
  ON c.project_id=sys.project_id AND c.asset_id=sys.asset_id AND c.check_type='EMERGENCY_STOP_CHAIN'
WHERE sys.project_id=@projectId AND UPPER(sys.asset_type)='BESS_SYSTEM'
  AND COALESCE(UPPER(c.result),'NOT RECORDED') NOT IN ('PASS','PASSED','OK');

-- RULE:BESS-007|BLOCKER|BESS - Thermal|HVAC commissioning test incomplete or failed
SELECT COALESCE(b.block_code,'') AS block_code, hvac.asset_code,
       'HVAC functional check is ' || COALESCE(c.result,'NOT RECORDED') || '.' AS message
FROM assets hvac
LEFT JOIN blocks b ON b.block_id=hvac.block_id
LEFT JOIN bess_commissioning_checks c
  ON c.project_id=hvac.project_id AND c.asset_id=hvac.asset_id AND c.check_type='HVAC_FUNCTIONAL'
WHERE hvac.project_id=@projectId AND UPPER(hvac.asset_type)='HVAC'
  AND COALESCE(UPPER(c.result),'NOT RECORDED') NOT IN ('PASS','PASSED','OK');

-- RULE:BESS-008|BLOCKER|BESS - Fire Safety|Fire detection/suppression test incomplete or failed
SELECT COALESCE(b.block_code,'') AS block_code, fs.asset_code,
       'Fire-system functional check is ' || COALESCE(c.result,'NOT RECORDED') || '.' AS message
FROM assets fs
LEFT JOIN blocks b ON b.block_id=fs.block_id
LEFT JOIN bess_commissioning_checks c
  ON c.project_id=fs.project_id AND c.asset_id=fs.asset_id AND c.check_type='FIRE_SYSTEM_FUNCTIONAL'
WHERE fs.project_id=@projectId AND UPPER(fs.asset_type)='FIRE_SYSTEM'
  AND COALESCE(UPPER(c.result),'NOT RECORDED') NOT IN ('PASS','PASSED','OK');

-- RULE:BESS-009|BLOCKER|BESS - Configuration|PCS firmware differs from approved baseline
SELECT COALESCE(b.block_code,'') AS block_code, pcs.asset_code,
       'Installed PCS firmware=' || COALESCE(pe.installed_firmware,'NOT RECORDED') ||
       ', approved baseline=' || COALESCE(pe.approved_firmware,'NOT RECORDED') || '.' AS message
FROM assets pcs
JOIN bess_pcs_engineering pe ON pe.asset_id=pcs.asset_id
LEFT JOIN blocks b ON b.block_id=pcs.block_id
WHERE pcs.project_id=@projectId AND UPPER(pcs.asset_type)='PCS'
  AND COALESCE(TRIM(pe.installed_firmware),'') <> COALESCE(TRIM(pe.approved_firmware),'');

-- RULE:BESS-010|BLOCKER|BESS - Controls|EMS/PPC interface validation incomplete or failed
SELECT COALESCE(b.block_code,'') AS block_code, ems.asset_code,
       'EMS/PPC interface check is ' || COALESCE(c.result,'NOT RECORDED') || '.' AS message
FROM assets ems
LEFT JOIN blocks b ON b.block_id=ems.block_id
LEFT JOIN bess_commissioning_checks c
  ON c.project_id=ems.project_id AND c.asset_id=ems.asset_id AND c.check_type='EMS_PPC_INTERFACE'
WHERE ems.project_id=@projectId AND UPPER(ems.asset_type)='EMS_PPC'
  AND COALESCE(UPPER(c.result),'NOT RECORDED') NOT IN ('PASS','PASSED','OK');

-- V0.6 GRID CONNECTION & PROTECTION INTELLIGENCE

-- RULE:GRID-001|BLOCKER|Grid - Protection|Protection relay setting differs from approved baseline
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_RELAY_SETTING_DEVIATION_PCT'),2.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,
       s.setting_key || ': approved=' || ROUND(s.approved_value,3) || ' ' || COALESCE(s.unit,'') || ', installed=' || ROUND(s.installed_value,3) || ' ' || COALESCE(s.unit,'') || ', deviation=' || ROUND(ABS(s.installed_value-s.approved_value)/NULLIF(ABS(s.approved_value),0)*100.0,2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM grid_setting_checks s JOIN assets a ON a.asset_id=s.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE s.project_id=@projectId AND UPPER(a.asset_type)='PROTECTION_RELAY' AND ABS(s.installed_value-s.approved_value)/NULLIF(ABS(s.approved_value),0)*100.0 > cfg.lim;

-- RULE:GRID-002|BLOCKER|Grid - Instrument Transformers|CT ratio differs from approved design
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Approved CT ratio=' || ROUND(s.approved_value,3) || ', installed=' || ROUND(s.installed_value,3) || ' ' || COALESCE(s.unit,'') || '.' AS message
FROM grid_setting_checks s JOIN assets a ON a.asset_id=s.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE s.project_id=@projectId AND UPPER(a.asset_type)='CT' AND UPPER(s.setting_key)='CT_RATIO' AND ABS(s.installed_value-s.approved_value)>0.0001;

-- RULE:GRID-003|BLOCKER|Grid - Instrument Transformers|VT ratio differs from approved design
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Approved VT ratio=' || ROUND(s.approved_value,3) || ', installed=' || ROUND(s.installed_value,3) || ' ' || COALESCE(s.unit,'') || '.' AS message
FROM grid_setting_checks s JOIN assets a ON a.asset_id=s.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE s.project_id=@projectId AND UPPER(a.asset_type)='VT' AND UPPER(s.setting_key)='VT_RATIO' AND ABS(s.installed_value-s.approved_value)>0.0001;

-- RULE:GRID-004|BLOCKER|Grid - MV Switchgear|MV breaker functional test missing or failed
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'MV breaker functional check result=' || COALESCE(c.result,'MISSING') || '. ' || COALESCE(c.details,'') AS message
FROM assets a LEFT JOIN blocks b ON b.block_id=a.block_id LEFT JOIN grid_commissioning_checks c ON c.project_id=@projectId AND c.asset_id=a.asset_id AND UPPER(c.check_type)='BREAKER_FUNCTIONAL'
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='MV_BREAKER' AND (c.check_id IS NULL OR UPPER(COALESCE(c.result,'')) NOT IN ('PASS','PASSED','OK'));

-- RULE:GRID-005|BLOCKER|Grid - Transformer|Transformer insulation resistance below configured minimum
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MIN_TRANSFORMER_IR_MOHM'),500.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Transformer IR=' || ROUND(t.measured_value,2) || ' MOhm, minimum=' || ROUND(cfg.lim,2) || ' MOhm.' AS message
FROM grid_transformer_tests t JOIN assets a ON a.asset_id=t.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE t.project_id=@projectId AND UPPER(t.test_type)='INSULATION_RESISTANCE' AND t.measured_value<cfg.lim;

-- RULE:GRID-006|BLOCKER|Grid - Transformer|Transformer ratio error exceeds configured tolerance
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_TRANSFORMER_RATIO_ERROR_PCT'),0.5) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Transformer ratio error=' || ROUND(t.measured_value,3) || '%, allowed=' || ROUND(cfg.lim,3) || '%.' AS message
FROM grid_transformer_tests t JOIN assets a ON a.asset_id=t.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE t.project_id=@projectId AND UPPER(t.test_type)='RATIO_ERROR_PCT' AND ABS(t.measured_value)>cfg.lim;

-- RULE:GRID-007|BLOCKER|Grid - Protection|Anti-islanding test missing or failed
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Anti-islanding check result=' || COALESCE(c.result,'MISSING') || '. ' || COALESCE(c.details,'') AS message
FROM assets a LEFT JOIN blocks b ON b.block_id=a.block_id LEFT JOIN grid_commissioning_checks c ON c.project_id=@projectId AND c.asset_id=a.asset_id AND UPPER(c.check_type)='ANTI_ISLANDING'
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='POI' AND (c.check_id IS NULL OR UPPER(COALESCE(c.result,'')) NOT IN ('PASS','PASSED','OK'));

-- RULE:GRID-008|BLOCKER|Grid - Synchronization|Grid synchronization test missing or failed
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Grid synchronization check result=' || COALESCE(c.result,'MISSING') || '. ' || COALESCE(c.details,'') AS message
FROM assets a LEFT JOIN blocks b ON b.block_id=a.block_id LEFT JOIN grid_commissioning_checks c ON c.project_id=@projectId AND c.asset_id=a.asset_id AND UPPER(c.check_type)='GRID_SYNCHRONIZATION'
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='POI' AND (c.check_id IS NULL OR UPPER(COALESCE(c.result,'')) NOT IN ('PASS','PASSED','OK'));

-- RULE:GRID-009|BLOCKER|Grid - PPC|Active-power setpoint tracking outside configured tolerance
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_ACTIVE_POWER_TRACKING_ERROR_PCT'),2.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Active-power command=' || ROUND(r.commanded_value,3) || ' ' || COALESCE(r.unit,'') || ', measured=' || ROUND(r.measured_value,3) || ', error=' || ROUND(ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0,2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM grid_response_tests r JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE r.project_id=@projectId AND UPPER(r.response_type)='ACTIVE_POWER_TRACKING' AND ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0>cfg.lim;

-- RULE:GRID-010|BLOCKER|Grid - PPC|Reactive-power response outside configured tolerance
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_REACTIVE_POWER_TRACKING_ERROR_PCT'),2.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Reactive-power command=' || ROUND(r.commanded_value,3) || ' ' || COALESCE(r.unit,'') || ', measured=' || ROUND(r.measured_value,3) || ', error=' || ROUND(ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0,2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM grid_response_tests r JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE r.project_id=@projectId AND UPPER(r.response_type)='REACTIVE_POWER_TRACKING' AND ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0>cfg.lim;

-- RULE:GRID-011|BLOCKER|Grid - PPC|Frequency response outside configured envelope
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_FREQUENCY_RESPONSE_ERROR_PCT'),2.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Frequency-response expected=' || ROUND(r.commanded_value,3) || ', measured=' || ROUND(r.measured_value,3) || ', error=' || ROUND(ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0,2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM grid_response_tests r JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE r.project_id=@projectId AND UPPER(r.response_type)='FREQUENCY_RESPONSE' AND ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0>cfg.lim;

-- RULE:GRID-012|BLOCKER|Grid - PPC|Voltage-control response outside configured envelope
WITH cfg AS (SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@projectId AND parameter_key='GRID_MAX_VOLTAGE_RESPONSE_ERROR_PCT'),2.0) AS lim)
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Voltage-response expected=' || ROUND(r.commanded_value,3) || ', measured=' || ROUND(r.measured_value,3) || ', error=' || ROUND(ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0,2) || '%, allowed=' || ROUND(cfg.lim,2) || '%.' AS message
FROM grid_response_tests r JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id CROSS JOIN cfg
WHERE r.project_id=@projectId AND UPPER(r.response_type)='VOLTAGE_RESPONSE' AND ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0>cfg.lim;

-- RULE:GRID-013|BLOCKER|Grid - PPC|Export limitation test missing or failed
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'Export-limitation check result=' || COALESCE(c.result,'MISSING') || '. ' || COALESCE(c.details,'') AS message
FROM assets a LEFT JOIN blocks b ON b.block_id=a.block_id LEFT JOIN grid_commissioning_checks c ON c.project_id=@projectId AND c.asset_id=a.asset_id AND UPPER(c.check_type)='EXPORT_LIMITATION'
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='POI' AND (c.check_id IS NULL OR UPPER(COALESCE(c.result,'')) NOT IN ('PASS','PASSED','OK'));

-- RULE:GRID-014|BLOCKER|Grid - PPC|PPC grid-control communications missing or failed
SELECT COALESCE(b.block_code,'') AS block_code,a.asset_code,'PPC/grid communications result=' || COALESCE(c.result,'MISSING') || '. ' || COALESCE(c.details,'') AS message
FROM assets a LEFT JOIN blocks b ON b.block_id=a.block_id LEFT JOIN grid_commissioning_checks c ON c.project_id=@projectId AND c.asset_id=a.asset_id AND UPPER(c.check_type)='PPC_GRID_COMMUNICATION'
WHERE a.project_id=@projectId AND UPPER(a.asset_type)='PPC' AND (c.check_id IS NULL OR UPPER(COALESCE(c.result,'')) NOT IN ('PASS','PASSED','OK'));

-- V0.7 COMMISSIONING DOSSIER & DOCUMENT INTELLIGENCE

-- RULE:DOC7-001|BLOCKER|Documentation - Evidence|Mandatory commissioning evidence missing
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': ' || r.title || ' is mandatory but no evidence is registered.' AS message
FROM document_requirements r
LEFT JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND r.mandatory=1 AND r.requirement_code<>'DOC-HO-001' AND e.evidence_id IS NULL;

-- RULE:DOC7-002|BLOCKER|Documentation - Revision Control|Evidence revision is superseded
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': evidence revision ' || COALESCE(e.revision,'<blank>') || ' does not match required revision ' || COALESCE(r.expected_revision,'<not set>') || '.' AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND r.current_revision_required=1 AND COALESCE(r.expected_revision,'')<>'' AND UPPER(COALESCE(e.revision,''))<>UPPER(r.expected_revision);

-- RULE:DOC7-003|BLOCKER|Documentation - Approval|Required evidence is not approved
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': latest approval status=' || COALESCE((SELECT da.status FROM document_approvals da WHERE da.evidence_id=e.evidence_id ORDER BY da.approval_id DESC LIMIT 1),'MISSING') || '.' AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND r.approval_required=1 AND r.requirement_code<>'DOC-HO-001'
  AND UPPER(COALESCE((SELECT da.status FROM document_approvals da WHERE da.evidence_id=e.evidence_id ORDER BY da.approval_id DESC LIMIT 1),''))<>'APPROVED';

-- RULE:DOC7-004|BLOCKER|Documentation - File Integrity|Registered evidence file is unavailable
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': registered file is unavailable: ' || COALESCE(e.file_path,e.file_name,'<no path>') || '.' AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND e.file_exists=0 AND r.requirement_code<>'DOC-HO-001';

-- RULE:DOC7-005|BLOCKER|Documentation - Controlled References|Evidence references superseded controlled document
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': references ' || e.references_document_code || ' Rev ' || e.references_revision || ', but current controlled revision is ' || cur.current_revision || '.' AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
JOIN (
  SELECT dr.project_id,dr.document_code,dr.revision AS current_revision
  FROM document_revisions dr WHERE dr.is_current=1
) cur ON cur.project_id=r.project_id AND cur.document_code=e.references_document_code
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND COALESCE(e.references_document_code,'')<>'' AND UPPER(COALESCE(e.references_revision,''))<>UPPER(cur.current_revision);

-- RULE:DOC7-006|WARNING|Documentation - File Integrity|Mandatory evidence integrity hash missing
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': SHA-256 integrity hash is missing for ' || COALESCE(e.file_name,e.document_code) || '.' AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND r.integrity_hash_required=1 AND e.file_exists=1 AND COALESCE(TRIM(e.sha256),'')='';

-- RULE:DOC7-007|BLOCKER|Documentation - Review|Latest evidence review is rejected
SELECT COALESCE(b.block_code,'PROJECT') AS block_code,COALESCE(a.asset_code,'') AS asset_code,
       r.requirement_code || ': latest review status=REJECTED. ' || COALESCE((SELECT dr.comment FROM document_reviews dr WHERE dr.evidence_id=e.evidence_id ORDER BY dr.review_id DESC LIMIT 1),'') AS message
FROM document_requirements r
JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@projectId AND UPPER(COALESCE((SELECT dr.status FROM document_reviews dr WHERE dr.evidence_id=e.evidence_id ORDER BY dr.review_id DESC LIMIT 1),''))='REJECTED';

-- RULE:DOC7-008|BLOCKER|Documentation - Handover|Final handover certificate missing or not approved
SELECT 'PROJECT' AS block_code,'' AS asset_code,
       r.requirement_code || ': final readiness / handover certificate is missing, unavailable or not approved.' AS message
FROM document_requirements r
LEFT JOIN document_evidence e ON e.requirement_id=r.requirement_id
WHERE r.project_id=@projectId AND r.requirement_code='DOC-HO-001' AND (
    e.evidence_id IS NULL OR e.file_exists=0 OR
    UPPER(COALESCE((SELECT da.status FROM document_approvals da WHERE da.evidence_id=e.evidence_id ORDER BY da.approval_id DESC LIMIT 1),''))<>'APPROVED'
);
