PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS bess_rack_engineering(
    asset_id INTEGER PRIMARY KEY,
    soc_pct REAL,
    rack_voltage_v REAL,
    min_cell_voltage_v REAL,
    max_cell_voltage_v REAL,
    min_temp_c REAL,
    max_temp_c REAL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bess_pcs_engineering(
    asset_id INTEGER PRIMARY KEY,
    rated_power_mw REAL,
    dc_voltage_v REAL,
    approved_firmware TEXT,
    installed_firmware TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bess_commissioning_checks(
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

CREATE INDEX IF NOT EXISTS idx_bess_rack_asset ON bess_rack_engineering(asset_id);
CREATE INDEX IF NOT EXISTS idx_bess_pcs_asset ON bess_pcs_engineering(asset_id);
CREATE INDEX IF NOT EXISTS idx_bess_checks_project ON bess_commissioning_checks(project_id,asset_id,check_type);

INSERT OR IGNORE INTO diagnostic_knowledge(rule_id,asset_type,diagnosis,cause_order,possible_cause,recommended_action,priority) VALUES
('BESS-001','BESS_RACK','Battery rack state-of-charge differs materially from peer racks in the same container.',1,'Rack balancing is incomplete or the rack has not completed an equivalent charge/discharge history.','Review rack SOC history, complete the approved balancing sequence, and repeat SOC comparison after stabilization.','HIGH'),
('BESS-001','BESS_RACK','Battery rack state-of-charge differs materially from peer racks in the same container.',2,'BMS SOC estimation or calibration is inconsistent for the affected rack.','Verify BMS calibration, coulomb-counting state, current-sensor data, and rack reset/recalibration procedure before retest.','HIGH'),
('BESS-002','BESS_RACK','Battery rack DC voltage deviates beyond the configured peer-rack tolerance.',1,'Rack SOC or module voltage distribution is materially different from adjacent racks.','Compare module/cell voltage distribution, rack contactor state, and SOC before attempting parallel operation.','HIGH'),
('BESS-002','BESS_RACK','Battery rack DC voltage deviates beyond the configured peer-rack tolerance.',2,'Measurement mapping, sensor calibration, or BMS voltage acquisition is incorrect.','Cross-check rack voltage with an approved independent measurement and verify BMS channel mapping/calibration.','MEDIUM'),
('BESS-003','BESS_RACK','Cell voltage spread inside the rack exceeds the configured commissioning limit.',1,'One or more cells/modules are insufficiently balanced or degraded.','Review cell-level voltage distribution, execute the approved balancing procedure, and investigate persistent outliers.','HIGH'),
('BESS-003','BESS_RACK','Cell voltage spread inside the rack exceeds the configured commissioning limit.',2,'Cell measurement channel or harness connection is abnormal.','Verify BMS sense harness connections, channel mapping, and measurement plausibility before concluding a cell defect.','HIGH'),
('BESS-004','BESS_RACK','Temperature spread inside the battery rack exceeds the configured limit.',1,'Cooling airflow or HVAC distribution is uneven across the rack/container.','Inspect HVAC operation, airflow path, filters, fan status, and rack inlet/outlet temperatures; correct and thermally stabilize before retest.','HIGH'),
('BESS-004','BESS_RACK','Temperature spread inside the battery rack exceeds the configured limit.',2,'Temperature sensor placement, wiring, or calibration is inconsistent.','Verify sensor locations, harness integrity, BMS mapping, and calibration against an approved reference instrument.','MEDIUM'),
('BESS-005','PCS','PCS-to-BMS communication commissioning has not achieved a passing state.',1,'Protocol mapping, addressing, baud/network settings, or gateway configuration is incorrect.','Verify communication topology, addresses, protocol parameters, time synchronization, and required data points end-to-end.','CRITICAL'),
('BESS-005','PCS','PCS-to-BMS communication commissioning has not achieved a passing state.',2,'Physical network, fiber, Ethernet, CAN, or serial connection is open or unstable.','Inspect communication hardware, link status, terminations, switches/gateways, and perform controlled communication retest.','HIGH'),
('BESS-006','BESS_SYSTEM','The emergency-stop chain has not been proven in the required commissioning state.',1,'One or more E-stop devices, safety relays, interlocks, or trip paths are not included in the verified chain.','Execute the approved cause-and-effect/E-stop test from each required initiation point and verify safe isolation and reset behavior.','CRITICAL'),
('BESS-006','BESS_SYSTEM','The emergency-stop chain has not been proven in the required commissioning state.',2,'Safety PLC or hardwired interlock logic does not match the approved cause-and-effect matrix.','Compare implemented logic against the approved safety narrative and cause-and-effect documentation before retest.','CRITICAL'),
('BESS-007','HVAC','Battery-container HVAC functional commissioning has not passed.',1,'HVAC unit, fan, compressor, thermostat, or BMS command/feedback path is unavailable or incorrectly configured.','Verify HVAC power, control signals, alarms, temperature setpoints, airflow, and BMS feedback under the approved functional test.','HIGH'),
('BESS-007','HVAC','Battery-container HVAC functional commissioning has not passed.',2,'Environmental interlocks or alarm thresholds prevent normal HVAC operation.','Review active alarms/interlocks, configured thresholds, and environmental sensors before repeating the functional test.','MEDIUM'),
('BESS-008','FIRE_SYSTEM','Fire detection/suppression functional commissioning has not reached a passing state.',1,'Detector, suppression release circuit, panel interface, alarm routing, or interlock is incomplete.','Execute the approved fire-system cause-and-effect test with authorized specialists and verify all required alarms, trips, and interfaces.','CRITICAL'),
('BESS-008','FIRE_SYSTEM','Fire detection/suppression functional commissioning has not reached a passing state.',2,'Fire-system interface to BMS/EMS/PCS shutdown logic is missing or incorrectly mapped.','Verify dry contacts/network points and shutdown sequence against the approved fire strategy and cause-and-effect matrix.','CRITICAL'),
('BESS-009','PCS','Installed PCS firmware does not match the approved commissioning baseline.',1,'PCS was delivered or serviced with a different firmware package than the approved project baseline.','Verify the approved firmware matrix, compatibility notes, rollback requirements, and controlled firmware update procedure before operation.','HIGH'),
('BESS-009','PCS','Installed PCS firmware does not match the approved commissioning baseline.',2,'Firmware inventory or asset record is stale rather than the physical PCS actually being noncompliant.','Read firmware directly from the PCS/HMI/service interface and reconcile the controlled configuration register.','MEDIUM'),
('BESS-010','EMS_PPC','EMS/PPC control-interface validation has not achieved a passing state.',1,'Active/reactive-power setpoints, SOC limits, ramp rates, or feedback tags are incorrectly mapped.','Perform end-to-end command and feedback testing for the approved control points, including limits, scaling, sign convention, and response.','CRITICAL'),
('BESS-010','EMS_PPC','EMS/PPC control-interface validation has not achieved a passing state.',2,'Network route, time synchronization, protocol gateway, or plant-controller configuration is incomplete.','Verify communications architecture, synchronization, gateway configuration, control authority, and fallback behavior before repeating interface tests.','HIGH');

INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.5.0');
