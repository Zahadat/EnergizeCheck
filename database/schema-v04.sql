PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS diagnostic_knowledge(
    diagnostic_id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id TEXT NOT NULL,
    asset_type TEXT NOT NULL DEFAULT 'ANY',
    diagnosis TEXT NOT NULL,
    cause_order INTEGER NOT NULL DEFAULT 1,
    possible_cause TEXT NOT NULL,
    recommended_action TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'MEDIUM',
    UNIQUE(rule_id, asset_type, cause_order)
);

CREATE TABLE IF NOT EXISTS finding_cases(
    case_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    rule_id TEXT NOT NULL,
    block_code TEXT NOT NULL DEFAULT '',
    asset_code TEXT NOT NULL DEFAULT '',
    severity TEXT NOT NULL,
    category TEXT,
    title TEXT,
    message TEXT,
    status TEXT NOT NULL DEFAULT 'OPEN',
    assigned_to TEXT,
    root_cause TEXT,
    corrective_action TEXT,
    retest_result TEXT,
    first_detected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_detected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id, rule_id, block_code, asset_code)
);

CREATE TABLE IF NOT EXISTS finding_case_history(
    history_id INTEGER PRIMARY KEY AUTOINCREMENT,
    case_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    note TEXT,
    changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(case_id) REFERENCES finding_cases(case_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_diag_rule ON diagnostic_knowledge(rule_id,asset_type);
CREATE INDEX IF NOT EXISTS idx_cases_project ON finding_cases(project_id,status);
CREATE INDEX IF NOT EXISTS idx_case_history_case ON finding_case_history(case_id,changed_at);

INSERT OR IGNORE INTO diagnostic_knowledge(rule_id,asset_type,diagnosis,cause_order,possible_cause,recommended_action,priority) VALUES
('ENG-STR-001','STRING','Measured open-circuit voltage is materially different from the temperature-corrected design expectation.',1,'Physical module count differs from the approved string schedule.','Verify the installed module count and compare it with the approved string schedule and as-built record.','HIGH'),
('ENG-STR-001','STRING','Measured open-circuit voltage is materially different from the temperature-corrected design expectation.',2,'Open, loose, contaminated, or high-resistance DC connector.','Perform continuity checks and inspect DC connectors, terminations, and polarity at both ends of the string.','HIGH'),
('ENG-STR-001','STRING','Measured open-circuit voltage is materially different from the temperature-corrected design expectation.',3,'One or more modules or bypass-diode paths are abnormal.','Measure module-level voltage where safe and permitted, then inspect suspect modules and bypass conditions.','MEDIUM'),
('ENG-STR-001','STRING','Measured open-circuit voltage is materially different from the temperature-corrected design expectation.',4,'String is connected to the wrong MPPT or field label does not match the database hierarchy.','Trace the string physically and compare labels, combiner/MPPT assignment, SLD, and asset mapping.','MEDIUM'),
('ENG-STR-001','STRING','Measured open-circuit voltage is materially different from the temperature-corrected design expectation.',5,'Measurement temperature, module data, or instrument entry is incorrect.','Verify instrument calibration, measurement conditions, module Voc data, and recorded temperature before concluding a field defect.','MEDIUM'),
('ENG-STR-002','STRING','String insulation resistance is below the configured project acceptance threshold.',1,'Moisture ingress, damaged insulation, or contaminated connector/termination.','Isolate the affected circuit, inspect connectors and cable routes, and repeat insulation-resistance testing according to the approved method statement.','HIGH'),
('ENG-STR-002','STRING','String insulation resistance is below the configured project acceptance threshold.',2,'DC cable insulation has been damaged during pulling, trenching, or termination.','Sectionalize the circuit where practical and test segments to localize the insulation defect.','HIGH'),
('ENG-STR-003','STRING','Recorded polarity does not satisfy the commissioning acceptance state.',1,'Positive and negative conductors or connectors are reversed.','Do not energize. Verify polarity at the string, combiner/MPPT input, labels, and connector mating before correction and retest.','CRITICAL'),
('ENG-INV-001','STRING','Cold-condition string voltage exceeds the configured inverter maximum DC voltage.',1,'String contains too many series modules for the design minimum temperature.','Recheck module count, manufacturer temperature coefficient, design minimum temperature, and inverter maximum DC voltage.','CRITICAL'),
('ENG-INV-001','STRING','Cold-condition string voltage exceeds the configured inverter maximum DC voltage.',2,'Incorrect module electrical data or project design temperature has been entered.','Verify approved module datasheet values and project climatic/design assumptions before changing the physical configuration.','HIGH'),
('ENG-INV-002','STRING','String voltage is outside the configured inverter MPPT operating window.',1,'String length or module electrical characteristics are incompatible with the selected inverter input window.','Recalculate the approved string sizing across the project temperature range and verify inverter configuration.','HIGH'),
('ENG-INV-003','MPPT','The number of strings assigned to an MPPT exceeds the configured inverter limit.',1,'Field string assignment differs from the approved design or duplicate mapping exists.','Compare physical input labels and the string schedule, then correct the mapping or approved design configuration.','HIGH'),
('ENG-CAB-001','ANY','Installed conductor cross-section is below the approved design value.',1,'Incorrect cable was installed or a material substitution was made without approved design change.','Verify cable markings and procurement records. Replace the cable or obtain an approved engineering revision before energization.','CRITICAL'),
('ENG-CAB-002','ANY','Calculated cable voltage drop exceeds the configured project limit.',1,'Cable route is longer than the design basis.','Verify as-built route length and recalculate the circuit using the approved operating current and voltage.','HIGH'),
('ENG-CAB-002','ANY','Calculated cable voltage drop exceeds the configured project limit.',2,'Installed conductor is undersized for the circuit length/current.','Review conductor sizing, ampacity, voltage-drop design, and approved cable schedule.','HIGH'),
('ENG-CAB-003','ANY','Cable insulation resistance is below the configured project minimum.',1,'Cable or termination insulation is damaged, wet, contaminated, or improperly prepared.','Isolate and sectionalize the circuit, inspect terminations and cable route, correct the defect, and perform a controlled retest.','HIGH'),
('TST-001','STRING','A required passing insulation-resistance commissioning record is missing.',1,'Test was not completed, failed, or the result was not linked to the correct asset.','Verify the commissioning package and asset code. Perform the required test if evidence is genuinely missing.','HIGH'),
('DOC-001','ANY','Installation evidence references a superseded project document revision.',1,'Construction continued using an obsolete drawing or the installation record was linked to the wrong revision.','Verify the installed condition against the current approved revision and document any required rework or formal as-built acceptance.','HIGH'),
('NCR-001','ANY','An energization-critical NCR or issue remains open.',1,'Corrective action has not been completed or formally accepted.','Complete the corrective action, attach objective evidence, perform required retest/inspection, and close the NCR through the project quality process.','CRITICAL'),
('SER-001','PV_MODULE','The same equipment serial number is assigned to more than one installed asset.',1,'Duplicate scanning, transcription error, or incorrect physical asset mapping.','Physically verify the affected serials and locations, then correct the asset register while preserving the audit trail.','HIGH');

INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.4.0');
