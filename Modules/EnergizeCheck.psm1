Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ECSqlFile {
    param([string]$DatabasePath, [string]$SqlFile)
    $sql = Get-Content -LiteralPath $SqlFile -Raw
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $sql | Out-Null
}

function Import-ECCsvFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "CSV not found: $Path" }
    $first = Get-Content -LiteralPath $Path -TotalCount 1
    $commaCount = ([regex]::Matches([string]$first, ',')).Count
    $semiCount = ([regex]::Matches([string]$first, ';')).Count
    $delimiter = if ($semiCount -gt $commaCount) { ';' } else { ',' }
    return @(Import-Csv -LiteralPath $Path -Delimiter $delimiter)
}

function ConvertTo-ECSafeDouble {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0.0 }
    $text = ([string]$Value).Trim().Replace(',', '.')
    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
    throw "Value '$Value' is not a valid number."
}

function ConvertTo-ECDateText {
    param($Value, [switch]$AllowBlank)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        if ($AllowBlank) { return $null }
        throw 'Date is required.'
    }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [ref]$dt)) { return $dt.ToString('yyyy-MM-dd') }
    throw "Date '$Value' could not be parsed. Use YYYY-MM-DD when possible."
}

function ConvertTo-ECBooleanInt {
    param($Value)
    $t = ([string]$Value).Trim().ToUpperInvariant()
    if ($t -in @('1','TRUE','YES','Y','CURRENT')) { return 1 }
    if ($t -in @('0','FALSE','NO','N','SUPERSEDED')) { return 0 }
    throw "Boolean value '$Value' is invalid. Use TRUE/FALSE, YES/NO, or 1/0."
}

function Initialize-ECDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath, [switch]$Reset)

    $dir = Split-Path -Parent $DatabasePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($Reset -and (Test-Path $DatabasePath)) { Remove-Item -LiteralPath $DatabasePath -Force }

    $schema = Join-Path $PSScriptRoot '..\database\schema.sql'
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $schema
    Write-Host "Database initialized: $DatabasePath" -ForegroundColor Green
}

function Add-ECDemoData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $seed = Join-Path $PSScriptRoot '..\database\seed-demo.sql'
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $seed
    Write-Host 'Synthetic PV/BESS demo data loaded.' -ForegroundColor Green
}

function Get-ECProjects {
    param([Parameter(Mandatory)][string]$DatabasePath)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT project_id AS ProjectId,
       project_code AS ProjectCode,
       project_name AS ProjectName,
       location AS Location,
       project_type AS ProjectType,
       pv_capacity_mwp AS PvMWp,
       bess_capacity_mwh AS BessMWh,
       client AS Client,
       epc_contractor AS EPC,
       status AS Status,
       project_name || ' [' || project_code || ']' AS DisplayName
FROM projects
ORDER BY project_name;
'@
}

function Get-ECProject {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT project_id AS ProjectId, project_code AS ProjectCode, project_name AS ProjectName, location AS Location,
       project_type AS ProjectType, pv_capacity_mwp AS PvMWp, bess_capacity_mwh AS BessMWh,
       client AS Client, epc_contractor AS EPC, status AS Status
FROM projects WHERE project_id=@p;
'@ -SqlParameters @{p=$ProjectId}
}

function New-ECProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$ProjectCode,
        [Parameter(Mandatory)][string]$ProjectName,
        [string]$Location,
        [ValidateSet('PV','BESS','HYBRID')][string]$ProjectType='PV',
        [double]$PvCapacityMWp=0,
        [double]$BessCapacityMWh=0,
        [string]$Client,
        [string]$EpcContractor,
        [string]$Status='IN PROGRESS'
    )
    $ProjectCode = $ProjectCode.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($ProjectCode)) { throw 'Project code is required.' }
    if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw 'Project name is required.' }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO projects(project_code,project_name,location,project_type,pv_capacity_mwp,bess_capacity_mwh,client,epc_contractor,status,updated_at)
VALUES(@code,@name,@location,@type,@pv,@bess,@client,@epc,@status,datetime('now'));
'@ -SqlParameters @{code=$ProjectCode;name=$ProjectName.Trim();location=$Location;type=$ProjectType;pv=$PvCapacityMWp;bess=$BessCapacityMWh;client=$Client;epc=$EpcContractor;status=$Status} | Out-Null

    $id = (Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT project_id AS id FROM projects WHERE project_code=@c;' -SqlParameters @{c=$ProjectCode}).id
    return [int]$id
}

function Get-ECProjectStats {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT
 (SELECT COUNT(*) FROM blocks WHERE project_id=@p) AS Blocks,
 (SELECT COUNT(*) FROM assets WHERE project_id=@p) AS Assets,
 (SELECT COUNT(*) FROM test_results WHERE project_id=@p) AS Tests,
 (SELECT COUNT(*) FROM issues WHERE project_id=@p AND UPPER(status) NOT IN ('CLOSED','RESOLVED')) AS OpenIssues,
 (SELECT COUNT(*) FROM import_jobs WHERE project_id=@p) AS Imports,
 (SELECT COUNT(*) FROM rule_findings WHERE project_id=@p AND run_id=(SELECT MAX(run_id) FROM validation_runs WHERE project_id=@p)) AS Findings;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECBlockId {
    param([string]$DatabasePath,[int]$ProjectId,[string]$BlockCode)
    if ([string]::IsNullOrWhiteSpace($BlockCode)) { return $null }
    $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT block_id AS id FROM blocks WHERE project_id=@p AND block_code=@c;' -SqlParameters @{p=$ProjectId;c=$BlockCode.Trim()}
    if ($null -eq $r) { return $null }
    return [int]$r.id
}

function Get-ECAssetId {
    param([string]$DatabasePath,[int]$ProjectId,[string]$AssetCode)
    if ([string]::IsNullOrWhiteSpace($AssetCode)) { return $null }
    $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id AS id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode.Trim()}
    if ($null -eq $r) { return $null }
    return [int]$r.id
}

function Get-ECDocumentRevisionId {
    param([string]$DatabasePath,[int]$ProjectId,[string]$DocumentCode,[string]$Revision)
    if ([string]::IsNullOrWhiteSpace($DocumentCode) -or [string]::IsNullOrWhiteSpace($Revision)) { return $null }
    $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT revision_id AS id FROM document_revisions WHERE project_id=@p AND document_code=@d AND revision=@r;' -SqlParameters @{p=$ProjectId;d=$DocumentCode.Trim();r=$Revision.Trim()}
    if ($null -eq $r) { return $null }
    return [int]$r.id
}

function Get-ECImportDefinition {
    param([Parameter(Mandatory)][string]$ImportType)
    $defs = @{
        'Plant Structure' = @(
            @{Field='BlockCode';Required=$true;Aliases=@('Block','Block Code','BlockCode','Area','AreaCode')},
            @{Field='BlockName';Required=$false;Aliases=@('Block Name','BlockName','Area Name')},
            @{Field='AssetType';Required=$true;Aliases=@('Asset Type','AssetType','Type','Equipment Type')},
            @{Field='AssetCode';Required=$true;Aliases=@('Asset','Asset Code','AssetCode','Code','Equipment Code')},
            @{Field='ParentAssetCode';Required=$false;Aliases=@('Parent','Parent Asset','ParentAssetCode','Parent Code')},
            @{Field='Manufacturer';Required=$false;Aliases=@('Manufacturer','Make','Brand')},
            @{Field='Model';Required=$false;Aliases=@('Model','Product Model')},
            @{Field='SerialNumber';Required=$false;Aliases=@('Serial','Serial Number','SerialNumber','SN')},
            @{Field='Status';Required=$false;Aliases=@('Status','Installation Status')}
        );
        'String Schedule' = @(
            @{Field='BlockCode';Required=$true;Aliases=@('Block','Block Code','BlockCode')},
            @{Field='InverterCode';Required=$true;Aliases=@('Inverter','Inverter Code','InverterCode')},
            @{Field='MPPTCode';Required=$true;Aliases=@('MPPT','MPPT Code','MPPTCode')},
            @{Field='StringCode';Required=$true;Aliases=@('String','String Code','StringCode')},
            @{Field='ExpectedModules';Required=$true;Aliases=@('Expected Modules','ExpectedModules','ModuleCount','Modules')},
            @{Field='ModuleModel';Required=$false;Aliases=@('Module Model','ModuleModel','PV Module Model')},
            @{Field='Status';Required=$false;Aliases=@('Status','Installation Status')}
        );
        'Installed Equipment' = @(
            @{Field='BlockCode';Required=$true;Aliases=@('Block','Block Code','BlockCode')},
            @{Field='ParentAssetCode';Required=$false;Aliases=@('Parent','Parent Asset','ParentAssetCode','String','MPPT','Inverter')},
            @{Field='AssetType';Required=$true;Aliases=@('Asset Type','AssetType','Type')},
            @{Field='AssetCode';Required=$true;Aliases=@('Asset','Asset Code','AssetCode','Code')},
            @{Field='Manufacturer';Required=$false;Aliases=@('Manufacturer','Make','Brand')},
            @{Field='Model';Required=$false;Aliases=@('Model','Product Model')},
            @{Field='SerialNumber';Required=$false;Aliases=@('Serial','Serial Number','SerialNumber','SN')},
            @{Field='InstallationDate';Required=$true;Aliases=@('Installation Date','InstalledAt','InstallationDate','Date')},
            @{Field='DrawingCode';Required=$false;Aliases=@('Drawing','Drawing Code','DrawingCode','Document Code')},
            @{Field='DrawingRevision';Required=$false;Aliases=@('Revision','Drawing Revision','DrawingRevision')},
            @{Field='Installer';Required=$false;Aliases=@('Installer','Subcontractor','Installed By')},
            @{Field='Status';Required=$false;Aliases=@('Status','Installation Status')}
        );
        'Materials' = @(
            @{Field='BlockCode';Required=$false;Aliases=@('Block','Block Code','BlockCode')},
            @{Field='MaterialCode';Required=$true;Aliases=@('Material','Material Code','MaterialCode','Item Code')},
            @{Field='Description';Required=$false;Aliases=@('Description','Material Description')},
            @{Field='OpeningQty';Required=$false;Aliases=@('Opening','Opening Qty','OpeningQty')},
            @{Field='DeliveredQty';Required=$false;Aliases=@('Delivered','Delivered Qty','DeliveredQty')},
            @{Field='IssuedQty';Required=$false;Aliases=@('Issued','Issued Qty','IssuedQty')},
            @{Field='ReturnedQty';Required=$false;Aliases=@('Returned','Returned Qty','ReturnedQty')},
            @{Field='InstalledQty';Required=$false;Aliases=@('Installed','Installed Qty','InstalledQty')},
            @{Field='DamagedQty';Required=$false;Aliases=@('Damaged','Damaged Qty','DamagedQty')},
            @{Field='PhysicalRemaining';Required=$true;Aliases=@('Physical Remaining','PhysicalRemaining','Stock','Remaining')}
        );
        'Tests' = @(
            @{Field='AssetCode';Required=$true;Aliases=@('Asset','Asset Code','AssetCode')},
            @{Field='TestType';Required=$true;Aliases=@('Test','Test Type','TestType')},
            @{Field='TestDate';Required=$true;Aliases=@('Test Date','TestDate','Date')},
            @{Field='Result';Required=$true;Aliases=@('Result','Status')},
            @{Field='Value';Required=$false;Aliases=@('Value','Measured Value')},
            @{Field='Unit';Required=$false;Aliases=@('Unit','Units')},
            @{Field='Technician';Required=$false;Aliases=@('Technician','Engineer','Tested By')},
            @{Field='Notes';Required=$false;Aliases=@('Notes','Comments','Remarks')}
        );
        'NCR / Punch List' = @(
            @{Field='IssueCode';Required=$true;Aliases=@('Issue','Issue Code','IssueCode','NCR','NCR Number')},
            @{Field='AssetCode';Required=$true;Aliases=@('Asset','Asset Code','AssetCode')},
            @{Field='Severity';Required=$true;Aliases=@('Severity','Priority')},
            @{Field='Category';Required=$false;Aliases=@('Category','Type')},
            @{Field='Description';Required=$true;Aliases=@('Description','Issue Description')},
            @{Field='Status';Required=$true;Aliases=@('Status','Issue Status')},
            @{Field='OpenedAt';Required=$true;Aliases=@('Opened','Opened At','OpenedAt','Open Date')},
            @{Field='ClosedAt';Required=$false;Aliases=@('Closed','Closed At','ClosedAt','Close Date')}
        );
        'Documents' = @(
            @{Field='DocumentCode';Required=$true;Aliases=@('Document','Document Code','DocumentCode','Drawing Code')},
            @{Field='Revision';Required=$true;Aliases=@('Revision','Rev')},
            @{Field='ApprovedAt';Required=$true;Aliases=@('Approved','Approved At','ApprovedAt','Approval Date')},
            @{Field='IsCurrent';Required=$true;Aliases=@('Current','IsCurrent','Current Revision')},
            @{Field='Title';Required=$false;Aliases=@('Title','Document Title','Drawing Title')}
        );
        'Delivery Register' = @(
            @{Field='SerialNumber';Required=$true;Aliases=@('Serial','Serial Number','SerialNumber','SN')},
            @{Field='AssetType';Required=$false;Aliases=@('Asset Type','AssetType','Type')},
            @{Field='DeliveryNote';Required=$false;Aliases=@('Delivery Note','DeliveryNote','DN')},
            @{Field='DeliveredAt';Required=$false;Aliases=@('Delivered At','DeliveredAt','Delivery Date')}
        )
    }
    if (-not $defs.ContainsKey($ImportType)) { throw "Unknown import type: $ImportType" }
    return @($defs[$ImportType] | ForEach-Object { [pscustomobject]$_ })
}

function Get-ECAutoColumnMap {
    param([Parameter(Mandatory)][string]$ImportType,[Parameter(Mandatory)][string[]]$Headers)
    $definition = Get-ECImportDefinition -ImportType $ImportType
    $map = @{}
    foreach ($d in $definition) {
        $match = $null
        foreach ($h in $Headers) {
            foreach ($alias in $d.Aliases) {
                if ($h.Trim().ToLowerInvariant() -eq ([string]$alias).Trim().ToLowerInvariant()) { $match = $h; break }
            }
            if ($match) { break }
        }
        if ($match) { $map[$d.Field] = $match }
    }
    return $map
}

