PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS engineering_parameters(
    parameter_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    parameter_key TEXT NOT NULL,
    parameter_value REAL NOT NULL,
    unit TEXT,
    description TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id, parameter_key)
);

CREATE TABLE IF NOT EXISTS string_engineering(
    asset_id INTEGER PRIMARY KEY,
    module_voc_stc_v REAL NOT NULL,
    voc_temp_coeff_pct_c REAL NOT NULL,
    measurement_temp_c REAL,
    measured_voc_v REAL,
    measured_isc_a REAL,
    measured_ir_mohm REAL,
    polarity TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS inverter_engineering(
    asset_id INTEGER PRIMARY KEY,
    max_dc_voltage_v REAL,
    mppt_min_voltage_v REAL,
    mppt_max_voltage_v REAL,
    max_strings_per_mppt INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS cable_engineering(
    cable_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    block_id INTEGER,
    cable_code TEXT NOT NULL,
    from_asset_id INTEGER,
    to_asset_id INTEGER,
    conductor_material TEXT NOT NULL DEFAULT 'CU',
    phase_type TEXT NOT NULL DEFAULT 'DC',
    design_size_mm2 REAL NOT NULL,
    installed_size_mm2 REAL NOT NULL,
    length_m REAL NOT NULL,
    design_current_a REAL NOT NULL,
    system_voltage_v REAL NOT NULL,
    max_voltage_drop_pct REAL,
    measured_ir_mohm REAL,
    status TEXT NOT NULL DEFAULT 'INSTALLED',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(block_id) REFERENCES blocks(block_id) ON DELETE SET NULL,
    FOREIGN KEY(from_asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL,
    FOREIGN KEY(to_asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL,
    UNIQUE(project_id, cable_code)
);

CREATE INDEX IF NOT EXISTS idx_eng_params_project ON engineering_parameters(project_id);
CREATE INDEX IF NOT EXISTS idx_string_eng_asset ON string_engineering(asset_id);
CREATE INDEX IF NOT EXISTS idx_inverter_eng_asset ON inverter_engineering(asset_id);
CREATE INDEX IF NOT EXISTS idx_cable_eng_project ON cable_engineering(project_id);

INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.3.0');
