PRAGMA foreign_keys=ON;

DELETE FROM readiness_results;
DELETE FROM rule_findings;
DELETE FROM validation_runs;
DELETE FROM import_errors;
DELETE FROM import_jobs;
DELETE FROM issues;
DELETE FROM test_results;
DELETE FROM delivered_serials;
DELETE FROM installation_records;
DELETE FROM design_requirements;
DELETE FROM assets;
DELETE FROM document_revisions;
DELETE FROM material_balances;
DELETE FROM blocks;
DELETE FROM projects;

INSERT INTO projects(project_id,project_code,project_name,location,project_type,pv_capacity_mwp,bess_capacity_mwh,client,epc_contractor,status)
VALUES(1,'DEMO-PV-BESS','Synthetic PV + BESS Commissioning Project','Romania','HYBRID',7.127,20.04,'Demo Owner','Demo EPC','COMMISSIONING');

INSERT INTO blocks(block_id,project_id,block_code,block_name) VALUES
(1,1,'BLK-01','Inverter Block 01'),
(2,1,'BLK-02','Inverter Block 02');

INSERT INTO document_revisions(revision_id,project_id,document_code,revision,approved_at,is_current,title) VALUES
(1,1,'SLD-001','A','2026-07-01',0,'PV Plant Single Line Diagram'),
(2,1,'SLD-001','B','2026-08-01',1,'PV Plant Single Line Diagram');

INSERT INTO assets(asset_id,project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,serial_number,status,source) VALUES
(1,1,1,'INVERTER','INV-B1',NULL,'DemoInverter','INV-350K','INV-SN-001','INSTALLED','DEMO'),
(2,1,1,'MPPT','MPPT-B1-01',1,NULL,NULL,NULL,'INSTALLED','DEMO'),
(3,1,1,'STRING','STR-B1-01',2,NULL,NULL,NULL,'INSTALLED','DEMO'),
(4,1,2,'INVERTER','INV-B2',NULL,'DemoInverter','INV-350K','INV-SN-002','INSTALLED','DEMO'),
(5,1,2,'MPPT','MPPT-B2-01',4,NULL,NULL,NULL,'INSTALLED','DEMO'),
(6,1,2,'STRING','STR-B2-01',5,NULL,NULL,NULL,'INSTALLED','DEMO'),
(7,1,1,'PV_MODULE','MOD-B1-001',3,'Jinko','Demo-640W','SN-DUP-001','INSTALLED','DEMO'),
(8,1,1,'PV_MODULE','MOD-B1-002',3,'Jinko','Demo-640W','SN-B1-002','INSTALLED','DEMO'),
(9,1,1,'PV_MODULE','MOD-B1-003',3,'Jinko','Demo-640W','SN-B1-003','INSTALLED','DEMO'),
(10,1,1,'PV_MODULE','MOD-B1-004',3,'Jinko','Demo-640W','SN-DUP-001','INSTALLED','DEMO'),
(11,1,2,'PV_MODULE','MOD-B2-001',6,'Jinko','Demo-640W','SN-B2-001','INSTALLED','DEMO'),
(12,1,2,'PV_MODULE','MOD-B2-002',6,'Jinko','Demo-640W','SN-B2-002','INSTALLED','DEMO'),
(13,1,2,'PV_MODULE','MOD-B2-003',6,'Jinko','Demo-640W','SN-B2-003','INSTALLED','DEMO');

INSERT INTO design_requirements(asset_id,requirement_key,requirement_value) VALUES
(3,'EXPECTED_MODULE_COUNT','4'),
(6,'EXPECTED_MODULE_COUNT','4');

INSERT INTO installation_records(asset_id,installed_at,document_revision_id,installer) VALUES
(1,'2026-08-15',1,'Demo Team'),
(2,'2026-08-15',2,'Demo Team'),
(3,'2026-08-15',2,'Demo Team'),
(4,'2026-08-16',2,'Demo Team'),
(5,'2026-08-16',2,'Demo Team'),
(6,'2026-08-16',2,'Demo Team'),
(7,'2026-08-15',2,'Demo Team'),
(8,'2026-08-15',2,'Demo Team'),
(9,'2026-08-15',2,'Demo Team'),
(10,'2026-08-15',2,'Demo Team'),
(11,'2026-08-16',2,'Demo Team'),
(12,'2026-08-16',2,'Demo Team'),
(13,'2026-08-16',2,'Demo Team');

INSERT INTO delivered_serials(project_id,serial_number,asset_type,delivery_note,delivered_at) VALUES
(1,'INV-SN-001','INVERTER','DN-INV-001','2026-08-10'),
(1,'INV-SN-002','INVERTER','DN-INV-002','2026-08-10'),
(1,'SN-DUP-001','PV_MODULE','DN-001','2026-08-10'),
(1,'SN-B1-002','PV_MODULE','DN-001','2026-08-10'),
(1,'SN-B1-003','PV_MODULE','DN-001','2026-08-10'),
(1,'SN-B2-001','PV_MODULE','DN-002','2026-08-11'),
(1,'SN-B2-002','PV_MODULE','DN-002','2026-08-11');
-- SN-B2-003 intentionally absent.

INSERT INTO test_results(test_result_id,project_id,asset_id,test_type,test_date,result,value,unit,technician) VALUES
(1,1,3,'IR','2026-08-14','PASS',450,'MOhm','Demo Engineer');
-- STR-B2-01 intentionally has no IR test.

INSERT INTO issues(issue_id,project_id,issue_code,asset_id,severity,category,description,status,opened_at) VALUES
(1,1,'NCR-001',1,'BLOCKER','Termination','Open critical AC termination NCR','OPEN','2026-08-18');

INSERT INTO material_balances(material_id,project_id,block_id,material_code,description,opening_qty,delivered_qty,issued_qty,returned_qty,installed_qty,damaged_qty,physical_remaining,expected_remaining) VALUES
(1,1,2,'DC-CABLE-6MM','6 mm2 PV cable',1000,500,800,50,760,10,700,740);
