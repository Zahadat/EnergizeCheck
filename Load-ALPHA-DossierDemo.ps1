[CmdletBinding()]
param([string]$DatabasePath=(Join-Path $PSScriptRoot 'data\energizecheck.db'))
$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PSSQLite -Force
Remove-Module EnergizeCheck -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force
Initialize-ECV07Schema -DatabasePath $DatabasePath
$p=Get-ECProjects -DatabasePath $DatabasePath|Where-Object ProjectCode -eq 'ALPHA-001'|Select-Object -First 1
if($null -eq $p){throw 'ALPHA-001 not found. Complete the prior demo stages first.'}
$ProjectId=[int]$p.ProjectId

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' COMMISSIONING DOSSIER & DOCUMENT DEMO' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$repairGrid=Join-Path $PSScriptRoot 'Repair-ALPHA-GridDemo.ps1';if(Test-Path $repairGrid){& $repairGrid -DatabasePath $DatabasePath|Out-Null}

Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM dossier_results WHERE project_id=@p;DELETE FROM document_approvals WHERE evidence_id IN(SELECT evidence_id FROM document_evidence WHERE project_id=@p);DELETE FROM document_reviews WHERE evidence_id IN(SELECT evidence_id FROM document_evidence WHERE project_id=@p);DELETE FROM document_versions WHERE evidence_id IN(SELECT evidence_id FROM document_evidence WHERE project_id=@p);DELETE FROM document_evidence WHERE project_id=@p;DELETE FROM document_requirements WHERE project_id=@p;DELETE FROM dossier_sections WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}|Out-Null

$evidenceRoot=Join-Path $PSScriptRoot 'evidence\ALPHA-001';if(Test-Path $evidenceRoot){Remove-Item $evidenceRoot -Recurse -Force};New-Item -ItemType Directory -Path $evidenceRoot -Force|Out-Null
function New-DemoEvidence([string]$Name,[string]$Text){$path=Join-Path $evidenceRoot $Name;Set-Content -LiteralPath $path -Value $Text -Encoding UTF8;return $path}

Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '01' -Title 'Project Information' -SortOrder 10
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '02' -Title 'Approved Drawings' -SortOrder 20
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '03' -Title 'PV Commissioning' -SortOrder 30
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '04' -Title 'BESS Commissioning' -SortOrder 40
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '05' -Title 'Grid and Protection' -SortOrder 50
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '06' -Title 'QA QC and NCR' -SortOrder 60
Set-ECDossierSection -DatabasePath $DatabasePath -ProjectId $ProjectId -SectionCode '07' -Title 'As Built and Handover' -SortOrder 70

Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PROJ-001' -SectionCode '01' -Title 'Project commissioning information sheet' -DocumentType 'PROJECT_INFO' -ApprovalRequired $true -IntegrityHashRequired $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-DWG-001' -SectionCode '02' -Title 'Current approved master SLD' -DocumentType 'DRAWING' -CurrentRevisionRequired $true -ExpectedRevision 'C' -ApprovalRequired $true -IntegrityHashRequired $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-001' -SectionCode '03' -Title 'PV string commissioning test register' -DocumentType 'TEST_REGISTER' -AssetCode 'INV-01' -ApprovalRequired $true -IntegrityHashRequired $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-002' -SectionCode '03' -Title 'Inverter commissioning checklist' -DocumentType 'CHECKLIST' -AssetCode 'INV-02' -ApprovalRequired $true -IntegrityHashRequired $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-BESS-001' -SectionCode '04' -Title 'BESS commissioning register' -DocumentType 'BESS_REGISTER' -AssetCode 'BESS-SYS-01' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-BESS-002' -SectionCode '04' -Title 'Emergency shutdown commissioning evidence' -DocumentType 'SAFETY_TEST' -AssetCode 'BESS-SYS-01' -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-001' -SectionCode '05' -Title 'Grid transformer signed commissioning report' -DocumentType 'TRANSFORMER_REPORT' -AssetCode 'TRF-GRID-01' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-002' -SectionCode '05' -Title 'Protection relay settings export' -DocumentType 'PROTECTION_SETTINGS' -AssetCode 'RELAY-01' -CurrentRevisionRequired $true -ExpectedRevision 'C' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-003' -SectionCode '05' -Title 'Grid synchronization commissioning report' -DocumentType 'GRID_TEST' -AssetCode 'POI-01' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-QA-001' -SectionCode '06' -Title 'Final NCR and punch-list closure register' -DocumentType 'NCR_REGISTER' -ApprovalRequired $true -IntegrityHashRequired $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-ASB-001' -SectionCode '07' -Title 'As-built SLD package' -DocumentType 'AS_BUILT' -CurrentRevisionRequired $true -ExpectedRevision 'C' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true
Set-ECDocumentRequirement -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-HO-001' -SectionCode '07' -Title 'Final energization and handover readiness certificate' -DocumentType 'HANDOVER_CERTIFICATE' -ApprovalRequired $true -IntegrityHashRequired $true -EnergizationCritical $true

Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT OR REPLACE INTO document_revisions(project_id,document_code,revision,approved_at,is_current,title) VALUES(@p,'MASTER-SLD','B','2026-08-01',0,'Master Single Line Diagram');INSERT OR REPLACE INTO document_revisions(project_id,document_code,revision,approved_at,is_current,title) VALUES(@p,'MASTER-SLD','C','2026-08-20',1,'Master Single Line Diagram');" -SqlParameters @{p=$ProjectId}|Out-Null

