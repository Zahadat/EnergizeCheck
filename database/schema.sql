PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS schema_meta(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.2.0');

CREATE TABLE IF NOT EXISTS projects(
    project_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_code TEXT UNIQUE NOT NULL,
    project_name TEXT NOT NULL,
    location TEXT,
    project_type TEXT NOT NULL DEFAULT 'PV',
    pv_capacity_mwp REAL,
    bess_capacity_mwh REAL,
    client TEXT,
    epc_contractor TEXT,
    status TEXT NOT NULL DEFAULT 'IN PROGRESS',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS blocks(
    block_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    block_code TEXT NOT NULL,
    block_name TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id, block_code)
);

CREATE TABLE IF NOT EXISTS assets(
    asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    block_id INTEGER,
    asset_type TEXT NOT NULL,
    asset_code TEXT NOT NULL,
    parent_asset_id INTEGER,
    manufacturer TEXT,
    model TEXT,
    serial_number TEXT,
    status TEXT NOT NULL DEFAULT 'PLANNED',
    source TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(block_id) REFERENCES blocks(block_id) ON DELETE SET NULL,
    FOREIGN KEY(parent_asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL,
    UNIQUE(project_id, asset_code)
);

CREATE TABLE IF NOT EXISTS design_requirements(
    requirement_id INTEGER PRIMARY KEY AUTOINCREMENT,
    asset_id INTEGER NOT NULL,
    requirement_key TEXT NOT NULL,
    requirement_value TEXT NOT NULL,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    UNIQUE(asset_id, requirement_key)
);

CREATE TABLE IF NOT EXISTS document_revisions(
    revision_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    document_code TEXT NOT NULL,
    revision TEXT NOT NULL,
    approved_at TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 0,
    title TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id, document_code, revision)
);

CREATE TABLE IF NOT EXISTS installation_records(
    installation_id INTEGER PRIMARY KEY AUTOINCREMENT,
    asset_id INTEGER UNIQUE NOT NULL,
    installed_at TEXT NOT NULL,
    document_revision_id INTEGER,
    installer TEXT,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    FOREIGN KEY(document_revision_id) REFERENCES document_revisions(revision_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS delivered_serials(
    delivered_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    serial_number TEXT NOT NULL,
    asset_type TEXT,
    delivery_note TEXT,
    delivered_at TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id, serial_number)
);

CREATE TABLE IF NOT EXISTS test_results(
    test_result_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    asset_id INTEGER NOT NULL,
    test_type TEXT NOT NULL,
    test_date TEXT NOT NULL,
    result TEXT NOT NULL,
    value REAL,
    unit TEXT,
    technician TEXT,
    notes TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS issues(
    issue_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    issue_code TEXT NOT NULL,
    asset_id INTEGER,
    severity TEXT NOT NULL,
    category TEXT,
    description TEXT NOT NULL,
    status TEXT NOT NULL,
    opened_at TEXT NOT NULL,
    closed_at TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL,
    UNIQUE(project_id, issue_code)
);

CREATE TABLE IF NOT EXISTS material_balances(
    material_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    block_id INTEGER,
    material_code TEXT NOT NULL,
    description TEXT,
    opening_qty REAL NOT NULL DEFAULT 0,
    delivered_qty REAL NOT NULL DEFAULT 0,
    issued_qty REAL NOT NULL DEFAULT 0,
    returned_qty REAL NOT NULL DEFAULT 0,
    installed_qty REAL NOT NULL DEFAULT 0,
    damaged_qty REAL NOT NULL DEFAULT 0,
    physical_remaining REAL NOT NULL DEFAULT 0,
    expected_remaining REAL NOT NULL DEFAULT 0,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(block_id) REFERENCES blocks(block_id) ON DELETE SET NULL,
    UNIQUE(project_id, material_code)
);

CREATE TABLE IF NOT EXISTS import_jobs(
    import_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    rows_total INTEGER NOT NULL DEFAULT 0,
    rows_imported INTEGER NOT NULL DEFAULT 0,
    rows_failed INTEGER NOT NULL DEFAULT 0,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS import_errors(
    error_id INTEGER PRIMARY KEY AUTOINCREMENT,
    import_id INTEGER NOT NULL,
    row_number INTEGER,
    field_name TEXT,
    error_message TEXT NOT NULL,
    FOREIGN KEY(import_id) REFERENCES import_jobs(import_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS validation_runs(
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rule_findings(
    finding_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    project_id INTEGER NOT NULL,
    rule_id TEXT NOT NULL,
    severity TEXT NOT NULL,
    category TEXT NOT NULL,
    rule_name TEXT NOT NULL,
    block_code TEXT,
    asset_code TEXT,
    message TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(run_id) REFERENCES validation_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS readiness_results(
    readiness_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    block_id INTEGER NOT NULL,
    readiness_score INTEGER NOT NULL,
    decision TEXT NOT NULL,
    blocker_count INTEGER NOT NULL,
    warning_count INTEGER NOT NULL,
    calculated_at TEXT NOT NULL,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(block_id) REFERENCES blocks(block_id) ON DELETE CASCADE,
    UNIQUE(project_id, block_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_project ON blocks(project_id);
CREATE INDEX IF NOT EXISTS idx_assets_project ON assets(project_id);
CREATE INDEX IF NOT EXISTS idx_assets_block ON assets(block_id);
CREATE INDEX IF NOT EXISTS idx_assets_serial ON assets(project_id, serial_number);
CREATE INDEX IF NOT EXISTS idx_tests_project ON test_results(project_id);
CREATE INDEX IF NOT EXISTS idx_issues_project ON issues(project_id);
CREATE INDEX IF NOT EXISTS idx_findings_project_run ON rule_findings(project_id, run_id);
CREATE INDEX IF NOT EXISTS idx_import_jobs_project ON import_jobs(project_id);