function Get-ECMappedValue {
    param($Row,[hashtable]$ColumnMap,[string]$Field)
    if (-not $ColumnMap.ContainsKey($Field)) { return $null }
    $column = [string]$ColumnMap[$Field]
    if ([string]::IsNullOrWhiteSpace($column) -or $column -eq '<Not mapped>') { return $null }
    $property = $Row.PSObject.Properties[$column]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ECImportData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$ImportType,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][hashtable]$ColumnMap
    )
    if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }
    $rows = @(Import-ECCsvFile -Path $CsvPath)
    $definition = Get-ECImportDefinition -ImportType $ImportType
    $errors = New-Object System.Collections.Generic.List[object]

    foreach ($d in $definition | Where-Object Required) {
        if (-not $ColumnMap.ContainsKey($d.Field) -or [string]::IsNullOrWhiteSpace([string]$ColumnMap[$d.Field]) -or [string]$ColumnMap[$d.Field] -eq '<Not mapped>') {
            $errors.Add([pscustomobject]@{Row=0;Field=$d.Field;Message="Required field '$($d.Field)' is not mapped."})
        }
    }
    if ($errors.Count -gt 0) {
        return [pscustomobject]@{Total=$rows.Count;Valid=0;Invalid=$rows.Count;Errors=$errors.ToArray()}
    }

    $seenPlantAssetCodes = @{}

    for ($i=0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowNum = $i + 2
        foreach ($d in $definition | Where-Object Required) {
            $v = Get-ECMappedValue -Row $row -ColumnMap $ColumnMap -Field $d.Field
            if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) {
                $errors.Add([pscustomobject]@{Row=$rowNum;Field=$d.Field;Message="Required value is blank."})
            }
        }

        try {
            switch ($ImportType) {
                'Plant Structure' {
                    $assetType = ([string](Get-ECMappedValue $row $ColumnMap 'AssetType')).Trim().ToUpperInvariant()
                    $assetCode = ([string](Get-ECMappedValue $row $ColumnMap 'AssetCode')).Trim()
                    $parentCode = ([string](Get-ECMappedValue $row $ColumnMap 'ParentAssetCode')).Trim()
                    if ($assetCode -and $parentCode -and $assetCode -eq $parentCode) { throw 'AssetCode cannot be its own ParentAssetCode.' }
                    if ($assetCode) {
                        $key = $assetCode.ToUpperInvariant()
                        if ($seenPlantAssetCodes.ContainsKey($key)) {
                            throw "Duplicate AssetCode '$assetCode' in Plant Structure CSV. Asset codes must be unique within the project in v0.2.1. First occurrence was row $($seenPlantAssetCodes[$key])."
                        }
                        $seenPlantAssetCodes[$key] = $rowNum
                    }
                    if ($assetType -notmatch '^[A-Z0-9_ -]+$') { throw "AssetType '$assetType' contains unsupported characters." }
                }
                'String Schedule' {
                    $n = [int](Get-ECMappedValue $row $ColumnMap 'ExpectedModules')
                    if ($n -le 0) { throw 'ExpectedModules must be greater than zero.' }
                }
                'Installed Equipment' { ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'InstallationDate') | Out-Null }
                'Materials' {
                    foreach ($f in @('OpeningQty','DeliveredQty','IssuedQty','ReturnedQty','InstalledQty','DamagedQty','PhysicalRemaining')) {
                        $v = Get-ECMappedValue $row $ColumnMap $f
                        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { ConvertTo-ECSafeDouble $v | Out-Null }
                    }
                }
                'Tests' { ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'TestDate') | Out-Null }
                'NCR / Punch List' { ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'OpenedAt') | Out-Null }
                'Documents' {
                    ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'ApprovedAt') | Out-Null
                    ConvertTo-ECBooleanInt (Get-ECMappedValue $row $ColumnMap 'IsCurrent') | Out-Null
                }
                'Delivery Register' {
                    $d = Get-ECMappedValue $row $ColumnMap 'DeliveredAt'
                    if ($d) { ConvertTo-ECDateText $d | Out-Null }
                }
            }
        } catch {
            $errors.Add([pscustomobject]@{Row=$rowNum;Field='Format';Message=$_.Exception.Message})
        }
    }

    $badRows = @($errors | Where-Object Row -gt 0 | Select-Object -ExpandProperty Row -Unique).Count
    return [pscustomobject]@{Total=$rows.Count;Valid=($rows.Count-$badRows);Invalid=$badRows;Errors=$errors.ToArray()}
}

function Import-ECProjectData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$ImportType,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][hashtable]$ColumnMap
    )
    $test = Test-ECImportData -DatabasePath $DatabasePath -ProjectId $ProjectId -ImportType $ImportType -CsvPath $CsvPath -ColumnMap $ColumnMap
    if ($test.Errors.Count -gt 0) {
        $fatal = @($test.Errors | Where-Object Row -eq 0)
        if ($fatal.Count -gt 0) { throw ($fatal.Message -join '; ') }
    }

    $rows = @(Import-ECCsvFile -Path $CsvPath)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO import_jobs(project_id,import_type,file_name,rows_total,rows_imported,rows_failed)