$proj=New-DemoEvidence 'project-info.txt' 'ALPHA-001 project commissioning information';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PROJ-001' -DocumentCode 'PROJECT-INFO' -FilePath $proj -Revision '01'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PROJ-001' -Status APPROVED -Approver 'Project Manager'
$sld=New-DemoEvidence 'master-sld-rev-c.txt' 'Controlled Master SLD Revision C';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-DWG-001' -DocumentCode 'MASTER-SLD' -FilePath $sld -Revision 'C'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-DWG-001' -Status APPROVED -Approver 'Design Manager'
$pv1=New-DemoEvidence 'pv-string-register.txt' 'PV string commissioning register - all strings passed';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-001' -DocumentCode 'PV-STR-REG' -FilePath $pv1 -Revision '01'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-001' -Status APPROVED -Approver 'Commissioning Lead'
$pv2=New-DemoEvidence 'inverter-checklist.txt' 'Inverter commissioning checklist';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-002' -DocumentCode 'INV-COM' -FilePath $pv2 -Revision '01'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-PV-002' -Status APPROVED -Approver 'Commissioning Lead'

$bess=New-DemoEvidence 'bess-register.txt' 'BESS commissioning register';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-BESS-001' -DocumentCode 'BESS-COM' -FilePath $bess -Revision '01'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-BESS-001' -Status PENDING -Approver 'BESS Technical Manager' -Comment 'Awaiting final signature.'
$estop=New-DemoEvidence 'bess-estop-evidence.txt' 'Emergency stop functional evidence';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-BESS-002' -DocumentCode 'BESS-ESTOP' -FilePath $estop -Revision '01' -SkipHash|Out-Null

$relay=New-DemoEvidence 'relay-settings-rev-b.txt' 'Protection relay settings export Revision B';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-002' -DocumentCode 'RELAY-SETTINGS' -FilePath $relay -Revision 'B'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-002' -Status APPROVED -Approver 'Protection Engineer'
$sync=New-DemoEvidence 'grid-sync-report.txt' 'Grid synchronization report performed against MASTER-SLD Rev B';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-003' -DocumentCode 'GRID-SYNC' -FilePath $sync -Revision '01' -ReferencesDocumentCode 'MASTER-SLD' -ReferencesRevision 'B'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-GRID-003' -Status APPROVED -Approver 'Grid Commissioning Manager'

$ncr=New-DemoEvidence 'final-ncr-register.txt' 'Final NCR register';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-QA-001' -DocumentCode 'NCR-FINAL' -FilePath $ncr -Revision '01'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-QA-001' -Status APPROVED -Approver 'QA Manager';Set-ECDocumentReview -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-QA-001' -Status REJECTED -Reviewer 'Owner Engineer' -Comment 'Closure evidence for one historical NCR is not attached.'

$missingAsBuilt=Join-Path $evidenceRoot 'as-built-sld-rev-c.txt';Set-ECDocumentEvidence -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-ASB-001' -DocumentCode 'ASBUILT-SLD' -FilePath $missingAsBuilt -Revision 'C'|Out-Null;Set-ECDocumentApproval -DatabasePath $DatabasePath -ProjectId $ProjectId -RequirementCode 'DOC-ASB-001' -Status APPROVED -Approver 'Design Manager'
# DOC-GRID-001 intentionally has no evidence.
# DOC-HO-001 intentionally has no evidence.

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $ProjectId|Out-Null
Update-ECDossierResults -DatabasePath $DatabasePath -ProjectId $ProjectId
$doc=@(Get-ECDossierFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
Write-Host '';Write-Host "Document / dossier findings: $($doc.Count)" -ForegroundColor Yellow;$doc|Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize
Write-Host '';Get-ECDossierOverview -DatabasePath $DatabasePath -ProjectId $ProjectId|Format-Table -AutoSize
