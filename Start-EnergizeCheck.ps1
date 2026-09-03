[CmdletBinding()]
param(
    [switch]$ResetDemo,
    [switch]$OpenReport,
    [switch]$Gui,
    [string]$ProjectCode,
    [string]$DatabasePath = (Join-Path $PSScriptRoot 'data\energizecheck.db')
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name PSSQLite)) { throw "PSSQLite is not installed. Run .\Install-Dependencies.ps1 first." }
Import-Module PSSQLite -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force

if ($ResetDemo -or -not (Test-Path $DatabasePath)) {
    Initialize-ECDatabase -DatabasePath $DatabasePath -Reset
    Add-ECDemoData -DatabasePath $DatabasePath
}

if ($Gui) {
    $guiPath = Join-Path $PSScriptRoot 'Launch-EnergizeCheckGUI.ps1'
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $guiPath -DatabasePath $DatabasePath
    exit
}

$projects = @(Get-ECProjects -DatabasePath $DatabasePath)
if ($projects.Count -eq 0) { throw 'No project exists in the database. Launch the GUI and create a project.' }

if ($ProjectCode) {
    $project = $projects | Where-Object ProjectCode -eq $ProjectCode | Select-Object -First 1
    if ($null -eq $project) { throw "Project code '$ProjectCode' was not found." }
} else {
    $project = $projects | Select-Object -First 1
}

Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $project.ProjectId | Out-Null
Show-ECSummary -DatabasePath $DatabasePath -ProjectId $project.ProjectId
$report = Export-ECReport -DatabasePath $DatabasePath -ProjectId $project.ProjectId
Write-Host ''
Write-Host "Database: $DatabasePath" -ForegroundColor DarkGray
Write-Host "Report:   $report" -ForegroundColor DarkGray
if ($OpenReport) { Start-Process $report }
