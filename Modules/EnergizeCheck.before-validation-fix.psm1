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
        return [pscustomobject]@{Total=$rows.Count;Valid=0;Invalid=$rows.Count;Errors=@($errors)}
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
    return [pscustomobject]@{Total=$rows.Count;Valid=($rows.Count-$badRows);Invalid=$badRows;Errors=@($errors)}
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

Export-ModuleMember -Function Import-ECCsvFile,Initialize-ECDatabase,Add-ECDemoData,Get-ECProjects,Get-ECProject,New-ECProject,Get-ECProjectStats,Get-ECImportDefinition,Get-ECAutoColumnMap,Test-ECImportData,Import-ECProjectData,Get-ECImportHistory,Get-ECImportErrors,Invoke-ECValidation,Get-ECFindings,Get-ECReadiness,Show-ECSummary,Export-ECReport,Repair-ECDemoData
