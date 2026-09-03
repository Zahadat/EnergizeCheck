PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS grid_setting_checks(
    setting_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    setting_key TEXT NOT NULL,
    approved_value REAL,
    installed_value REAL,
    unit TEXT,
    approved_revision TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    UNIQUE(project_id,asset_id,setting_key)
);

CREATE TABLE IF NOT EXISTS grid_transformer_tests(
    test_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    test_type TEXT NOT NULL,
    measured_value REAL,
    unit TEXT,
    tested_at TEXT,
    details TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    UNIQUE(project_id,asset_id,test_type)
);

CREATE TABLE IF NOT EXISTS grid_response_tests(
    response_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    response_type TEXT NOT NULL,
    commanded_value REAL,
    measured_value REAL,
    unit TEXT,
    tested_at TEXT,
    details TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    UNIQUE(project_id,asset_id,response_type)
);

CREATE TABLE IF NOT EXISTS grid_commissioning_checks(
    check_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    check_type TEXT NOT NULL,
    result TEXT NOT NULL,
    tested_at TEXT,
    details TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    UNIQUE(project_id,asset_id,check_type)
);

CREATE INDEX IF NOT EXISTS idx_grid_setting_project ON grid_setting_checks(project_id,asset_id);
CREATE INDEX IF NOT EXISTS idx_grid_transformer_project ON grid_transformer_tests(project_id,asset_id);
CREATE INDEX IF NOT EXISTS idx_grid_response_project ON grid_response_tests(project_id,asset_id);
CREATE INDEX IF NOT EXISTS idx_grid_checks_project ON grid_commissioning_checks(project_id,asset_id,check_type);

INSERT OR IGNORE INTO diagnostic_knowledge(rule_id,asset_type,diagnosis,cause_order,possible_cause,recommended_action,priority) VALUES
('GRID-001','PROTECTION_RELAY','Protection relay setting differs from the approved controlled baseline.',1,'Incorrect or superseded relay settings file was loaded.','Verify the approved protection-study revision, export installed settings, correct the discrepancy and repeat secondary injection testing.','CRITICAL'),
('GRID-002','CT','Current-transformer ratio does not match the approved design.',1,'Incorrect CT ratio or relay/meter scaling is configured.','Verify CT nameplate, secondary wiring, ratio configuration, polarity and approved SLD/protection study.','CRITICAL'),
('GRID-003','VT','Voltage-transformer ratio does not match the approved design.',1,'Incorrect VT ratio or protection/meter/PPC scaling is configured.','Verify VT nameplate, secondary wiring, fuses, scaling and the latest approved design documents.','CRITICAL'),
('GRID-004','MV_BREAKER','MV breaker functional commissioning has not passed.',1,'Trip/close circuit, interlock, auxiliary contact, control power or SCADA/protection path is incomplete.','Perform the approved breaker functional test including local/remote close-trip, interlocks, indications and trip path.','CRITICAL'),
('GRID-005','GRID_TRANSFORMER','Transformer insulation resistance is below the configured project criterion.',1,'Moisture, contamination, insulation condition or test setup may be abnormal.','Verify isolation and test setup, inspect for moisture/contamination and repeat the approved insulation test.','CRITICAL'),
('GRID-006','GRID_TRANSFORMER','Transformer ratio error exceeds the configured commissioning tolerance.',1,'Tap position, winding connection, nameplate ratio or test setup may be incorrect.','Verify tap position and nameplate data, then repeat ratio testing on the required phases/taps.','CRITICAL'),
('GRID-007','POI','Anti-islanding commissioning has not passed.',1,'Protection logic, thresholds, trip path or controller permissives do not match the approved scheme.','Execute the approved anti-islanding procedure and verify relay logic, trip outputs and plant shutdown sequence.','CRITICAL'),
('GRID-008','POI','Grid synchronization test has not passed.',1,'Voltage, frequency, phase angle, synch-check settings or VT phasing may be outside the approved window.','Verify synch-check settings, VT phasing, references and breaker closing logic before retest.','CRITICAL'),
('GRID-009','PPC','Active-power setpoint tracking error exceeds the configured tolerance.',1,'PPC scaling, ramp limits, available power or active-power control tuning may be incorrect.','Verify command scaling, available power, ramp-rate limits and controller tuning; repeat stepped active-power commands.','HIGH'),
('GRID-010','PPC','Reactive-power response error exceeds the configured tolerance.',1,'Reactive-power/PF scaling, sign convention, capability limits or controller tuning may be incorrect.','Verify Q/PF mode, scaling, sign convention and controller tuning before repeating reactive-power steps.','HIGH'),
('GRID-011','PPC','Frequency-response result lies outside the configured envelope.',1,'Frequency-watt droop, deadband, gain or enable state may not match approved settings.','Verify frequency-response parameters and repeat the approved response test with synchronized data capture.','HIGH'),
('GRID-012','PPC','Voltage-control response lies outside the configured envelope.',1,'Voltage/reactive droop, setpoint scaling, deadband or control mode may be incorrect.','Verify voltage-control mode and approved droop/deadband settings, then repeat response testing.','HIGH'),
('GRID-013','POI','Export-limitation functional test has not passed.',1,'Export setpoint, POI metering feedback or curtailment command path may be incorrect.','Verify export limit, meter/PPC feedback, curtailment commands and fail-safe behavior before retest.','CRITICAL'),
('GRID-014','PPC','PPC/grid-control communications commissioning has not passed.',1,'Protocol mapping, gateway, addressing, time synchronization or required points may be incomplete.','Verify communications architecture, point list, addresses, synchronization, commands and feedback end-to-end.','CRITICAL');

INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.6.0');