VALUES(@p,@t,@f,@total,0,0);
'@ -SqlParameters @{p=$ProjectId;t=$ImportType;f=[IO.Path]::GetFileName($CsvPath);total=$rows.Count} | Out-Null
    $importId = [int](Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT MAX(import_id) AS id FROM import_jobs WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}).id

    $imported = 0
    $failed = 0
    for ($i=0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowNum = $i + 2
        try {
            switch ($ImportType) {
                'Plant Structure' {
                    $blockCode = ([string](Get-ECMappedValue $row $ColumnMap 'BlockCode')).Trim()
                    $blockName = [string](Get-ECMappedValue $row $ColumnMap 'BlockName')
                    $assetType = ([string](Get-ECMappedValue $row $ColumnMap 'AssetType')).Trim().ToUpperInvariant()
                    $assetCode = ([string](Get-ECMappedValue $row $ColumnMap 'AssetCode')).Trim()
                    $parentCode = ([string](Get-ECMappedValue $row $ColumnMap 'ParentAssetCode')).Trim()
                    $mfg = [string](Get-ECMappedValue $row $ColumnMap 'Manufacturer')
                    $model = [string](Get-ECMappedValue $row $ColumnMap 'Model')
                    $serial = [string](Get-ECMappedValue $row $ColumnMap 'SerialNumber')
                    $status = [string](Get-ECMappedValue $row $ColumnMap 'Status')
                    if ([string]::IsNullOrWhiteSpace($status)) { $status='PLANNED' }

                    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT OR IGNORE INTO blocks(project_id,block_code,block_name) VALUES(@p,@c,@n);' -SqlParameters @{p=$ProjectId;c=$blockCode;n=$blockName} | Out-Null
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'UPDATE blocks SET block_name=COALESCE(NULLIF(@n,'''') ,block_name) WHERE project_id=@p AND block_code=@c;' -SqlParameters @{p=$ProjectId;c=$blockCode;n=$blockName} | Out-Null
                    $blockId = Get-ECBlockId $DatabasePath $ProjectId $blockCode

                    $parentId = $null
                    if (-not [string]::IsNullOrWhiteSpace($parentCode)) {
                        $parentId = Get-ECAssetId $DatabasePath $ProjectId $parentCode
                        if ($null -eq $parentId) { throw "Parent asset '$parentCode' does not exist yet. Put parent rows before child rows in Plant Structure." }
                    }

                    $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id,block_id,asset_type FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$assetCode}
                    if ($null -ne $existing -and [int]$existing.block_id -ne [int]$blockId) {
                        throw "AssetCode '$assetCode' already exists in another block. v0.2.1 requires project-wide unique asset codes."
                    }

                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR IGNORE INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,serial_number,status,source)
VALUES(@p,@b,@type,@code,@parent,@mfg,@model,NULLIF(@serial,''),@status,'CSV');
'@ -SqlParameters @{p=$ProjectId;b=$blockId;type=$assetType;code=$assetCode;parent=$parentId;mfg=$mfg;model=$model;serial=$serial;status=$status.ToUpperInvariant()} | Out-Null
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE assets SET block_id=@b,asset_type=@type,parent_asset_id=@parent,manufacturer=@mfg,model=@model,serial_number=NULLIF(@serial,''),status=@status,source='CSV'
WHERE project_id=@p AND asset_code=@code;
'@ -SqlParameters @{p=$ProjectId;b=$blockId;type=$assetType;code=$assetCode;parent=$parentId;mfg=$mfg;model=$model;serial=$serial;status=$status.ToUpperInvariant()} | Out-Null
                }
                'String Schedule' {
                    $blockCode = ([string](Get-ECMappedValue $row $ColumnMap 'BlockCode')).Trim()
                    $invCode = ([string](Get-ECMappedValue $row $ColumnMap 'InverterCode')).Trim()
                    $mpptCode = ([string](Get-ECMappedValue $row $ColumnMap 'MPPTCode')).Trim()
                    $stringCode = ([string](Get-ECMappedValue $row $ColumnMap 'StringCode')).Trim()
                    $expected = [int](Get-ECMappedValue $row $ColumnMap 'ExpectedModules')
                    $moduleModel = [string](Get-ECMappedValue $row $ColumnMap 'ModuleModel')
                    $status = [string](Get-ECMappedValue $row $ColumnMap 'Status')
                    if ([string]::IsNullOrWhiteSpace($status)) { $status='PLANNED' }
                    $blockId = Get-ECBlockId $DatabasePath $ProjectId $blockCode
                    if ($null -eq $blockId) { throw "Block '$blockCode' does not exist. Import Plant Structure first." }
                    $invId = Get-ECAssetId $DatabasePath $ProjectId $invCode
                    if ($null -eq $invId) { throw "Inverter '$invCode' does not exist. Import Plant Structure first." }

                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR IGNORE INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,status,source)
VALUES(@p,@b,'MPPT',@c,@parent,@status,'CSV');
'@ -SqlParameters @{p=$ProjectId;b=$blockId;c=$mpptCode;parent=$invId;status=$status.ToUpperInvariant()} | Out-Null
                    $mpptId = Get-ECAssetId $DatabasePath $ProjectId $mpptCode
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR IGNORE INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,model,status,source)
VALUES(@p,@b,'STRING',@c,@parent,@model,@status,'CSV');
'@ -SqlParameters @{p=$ProjectId;b=$blockId;c=$stringCode;parent=$mpptId;model=$moduleModel;status=$status.ToUpperInvariant()} | Out-Null
                    $stringId = Get-ECAssetId $DatabasePath $ProjectId $stringCode
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT OR REPLACE INTO design_requirements(asset_id,requirement_key,requirement_value) VALUES(@a,''EXPECTED_MODULE_COUNT'',@v);' -SqlParameters @{a=$stringId;v=[string]$expected} | Out-Null
                }
                'Installed Equipment' {
                    $blockCode = ([string](Get-ECMappedValue $row $ColumnMap 'BlockCode')).Trim()
                    $assetCode = ([string](Get-ECMappedValue $row $ColumnMap 'AssetCode')).Trim()
                    $assetType = ([string](Get-ECMappedValue $row $ColumnMap 'AssetType')).Trim().ToUpperInvariant()
                    $parentCode = [string](Get-ECMappedValue $row $ColumnMap 'ParentAssetCode')
                    $mfg = [string](Get-ECMappedValue $row $ColumnMap 'Manufacturer')
                    $model = [string](Get-ECMappedValue $row $ColumnMap 'Model')
                    $serial = [string](Get-ECMappedValue $row $ColumnMap 'SerialNumber')
                    $installedAt = ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'InstallationDate')
                    $drawingCode = [string](Get-ECMappedValue $row $ColumnMap 'DrawingCode')
                    $drawingRev = [string](Get-ECMappedValue $row $ColumnMap 'DrawingRevision')
                    $installer = [string](Get-ECMappedValue $row $ColumnMap 'Installer')
                    $status = [string](Get-ECMappedValue $row $ColumnMap 'Status')
                    if ([string]::IsNullOrWhiteSpace($status)) { $status='INSTALLED' }
                    $blockId = Get-ECBlockId $DatabasePath $ProjectId $blockCode
                    if ($null -eq $blockId) { throw "Block '$blockCode' does not exist." }
                    $parentId = $null
                    if (-not [string]::IsNullOrWhiteSpace($parentCode)) {
                        $parentId = Get-ECAssetId $DatabasePath $ProjectId $parentCode.Trim()
                        if ($null -eq $parentId) { throw "Parent asset '$parentCode' does not exist." }
                    }
                    $revisionId = $null
                    if (-not [string]::IsNullOrWhiteSpace($drawingCode) -or -not [string]::IsNullOrWhiteSpace($drawingRev)) {
                        if ([string]::IsNullOrWhiteSpace($drawingCode) -or [string]::IsNullOrWhiteSpace($drawingRev)) { throw 'Both DrawingCode and DrawingRevision are required when linking a drawing.' }
                        $revisionId = Get-ECDocumentRevisionId $DatabasePath $ProjectId $drawingCode.Trim() $drawingRev.Trim()
                        if ($null -eq $revisionId) { throw "Document '$drawingCode' revision '$drawingRev' is not registered. Import Documents first." }
                    }
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR IGNORE INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,serial_number,status,source)
VALUES(@p,@b,@type,@code,@parent,@mfg,@model,@serial,@status,'CSV');
'@ -SqlParameters @{p=$ProjectId;b=$blockId;type=$assetType;code=$assetCode;parent=$parentId;mfg=$mfg;model=$model;serial=$serial;status=$status.ToUpperInvariant()} | Out-Null
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE assets SET block_id=@b,asset_type=@type,parent_asset_id=@parent,manufacturer=@mfg,model=@model,serial_number=NULLIF(@serial,''),status=@status,source='CSV'
WHERE project_id=@p AND asset_code=@code;
'@ -SqlParameters @{p=$ProjectId;b=$blockId;type=$assetType;code=$assetCode;parent=$parentId;mfg=$mfg;model=$model;serial=$serial;status=$status.ToUpperInvariant()} | Out-Null
                    $assetId = Get-ECAssetId $DatabasePath $ProjectId $assetCode
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO installation_records(asset_id,installed_at,document_revision_id,installer)
VALUES(@a,@d,@r,@i);
'@ -SqlParameters @{a=$assetId;d=$installedAt;r=$revisionId;i=$installer} | Out-Null
                }
                'Materials' {
                    $blockCode = [string](Get-ECMappedValue $row $ColumnMap 'BlockCode')
                    $blockId = $null
                    if (-not [string]::IsNullOrWhiteSpace($blockCode)) {
                        $blockId = Get-ECBlockId $DatabasePath $ProjectId $blockCode.Trim()
                        if ($null -eq $blockId) { throw "Block '$blockCode' does not exist." }
                    }
                    $code = ([string](Get-ECMappedValue $row $ColumnMap 'MaterialCode')).Trim()
                    $desc = [string](Get-ECMappedValue $row $ColumnMap 'Description')
                    $opening = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'OpeningQty')
                    $delivered = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'DeliveredQty')
                    $issued = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'IssuedQty')
                    $returned = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'ReturnedQty')
                    $installed = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'InstalledQty')
                    $damaged = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'DamagedQty')
                    $physical = ConvertTo-ECSafeDouble (Get-ECMappedValue $row $ColumnMap 'PhysicalRemaining')
                    $expected = $opening + $delivered - $issued + $returned - $damaged
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO material_balances(project_id,block_id,material_code,description,opening_qty,delivered_qty,issued_qty,returned_qty,installed_qty,damaged_qty,physical_remaining,expected_remaining)
VALUES(@p,@b,@c,@d,@o,@del,@iss,@ret,@inst,@dam,@phy,@exp);
'@ -SqlParameters @{p=$ProjectId;b=$blockId;c=$code;d=$desc;o=$opening;del=$delivered;iss=$issued;ret=$returned;inst=$installed;dam=$damaged;phy=$physical;exp=$expected} | Out-Null
                }
                'Tests' {
                    $assetCode = ([string](Get-ECMappedValue $row $ColumnMap 'AssetCode')).Trim()
                    $assetId = Get-ECAssetId $DatabasePath $ProjectId $assetCode
                    if ($null -eq $assetId) { throw "Asset '$assetCode' does not exist." }
                    $testType = ([string](Get-ECMappedValue $row $ColumnMap 'TestType')).Trim()
                    $testDate = ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'TestDate')
                    $result = ([string](Get-ECMappedValue $row $ColumnMap 'Result')).Trim().ToUpperInvariant()
                    $valueRaw = Get-ECMappedValue $row $ColumnMap 'Value'
                    $value = $null
                    if ($null -ne $valueRaw -and -not [string]::IsNullOrWhiteSpace([string]$valueRaw)) { $value = ConvertTo-ECSafeDouble $valueRaw }
                    $unit = [string](Get-ECMappedValue $row $ColumnMap 'Unit')
                    $tech = [string](Get-ECMappedValue $row $ColumnMap 'Technician')
                    $notes = [string](Get-ECMappedValue $row $ColumnMap 'Notes')
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO test_results(project_id,asset_id,test_type,test_date,result,value,unit,technician,notes)
VALUES(@p,@a,@t,@d,@r,@v,@u,@tech,@n);
'@ -SqlParameters @{p=$ProjectId;a=$assetId;t=$testType;d=$testDate;r=$result;v=$value;u=$unit;tech=$tech;n=$notes} | Out-Null
                }
                'NCR / Punch List' {
                    $issueCode = ([string](Get-ECMappedValue $row $ColumnMap 'IssueCode')).Trim()
                    $assetCode = ([string](Get-ECMappedValue $row $ColumnMap 'AssetCode')).Trim()
                    $assetId = Get-ECAssetId $DatabasePath $ProjectId $assetCode
                    if ($null -eq $assetId) { throw "Asset '$assetCode' does not exist." }
                    $sev = ([string](Get-ECMappedValue $row $ColumnMap 'Severity')).Trim().ToUpperInvariant()
                    if ($sev -notin @('BLOCKER','WARNING','INFO')) { throw "Severity '$sev' must be BLOCKER, WARNING, or INFO." }
                    $cat = [string](Get-ECMappedValue $row $ColumnMap 'Category')
                    $desc = [string](Get-ECMappedValue $row $ColumnMap 'Description')
                    $status = ([string](Get-ECMappedValue $row $ColumnMap 'Status')).Trim().ToUpperInvariant()
                    $opened = ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'OpenedAt')
                    $closed = ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'ClosedAt') -AllowBlank
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO issues(project_id,issue_code,asset_id,severity,category,description,status,opened_at,closed_at)
VALUES(@p,@c,@a,@s,@cat,@d,@status,@o,@closed);
'@ -SqlParameters @{p=$ProjectId;c=$issueCode;a=$assetId;s=$sev;cat=$cat;d=$desc;status=$status;o=$opened;closed=$closed} | Out-Null
                }
                'Documents' {
                    $code = ([string](Get-ECMappedValue $row $ColumnMap 'DocumentCode')).Trim()
                    $rev = ([string](Get-ECMappedValue $row $ColumnMap 'Revision')).Trim()
                    $approved = ConvertTo-ECDateText (Get-ECMappedValue $row $ColumnMap 'ApprovedAt')
                    $current = ConvertTo-ECBooleanInt (Get-ECMappedValue $row $ColumnMap 'IsCurrent')
                    $title = [string](Get-ECMappedValue $row $ColumnMap 'Title')
                    if ($current -eq 1) {
                        Invoke-SqliteQuery -DataSource $DatabasePath -Query 'UPDATE document_revisions SET is_current=0 WHERE project_id=@p AND document_code=@c;' -SqlParameters @{p=$ProjectId;c=$code} | Out-Null
                    }
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO document_revisions(project_id,document_code,revision,approved_at,is_current,title)
VALUES(@p,@c,@r,@a,@i,@t);
'@ -SqlParameters @{p=$ProjectId;c=$code;r=$rev;a=$approved;i=$current;t=$title} | Out-Null
                }
                'Delivery Register' {
                    $serial = ([string](Get-ECMappedValue $row $ColumnMap 'SerialNumber')).Trim()
                    $type = [string](Get-ECMappedValue $row $ColumnMap 'AssetType')
                    $note = [string](Get-ECMappedValue $row $ColumnMap 'DeliveryNote')
                    $dateRaw = Get-ECMappedValue $row $ColumnMap 'DeliveredAt'
                    $date = $null
                    if ($dateRaw) { $date = ConvertTo-ECDateText $dateRaw }
                    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO delivered_serials(project_id,serial_number,asset_type,delivery_note,delivered_at)
VALUES(@p,@s,@t,@n,@d);
'@ -SqlParameters @{p=$ProjectId;s=$serial;t=$type;n=$note;d=$date} | Out-Null
                }
            }
            $imported++
        } catch {
            $failed++
            Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO import_errors(import_id,row_number,field_name,error_message) VALUES(@i,@r,'Row',@m);
'@ -SqlParameters @{i=$importId;r=$rowNum;m=$_.Exception.Message} | Out-Null
        }
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'UPDATE import_jobs SET rows_imported=@ok, rows_failed=@bad WHERE import_id=@i;' -SqlParameters @{ok=$imported;bad=$failed;i=$importId} | Out-Null
    return [pscustomobject]@{ImportId=$importId;Total=$rows.Count;Imported=$imported;Failed=$failed}
}

function Get-ECImportHistory {
    param([string]$DatabasePath,[int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT import_id AS ImportId, import_type AS Type, file_name AS File, rows_total AS Total,
       rows_imported AS Imported, rows_failed AS Failed, imported_at AS ImportedAt
FROM import_jobs WHERE project_id=@p ORDER BY import_id DESC LIMIT 50;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECImportErrors {
    param([string]$DatabasePath,[int]$ImportId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT row_number AS Row, field_name AS Field, error_message AS Message
FROM import_errors WHERE import_id=@i ORDER BY error_id;
'@ -SqlParameters @{i=$ImportId}
}

function Invoke-ECValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO validation_runs(project_id,started_at,status) VALUES(@p,@d,'RUNNING');" -SqlParameters @{p=$ProjectId;d=$now} | Out-Null
    $runId = [int](Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT MAX(run_id) AS id FROM validation_runs WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}).id

    $ruleFile = Join-Path $PSScriptRoot '..\database\rules.sql'
    $raw = Get-Content -LiteralPath $ruleFile -Raw
    $sections = [regex]::Split($raw, '(?m)^-- RULE:') | Where-Object { $_.Trim() }

    foreach ($section in $sections) {
        $lines = $section.Trim() -split "`r?`n"
        $meta = $lines[0].Trim().Split('|')
        if ($meta.Count -lt 4) { continue }
        $ruleId = $meta[0].Trim(); $severity = $meta[1].Trim(); $category = $meta[2].Trim(); $name = $meta[3].Trim()
        $sql = ($lines[1..($lines.Count-1)] -join "`n").Trim()
        $rows = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $sql -SqlParameters @{projectId=$ProjectId})
        foreach ($row in $rows) {
            Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO rule_findings(run_id,project_id,rule_id,severity,category,rule_name,block_code,asset_code,message,created_at)
VALUES(@run,@p,@rule,@sev,@cat,@name,@block,@asset,@msg,datetime('now'));
'@ -SqlParameters @{
                run=$runId;p=$ProjectId;rule=$ruleId;sev=$severity;cat=$category;name=$name;
                block=[string]$row.block_code;asset=[string]$row.asset_code;msg=[string]$row.message
            } | Out-Null
        }
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM readiness_results WHERE project_id=@p;' -SqlParameters @{p=$ProjectId} | Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO readiness_results(project_id,block_id,readiness_score,decision,blocker_count,warning_count,calculated_at)
SELECT @p, b.block_id,
       MAX(0, 100 - 22 * SUM(CASE WHEN f.severity='BLOCKER' THEN 1 ELSE 0 END)
                   - 8 * SUM(CASE WHEN f.severity='WARNING' THEN 1 ELSE 0 END)) AS score,
       CASE WHEN SUM(CASE WHEN f.severity='BLOCKER' THEN 1 ELSE 0 END) > 0 THEN 'NOT READY' ELSE 'READY' END,
       SUM(CASE WHEN f.severity='BLOCKER' THEN 1 ELSE 0 END),
       SUM(CASE WHEN f.severity='WARNING' THEN 1 ELSE 0 END),
       datetime('now')
FROM blocks b
LEFT JOIN rule_findings f ON f.block_code=b.block_code AND f.project_id=@p AND f.run_id=@r
WHERE b.project_id=@p
GROUP BY b.block_id;
'@ -SqlParameters @{p=$ProjectId;r=$runId} | Out-Null

    Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE validation_runs SET finished_at=datetime('now'), status='COMPLETE' WHERE run_id=@r;" -SqlParameters @{r=$runId} | Out-Null
    if (Get-Command Sync-ECFindingCases -ErrorAction SilentlyContinue) { Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId $ProjectId }
    return Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId
}

function Get-ECFindings {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT severity AS Severity, rule_id AS Rule, category AS Category, block_code AS Block,
       COALESCE(asset_code,'') AS Asset, message AS Message
FROM rule_findings
WHERE project_id=@p AND run_id=(SELECT MAX(run_id) FROM validation_runs WHERE project_id=@p)
ORDER BY CASE severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END, block_code, rule_id;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECReadiness {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT b.block_code AS Block,
       rr.readiness_score AS Score,
       rr.decision AS Decision,
       rr.blocker_count AS Blockers,
       rr.warning_count AS Warnings
FROM readiness_results rr
JOIN blocks b ON b.block_id=rr.block_id
WHERE rr.project_id=@p
ORDER BY b.block_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Show-ECSummary {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $project = Get-ECProject -DatabasePath $DatabasePath -ProjectId $ProjectId
    $blocks = @(Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $findings = @(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
    Write-Host ''
    Write-Host "=== ENERGIZECHECK READINESS: $($project.ProjectName) ===" -ForegroundColor Cyan
    $blocks | Format-Table -AutoSize
    Write-Host "Findings: $($findings.Count)" -ForegroundColor Yellow
    if ($findings.Count -gt 0) { $findings | Format-Table Severity,Rule,Block,Asset,Message -Wrap -AutoSize }
}

function Export-ECReport {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $reportDir = Join-Path $PSScriptRoot '..\reports'
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $project = Get-ECProject -DatabasePath $DatabasePath -ProjectId $ProjectId
    $safeCode = ($project.ProjectCode -replace '[^A-Za-z0-9_-]','_')
    $path = Join-Path $reportDir ("readiness-{0}.html" -f $safeCode)
    $blocks = @(Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $findings = @(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $stats = Get-ECProjectStats -DatabasePath $DatabasePath -ProjectId $ProjectId

    $blockRows = ($blocks | ForEach-Object {
        $class = if ($_.Decision -eq 'READY') {'ready'} else {'notready'}
        "<tr><td>$($_.Block)</td><td>$($_.Score)%</td><td class='$class'>$($_.Decision)</td><td>$($_.Blockers)</td><td>$($_.Warnings)</td></tr>"
    }) -join "`n"
    if ($findings.Count -eq 0) {
        $findingRows = '<tr><td colspan="6" class="ready">No open validation findings.</td></tr>'
    } else {
        $findingRows = ($findings | ForEach-Object {
            "<tr><td>$($_.Severity)</td><td>$($_.Rule)</td><td>$($_.Category)</td><td>$($_.Block)</td><td>$($_.Asset)</td><td>$([System.Net.WebUtility]::HtmlEncode($_.Message))</td></tr>"
        }) -join "`n"
    }

    $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>EnergizeCheck - $($project.ProjectCode)</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:36px;color:#17202a;background:#fff}h1{margin-bottom:2px}.sub{color:#667085;margin-bottom:22px}
.meta{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;background:#f5f7fa;padding:16px;border-radius:8px;margin:16px 0 24px}.card{padding:10px;background:#fff;border:1px solid #e4e7ec;border-radius:6px}
table{border-collapse:collapse;width:100%;margin:12px 0 28px}th,td{border:1px solid #d8dde3;padding:9px;text-align:left;vertical-align:top}th{background:#eef2f5}.ready{font-weight:700;color:#157347}.notready{font-weight:700;color:#b02a37}
</style></head><body>
<h1>EnergizeCheck</h1><div class="sub">PV/BESS Commissioning Readiness &amp; As-Built Integrity Report</div>
<h2>$([System.Net.WebUtility]::HtmlEncode($project.ProjectName))</h2>
<div class="meta"><div class="card"><b>Project Code</b><br>$($project.ProjectCode)</div><div class="card"><b>Type</b><br>$($project.ProjectType)</div><div class="card"><b>Location</b><br>$([System.Net.WebUtility]::HtmlEncode([string]$project.Location))</div><div class="card"><b>PV Capacity</b><br>$($project.PvMWp) MWp</div><div class="card"><b>BESS Capacity</b><br>$($project.BessMWh) MWh</div><div class="card"><b>Generated</b><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div></div>
<h2>Block Readiness</h2><table><thead><tr><th>Block</th><th>Score</th><th>Decision</th><th>Blockers</th><th>Warnings</th></tr></thead><tbody>$blockRows</tbody></table>
<h2>Validation Findings</h2><table><thead><tr><th>Severity</th><th>Rule</th><th>Category</th><th>Block</th><th>Asset</th><th>Finding</th></tr></thead><tbody>$findingRows</tbody></table>
</body></html>
"@
    Set-Content -LiteralPath $path -Value $html -Encoding UTF8
    return (Resolve-Path $path).Path
}

function Repair-ECDemoData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[int]$ProjectId=1)

    Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE assets SET serial_number='SN-B1-004-FIX' WHERE project_id=@p AND asset_code='MOD-B1-004';" -SqlParameters @{p=$ProjectId} | Out-Null
    foreach ($serial in @('SN-B1-004-FIX','SN-B2-003','SN-B2-004')) {
        Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT OR IGNORE INTO delivered_serials(project_id,serial_number,asset_type,delivery_note) VALUES(@p,@s,'PV_MODULE','DN-REPAIR');" -SqlParameters @{p=$ProjectId;s=$serial} | Out-Null
    }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE installation_records SET document_revision_id=(SELECT revision_id FROM document_revisions WHERE project_id=@p AND document_code='SLD-001' AND is_current=1)
WHERE asset_id=(SELECT asset_id FROM assets WHERE project_id=@p AND asset_code='INV-B1');
'@ -SqlParameters @{p=$ProjectId} | Out-Null

    $exists = [int](Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) AS n FROM assets WHERE project_id=@p AND asset_code='MOD-B2-004';" -SqlParameters @{p=$ProjectId}).n
    if ($exists -eq 0) {
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO assets(project_id,block_id,asset_type,asset_code,parent_asset_id,manufacturer,model,serial_number,status,source)
SELECT project_id,block_id,'PV_MODULE','MOD-B2-004',asset_id,'Jinko','Demo-640W','SN-B2-004','INSTALLED','DEMO-FIX'
FROM assets WHERE project_id=@p AND asset_code='STR-B2-01';
'@ -SqlParameters @{p=$ProjectId} | Out-Null
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO installation_records(asset_id,installed_at,document_revision_id,installer)
SELECT a.asset_id,'2026-08-18',(SELECT revision_id FROM document_revisions WHERE project_id=@p AND document_code='SLD-001' AND is_current=1),'Demo Team'
FROM assets a WHERE a.project_id=@p AND a.asset_code='MOD-B2-004';
'@ -SqlParameters @{p=$ProjectId} | Out-Null
    }

    $strB1 = Get-ECAssetId $DatabasePath $ProjectId 'STR-B1-01'
    $strB2 = Get-ECAssetId $DatabasePath $ProjectId 'STR-B2-01'
    Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE test_results SET test_date='2026-08-19' WHERE project_id=@p AND asset_id=@a AND UPPER(test_type)='IR';" -SqlParameters @{p=$ProjectId;a=$strB1} | Out-Null
    $hasB2 = [int](Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) AS n FROM test_results WHERE project_id=@p AND asset_id=@a AND UPPER(test_type)='IR' AND UPPER(result)='PASS';" -SqlParameters @{p=$ProjectId;a=$strB2}).n
    if ($hasB2 -eq 0) {
        Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO test_results(project_id,asset_id,test_type,test_date,result,value,unit,technician) VALUES(@p,@a,'IR','2026-08-19','PASS',500,'MOhm','Demo Engineer');" -SqlParameters @{p=$ProjectId;a=$strB2} | Out-Null
    }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE issues SET status='CLOSED', closed_at='2026-08-20' WHERE project_id=@p AND issue_code='NCR-001';" -SqlParameters @{p=$ProjectId} | Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE material_balances SET physical_remaining=expected_remaining WHERE project_id=@p AND material_code='DC-CABLE-6MM';" -SqlParameters @{p=$ProjectId} | Out-Null
    Write-Host 'Synthetic demo fixes applied.' -ForegroundColor Green
}



# -----------------------------------------------------------------------------
# EnergizeCheck v0.3 - Engineering Intelligence
# -----------------------------------------------------------------------------

function Initialize-ECEngineeringSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $sqlFile = Join-Path $PSScriptRoot '..\database\schema-v03.sql'
    if (-not (Test-Path -LiteralPath $sqlFile)) { throw "v0.3 schema file not found: $sqlFile" }
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $sqlFile
}

function Set-ECParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][double]$Value,
        [string]$Unit,
        [string]$Description
    )
    $Key = $Key.Trim().ToUpperInvariant()
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO engineering_parameters(project_id,parameter_key,parameter_value,unit,description,updated_at)
VALUES(@p,@k,@v,@u,@d,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;k=$Key;v=$Value;u=$Unit;d=$Description} | Out-Null
}

function Get-ECParameters {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT parameter_key AS Parameter, parameter_value AS Value, COALESCE(unit,'') AS Unit, COALESCE(description,'') AS Description
FROM engineering_parameters WHERE project_id=@p ORDER BY parameter_key;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECStringEngineering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$StringCode,
        [Parameter(Mandatory)][double]$ModuleVocStcV,
        [Parameter(Mandatory)][double]$VocTempCoeffPctC,
        [double]$MeasurementTempC=25,
        [Nullable[double]]$MeasuredVocV,
        [Nullable[double]]$MeasuredIscA,
        [Nullable[double]]$MeasuredIRMOhm,
        [string]$Polarity
    )
    $asset = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT asset_id,asset_type FROM assets WHERE project_id=@p AND asset_code=@c;" -SqlParameters @{p=$ProjectId;c=$StringCode}
    if ($null -eq $asset) { throw "String '$StringCode' does not exist." }
    if ([string]$asset.asset_type -ne 'STRING') { throw "Asset '$StringCode' is not a STRING." }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO string_engineering(asset_id,module_voc_stc_v,voc_temp_coeff_pct_c,measurement_temp_c,measured_voc_v,measured_isc_a,measured_ir_mohm,polarity,updated_at)
VALUES(@a,@voc,@tc,@temp,@mv,@mi,@ir,@pol,datetime('now'));
'@ -SqlParameters @{a=[int]$asset.asset_id;voc=$ModuleVocStcV;tc=$VocTempCoeffPctC;temp=$MeasurementTempC;mv=$MeasuredVocV;mi=$MeasuredIscA;ir=$MeasuredIRMOhm;pol=$Polarity} | Out-Null
}

function Get-ECStringEngineering {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH cfg AS (
 SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='STRING_VOC_TOLERANCE_PCT'),5.0) AS tol
), q AS (
 SELECT COALESCE(b.block_code,'') AS block_code,
        s.asset_code AS string_code,
        CAST(dr.requirement_value AS INTEGER) AS modules,
        se.module_voc_stc_v AS module_voc,
        se.measurement_temp_c AS temp_c,
        CAST(dr.requirement_value AS REAL)*se.module_voc_stc_v*(1.0+(se.voc_temp_coeff_pct_c/100.0)*(COALESCE(se.measurement_temp_c,25.0)-25.0)) AS expected_voc,
        se.measured_voc_v AS measured_voc,
        se.measured_ir_mohm AS measured_ir,
        se.polarity AS polarity,
        cfg.tol AS tol
 FROM string_engineering se
 JOIN assets s ON s.asset_id=se.asset_id
 LEFT JOIN blocks b ON b.block_id=s.block_id
 LEFT JOIN design_requirements dr ON dr.asset_id=s.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
 CROSS JOIN cfg
 WHERE s.project_id=@p
)
SELECT block_code AS Block, string_code AS String, modules AS Modules,
       ROUND(module_voc,2) AS ModuleVoc, ROUND(temp_c,1) AS TempC,
       ROUND(expected_voc,2) AS ExpectedVoc, ROUND(measured_voc,2) AS MeasuredVoc,
       ROUND(ABS(measured_voc-expected_voc)/NULLIF(expected_voc,0)*100.0,2) AS VocDeviationPct,
       ROUND(measured_ir,2) AS IR_MOhm, COALESCE(polarity,'') AS Polarity,
       tol AS AllowedVocDeviationPct
FROM q ORDER BY block_code,string_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECInverterEngineering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$InverterCode,
        [double]$MaxDcVoltageV,
        [double]$MpptMinVoltageV,
        [double]$MpptMaxVoltageV,
        [int]$MaxStringsPerMppt
    )
    $asset = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT asset_id,asset_type FROM assets WHERE project_id=@p AND asset_code=@c;" -SqlParameters @{p=$ProjectId;c=$InverterCode}
    if ($null -eq $asset) { throw "Inverter '$InverterCode' does not exist." }
    if ([string]$asset.asset_type -ne 'INVERTER') { throw "Asset '$InverterCode' is not an INVERTER." }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO inverter_engineering(asset_id,max_dc_voltage_v,mppt_min_voltage_v,mppt_max_voltage_v,max_strings_per_mppt,updated_at)
VALUES(@a,@maxdc,@minmppt,@maxmppt,@maxstr,datetime('now'));
'@ -SqlParameters @{a=[int]$asset.asset_id;maxdc=$MaxDcVoltageV;minmppt=$MpptMinVoltageV;maxmppt=$MpptMaxVoltageV;maxstr=$MaxStringsPerMppt} | Out-Null
}

function Get-ECInverterEngineering {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block, inv.asset_code AS Inverter,
       ie.max_dc_voltage_v AS MaxDcV, ie.mppt_min_voltage_v AS MpptMinV,
       ie.mppt_max_voltage_v AS MpptMaxV, ie.max_strings_per_mppt AS MaxStringsPerMppt
FROM inverter_engineering ie
JOIN assets inv ON inv.asset_id=ie.asset_id
LEFT JOIN blocks b ON b.block_id=inv.block_id
WHERE inv.project_id=@p ORDER BY b.block_code,inv.asset_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECCableEngineering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$CableCode,
        [string]$BlockCode,
        [string]$FromAssetCode,
        [string]$ToAssetCode,
        [ValidateSet('CU','AL')][string]$ConductorMaterial='CU',
        [ValidateSet('DC','AC1','AC3')][string]$PhaseType='DC',
        [Parameter(Mandatory)][double]$DesignSizeMm2,
        [Parameter(Mandatory)][double]$InstalledSizeMm2,
        [Parameter(Mandatory)][double]$LengthM,
        [Parameter(Mandatory)][double]$DesignCurrentA,
        [Parameter(Mandatory)][double]$SystemVoltageV,
        [Nullable[double]]$MaxVoltageDropPct,
        [Nullable[double]]$MeasuredIRMOhm,
        [string]$Status='INSTALLED'
    )
    $blockId = $null
    if (-not [string]::IsNullOrWhiteSpace($BlockCode)) { $blockId=Get-ECBlockId $DatabasePath $ProjectId $BlockCode; if ($null -eq $blockId) { throw "Block '$BlockCode' does not exist." } }
    $fromId=$null; if (-not [string]::IsNullOrWhiteSpace($FromAssetCode)) { $fromId=Get-ECAssetId $DatabasePath $ProjectId $FromAssetCode; if ($null -eq $fromId){throw "From asset '$FromAssetCode' does not exist."} }
    $toId=$null; if (-not [string]::IsNullOrWhiteSpace($ToAssetCode)) { $toId=Get-ECAssetId $DatabasePath $ProjectId $ToAssetCode; if ($null -eq $toId){throw "To asset '$ToAssetCode' does not exist."} }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO cable_engineering(project_id,block_id,cable_code,from_asset_id,to_asset_id,conductor_material,phase_type,design_size_mm2,installed_size_mm2,length_m,design_current_a,system_voltage_v,max_voltage_drop_pct,measured_ir_mohm,status,updated_at)
VALUES(@p,@b,@c,@f,@t,@mat,@phase,@design,@installed,@len,@amps,@volts,@maxdrop,@ir,@status,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;b=$blockId;c=$CableCode;f=$fromId;t=$toId;mat=$ConductorMaterial;phase=$PhaseType;design=$DesignSizeMm2;installed=$InstalledSizeMm2;len=$LengthM;amps=$DesignCurrentA;volts=$SystemVoltageV;maxdrop=$MaxVoltageDropPct;ir=$MeasuredIRMOhm;status=$Status} | Out-Null
}

function Get-ECCableEngineering {
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH cfg AS (
 SELECT COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='MAX_CABLE_VDROP_PCT'),2.0) AS project_limit
), q AS (
 SELECT c.*,COALESCE(b.block_code,'') AS block_code,
        CASE UPPER(c.conductor_material) WHEN 'AL' THEN 0.0282 ELSE 0.0175 END AS rho,
        CASE UPPER(c.phase_type) WHEN 'AC3' THEN 1.7320508075688772 ELSE 2.0 END AS factor,
        COALESCE(c.max_voltage_drop_pct,cfg.project_limit) AS allowed_drop
 FROM cable_engineering c LEFT JOIN blocks b ON b.block_id=c.block_id CROSS JOIN cfg WHERE c.project_id=@p
)
SELECT block_code AS Block,cable_code AS Cable,phase_type AS Type,conductor_material AS Material,
       design_size_mm2 AS DesignMm2,installed_size_mm2 AS InstalledMm2,length_m AS LengthM,
       design_current_a AS CurrentA,system_voltage_v AS VoltageV,
       ROUND(factor*length_m*design_current_a*rho/NULLIF(installed_size_mm2,0)/NULLIF(system_voltage_v,0)*100.0,2) AS VoltageDropPct,
       allowed_drop AS AllowedDropPct,measured_ir_mohm AS IR_MOhm
FROM q ORDER BY block_code,cable_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Clear-ECEngineeringData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM cable_engineering WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}|Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM string_engineering WHERE asset_id IN (SELECT asset_id FROM assets WHERE project_id=@p);' -SqlParameters @{p=$ProjectId}|Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM inverter_engineering WHERE asset_id IN (SELECT asset_id FROM assets WHERE project_id=@p);' -SqlParameters @{p=$ProjectId}|Out-Null
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM engineering_parameters WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}|Out-Null
}



# -----------------------------------------------------------------------------
# EnergizeCheck v0.4 - Asset Explorer, Diagnostics and Finding Workflow
# -----------------------------------------------------------------------------

function Initialize-ECV04Schema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $sqlFile = Join-Path $PSScriptRoot '..\database\schema-v04.sql'
    if (-not (Test-Path -LiteralPath $sqlFile)) { throw "v0.4 schema file not found: $sqlFile" }
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $sqlFile

    # Backfill lifecycle cases from all historical validation runs so the workflow
    # remains useful even when the current project has already been remediated.
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR IGNORE INTO finding_cases(
    project_id,rule_id,block_code,asset_code,severity,category,title,message,status,
    first_detected_at,last_detected_at,closed_at
)
SELECT
    project_id,
    rule_id,
    COALESCE(block_code,''),
    COALESCE(asset_code,''),
    MAX(severity),
    MAX(category),
    MAX(rule_name),
    MAX(message),
    'CLOSED',
    MIN(created_at),
    MAX(created_at),
    MAX(created_at)
FROM rule_findings
GROUP BY project_id,rule_id,COALESCE(block_code,''),COALESCE(asset_code,'');
'@ | Out-Null

    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO finding_case_history(case_id,status,note,changed_at)
SELECT c.case_id,c.status,'Backfilled from EnergizeCheck validation history.',c.last_detected_at
FROM finding_cases c
WHERE NOT EXISTS(SELECT 1 FROM finding_case_history h WHERE h.case_id=c.case_id);
'@ | Out-Null

    foreach ($p in @(Get-ECProjects -DatabasePath $DatabasePath)) {
        Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId ([int]$p.ProjectId)
    }
}

function Get-ECKPIs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH latest AS (
    SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p
)
SELECT
    CAST(ROUND(COALESCE((SELECT AVG(readiness_score) FROM readiness_results WHERE project_id=@p),0),0) AS INTEGER) AS ProjectReadiness,
    (SELECT COUNT(*) FROM blocks WHERE project_id=@p) AS Blocks,
    (SELECT COUNT(*) FROM assets WHERE project_id=@p) AS Assets,
    (SELECT COUNT(*) FROM rule_findings WHERE project_id=@p AND run_id=(SELECT run_id FROM latest) AND severity='BLOCKER') AS Blockers,
    (SELECT COUNT(*) FROM rule_findings WHERE project_id=@p AND run_id=(SELECT run_id FROM latest) AND severity='WARNING') AS Warnings,
    (SELECT COUNT(*) FROM test_results WHERE project_id=@p AND UPPER(result) IN ('FAIL','FAILED','NOK')) AS FailedTests,
    (SELECT COUNT(*) FROM issues WHERE project_id=@p AND UPPER(status) NOT IN ('CLOSED','RESOLVED')) AS OpenNCRs;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECReadinessBreakdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH areas(area_name,sort_order) AS (
    VALUES
      ('Design Integrity',1),
      ('Asset Traceability',2),
      ('Documentation',3),
      ('Electrical Tests',4),
      ('Quality / NCR',5),
      ('Electrical Engineering',6),
      ('Cable Engineering',7),
      ('Material Reconciliation',8),
      ('Other',9)
), latest AS (
    SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p
), mapped AS (
    SELECT
      block_code,
      severity,
      CASE
        WHEN category IN ('Design Integrity','Asset Hierarchy') THEN 'Design Integrity'
        WHEN category='Asset Traceability' THEN 'Asset Traceability'
        WHEN category='Revision Integrity' THEN 'Documentation'
        WHEN category='Commissioning Tests' THEN 'Electrical Tests'
        WHEN category='Quality' THEN 'Quality / NCR'
        WHEN category IN ('Engineering - Strings','Engineering - Inverters') THEN 'Electrical Engineering'
        WHEN category='Engineering - Cables' THEN 'Cable Engineering'
        WHEN category='Materials' THEN 'Material Reconciliation'
        ELSE 'Other'
      END AS area_name
    FROM rule_findings
    WHERE project_id=@p AND run_id=(SELECT run_id FROM latest)
), agg AS (
    SELECT block_code,area_name,
           SUM(CASE WHEN severity='BLOCKER' THEN 1 ELSE 0 END) AS blockers,
           SUM(CASE WHEN severity='WARNING' THEN 1 ELSE 0 END) AS warnings
    FROM mapped
    GROUP BY block_code,area_name
)
SELECT
    b.block_code AS Block,
    a.area_name AS Area,
    MAX(0,100 - 22*COALESCE(g.blockers,0) - 8*COALESCE(g.warnings,0)) AS Score,
    CASE
      WHEN COALESCE(g.blockers,0)>0 THEN 'NOT READY'
      WHEN COALESCE(g.warnings,0)>0 THEN 'ATTENTION'
      ELSE 'READY'
    END AS Decision,
    COALESCE(g.blockers,0) AS Blockers,
    COALESCE(g.warnings,0) AS Warnings
FROM blocks b
CROSS JOIN areas a
LEFT JOIN agg g ON g.block_code=b.block_code AND g.area_name=a.area_name
WHERE b.project_id=@p
ORDER BY b.block_code,a.sort_order;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECAssetTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH RECURSIVE tree(asset_id,block_id,asset_type,asset_code,parent_asset_id,status,depth) AS (
    SELECT asset_id,block_id,asset_type,asset_code,parent_asset_id,status,0
    FROM assets
    WHERE project_id=@p AND parent_asset_id IS NULL
    UNION ALL
    SELECT c.asset_id,c.block_id,c.asset_type,c.asset_code,c.parent_asset_id,c.status,t.depth+1
    FROM assets c
    JOIN tree t ON c.parent_asset_id=t.asset_id
    WHERE c.project_id=@p
)
SELECT
    COALESCE(b.block_code,'UNASSIGNED') AS Block,
    t.asset_id AS AssetId,
    t.asset_code AS AssetCode,
    t.asset_type AS AssetType,
    COALESCE(p.asset_code,'') AS ParentAssetCode,
    t.status AS Status,
    t.depth AS Depth
FROM tree t
LEFT JOIN blocks b ON b.block_id=t.block_id
LEFT JOIN assets p ON p.asset_id=t.parent_asset_id
ORDER BY Block,t.depth,t.asset_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECAssetSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$AssetCode
    )
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH RECURSIVE chain(asset_id,asset_code,parent_asset_id,depth) AS (
    SELECT asset_id,asset_code,parent_asset_id,0
    FROM assets WHERE project_id=@p AND asset_code=@c
    UNION ALL
    SELECT parent.asset_id,parent.asset_code,parent.parent_asset_id,chain.depth+1
    FROM assets parent
    JOIN chain ON chain.parent_asset_id=parent.asset_id
    WHERE parent.project_id=@p
), latest AS (
    SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p
)
SELECT
    a.asset_id AS AssetId,
    a.asset_code AS AssetCode,
    a.asset_type AS AssetType,
    a.status AS InstallationStatus,
    COALESCE(b.block_code,'UNASSIGNED') AS Block,
    COALESCE(parent.asset_code,'') AS Parent,
    COALESCE(a.manufacturer,'') AS Manufacturer,
    COALESCE(a.model,'') AS Model,
    COALESCE(a.serial_number,'') AS SerialNumber,
    COALESCE(b.block_code,'UNASSIGNED') || ' > ' ||
      (SELECT GROUP_CONCAT(asset_code,' > ') FROM (SELECT asset_code FROM chain ORDER BY depth DESC)) AS Path,
    (SELECT COUNT(*) FROM assets child WHERE child.parent_asset_id=a.asset_id) AS Children,
    (SELECT COUNT(*) FROM rule_findings f WHERE f.project_id=@p AND f.run_id=(SELECT run_id FROM latest) AND f.asset_code=a.asset_code AND f.severity='BLOCKER') AS Blockers,
    (SELECT COUNT(*) FROM rule_findings f WHERE f.project_id=@p AND f.run_id=(SELECT run_id FROM latest) AND f.asset_code=a.asset_code AND f.severity='WARNING') AS Warnings,
    CASE
      WHEN (SELECT COUNT(*) FROM rule_findings f WHERE f.project_id=@p AND f.run_id=(SELECT run_id FROM latest) AND f.asset_code=a.asset_code AND f.severity='BLOCKER')>0 THEN 'NOT READY'
      WHEN (SELECT COUNT(*) FROM rule_findings f WHERE f.project_id=@p AND f.run_id=(SELECT run_id FROM latest) AND f.asset_code=a.asset_code AND f.severity='WARNING')>0 THEN 'ATTENTION'
      ELSE 'READY'
    END AS EngineeringState
FROM assets a
LEFT JOIN blocks b ON b.block_id=a.block_id
LEFT JOIN assets parent ON parent.asset_id=a.parent_asset_id
WHERE a.project_id=@p AND a.asset_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
}

function Get-ECAssetCurrentFindings {
    [CmdletBinding()]
    param([string]$DatabasePath,[int]$ProjectId,[string]$AssetCode)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT severity AS Severity,rule_id AS Rule,category AS Category,message AS Message
FROM rule_findings
WHERE project_id=@p
  AND run_id=(SELECT MAX(run_id) FROM validation_runs WHERE project_id=@p)
  AND COALESCE(asset_code,'')=@c
ORDER BY CASE severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,rule_id;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
}

function Get-ECDiagnosticsForAsset {
    [CmdletBinding()]
    param([string]$DatabasePath,[int]$ProjectId,[string]$AssetCode)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH latest AS (
    SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p
)
SELECT
    f.severity AS Severity,
    f.rule_id AS Rule,
    COALESCE(d.diagnosis,f.rule_name) AS Diagnosis,
    COALESCE(d.priority,f.severity) AS Priority,
    COALESCE(d.possible_cause,'Review the rule message, approved design documents, commissioning method statement, and physical installation.') AS PossibleCause,
    COALESCE(d.recommended_action,'Investigate the affected asset, document objective evidence, correct the condition, and perform the required retest.') AS RecommendedAction
FROM rule_findings f
JOIN assets a ON a.project_id=f.project_id AND a.asset_code=f.asset_code
LEFT JOIN diagnostic_knowledge d
  ON d.rule_id=f.rule_id
 AND (d.asset_type='ANY' OR UPPER(d.asset_type)=UPPER(a.asset_type))
WHERE f.project_id=@p
  AND f.run_id=(SELECT run_id FROM latest)
  AND f.asset_code=@c
ORDER BY CASE f.severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
         f.rule_id,COALESCE(d.cause_order,999);
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
}

function Get-ECAssetEngineeringMetrics {
    [CmdletBinding()]
    param([string]$DatabasePath,[int]$ProjectId,[string]$AssetCode)
    $asset = Get-ECAssetSummary -DatabasePath $DatabasePath -ProjectId $ProjectId -AssetCode $AssetCode
    if ($null -eq $asset) { return }
    $type = ([string]$asset.AssetType).ToUpperInvariant()

    if ($type -eq 'STRING') {
        $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT
  CAST(dr.requirement_value AS INTEGER) AS modules,
  se.module_voc_stc_v AS module_voc,
  se.voc_temp_coeff_pct_c AS temp_coeff,
  COALESCE(se.measurement_temp_c,25) AS temp_c,
  se.measured_voc_v AS measured_voc,
  se.measured_isc_a AS measured_isc,
  se.measured_ir_mohm AS measured_ir,
  se.polarity AS polarity,
  COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='STRING_VOC_TOLERANCE_PCT'),5) AS voc_tol,
  COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='MIN_STRING_IR_MOHM'),100) AS min_ir
FROM assets a
LEFT JOIN design_requirements dr ON dr.asset_id=a.asset_id AND dr.requirement_key='EXPECTED_MODULE_COUNT'
LEFT JOIN string_engineering se ON se.asset_id=a.asset_id
WHERE a.project_id=@p AND a.asset_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
        if ($null -ne $r -and $null -ne $r.module_voc) {
            $expected = [double]$r.modules * [double]$r.module_voc * (1.0 + ([double]$r.temp_coeff/100.0) * ([double]$r.temp_c-25.0))
            $dev = $null
            if ($expected -ne 0 -and $null -ne $r.measured_voc) { $dev = ([double]$r.measured_voc-$expected)/$expected*100.0 }
            $vocResult = if ($null -eq $r.measured_voc) {'NOT TESTED'} elseif ([Math]::Abs($dev) -le [double]$r.voc_tol) {'PASS'} else {'FAIL'}
            $irResult = if ($null -eq $r.measured_ir) {'NOT TESTED'} elseif ([double]$r.measured_ir -ge [double]$r.min_ir) {'PASS'} else {'FAIL'}
            $polResult = if ([string]::IsNullOrWhiteSpace([string]$r.polarity)) {'NOT TESTED'} elseif (([string]$r.polarity).ToUpperInvariant() -in @('PASS','POSITIVE','CORRECT','OK')) {'PASS'} else {'FAIL'}
            $measuredVocText = if($null -eq $r.measured_voc){''}else{('{0:N2} V' -f [double]$r.measured_voc)}
            $devText = if($null -eq $dev){''}else{('{0:N2} %' -f $dev)}
            $irText = if($null -eq $r.measured_ir){''}else{('{0:N2} MOhm' -f [double]$r.measured_ir)}
            $iscText = if($null -eq $r.measured_isc){''}else{('{0:N2} A' -f [double]$r.measured_isc)}
            [pscustomobject]@{Check='Module count';Value=[string]$r.modules;Acceptance='Design baseline';Result='REFERENCE'}
            [pscustomobject]@{Check='Expected Voc';Value=('{0:N2} V' -f $expected);Acceptance=('Temperature corrected at {0:N1} C' -f [double]$r.temp_c);Result='REFERENCE'}
            [pscustomobject]@{Check='Measured Voc';Value=$measuredVocText;Acceptance=('Deviation <= {0:N2} %' -f [double]$r.voc_tol);Result=$vocResult}
            [pscustomobject]@{Check='Voc deviation';Value=$devText;Acceptance=('+/- {0:N2} %' -f [double]$r.voc_tol);Result=$vocResult}
            [pscustomobject]@{Check='Insulation resistance';Value=$irText;Acceptance=('>= {0:N2} MOhm' -f [double]$r.min_ir);Result=$irResult}
            [pscustomobject]@{Check='Polarity';Value=[string]$r.polarity;Acceptance='PASS / correct polarity';Result=$polResult}
            [pscustomobject]@{Check='Measured Isc';Value=$iscText;Acceptance='Recorded measurement';Result='INFO'}
        }
    }
    elseif ($type -eq 'INVERTER') {
        $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT ie.max_dc_voltage_v,ie.mppt_min_voltage_v,ie.mppt_max_voltage_v,ie.max_strings_per_mppt
FROM assets a LEFT JOIN inverter_engineering ie ON ie.asset_id=a.asset_id
WHERE a.project_id=@p AND a.asset_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
        $maxDcText = if($null -eq $r.max_dc_voltage_v){''}else{"$($r.max_dc_voltage_v) V"}
        $mpptText = if($null -eq $r.mppt_min_voltage_v){''}else{"$($r.mppt_min_voltage_v)-$($r.mppt_max_voltage_v) V"}
        [pscustomobject]@{Check='Maximum DC voltage';Value=$maxDcText;Acceptance='Manufacturer / approved design';Result='REFERENCE'}
        [pscustomobject]@{Check='MPPT voltage window';Value=$mpptText;Acceptance='Manufacturer / approved design';Result='REFERENCE'}
        [pscustomobject]@{Check='Maximum strings per MPPT';Value=[string]$r.max_strings_per_mppt;Acceptance='Configured inverter limit';Result='REFERENCE'}
    }
    elseif ($type -eq 'MPPT') {
        $r = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COUNT(s.asset_id) AS string_count,ie.max_strings_per_mppt AS max_strings
FROM assets mppt
LEFT JOIN assets s ON s.parent_asset_id=mppt.asset_id AND UPPER(s.asset_type)='STRING'
LEFT JOIN assets inv ON inv.asset_id=mppt.parent_asset_id
LEFT JOIN inverter_engineering ie ON ie.asset_id=inv.asset_id
WHERE mppt.project_id=@p AND mppt.asset_code=@c
GROUP BY mppt.asset_id;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode}
        $result = if($null -eq $r.max_strings){'INFO'}elseif([int]$r.string_count -le [int]$r.max_strings){'PASS'}else{'FAIL'}
        $acceptance = if($null -eq $r.max_strings){'No configured limit'}else{"<= $($r.max_strings)"}
        [pscustomobject]@{Check='Assigned strings';Value=[string]$r.string_count;Acceptance=$acceptance;Result=$result}
    }
    elseif ($type -eq 'BESS_RACK') {
        $rows=@(Get-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Rack -eq $AssetCode})
        if($rows.Count -gt 0){
            $r=$rows[0]
            $socResult=if([double]$r.SocDeviationPct -le [double]$r.AllowedSocDevPct){'PASS'}else{'FAIL'}
            $vResult=if([double]$r.VoltageDeviationPct -le [double]$r.AllowedVoltageDevPct){'PASS'}else{'FAIL'}
            $cellResult=if([double]$r.CellSpreadmV -le [double]$r.AllowedCellSpreadmV){'PASS'}else{'FAIL'}
            $tempResult=if([double]$r.TempSpreadC -le [double]$r.AllowedTempSpreadC){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check='Rack SOC';Value=("{0:N2} %" -f [double]$r.SocPct);Acceptance=("Peer deviation <= {0:N2} %" -f [double]$r.AllowedSocDevPct);Result=$socResult}
            [pscustomobject]@{Check='SOC deviation';Value=("{0:N2} %" -f [double]$r.SocDeviationPct);Acceptance=("<= {0:N2} %" -f [double]$r.AllowedSocDevPct);Result=$socResult}
            [pscustomobject]@{Check='Rack voltage';Value=("{0:N2} V" -f [double]$r.RackVoltageV);Acceptance=("Peer deviation <= {0:N2} %" -f [double]$r.AllowedVoltageDevPct);Result=$vResult}
            [pscustomobject]@{Check='Voltage deviation';Value=("{0:N2} %" -f [double]$r.VoltageDeviationPct);Acceptance=("<= {0:N2} %" -f [double]$r.AllowedVoltageDevPct);Result=$vResult}
            [pscustomobject]@{Check='Cell voltage spread';Value=("{0:N1} mV" -f [double]$r.CellSpreadmV);Acceptance=("<= {0:N1} mV" -f [double]$r.AllowedCellSpreadmV);Result=$cellResult}
            [pscustomobject]@{Check='Temperature spread';Value=("{0:N2} C" -f [double]$r.TempSpreadC);Acceptance=("<= {0:N2} C" -f [double]$r.AllowedTempSpreadC);Result=$tempResult}
        }
    }
    elseif ($type -eq 'PCS') {
        $r=@(Get-ECBessPcsEngineering -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.PCS -eq $AssetCode})
        if($r.Count -gt 0){
            [pscustomobject]@{Check='Rated power';Value=("$($r[0].RatedPowerMW) MW");Acceptance='Approved PCS design';Result='REFERENCE'}
            [pscustomobject]@{Check='DC voltage';Value=("$($r[0].DcVoltageV) V");Acceptance='Commissioning record';Result='INFO'}
            [pscustomobject]@{Check='Approved firmware';Value=[string]$r[0].ApprovedFirmware;Acceptance='Controlled baseline';Result='REFERENCE'}
            [pscustomobject]@{Check='Installed firmware';Value=[string]$r[0].InstalledFirmware;Acceptance=[string]$r[0].ApprovedFirmware;Result=[string]$r[0].FirmwareStatus}
        }
        foreach($c in @(Get-ECBessCommissioningChecks -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            $checkResult=if(([string]$c.Result).ToUpperInvariant() -in @('PASS','PASSED','OK')){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check=("BESS Check: " + [string]$c.CheckType);Value=[string]$c.Result;Acceptance='PASS';Result=$checkResult}
        }
    }
    elseif ($type -in @('BESS_SYSTEM','HVAC','FIRE_SYSTEM','EMS_PPC')) {
        foreach($c in @(Get-ECBessCommissioningChecks -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            $checkResult=if(([string]$c.Result).ToUpperInvariant() -in @('PASS','PASSED','OK')){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check=("BESS Check: " + [string]$c.CheckType);Value=[string]$c.Result;Acceptance='PASS';Result=$checkResult}
        }
    }
    elseif ($type -in @('PROTECTION_RELAY','CT','VT')) {
        foreach($s in @(Get-ECGridSettings -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            $result=if([string]$s.EqualityStatus -eq 'PASS'){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check=('Grid setting: ' + [string]$s.Setting);Value=("$($s.Installed) $($s.Unit)");Acceptance=("Approved $($s.Approved) $($s.Unit) | $($s.ApprovedRevision)");Result=$result}
        }
    }
    elseif ($type -eq 'GRID_TRANSFORMER') {
        foreach($t in @(Get-ECGridTransformerTests -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Transformer -eq $AssetCode})){
            [pscustomobject]@{Check=('Transformer test: ' + [string]$t.TestType);Value=("$($t.MeasuredValue) $($t.Unit)");Acceptance='Configured project criterion';Result='CALCULATED'}
        }
    }
    elseif ($type -eq 'PPC') {
        foreach($r in @(Get-ECGridResponseTests -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            [pscustomobject]@{Check=('Grid response: ' + [string]$r.ResponseType);Value=("$($r.Measured) $($r.Unit) | error $($r.ErrorPct)%");Acceptance=("Expected $($r.Commanded) $($r.Unit)");Result='CALCULATED'}
        }
        foreach($c in @(Get-ECGridCommissioningChecks -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            $res=if(([string]$c.Result).ToUpperInvariant() -in @('PASS','PASSED','OK')){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check=('Grid check: ' + [string]$c.CheckType);Value=[string]$c.Result;Acceptance='PASS';Result=$res}
        }
    }
    elseif ($type -in @('POI','MV_BREAKER','GRID_SYSTEM','MV_SWITCHGEAR','REVENUE_METER')) {
        foreach($c in @(Get-ECGridCommissioningChecks -DatabasePath $DatabasePath -ProjectId $ProjectId | Where-Object {$_.Asset -eq $AssetCode})){
            $res=if(([string]$c.Result).ToUpperInvariant() -in @('PASS','PASSED','OK')){'PASS'}else{'FAIL'}
            [pscustomobject]@{Check=('Grid check: ' + [string]$c.CheckType);Value=[string]$c.Result;Acceptance='PASS';Result=$res}
        }
    }
    else {
        [pscustomobject]@{Check='Installation status';Value=[string]$asset.InstallationStatus;Acceptance='Project record';Result='INFO'}
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.Manufacturer)) {[pscustomobject]@{Check='Manufacturer';Value=[string]$asset.Manufacturer;Acceptance='Asset register';Result='INFO'}}
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.Model)) {[pscustomobject]@{Check='Model';Value=[string]$asset.Model;Acceptance='Asset register';Result='INFO'}}
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.SerialNumber)) {[pscustomobject]@{Check='Serial number';Value=[string]$asset.SerialNumber;Acceptance='Traceability record';Result='INFO'}}
    }

    foreach ($t in @(Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT test_type,test_date,result,value,unit FROM test_results
WHERE project_id=@p AND asset_id=(SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c)
ORDER BY test_date DESC LIMIT 10;
'@ -SqlParameters @{p=$ProjectId;c=$AssetCode})) {
        $val = if($null -eq $t.value){[string]$t.test_date}else{"$($t.value) $($t.unit) | $($t.test_date)"}
        [pscustomobject]@{Check=("Test: " + [string]$t.test_type);Value=$val;Acceptance='Commissioning record';Result=[string]$t.result}
    }
}

function Sync-ECFindingCases {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $current = @(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $keys = @{}
    foreach ($f in $current) {
        $block=[string]$f.Block; $asset=[string]$f.Asset
        $key=("$($f.Rule)|$block|$asset").ToUpperInvariant(); $keys[$key]=$true
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT case_id,status FROM finding_cases
WHERE project_id=@p AND rule_id=@r AND block_code=@b AND asset_code=@a;
'@ -SqlParameters @{p=$ProjectId;r=[string]$f.Rule;b=$block;a=$asset}
        if ($null -eq $existing) {
            Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO finding_cases(project_id,rule_id,block_code,asset_code,severity,category,title,message,status,first_detected_at,last_detected_at)
VALUES(@p,@r,@b,@a,@s,@cat,@title,@msg,'OPEN',datetime('now'),datetime('now'));
'@ -SqlParameters @{p=$ProjectId;r=[string]$f.Rule;b=$block;a=$asset;s=[string]$f.Severity;cat=[string]$f.Category;title=[string]$f.Rule;msg=[string]$f.Message}|Out-Null
            $caseId=[int](Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT MAX(case_id) AS id FROM finding_cases WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}).id
            Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO finding_case_history(case_id,status,note) VALUES(@c,'OPEN','Finding detected by validation engine.');" -SqlParameters @{c=$caseId}|Out-Null
        }
        else {
            $caseId=[int]$existing.case_id; $oldStatus=[string]$existing.status
            $newStatus=if($oldStatus -eq 'CLOSED'){'REOPENED'}else{$oldStatus}
            Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE finding_cases
SET severity=@s,category=@cat,message=@msg,last_detected_at=datetime('now'),status=@status,closed_at=NULL
WHERE case_id=@c;
'@ -SqlParameters @{s=[string]$f.Severity;cat=[string]$f.Category;msg=[string]$f.Message;status=$newStatus;c=$caseId}|Out-Null
            if($oldStatus -eq 'CLOSED'){
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO finding_case_history(case_id,status,note) VALUES(@c,'REOPENED','Finding reappeared in validation.');" -SqlParameters @{c=$caseId}|Out-Null
            }
        }
    }

    foreach ($c in @(Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT case_id,rule_id,block_code,asset_code,status FROM finding_cases WHERE project_id=@p;
'@ -SqlParameters @{p=$ProjectId})) {
        $key=("$($c.rule_id)|$($c.block_code)|$($c.asset_code)").ToUpperInvariant()
        if (-not $keys.ContainsKey($key) -and [string]$c.status -notin @('CLOSED')) {
            Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE finding_cases SET status='CLOSED',closed_at=datetime('now'),retest_result=COALESCE(NULLIF(retest_result,''),'PASS') WHERE case_id=@c;
'@ -SqlParameters @{c=[int]$c.case_id}|Out-Null
            Invoke-SqliteQuery -DataSource $DatabasePath -Query "INSERT INTO finding_case_history(case_id,status,note) VALUES(@c,'CLOSED','Validation no longer detects this finding.');" -SqlParameters @{c=[int]$c.case_id}|Out-Null
        }
    }
}

function Get-ECFindingCases {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[switch]$OpenOnly)
    Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId $ProjectId
    $where = if($OpenOnly){"AND status<>'CLOSED'"}else{''}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query ("SELECT case_id AS CaseId,severity AS Severity,rule_id AS Rule,category AS Category,block_code AS Block,asset_code AS Asset,status AS Status,COALESCE(assigned_to,'') AS AssignedTo,first_detected_at AS FirstDetected,last_detected_at AS LastDetected,COALESCE(root_cause,'') AS RootCause,COALESCE(corrective_action,'') AS CorrectiveAction,COALESCE(retest_result,'') AS RetestResult FROM finding_cases WHERE project_id=@p " + $where + " ORDER BY CASE status WHEN 'OPEN' THEN 1 WHEN 'REOPENED' THEN 2 WHEN 'UNDER INVESTIGATION' THEN 3 WHEN 'CORRECTIVE ACTION' THEN 4 WHEN 'READY FOR RETEST' THEN 5 WHEN 'ACKNOWLEDGED' THEN 6 ELSE 7 END,last_detected_at DESC;") -SqlParameters @{p=$ProjectId}
}

function Update-ECFindingCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$CaseId,
        [ValidateSet('OPEN','ACKNOWLEDGED','UNDER INVESTIGATION','CORRECTIVE ACTION','READY FOR RETEST','CLOSED','REOPENED')][string]$Status='OPEN',
        [string]$AssignedTo,
        [string]$RootCause,
        [string]$CorrectiveAction,
        [string]$RetestResult
    )
    $old=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT status FROM finding_cases WHERE case_id=@c;' -SqlParameters @{c=$CaseId}
    if($null -eq $old){throw "Finding case $CaseId does not exist."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE finding_cases SET status=@s,assigned_to=@assigned,root_cause=@root,corrective_action=@action,retest_result=@retest,
closed_at=CASE WHEN @s='CLOSED' THEN COALESCE(closed_at,datetime('now')) ELSE NULL END
WHERE case_id=@c;
'@ -SqlParameters @{s=$Status;assigned=$AssignedTo;root=$RootCause;action=$CorrectiveAction;retest=$RetestResult;c=$CaseId}|Out-Null
    $note="Workflow update. AssignedTo=$AssignedTo; Retest=$RetestResult"
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT INTO finding_case_history(case_id,status,note) VALUES(@c,@s,@n);' -SqlParameters @{c=$CaseId;s=$Status;n=$note}|Out-Null
}

function Get-ECFindingCaseHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$CaseId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT history_id AS HistoryId,status AS Status,COALESCE(note,'') AS Note,changed_at AS ChangedAt
FROM finding_case_history WHERE case_id=@c ORDER BY history_id DESC;
'@ -SqlParameters @{c=$CaseId}
}



# -----------------------------------------------------------------------------
# EnergizeCheck v0.5 - BESS Commissioning Intelligence
# -----------------------------------------------------------------------------

function Initialize-ECV05Schema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $sqlFile = Join-Path $PSScriptRoot '..\database\schema-v05.sql'
    if (-not (Test-Path -LiteralPath $sqlFile)) { throw "v0.5 schema file not found: $sqlFile" }
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $sqlFile
}

function Set-ECBessRackEngineering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$RackCode,
        [Nullable[double]]$SocPct,
        [Nullable[double]]$RackVoltageV,
        [Nullable[double]]$MinCellVoltageV,
        [Nullable[double]]$MaxCellVoltageV,
        [Nullable[double]]$MinTempC,
        [Nullable[double]]$MaxTempC
    )
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT asset_id,asset_type FROM assets WHERE project_id=@p AND asset_code=@c;" -SqlParameters @{p=$ProjectId;c=$RackCode}
    if($null -eq $asset){throw "BESS rack '$RackCode' does not exist."}
    if(([string]$asset.asset_type).ToUpperInvariant() -ne 'BESS_RACK'){throw "Asset '$RackCode' is not a BESS_RACK."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO bess_rack_engineering(asset_id,soc_pct,rack_voltage_v,min_cell_voltage_v,max_cell_voltage_v,min_temp_c,max_temp_c,updated_at)
VALUES(@a,@soc,@v,@mincell,@maxcell,@mint,@maxt,datetime('now'));
'@ -SqlParameters @{a=[int]$asset.asset_id;soc=$SocPct;v=$RackVoltageV;mincell=$MinCellVoltageV;maxcell=$MaxCellVoltageV;mint=$MinTempC;maxt=$MaxTempC}|Out-Null
}

function Get-ECBessRackEngineering {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH cfg AS (
 SELECT
   COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='BESS_MAX_RACK_SOC_DEVIATION_PCT'),3.0) AS soc_lim,
   COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='BESS_MAX_RACK_VOLTAGE_DEVIATION_PCT'),2.0) AS v_lim,
   COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='BESS_MAX_CELL_VOLTAGE_SPREAD_MV'),50.0) AS cell_lim,
   COALESCE((SELECT parameter_value FROM engineering_parameters WHERE project_id=@p AND parameter_key='BESS_MAX_RACK_TEMP_SPREAD_C'),8.0) AS temp_lim
), av AS (
 SELECT a.parent_asset_id,AVG(br.soc_pct) AS avg_soc,AVG(br.rack_voltage_v) AS avg_v
 FROM assets a JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
 WHERE a.project_id=@p AND UPPER(a.asset_type)='BESS_RACK'
 GROUP BY a.parent_asset_id
)
SELECT
 COALESCE(b.block_code,'') AS Block,
 COALESCE(parent.asset_code,'') AS Container,
 a.asset_code AS Rack,
 ROUND(br.soc_pct,2) AS SocPct,
 ROUND(av.avg_soc,2) AS PeerAvgSoc,
 ROUND(ABS(br.soc_pct-av.avg_soc),2) AS SocDeviationPct,
 ROUND(br.rack_voltage_v,2) AS RackVoltageV,
 ROUND(av.avg_v,2) AS PeerAvgVoltageV,
 ROUND(ABS(br.rack_voltage_v-av.avg_v)/NULLIF(av.avg_v,0)*100.0,2) AS VoltageDeviationPct,
 ROUND((br.max_cell_voltage_v-br.min_cell_voltage_v)*1000.0,1) AS CellSpreadmV,
 ROUND(br.max_temp_c-br.min_temp_c,2) AS TempSpreadC,
 cfg.soc_lim AS AllowedSocDevPct,
 cfg.v_lim AS AllowedVoltageDevPct,
 cfg.cell_lim AS AllowedCellSpreadmV,
 cfg.temp_lim AS AllowedTempSpreadC
FROM assets a
JOIN bess_rack_engineering br ON br.asset_id=a.asset_id
LEFT JOIN assets parent ON parent.asset_id=a.parent_asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
LEFT JOIN av ON av.parent_asset_id=a.parent_asset_id
CROSS JOIN cfg
WHERE a.project_id=@p AND UPPER(a.asset_type)='BESS_RACK'
ORDER BY b.block_code,a.asset_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECBessPcsEngineering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$PcsCode,
        [Nullable[double]]$RatedPowerMW,
        [Nullable[double]]$DcVoltageV,
        [string]$ApprovedFirmware,
        [string]$InstalledFirmware
    )
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT asset_id,asset_type FROM assets WHERE project_id=@p AND asset_code=@c;" -SqlParameters @{p=$ProjectId;c=$PcsCode}
    if($null -eq $asset){throw "PCS '$PcsCode' does not exist."}
    if(([string]$asset.asset_type).ToUpperInvariant() -ne 'PCS'){throw "Asset '$PcsCode' is not a PCS."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO bess_pcs_engineering(asset_id,rated_power_mw,dc_voltage_v,approved_firmware,installed_firmware,updated_at)
VALUES(@a,@mw,@dc,@approved,@installed,datetime('now'));
'@ -SqlParameters @{a=[int]$asset.asset_id;mw=$RatedPowerMW;dc=$DcVoltageV;approved=$ApprovedFirmware;installed=$InstalledFirmware}|Out-Null
}

function Get-ECBessPcsEngineering {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,pcs.asset_code AS PCS,
       pe.rated_power_mw AS RatedPowerMW,pe.dc_voltage_v AS DcVoltageV,
       COALESCE(pe.approved_firmware,'') AS ApprovedFirmware,
       COALESCE(pe.installed_firmware,'') AS InstalledFirmware,
       CASE WHEN COALESCE(TRIM(pe.approved_firmware),'')=COALESCE(TRIM(pe.installed_firmware),'') THEN 'PASS' ELSE 'FAIL' END AS FirmwareStatus
FROM bess_pcs_engineering pe
JOIN assets pcs ON pcs.asset_id=pe.asset_id
LEFT JOIN blocks b ON b.block_id=pcs.block_id
WHERE pcs.project_id=@p
ORDER BY b.block_code,pcs.asset_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECBessCommissioningCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$AssetCode,
        [Parameter(Mandatory)][string]$CheckType,
        [Parameter(Mandatory)][string]$Result,
        [string]$TestedAt,
        [string]$Details
    )
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;" -SqlParameters @{p=$ProjectId;c=$AssetCode}
    if($null -eq $asset){throw "BESS asset '$AssetCode' does not exist."}
    if([string]::IsNullOrWhiteSpace($TestedAt)){$TestedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO bess_commissioning_checks(project_id,asset_id,check_type,result,tested_at,details,updated_at)
VALUES(@p,@a,@type,@result,@tested,@details,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;a=[int]$asset.asset_id;type=$CheckType.Trim().ToUpperInvariant();result=$Result.Trim().ToUpperInvariant();tested=$TestedAt;details=$Details}|Out-Null
}

function Get-ECBessCommissioningChecks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,a.asset_code AS Asset,a.asset_type AS AssetType,
       c.check_type AS CheckType,c.result AS Result,COALESCE(c.tested_at,'') AS TestedAt,COALESCE(c.details,'') AS Details
FROM bess_commissioning_checks c
JOIN assets a ON a.asset_id=c.asset_id
LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE c.project_id=@p
ORDER BY b.block_code,a.asset_code,c.check_type;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECBessParameters {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT parameter_key AS Parameter,parameter_value AS Value,COALESCE(unit,'') AS Unit,COALESCE(description,'') AS Description
FROM engineering_parameters
WHERE project_id=@p AND parameter_key LIKE 'BESS_%'
ORDER BY parameter_key;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECBessOverview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH latest AS (SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p),
bess_blocks AS (
  SELECT DISTINCT b.block_id,b.block_code
  FROM blocks b JOIN assets a ON a.block_id=b.block_id
  WHERE b.project_id=@p AND UPPER(a.asset_type) IN ('BESS_SYSTEM','BESS_CONTAINER','BESS_RACK','PCS','BMS','HVAC','FIRE_SYSTEM','EMS_PPC','BESS_TRANSFORMER')
)
SELECT bb.block_code AS BessBlock,
       p.bess_capacity_mwh AS RatedEnergyMWh,
       (SELECT COUNT(*) FROM assets a WHERE a.project_id=@p AND a.block_id=bb.block_id AND UPPER(a.asset_type)='BESS_RACK') AS Racks,
       ROUND((SELECT AVG(br.soc_pct) FROM bess_rack_engineering br JOIN assets a ON a.asset_id=br.asset_id WHERE a.project_id=@p AND a.block_id=bb.block_id),2) AS AverageSocPct,
       ROUND((SELECT MIN(br.soc_pct) FROM bess_rack_engineering br JOIN assets a ON a.asset_id=br.asset_id WHERE a.project_id=@p AND a.block_id=bb.block_id),2) AS MinSocPct,
       ROUND((SELECT MAX(br.soc_pct) FROM bess_rack_engineering br JOIN assets a ON a.asset_id=br.asset_id WHERE a.project_id=@p AND a.block_id=bb.block_id),2) AS MaxSocPct,
       COALESCE((SELECT readiness_score FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=bb.block_id),100) AS ReadinessPct,
       COALESCE((SELECT blocker_count FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=bb.block_id),0) AS Blockers,
       COALESCE((SELECT warning_count FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=bb.block_id),0) AS Warnings
FROM bess_blocks bb CROSS JOIN projects p
WHERE p.project_id=@p
ORDER BY bb.block_code;
'@ -SqlParameters @{p=$ProjectId}
}



# -----------------------------------------------------------------------------
# EnergizeCheck v0.6 - Grid Connection & Protection Intelligence
# -----------------------------------------------------------------------------

function Initialize-ECV06Schema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $sqlFile = Join-Path $PSScriptRoot '..\database\schema-v06.sql'
    if (-not (Test-Path -LiteralPath $sqlFile)) { throw "v0.6 schema file not found: $sqlFile" }
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $sqlFile
}

function Set-ECGridSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$AssetCode,[Parameter(Mandatory)][string]$SettingKey,[double]$ApprovedValue,[double]$InstalledValue,[string]$Unit,[string]$ApprovedRevision='GRID-REV-A')
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode}
    if($null -eq $asset){throw "Grid asset '$AssetCode' does not exist."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO grid_setting_checks(project_id,asset_id,setting_key,approved_value,installed_value,unit,approved_revision,updated_at)
VALUES(@p,@a,@k,@approved,@installed,@unit,@rev,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;a=[int]$asset.asset_id;k=$SettingKey.Trim().ToUpperInvariant();approved=$ApprovedValue;installed=$InstalledValue;unit=$Unit;rev=$ApprovedRevision}|Out-Null
}

function Get-ECGridSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,a.asset_code AS Asset,a.asset_type AS AssetType,s.setting_key AS Setting,ROUND(s.approved_value,3) AS Approved,ROUND(s.installed_value,3) AS Installed,COALESCE(s.unit,'') AS Unit,COALESCE(s.approved_revision,'') AS ApprovedRevision,CASE WHEN ABS(COALESCE(s.approved_value,0)-COALESCE(s.installed_value,0))<0.0001 THEN 'PASS' ELSE 'CHECK' END AS EqualityStatus
FROM grid_setting_checks s JOIN assets a ON a.asset_id=s.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id WHERE s.project_id=@p ORDER BY b.block_code,a.asset_code,s.setting_key;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECGridTransformerTest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$AssetCode,[Parameter(Mandatory)][string]$TestType,[double]$MeasuredValue,[string]$Unit,[string]$TestedAt,[string]$Details)
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode}
    if($null -eq $asset){throw "Grid transformer asset '$AssetCode' does not exist."}
    if([string]::IsNullOrWhiteSpace($TestedAt)){$TestedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO grid_transformer_tests(project_id,asset_id,test_type,measured_value,unit,tested_at,details,updated_at)
VALUES(@p,@a,@t,@v,@u,@tested,@details,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;a=[int]$asset.asset_id;t=$TestType.Trim().ToUpperInvariant();v=$MeasuredValue;u=$Unit;tested=$TestedAt;details=$Details}|Out-Null
}

function Get-ECGridTransformerTests {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,a.asset_code AS Transformer,t.test_type AS TestType,ROUND(t.measured_value,3) AS MeasuredValue,COALESCE(t.unit,'') AS Unit,COALESCE(t.tested_at,'') AS TestedAt,COALESCE(t.details,'') AS Details
FROM grid_transformer_tests t JOIN assets a ON a.asset_id=t.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id WHERE t.project_id=@p ORDER BY b.block_code,a.asset_code,t.test_type;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECGridResponseTest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$AssetCode,[Parameter(Mandatory)][string]$ResponseType,[double]$CommandedValue,[double]$MeasuredValue,[string]$Unit,[string]$TestedAt,[string]$Details)
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode}
    if($null -eq $asset){throw "Grid response asset '$AssetCode' does not exist."}
    if([string]::IsNullOrWhiteSpace($TestedAt)){$TestedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO grid_response_tests(project_id,asset_id,response_type,commanded_value,measured_value,unit,tested_at,details,updated_at)
VALUES(@p,@a,@t,@cmd,@meas,@u,@tested,@details,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;a=[int]$asset.asset_id;t=$ResponseType.Trim().ToUpperInvariant();cmd=$CommandedValue;meas=$MeasuredValue;u=$Unit;tested=$TestedAt;details=$Details}|Out-Null
}

function Get-ECGridResponseTests {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,a.asset_code AS Asset,r.response_type AS ResponseType,ROUND(r.commanded_value,3) AS Commanded,ROUND(r.measured_value,3) AS Measured,COALESCE(r.unit,'') AS Unit,ROUND(ABS(r.measured_value-r.commanded_value)/NULLIF(ABS(r.commanded_value),0)*100.0,2) AS ErrorPct,COALESCE(r.tested_at,'') AS TestedAt,COALESCE(r.details,'') AS Details
FROM grid_response_tests r JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id WHERE r.project_id=@p ORDER BY b.block_code,a.asset_code,r.response_type;
'@ -SqlParameters @{p=$ProjectId}
}

function Set-ECGridCommissioningCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$AssetCode,[Parameter(Mandatory)][string]$CheckType,[Parameter(Mandatory)][string]$Result,[string]$TestedAt,[string]$Details)
    $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode}
    if($null -eq $asset){throw "Grid commissioning asset '$AssetCode' does not exist."}
    if([string]::IsNullOrWhiteSpace($TestedAt)){$TestedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO grid_commissioning_checks(project_id,asset_id,check_type,result,tested_at,details,updated_at)
VALUES(@p,@a,@t,@r,@tested,@details,datetime('now'));
'@ -SqlParameters @{p=$ProjectId;a=[int]$asset.asset_id;t=$CheckType.Trim().ToUpperInvariant();r=$Result.Trim().ToUpperInvariant();tested=$TestedAt;details=$Details}|Out-Null
}

function Get-ECGridCommissioningChecks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT COALESCE(b.block_code,'') AS Block,a.asset_code AS Asset,a.asset_type AS AssetType,c.check_type AS CheckType,c.result AS Result,COALESCE(c.tested_at,'') AS TestedAt,COALESCE(c.details,'') AS Details
FROM grid_commissioning_checks c JOIN assets a ON a.asset_id=c.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id WHERE c.project_id=@p ORDER BY b.block_code,a.asset_code,c.check_type;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECGridParameters {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT parameter_key AS Parameter,parameter_value AS Value,COALESCE(unit,'') AS Unit,COALESCE(description,'') AS Description FROM engineering_parameters WHERE project_id=@p AND parameter_key LIKE 'GRID_%' ORDER BY parameter_key;" -SqlParameters @{p=$ProjectId}
}

function Get-ECGridOverview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
WITH latest AS (SELECT MAX(run_id) AS run_id FROM validation_runs WHERE project_id=@p),gb AS (
 SELECT DISTINCT b.block_id,b.block_code FROM blocks b JOIN assets a ON a.block_id=b.block_id
 WHERE b.project_id=@p AND UPPER(a.asset_type) IN ('GRID_SYSTEM','POI','MV_SWITCHGEAR','MV_BREAKER','CT','VT','PROTECTION_RELAY','GRID_TRANSFORMER','PPC','REVENUE_METER')
)
SELECT gb.block_code AS GridBlock,(SELECT COUNT(*) FROM assets a WHERE a.project_id=@p AND a.block_id=gb.block_id) AS Assets,
 COALESCE((SELECT readiness_score FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=gb.block_id),100) AS ReadinessPct,
 COALESCE((SELECT blocker_count FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=gb.block_id),0) AS Blockers,
 COALESCE((SELECT warning_count FROM readiness_results rr WHERE rr.project_id=@p AND rr.block_id=gb.block_id),0) AS Warnings,
 (SELECT COUNT(*) FROM rule_findings rf,latest WHERE rf.project_id=@p AND rf.run_id=latest.run_id AND rf.rule_id LIKE 'GRID-%' AND rf.block_code=gb.block_code) AS GridFindings
FROM gb ORDER BY gb.block_code;
'@ -SqlParameters @{p=$ProjectId}
}



# -----------------------------------------------------------------------------
# EnergizeCheck v0.7 - Commissioning Dossier & Document Intelligence
# -----------------------------------------------------------------------------

function Initialize-ECV07Schema {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath)
    $sqlFile=Join-Path $PSScriptRoot '..\database\schema-v07.sql'
    if(-not(Test-Path -LiteralPath $sqlFile)){throw "v0.7 schema file not found: $sqlFile"}
    Invoke-ECSqlFile -DatabasePath $DatabasePath -SqlFile $sqlFile
}

function Set-ECDossierSection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$SectionCode,[Parameter(Mandatory)][string]$Title,[int]$SortOrder=100,[bool]$Mandatory=$true)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO dossier_sections(project_id,section_code,title,sort_order,mandatory)
VALUES(@p,@c,@t,@s,@m);
'@ -SqlParameters @{p=$ProjectId;c=$SectionCode.Trim();t=$Title;s=$SortOrder;m=if($Mandatory){1}else{0}}|Out-Null
}

function Set-ECDocumentRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$RequirementCode,[Parameter(Mandatory)][string]$SectionCode,
        [Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][string]$DocumentType,
        [string]$AssetCode,[bool]$Mandatory=$true,[bool]$CurrentRevisionRequired=$false,
        [bool]$ApprovalRequired=$false,[bool]$IntegrityHashRequired=$false,[bool]$EnergizationCritical=$false,
        [string]$ExpectedRevision,[string]$Notes
    )
    $section=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT section_id FROM dossier_sections WHERE project_id=@p AND section_code=@c;' -SqlParameters @{p=$ProjectId;c=$SectionCode}
    if($null -eq $section){throw "Dossier section '$SectionCode' does not exist."}
    $assetId=$null
    if(-not [string]::IsNullOrWhiteSpace($AssetCode)){
        $asset=Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT asset_id FROM assets WHERE project_id=@p AND asset_code=@c;' -SqlParameters @{p=$ProjectId;c=$AssetCode}
        if($null -eq $asset){throw "Asset '$AssetCode' does not exist."}
        $assetId=[int]$asset.asset_id
    }
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT OR REPLACE INTO document_requirements(project_id,requirement_code,section_id,asset_id,title,document_type,mandatory,current_revision_required,approval_required,integrity_hash_required,energization_critical,expected_revision,notes)
VALUES(@p,@code,@section,@asset,@title,@type,@mandatory,@current,@approval,@hash,@critical,@expected,@notes);
'@ -SqlParameters @{p=$ProjectId;code=$RequirementCode;section=[int]$section.section_id;asset=$assetId;title=$Title;type=$DocumentType;mandatory=if($Mandatory){1}else{0};current=if($CurrentRevisionRequired){1}else{0};approval=if($ApprovalRequired){1}else{0};hash=if($IntegrityHashRequired){1}else{0};critical=if($EnergizationCritical){1}else{0};expected=$ExpectedRevision;notes=$Notes}|Out-Null
}

function Set-ECDocumentEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,
        [Parameter(Mandatory)][string]$RequirementCode,[Parameter(Mandatory)][string]$DocumentCode,
        [string]$FilePath,[string]$Revision='01',[bool]$IsCurrent=$true,[string]$ReferencesDocumentCode,
        [string]$ReferencesRevision,[string]$ReceivedAt,[switch]$SkipHash
    )

    $req = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT requirement_id, asset_id
FROM document_requirements
WHERE project_id=@p AND requirement_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$RequirementCode}

    if($null -eq $req){
        throw "Document requirement '$RequirementCode' does not exist."
    }

    $exists = 0
    $fileName = ''
    $hash = ''

    if(-not [string]::IsNullOrWhiteSpace($FilePath)){
        $fileName = [IO.Path]::GetFileName($FilePath)
        if(Test-Path -LiteralPath $FilePath){
            $exists = 1
            if(-not $SkipHash){
                $hash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
            }
        }
    }

    if([string]::IsNullOrWhiteSpace($ReceivedAt)){
        $ReceivedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }

    $currentValue = if($IsCurrent){1}else{0}
    $requirementId = [int]$req.requirement_id
    $assetId = $req.asset_id

    # PSSQLite 1.1.0 can bundle an SQLite engine older than 3.24.
    # Avoid modern INSERT ... ON CONFLICT DO UPDATE syntax and use
    # explicit SELECT + INSERT/UPDATE for Windows PowerShell 5.1 compatibility.
    $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT evidence_id
FROM document_evidence
WHERE requirement_id=@r;
'@ -SqlParameters @{r=$requirementId}

    if($null -eq $existing){
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO document_evidence
(
    project_id,requirement_id,asset_id,document_code,file_name,file_path,
    revision,is_current,file_exists,sha256,references_document_code,
    references_revision,received_at,updated_at
)
VALUES
(
    @p,@req,@asset,@doc,@name,@path,
    @rev,@current,@exists,@hash,@refdoc,
    @refrev,@received,datetime('now')
);
'@ -SqlParameters @{
            p=$ProjectId
            req=$requirementId
            asset=$assetId
            doc=$DocumentCode
            name=$fileName
            path=$FilePath
            rev=$Revision
            current=$currentValue
            exists=$exists
            hash=$hash
            refdoc=$ReferencesDocumentCode
            refrev=$ReferencesRevision
            received=$ReceivedAt
        } | Out-Null
    }
    else {
        $evidenceId = [int]$existing.evidence_id
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE document_evidence
SET
    asset_id=@asset,
    document_code=@doc,
    file_name=@name,
    file_path=@path,
    revision=@rev,
    is_current=@current,
    file_exists=@exists,
    sha256=@hash,
    references_document_code=@refdoc,
    references_revision=@refrev,
    received_at=@received,
    updated_at=datetime('now')
WHERE evidence_id=@e;
'@ -SqlParameters @{
            e=$evidenceId
            asset=$assetId
            doc=$DocumentCode
            name=$fileName
            path=$FilePath
            rev=$Revision
            current=$currentValue
            exists=$exists
            hash=$hash
            refdoc=$ReferencesDocumentCode
            refrev=$ReferencesRevision
            received=$ReceivedAt
        } | Out-Null
    }

    $ev = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT evidence_id
FROM document_evidence
WHERE requirement_id=@r;
'@ -SqlParameters @{r=$requirementId}

    if($null -eq $ev){
        throw "Evidence insert/update failed for '$RequirementCode'."
    }

    $evidenceId = [int]$ev.evidence_id

    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE document_versions
SET is_current=0
WHERE evidence_id=@e;
'@ -SqlParameters @{e=$evidenceId} | Out-Null

    $existingVersion = Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT version_id
FROM document_versions
WHERE evidence_id=@e AND revision=@rev;
'@ -SqlParameters @{e=$evidenceId;rev=$Revision}

    if($null -eq $existingVersion){
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
INSERT INTO document_versions
(
    evidence_id,revision,file_name,file_path,sha256,is_current,created_at
)
VALUES
(
    @e,@rev,@name,@path,@hash,@current,datetime('now')
);
'@ -SqlParameters @{
            e=$evidenceId
            rev=$Revision
            name=$fileName
            path=$FilePath
            hash=$hash
            current=$currentValue
        } | Out-Null
    }
    else {
        Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
UPDATE document_versions
SET
    file_name=@name,
    file_path=@path,
    sha256=@hash,
    is_current=@current
WHERE version_id=@v;
'@ -SqlParameters @{
            v=[int]$existingVersion.version_id
            name=$fileName
            path=$FilePath
            hash=$hash
            current=$currentValue
        } | Out-Null
    }

    return $evidenceId
}

function Set-ECDocumentReview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$RequirementCode,[Parameter(Mandatory)][ValidateSet('ACCEPTED','REJECTED','PENDING')][string]$Status,[string]$Reviewer,[string]$Comment)
    $ev=Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT e.evidence_id FROM document_evidence e JOIN document_requirements r ON r.requirement_id=e.requirement_id WHERE r.project_id=@p AND r.requirement_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$RequirementCode}
    if($null -eq $ev){throw "Evidence for '$RequirementCode' does not exist."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT INTO document_reviews(evidence_id,reviewer,status,comment,reviewed_at) VALUES(@e,@r,@s,@c,datetime(''now''));' -SqlParameters @{e=[int]$ev.evidence_id;r=$Reviewer;s=$Status;c=$Comment}|Out-Null
}

function Set-ECDocumentApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId,[Parameter(Mandatory)][string]$RequirementCode,[Parameter(Mandatory)][ValidateSet('APPROVED','REJECTED','PENDING','CONDITIONAL')][string]$Status,[string]$Approver,[string]$Comment)
    $ev=Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT e.evidence_id FROM document_evidence e JOIN document_requirements r ON r.requirement_id=e.requirement_id WHERE r.project_id=@p AND r.requirement_code=@c;
'@ -SqlParameters @{p=$ProjectId;c=$RequirementCode}
    if($null -eq $ev){throw "Evidence for '$RequirementCode' does not exist."}
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT INTO document_approvals(evidence_id,approver,status,comment,approved_at) VALUES(@e,@a,@s,@c,datetime(''now''));' -SqlParameters @{e=[int]$ev.evidence_id;a=$Approver;s=$Status;c=$Comment}|Out-Null
}

function Get-ECDocumentMatrix {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT s.section_code AS Section,r.requirement_code AS Requirement,COALESCE(b.block_code,'PROJECT') AS Block,COALESCE(a.asset_code,'') AS Asset,r.title AS RequirementTitle,r.document_type AS DocumentType,
       CASE r.mandatory WHEN 1 THEN 'YES' ELSE 'NO' END AS Mandatory,COALESCE(e.document_code,'') AS Evidence,COALESCE(e.file_name,'') AS FileName,COALESCE(e.revision,'') AS Revision,COALESCE(r.expected_revision,'') AS ExpectedRevision,
       COALESCE((SELECT dr.status FROM document_reviews dr WHERE dr.evidence_id=e.evidence_id ORDER BY dr.review_id DESC LIMIT 1),'') AS Review,
       COALESCE((SELECT da.status FROM document_approvals da WHERE da.evidence_id=e.evidence_id ORDER BY da.approval_id DESC LIMIT 1),'') AS Approval,
       CASE WHEN e.evidence_id IS NULL THEN 'MISSING'
            WHEN e.file_exists=0 THEN 'FILE MISSING'
            WHEN r.current_revision_required=1 AND COALESCE(r.expected_revision,'')<>'' AND UPPER(COALESCE(e.revision,''))<>UPPER(r.expected_revision) THEN 'SUPERSEDED REVISION'
            WHEN UPPER(COALESCE((SELECT dr.status FROM document_reviews dr WHERE dr.evidence_id=e.evidence_id ORDER BY dr.review_id DESC LIMIT 1),''))='REJECTED' THEN 'REVIEW REJECTED'
            WHEN r.approval_required=1 AND UPPER(COALESCE((SELECT da.status FROM document_approvals da WHERE da.evidence_id=e.evidence_id ORDER BY da.approval_id DESC LIMIT 1),''))<>'APPROVED' THEN 'APPROVAL PENDING'
            WHEN COALESCE(e.references_document_code,'')<>'' AND UPPER(COALESCE(e.references_revision,''))<>UPPER(COALESCE((SELECT d.revision FROM document_revisions d WHERE d.project_id=r.project_id AND d.document_code=e.references_document_code AND d.is_current=1 ORDER BY d.revision_id DESC LIMIT 1),e.references_revision)) THEN 'OBSOLETE REFERENCE'
            WHEN r.integrity_hash_required=1 AND COALESCE(TRIM(e.sha256),'')='' THEN 'HASH MISSING'
            ELSE 'PASS' END AS Status,
       COALESCE(e.references_document_code,'') AS RefDocument,COALESCE(e.references_revision,'') AS RefRevision,COALESCE(e.sha256,'') AS SHA256,COALESCE(e.file_path,'') AS FilePath
FROM document_requirements r JOIN dossier_sections s ON s.section_id=r.section_id
LEFT JOIN document_evidence e ON e.requirement_id=r.requirement_id
LEFT JOIN assets a ON a.asset_id=r.asset_id LEFT JOIN blocks b ON b.block_id=a.block_id
WHERE r.project_id=@p ORDER BY s.sort_order,r.requirement_code;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECDossierOverview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $m=@(Get-ECDocumentMatrix -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $mandatory=@($m|Where-Object {$_.Mandatory -eq 'YES'})
    $pass=@($mandatory|Where-Object {$_.Status -eq 'PASS'})
    $findings=@(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $doc=@($findings|Where-Object {$_.Rule -like 'DOC7-*'})
    $technical=@($findings|Where-Object {$_.Rule -notlike 'DOC7-*'})
    $technicalBlockers=@($technical|Where-Object {$_.Severity -eq 'BLOCKER'}).Count
    $technicalPct=[Math]::Max(0,100-(20*$technicalBlockers))
    $docPct=if($mandatory.Count -eq 0){100}else{[Math]::Round(($pass.Count*100.0)/$mandatory.Count,0)}
    $handover=if($technicalBlockers -eq 0 -and $pass.Count -eq $mandatory.Count){'READY FOR HANDOVER'}else{'NOT READY FOR HANDOVER'}
    [pscustomobject]@{TechnicalReadinessPct=$technicalPct;DocumentReadinessPct=$docPct;HandoverStatus=$handover;MandatoryRequirements=$mandatory.Count;Compliant=$pass.Count;DocumentBlockers=@($doc|Where-Object {$_.Severity -eq 'BLOCKER'}).Count;DocumentWarnings=@($doc|Where-Object {$_.Severity -eq 'WARNING'}).Count}
}

function Update-ECDossierResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $matrix=@(Get-ECDocumentMatrix -DatabasePath $DatabasePath -ProjectId $ProjectId)
    Invoke-SqliteQuery -DataSource $DatabasePath -Query 'DELETE FROM dossier_results WHERE project_id=@p;' -SqlParameters @{p=$ProjectId}|Out-Null
    foreach($section in @(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT section_id,section_code FROM dossier_sections WHERE project_id=@p ORDER BY sort_order;' -SqlParameters @{p=$ProjectId})){
        $rows=@($matrix|Where-Object {$_.Section -eq [string]$section.section_code -and $_.Mandatory -eq 'YES'})
        $compliant=@($rows|Where-Object {$_.Status -eq 'PASS'}).Count
        $missing=@($rows|Where-Object {$_.Status -in @('MISSING','FILE MISSING')}).Count
        $blockers=@($rows|Where-Object {$_.Status -notin @('PASS','HASH MISSING')}).Count
        $warnings=@($rows|Where-Object {$_.Status -eq 'HASH MISSING'}).Count
        $pct=if($rows.Count -eq 0){100}else{[Math]::Round($compliant*100.0/$rows.Count,0)}
        Invoke-SqliteQuery -DataSource $DatabasePath -Query 'INSERT INTO dossier_results(project_id,section_id,total_required,compliant,missing,blockers,warnings,completeness_pct,calculated_at) VALUES(@p,@s,@t,@c,@m,@b,@w,@pct,datetime(''now''));' -SqlParameters @{p=$ProjectId;s=[int]$section.section_id;t=$rows.Count;c=$compliant;m=$missing;b=$blockers;w=$warnings;pct=$pct}|Out-Null
    }
}

function Get-ECDossierSectionSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Update-ECDossierResults -DatabasePath $DatabasePath -ProjectId $ProjectId
    Invoke-SqliteQuery -DataSource $DatabasePath -Query @'
SELECT s.section_code AS Section,s.title AS Title,r.total_required AS Required,r.compliant AS Compliant,r.missing AS Missing,r.blockers AS Blockers,r.warnings AS Warnings,ROUND(r.completeness_pct,0) AS CompletenessPct
FROM dossier_results r JOIN dossier_sections s ON s.section_id=r.section_id WHERE r.project_id=@p ORDER BY s.sort_order;
'@ -SqlParameters @{p=$ProjectId}
}

function Get-ECDossierFindings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    Get-ECFindings -DatabasePath $DatabasePath -ProjectId $ProjectId|Where-Object {$_.Rule -like 'DOC7-*'}
}

function Export-ECDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DatabasePath,[Parameter(Mandatory)][int]$ProjectId)
    $project=Get-ECProject -DatabasePath $DatabasePath -ProjectId $ProjectId
    if($null -eq $project){throw 'Project not found.'}
    $safe=([string]$project.ProjectCode -replace '[^A-Za-z0-9_-]','_')
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $root=Join-Path (Join-Path $PSScriptRoot '..\reports') ("dossier-{0}-{1}" -f $safe,$stamp)
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    $matrix=@(Get-ECDocumentMatrix -DatabasePath $DatabasePath -ProjectId $ProjectId)
    $overview=Get-ECDossierOverview -DatabasePath $DatabasePath -ProjectId $ProjectId
    $manifest=@()
    $sections=@(Invoke-SqliteQuery -DataSource $DatabasePath -Query 'SELECT section_code,title,sort_order FROM dossier_sections WHERE project_id=@p ORDER BY sort_order;' -SqlParameters @{p=$ProjectId})
    foreach($s in $sections){
        $folderName=("{0}-{1}" -f ([string]$s.section_code),([string]$s.title -replace '[^A-Za-z0-9 _-]','' -replace ' +','-'))
        $folder=Join-Path $root $folderName;New-Item -ItemType Directory -Path $folder -Force|Out-Null
        foreach($row in @($matrix|Where-Object {$_.Section -eq [string]$s.section_code})){
            $copied=''
            if(-not [string]::IsNullOrWhiteSpace([string]$row.FilePath) -and (Test-Path -LiteralPath ([string]$row.FilePath))){
                $dest=Join-Path $folder ([IO.Path]::GetFileName([string]$row.FilePath));Copy-Item -LiteralPath ([string]$row.FilePath) -Destination $dest -Force;$copied=$dest
            }
            $manifest+=[pscustomobject]@{Section=$row.Section;Requirement=$row.Requirement;Asset=$row.Asset;Evidence=$row.Evidence;Revision=$row.Revision;Approval=$row.Approval;Status=$row.Status;SHA256=$row.SHA256;SourcePath=$row.FilePath;PackagePath=$copied}
        }
    }
    $csv=Join-Path $root '00-Dossier-Manifest.csv';$manifest|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $sectionRows=(@(Get-ECDossierSectionSummary -DatabasePath $DatabasePath -ProjectId $ProjectId)|ForEach-Object{"<tr><td>$($_.Section)</td><td>$([Net.WebUtility]::HtmlEncode([string]$_.Title))</td><td>$($_.Required)</td><td>$($_.Compliant)</td><td>$($_.CompletenessPct)%</td><td>$($_.Blockers)</td><td>$($_.Warnings)</td></tr>"}) -join "`n"
    $matrixRows=($matrix|ForEach-Object{"<tr><td>$($_.Section)</td><td>$($_.Requirement)</td><td>$([Net.WebUtility]::HtmlEncode([string]$_.Asset))</td><td>$([Net.WebUtility]::HtmlEncode([string]$_.RequirementTitle))</td><td>$([Net.WebUtility]::HtmlEncode([string]$_.FileName))</td><td>$($_.Revision)</td><td>$($_.Approval)</td><td><b>$($_.Status)</b></td></tr>"}) -join "`n"
    $html=@"
<!doctype html><html><head><meta charset="utf-8"><title>EnergizeCheck Dossier - $($project.ProjectCode)</title><style>body{font-family:Segoe UI,Arial;margin:34px;color:#17202a}h1{margin-bottom:2px}.sub{color:#667085}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:20px 0}.card{border:1px solid #d9e1ea;padding:14px;border-radius:6px}.big{font-size:24px;font-weight:700}table{border-collapse:collapse;width:100%;margin:12px 0 26px}th,td{border:1px solid #d9e1ea;padding:8px;text-align:left;vertical-align:top}th{background:#eef2f5}</style></head><body>
<h1>EnergizeCheck Commissioning Dossier</h1><div class="sub">$([Net.WebUtility]::HtmlEncode([string]$project.ProjectName)) | $($project.ProjectCode) | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="cards"><div class="card">Technical readiness<div class="big">$($overview.TechnicalReadinessPct)%</div></div><div class="card">Document readiness<div class="big">$($overview.DocumentReadinessPct)%</div></div><div class="card">Mandatory evidence<div class="big">$($overview.Compliant)/$($overview.MandatoryRequirements)</div></div><div class="card">Handover<div class="big" style="font-size:16px">$($overview.HandoverStatus)</div></div></div>
<h2>Dossier sections</h2><table><tr><th>Section</th><th>Title</th><th>Required</th><th>Compliant</th><th>Complete</th><th>Blockers</th><th>Warnings</th></tr>$sectionRows</table>
<h2>Evidence matrix</h2><table><tr><th>Section</th><th>Requirement</th><th>Asset</th><th>Required evidence</th><th>File</th><th>Rev</th><th>Approval</th><th>Status</th></tr>$matrixRows</table>
<p>Manifest: 00-Dossier-Manifest.csv</p></body></html>
"@
    $index=Join-Path $root '00-Dossier-Index.html';Set-Content -LiteralPath $index -Value $html -Encoding UTF8
    return $index
}

Export-ModuleMember -Function Import-ECCsvFile,Initialize-ECDatabase,Add-ECDemoData,Get-ECProjects,Get-ECProject,New-ECProject,Get-ECProjectStats,Get-ECImportDefinition,Get-ECAutoColumnMap,Test-ECImportData,Import-ECProjectData,Get-ECImportHistory,Get-ECImportErrors,Invoke-ECValidation,Get-ECFindings,Get-ECReadiness,Show-ECSummary,Export-ECReport,Repair-ECDemoData,Initialize-ECEngineeringSchema,Set-ECParameter,Get-ECParameters,Set-ECStringEngineering,Get-ECStringEngineering,Set-ECInverterEngineering,Get-ECInverterEngineering,Set-ECCableEngineering,Get-ECCableEngineering,Clear-ECEngineeringData,Initialize-ECV04Schema,Get-ECKPIs,Get-ECReadinessBreakdown,Get-ECAssetTree,Get-ECAssetSummary,Get-ECAssetCurrentFindings,Get-ECDiagnosticsForAsset,Get-ECAssetEngineeringMetrics,Sync-ECFindingCases,Get-ECFindingCases,Update-ECFindingCase,Get-ECFindingCaseHistory,Initialize-ECV05Schema,Set-ECBessRackEngineering,Get-ECBessRackEngineering,Set-ECBessPcsEngineering,Get-ECBessPcsEngineering,Set-ECBessCommissioningCheck,Get-ECBessCommissioningChecks,Get-ECBessOverview,Get-ECBessParameters,Initialize-ECV06Schema,Set-ECGridSetting,Get-ECGridSettings,Set-ECGridTransformerTest,Get-ECGridTransformerTests,Set-ECGridResponseTest,Get-ECGridResponseTests,Set-ECGridCommissioningCheck,Get-ECGridCommissioningChecks,Get-ECGridOverview,Get-ECGridParameters,Initialize-ECV07Schema,Set-ECDossierSection,Set-ECDocumentRequirement,Set-ECDocumentEvidence,Set-ECDocumentReview,Set-ECDocumentApproval,Get-ECDocumentMatrix,Get-ECDossierOverview,Update-ECDossierResults,Get-ECDossierSectionSummary,Get-ECDossierFindings,Export-ECDossier

