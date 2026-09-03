PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS dossier_sections(
    section_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    section_code TEXT NOT NULL,
    title TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 100,
    mandatory INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    UNIQUE(project_id,section_code)
);

CREATE TABLE IF NOT EXISTS document_requirements(
    requirement_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    requirement_code TEXT NOT NULL,
    section_id INTEGER NOT NULL,
    asset_id INTEGER,
    title TEXT NOT NULL,
    document_type TEXT NOT NULL,
    mandatory INTEGER NOT NULL DEFAULT 1,
    current_revision_required INTEGER NOT NULL DEFAULT 0,
    approval_required INTEGER NOT NULL DEFAULT 0,
    integrity_hash_required INTEGER NOT NULL DEFAULT 0,
    energization_critical INTEGER NOT NULL DEFAULT 0,
    expected_revision TEXT,
    notes TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(section_id) REFERENCES dossier_sections(section_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL,
    UNIQUE(project_id,requirement_code)
);

CREATE TABLE IF NOT EXISTS document_evidence(
    evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    requirement_id INTEGER NOT NULL UNIQUE,
    asset_id INTEGER,
    document_code TEXT NOT NULL,
    file_name TEXT,
    file_path TEXT,
    revision TEXT,
    is_current INTEGER NOT NULL DEFAULT 1,
    file_exists INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT,
    references_document_code TEXT,
    references_revision TEXT,
    received_at TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(requirement_id) REFERENCES document_requirements(requirement_id) ON DELETE CASCADE,
    FOREIGN KEY(asset_id) REFERENCES assets(asset_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS document_versions(
    version_id INTEGER PRIMARY KEY AUTOINCREMENT,
    evidence_id INTEGER NOT NULL,
    revision TEXT NOT NULL,
    file_name TEXT,
    file_path TEXT,
    sha256 TEXT,
    is_current INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(evidence_id) REFERENCES document_evidence(evidence_id) ON DELETE CASCADE,
    UNIQUE(evidence_id,revision)
);

CREATE TABLE IF NOT EXISTS document_reviews(
    review_id INTEGER PRIMARY KEY AUTOINCREMENT,
    evidence_id INTEGER NOT NULL,
    reviewer TEXT,
    status TEXT NOT NULL,
    comment TEXT,
    reviewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(evidence_id) REFERENCES document_evidence(evidence_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS document_approvals(
    approval_id INTEGER PRIMARY KEY AUTOINCREMENT,
    evidence_id INTEGER NOT NULL,
    approver TEXT,
    status TEXT NOT NULL,
    comment TEXT,
    approved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(evidence_id) REFERENCES document_evidence(evidence_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dossier_results(
    result_id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    section_id INTEGER NOT NULL,
    total_required INTEGER NOT NULL DEFAULT 0,
    compliant INTEGER NOT NULL DEFAULT 0,
    missing INTEGER NOT NULL DEFAULT 0,
    blockers INTEGER NOT NULL DEFAULT 0,
    warnings INTEGER NOT NULL DEFAULT 0,
    completeness_pct REAL NOT NULL DEFAULT 0,
    calculated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY(section_id) REFERENCES dossier_sections(section_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_doc_req_project ON document_requirements(project_id,section_id,asset_id);
CREATE INDEX IF NOT EXISTS idx_doc_evidence_project ON document_evidence(project_id,requirement_id,asset_id);
CREATE INDEX IF NOT EXISTS idx_doc_versions_evidence ON document_versions(evidence_id,is_current);
CREATE INDEX IF NOT EXISTS idx_doc_reviews_evidence ON document_reviews(evidence_id,review_id);
CREATE INDEX IF NOT EXISTS idx_doc_approvals_evidence ON document_approvals(evidence_id,approval_id);
CREATE INDEX IF NOT EXISTS idx_dossier_results_project ON dossier_results(project_id,section_id,calculated_at);

INSERT OR IGNORE INTO diagnostic_knowledge(rule_id,asset_type,diagnosis,cause_order,possible_cause,recommended_action,priority) VALUES
('DOC7-001','ANY','Mandatory commissioning evidence is missing.',1,'Required test sheet, checklist, certificate or as-built record has not been submitted.','Locate or recreate the required evidence, verify asset/project association, then register the controlled file in the dossier.','CRITICAL'),
('DOC7-002','ANY','Evidence revision does not match the required controlled revision.',1,'A superseded test sheet, settings export or drawing package remains linked to the handover record.','Obtain the current approved revision, replace the evidence link, preserve the old version in history and revalidate.','CRITICAL'),
('DOC7-003','ANY','Required evidence has not received final approval.',1,'The document is pending review, approved conditionally, or no approval record exists.','Route the evidence to the designated approver, resolve comments, record final approval and revalidate.','CRITICAL'),
('DOC7-004','ANY','Registered evidence file is unavailable at the recorded path.',1,'The file was moved, renamed, deleted, stored on an unavailable share, or never copied to the controlled repository.','Restore the controlled file, update its path, verify accessibility and regenerate the integrity hash.','CRITICAL'),
('DOC7-005','ANY','Commissioning evidence references a superseded controlled document.',1,'The test or checklist was completed against an obsolete SLD, method statement or controlled setting revision.','Verify the current controlled revision, assess whether retest/reinspection is required, update the evidence reference and document the decision.','CRITICAL'),
('DOC7-006','ANY','Mandatory evidence is missing its integrity hash.',1,'The file was registered without a SHA-256 fingerprint or the integrity record was lost.','Recompute SHA-256 from the controlled file, store it with the evidence record and regenerate the dossier manifest.','HIGH'),
('DOC7-007','ANY','Latest document review is rejected.',1,'Reviewer comments or technical nonconformities remain unresolved.','Resolve the review comments, issue the corrected revision and record an accepted review before approval.','CRITICAL'),
('DOC7-008','ANY','Final readiness / handover certificate is missing or not approved.',1,'The project has not completed final commissioning sign-off and handover authorization.','Generate the final readiness certificate only after technical and dossier gates pass, obtain approval and include it in the handover package.','CRITICAL');

INSERT OR REPLACE INTO schema_meta(key,value) VALUES('schema_version','0.7.0');
