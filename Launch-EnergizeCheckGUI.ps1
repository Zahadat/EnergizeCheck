[CmdletBinding()]
param([string]$DatabasePath = (Join-Path $PSScriptRoot 'data\energizecheck.db'))

$ErrorActionPreference = 'Stop'
Import-Module PSSQLite -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\EnergizeCheck.psm1') -Force

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

if (-not (Test-Path $DatabasePath)) {
    Initialize-ECDatabase -DatabasePath $DatabasePath -Reset
    Add-ECDemoData -DatabasePath $DatabasePath
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="EnergizeCheck v0.7 - Commissioning Dossier + PV/BESS/Grid Intelligence"
        Height="820" Width="1380" MinHeight="720" MinWidth="1180"
        WindowStartupLocation="CenterScreen" Background="#F5F7FA">
    <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="205"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="#17202A">
            <Grid Margin="18,20">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <StackPanel Grid.Row="0" Margin="0,0,0,24">
                    <TextBlock Text="EnergizeCheck" Foreground="White" FontSize="25" FontWeight="Bold"/>
                    <TextBlock Text="PROJECT INTEGRITY" Foreground="#9FB3C8" FontSize="10" FontWeight="SemiBold" Margin="1,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Row="1">
                    <TextBlock Text="PROJECT" Foreground="#6F8295" FontSize="10" Margin="2,0,0,6"/>
                    <Button Name="NavProjects" Content="Projects" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavDashboard" Content="Dashboard" Height="38" Margin="0,0,0,16" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <TextBlock Text="DATA" Foreground="#6F8295" FontSize="10" Margin="2,0,0,6"/>
                    <Button Name="NavImports" Content="Imports" Height="38" Margin="0,0,0,16" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <TextBlock Text="ENGINEERING" Foreground="#6F8295" FontSize="10" Margin="2,0,0,6"/>
                    <Button Name="NavAssetExplorer" Content="Asset Explorer" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavEngineeringData" Content="Engineering Data" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavBessIntelligence" Content="BESS Intelligence" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavGridIntelligence" Content="Grid &amp; Protection" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavDossierIntelligence" Content="Dossier &amp; Documents" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavValidation" Content="Validation" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavFindingWorkflow" Content="Finding Workflow" Height="38" Margin="0,0,0,5" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <Button Name="NavReadiness" Content="Readiness" Height="38" Margin="0,0,0,16" HorizontalContentAlignment="Left" Padding="12,0"/>
                    <TextBlock Text="OUTPUT" Foreground="#6F8295" FontSize="10" Margin="2,0,0,6"/>
                    <Button Name="NavReports" Content="Reports" Height="38" HorizontalContentAlignment="Left" Padding="12,0"/>
                </StackPanel>
                <TextBlock Grid.Row="3" Text="v0.7.0  |  Dossier + Handover Intelligence" Foreground="#829AB1" FontSize="10"/>
            </Grid>
        </Border>

        <Grid Grid.Column="1">
            <Grid.RowDefinitions><RowDefinition Height="70"/><RowDefinition Height="*"/><RowDefinition Height="30"/></Grid.RowDefinitions>
            <Border Grid.Row="0" Background="White" BorderBrush="#E3E8EF" BorderThickness="0,0,0,1">
                <Grid Margin="24,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="420"/></Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Name="TxtPageTitle" Text="Projects" FontSize="23" FontWeight="SemiBold" Foreground="#17202A"/>
                        <TextBlock Name="TxtPageSubtitle" Text="Create and open PV/BESS projects" FontSize="11" Foreground="#667085"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <TextBlock Text="Active project" VerticalAlignment="Center" Foreground="#667085" Margin="0,0,10,0"/>
                        <ComboBox Name="CmbProject" Width="300" Height="32" DisplayMemberPath="DisplayName"/>
                    </StackPanel>
                </Grid>
            </Border>

            <Grid Grid.Row="1" Margin="24">
                <Grid Name="PageProjects">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
                        <Button Name="BtnNewProject" Content="+ New Project" Padding="18,9" Margin="0,0,8,0"/>
                        <Button Name="BtnOpenProject" Content="Open Selected" Padding="18,9"/>
                    </StackPanel>
                    <Border Grid.Row="1" Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Padding="8">
                        <DataGrid Name="GridProjects" AutoGenerateColumns="True" IsReadOnly="True" SelectionMode="Single"/>
                    </Border>
                </Grid>

                <Grid Name="PageDashboard" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="105"/><RowDefinition Height="250"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <UniformGrid Rows="1" Columns="7" Margin="0,0,0,14">
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="READINESS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatProjectReadiness" Text="0%" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="BLOCKS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatBlocks" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="ASSETS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatAssets" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="BLOCKERS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatBlockers" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="WARNINGS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatWarnings" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Margin="0,0,8,0" Padding="12"><StackPanel><TextBlock Text="FAILED TESTS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatFailedTests" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Padding="12"><StackPanel><TextBlock Text="OPEN NCRS" Foreground="#667085" FontSize="10"/><TextBlock Name="TxtStatOpenNCRs" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel></Border>
                    </UniformGrid>
                    <Grid Grid.Row="1" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.36*"/><ColumnDefinition Width="0.64*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Project Summary" Margin="0,0,10,0" Background="White"><TextBlock Name="TxtProjectSummary" Margin="16" TextWrapping="Wrap" FontSize="12" LineHeight="21"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Block Readiness" Background="White"><DataGrid Name="GridDashboardReadiness" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <GroupBox Grid.Row="2" Header="Readiness by Engineering Discipline" Background="White"><DataGrid Name="GridDashboardBreakdown" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                </Grid>

                <Grid Name="PageImports" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="215"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Padding="14" Margin="0,0,0,12">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                            <ComboBox Name="CmbImportType" Width="180" Height="32" HorizontalAlignment="Left"/>
                            <TextBox Name="TxtCsvPath" Grid.Column="1" Height="32" Margin="10,0" IsReadOnly="True" VerticalContentAlignment="Center"/>
                            <Button Name="BtnBrowseCsv" Grid.Column="2" Content="Choose CSV" Padding="12,6"/>
                        </Grid>
                    </Border>
                    <GroupBox Grid.Row="1" Header="Column Mapping" Background="White" Margin="0,0,0,12">
                        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="PanelMappings" Margin="12"/></ScrollViewer>
                    </GroupBox>
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.68*"/><ColumnDefinition Width="0.32*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="CSV Preview" Background="White" Margin="0,0,10,0"><DataGrid Name="GridPreview" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Import History" Background="White"><DataGrid Name="GridImportHistory" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <Grid Grid.Row="3" Margin="0,12,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <TextBlock Name="TxtImportStatus" VerticalAlignment="Center" Foreground="#475467"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal"><Button Name="BtnValidateImport" Content="Validate Import" Padding="16,8" Margin="0,0,8,0"/><Button Name="BtnImport" Content="Import Data" Padding="16,8"/></StackPanel>
                    </Grid>
                </Grid>


                <Grid Name="PageAssetExplorer" Visibility="Collapsed">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="0.31*"/><ColumnDefinition Width="0.69*"/></Grid.ColumnDefinitions>
                    <GroupBox Header="Electrical Asset Hierarchy" Background="White" Margin="0,0,12,0">
                        <TreeView Name="TreeAssets" Margin="10"/>
                    </GroupBox>
                    <Grid Grid.Column="1">
                        <Grid.RowDefinitions><RowDefinition Height="115"/><RowDefinition Height="0.46*"/><RowDefinition Height="0.54*"/></Grid.RowDefinitions>
                        <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Padding="16" Margin="0,0,0,10">
                            <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="130"/></Grid.ColumnDefinitions>
                                <StackPanel><TextBlock Name="TxtAssetTitle" Text="Select an asset" FontSize="20" FontWeight="SemiBold" Foreground="#17202A"/><TextBlock Name="TxtAssetPath" Text="Choose an inverter, MPPT, string, or module from the hierarchy." Foreground="#667085" Margin="0,5,0,0" TextWrapping="Wrap"/><TextBlock Name="TxtAssetMeta" Foreground="#475467" Margin="0,7,0,0" TextWrapping="Wrap"/></StackPanel>
                                <Border Grid.Column="1" Background="#EEF2F6" CornerRadius="4" Padding="10" VerticalAlignment="Top"><TextBlock Name="TxtAssetState" Text="--" HorizontalAlignment="Center" FontWeight="Bold"/></Border>
                            </Grid>
                        </Border>
                        <Grid Grid.Row="1" Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="0.58*"/><ColumnDefinition Width="0.42*"/></Grid.ColumnDefinitions>
                            <GroupBox Header="Engineering Metrics" Background="White" Margin="0,0,10,0"><DataGrid Name="GridAssetMetrics" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                            <GroupBox Grid.Column="1" Header="Current Findings" Background="White"><DataGrid Name="GridAssetFindings" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        </Grid>
                        <GroupBox Grid.Row="2" Header="Diagnostic Intelligence - Possible Causes and Recommended Investigation" Background="White"><DataGrid Name="GridAssetDiagnostics" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                </Grid>

                <Grid Name="PageEngineeringData" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="0.28*"/><RowDefinition Height="0.36*"/><RowDefinition Height="0.36*"/></Grid.RowDefinitions>
                    <GroupBox Header="Configurable Acceptance Criteria" Background="White" Margin="0,0,0,10"><DataGrid Name="GridEngineeringParameters" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="0.62*"/><ColumnDefinition Width="0.38*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="String Electrical Checks" Background="White" Margin="0,0,10,10"><DataGrid Name="GridStringEngineering" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Inverter Limits" Background="White" Margin="0,0,0,10"><DataGrid Name="GridInverterEngineering" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <GroupBox Grid.Row="2" Header="Cable Engineering Checks" Background="White"><DataGrid Name="GridCableEngineering" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                </Grid>

                <Grid Name="PageBessIntelligence" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="0.23*"/><RowDefinition Height="0.37*"/><RowDefinition Height="0.40*"/></Grid.RowDefinitions>
                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="0.55*"/><ColumnDefinition Width="0.45*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="BESS Commissioning Overview" Background="White" Margin="0,0,10,10"><DataGrid Name="GridBessOverview" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Configurable BESS Acceptance Criteria" Background="White" Margin="0,0,0,10"><DataGrid Name="GridBessParameters" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="0.68*"/><ColumnDefinition Width="0.32*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Battery Rack Health" Background="White" Margin="0,0,10,10"><DataGrid Name="GridBessRacks" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="PCS Configuration" Background="White" Margin="0,0,0,10"><DataGrid Name="GridBessPcs" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <GroupBox Grid.Row="2" Header="BESS Safety, Communications and Control Commissioning Checks" Background="White"><DataGrid Name="GridBessChecks" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                </Grid>


                <Grid Name="PageGridIntelligence" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="140"/><RowDefinition Height="255"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.48*"/><ColumnDefinition Width="0.52*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Grid Commissioning Overview" Background="White" Margin="0,0,10,0"><DataGrid Name="GridGridOverview" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Configurable Grid Acceptance Criteria" Background="White"><DataGrid Name="GridGridParameters" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <Grid Grid.Row="1" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.58*"/><ColumnDefinition Width="0.42*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Protection, CT and VT Controlled Settings" Background="White" Margin="0,0,10,0"><DataGrid Name="GridGridSettings" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Grid Transformer Tests" Background="White"><DataGrid Name="GridGridTransformerTests" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.52*"/><ColumnDefinition Width="0.48*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="PPC / Grid Response Tests" Background="White" Margin="0,0,10,0"><DataGrid Name="GridGridResponses" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="MV, POI and Grid Functional Commissioning" Background="White"><DataGrid Name="GridGridChecks" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                </Grid>


                <Grid Name="PageDossierIntelligence" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="145"/><RowDefinition Height="*"/><RowDefinition Height="180"/></Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.46*"/><ColumnDefinition Width="0.54*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Handover Readiness Overview" Background="White" Margin="0,0,10,0"><DataGrid Name="GridDossierOverview" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Dossier Section Completeness" Background="White"><DataGrid Name="GridDossierSections" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                    <GroupBox Grid.Row="1" Header="Commissioning Evidence Matrix" Background="White" Margin="0,0,0,12"><DataGrid Name="GridDossierMatrix" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="0.68*"/><ColumnDefinition Width="0.32*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Current Document / Dossier Findings" Background="White" Margin="0,0,10,0"><DataGrid Name="GridDossierFindings" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                        <GroupBox Grid.Column="1" Header="Handover Package" Background="White"><StackPanel Margin="16"><TextBlock Text="Generate a timestamped handover dossier with section folders, copied evidence, SHA-256 manifest data and an HTML evidence index." TextWrapping="Wrap" Foreground="#667085" Margin="0,0,0,14"/><StackPanel Orientation="Horizontal"><Button Name="BtnGenerateDossier" Content="Generate Dossier" Padding="15,8" Margin="0,0,8,0"/><Button Name="BtnOpenDossier" Content="Generate &amp; Open" Padding="15,8"/></StackPanel><TextBlock Name="TxtDossierPath" TextWrapping="Wrap" Foreground="#475467" Margin="0,14,0,0"/></StackPanel></GroupBox>
                    </Grid>
                </Grid>

                <Grid Name="PageValidation" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,12"><Button Name="BtnRunValidation" Content="Run Validation" Padding="18,9"/></StackPanel>
                    <GroupBox Grid.Row="1" Header="Open Findings" Background="White"><DataGrid Name="GridFindings" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                </Grid>

                <Grid Name="PageFindingWorkflow" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="0.52*"/><RowDefinition Height="0.48*"/></Grid.RowDefinitions>
                    <GroupBox Header="Finding Cases - Persistent QA / Commissioning Workflow" Background="White" Margin="0,0,0,10"><DataGrid Name="GridFindingCases" Margin="8" AutoGenerateColumns="True" IsReadOnly="True" SelectionMode="Single"/></GroupBox>
                    <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="0.62*"/><ColumnDefinition Width="0.38*"/></Grid.ColumnDefinitions>
                        <GroupBox Header="Selected Case" Background="White" Margin="0,0,10,0">
                            <Grid Margin="12"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="70"/><RowDefinition Height="70"/><RowDefinition Height="38"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                                <TextBlock Name="TxtCaseSummary" Grid.ColumnSpan="2" Text="Select a finding case." FontWeight="SemiBold" Margin="0,0,0,8" TextWrapping="Wrap"/>
                                <TextBlock Grid.Row="1" Text="Status" VerticalAlignment="Center"/><ComboBox Name="CmbCaseStatus" Grid.Row="1" Grid.Column="1" Margin="0,4"/>
                                <TextBlock Grid.Row="2" Text="Assigned to" VerticalAlignment="Center"/><TextBox Name="TxtCaseAssigned" Grid.Row="2" Grid.Column="1" Margin="0,4"/>
                                <TextBlock Grid.Row="3" Text="Root cause" VerticalAlignment="Top" Margin="0,7,0,0"/><TextBox Name="TxtCaseRootCause" Grid.Row="3" Grid.Column="1" Margin="0,4" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                                <TextBlock Grid.Row="4" Text="Corrective action" VerticalAlignment="Top" Margin="0,7,0,0"/><TextBox Name="TxtCaseAction" Grid.Row="4" Grid.Column="1" Margin="0,4" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                                <TextBlock Grid.Row="5" Text="Retest result" VerticalAlignment="Center"/><TextBox Name="TxtCaseRetest" Grid.Row="5" Grid.Column="1" Margin="0,4"/>
                                <Button Name="BtnSaveCase" Grid.Row="6" Grid.Column="1" Content="Save Case Update" HorizontalAlignment="Right" Padding="16,7" Margin="0,8,0,0"/>
                            </Grid>
                        </GroupBox>
                        <GroupBox Grid.Column="1" Header="Case Audit History" Background="White"><DataGrid Name="GridCaseHistory" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    </Grid>
                </Grid>

                <Grid Name="PageReadiness" Visibility="Collapsed">
                    <Grid.RowDefinitions><RowDefinition Height="0.30*"/><RowDefinition Height="0.70*"/></Grid.RowDefinitions>
                    <GroupBox Header="Commissioning Readiness by Block" Background="White" Margin="0,0,0,10"><DataGrid Name="GridReadiness" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                    <GroupBox Grid.Row="1" Header="Readiness Drill-Down by Discipline" Background="White"><DataGrid Name="GridReadinessBreakdown" Margin="8" AutoGenerateColumns="True" IsReadOnly="True"/></GroupBox>
                </Grid>

                <Grid Name="PageReports" Visibility="Collapsed">
                    <Border Background="White" BorderBrush="#D9E1EA" BorderThickness="1" CornerRadius="5" Padding="24" VerticalAlignment="Top">
                        <StackPanel><TextBlock Text="Commissioning Readiness Report" FontSize="19" FontWeight="SemiBold"/><TextBlock Text="Generate an HTML report for the active project containing project metadata, block readiness and current validation findings." TextWrapping="Wrap" Foreground="#667085" Margin="0,6,0,18"/>
                            <StackPanel Orientation="Horizontal"><Button Name="BtnGenerateReport" Content="Generate Report" Padding="18,9" Margin="0,0,8,0"/><Button Name="BtnOpenReport" Content="Generate &amp; Open" Padding="18,9"/></StackPanel>
                            <TextBlock Name="TxtReportPath" Margin="0,16,0,0" TextWrapping="Wrap" Foreground="#475467"/></StackPanel>
                    </Border>
                </Grid>
            </Grid>

            <Border Grid.Row="2" Background="White" BorderBrush="#E3E8EF" BorderThickness="0,1,0,0"><TextBlock Name="TxtStatus" Margin="24,0" VerticalAlignment="Center" Foreground="#667085" FontSize="11"/></Border>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:CurrentProjectId = $null
$script:CurrentCsvPath = $null
$script:PreviewRows = @()
$script:CsvHeaders = @()
$script:MappingControls = @{}
$script:LoadingProjects = $false

function W([string]$Name) { return $window.FindName($Name) }

function Show-Page([string]$Name,[string]$Title,[string]$Subtitle) {
    foreach ($p in @('PageProjects','PageDashboard','PageImports','PageAssetExplorer','PageEngineeringData','PageBessIntelligence','PageGridIntelligence','PageDossierIntelligence','PageValidation','PageFindingWorkflow','PageReadiness','PageReports')) { (W $p).Visibility='Collapsed' }
    (W $Name).Visibility='Visible'; (W 'TxtPageTitle').Text=$Title; (W 'TxtPageSubtitle').Text=$Subtitle
}

function Require-Project {
    if ($null -eq $script:CurrentProjectId) {
        [System.Windows.MessageBox]::Show('Create or open a project first.','EnergizeCheck') | Out-Null
        return $false
    }
    return $true
}

function Refresh-Projects {
    $script:LoadingProjects = $true
    $projects = @(Get-ECProjects -DatabasePath $DatabasePath)
    (W 'GridProjects').ItemsSource = $projects
    (W 'CmbProject').ItemsSource = $projects
    if ($projects.Count -gt 0) {
        $selectedIndex = 0
        if ($script:CurrentProjectId) {
            for ($i=0;$i -lt $projects.Count;$i++) { if ([int]$projects[$i].ProjectId -eq [int]$script:CurrentProjectId) { $selectedIndex=$i; break } }
        }
        (W 'CmbProject').SelectedIndex = $selectedIndex
        $script:CurrentProjectId = [int]$projects[$selectedIndex].ProjectId
    }
    $script:LoadingProjects = $false
    Refresh-CurrentProject
}

function Refresh-CurrentProject {
    if ($null -eq $script:CurrentProjectId) {
        (W 'TxtStatus').Text = "Database: $DatabasePath | No active project"
        return
    }
    $p = Get-ECProject -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId
    if ($null -eq $p) { return }
    $stats = Get-ECProjectStats -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId
    $kpis = Get-ECKPIs -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId
    (W 'TxtStatProjectReadiness').Text = ("$($kpis.ProjectReadiness)%")
    (W 'TxtStatBlocks').Text = [string]$kpis.Blocks
    (W 'TxtStatAssets').Text = [string]$kpis.Assets
    (W 'TxtStatBlockers').Text = [string]$kpis.Blockers
    (W 'TxtStatWarnings').Text = [string]$kpis.Warnings
    (W 'TxtStatFailedTests').Text = [string]$kpis.FailedTests
    (W 'TxtStatOpenNCRs').Text = [string]$kpis.OpenNCRs
    (W 'TxtProjectSummary').Text = "Project: $($p.ProjectName)`nCode: $($p.ProjectCode)`nType: $($p.ProjectType)`nLocation: $($p.Location)`nPV: $($p.PvMWp) MWp`nBESS: $($p.BessMWh) MWh`nClient: $($p.Client)`nEPC: $($p.EPC)`nStatus: $($p.Status)"
    $readiness = @(Get-ECReadiness -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDashboardReadiness').ItemsSource = $readiness
    (W 'GridReadiness').ItemsSource = $readiness
    (W 'GridFindings').ItemsSource = @(Get-ECFindings -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridImportHistory').ItemsSource = @(Get-ECImportHistory -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridEngineeringParameters').ItemsSource = @(Get-ECParameters -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridStringEngineering').ItemsSource = @(Get-ECStringEngineering -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridInverterEngineering').ItemsSource = @(Get-ECInverterEngineering -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridCableEngineering').ItemsSource = @(Get-ECCableEngineering -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridBessOverview').ItemsSource = @(Get-ECBessOverview -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridBessParameters').ItemsSource = @(Get-ECBessParameters -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridBessRacks').ItemsSource = @(Get-ECBessRackEngineering -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridBessPcs').ItemsSource = @(Get-ECBessPcsEngineering -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridBessChecks').ItemsSource = @(Get-ECBessCommissioningChecks -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridOverview').ItemsSource = @(Get-ECGridOverview -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridParameters').ItemsSource = @(Get-ECGridParameters -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridSettings').ItemsSource = @(Get-ECGridSettings -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridTransformerTests').ItemsSource = @(Get-ECGridTransformerTests -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridResponses').ItemsSource = @(Get-ECGridResponseTests -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridGridChecks').ItemsSource = @(Get-ECGridCommissioningChecks -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDossierOverview').ItemsSource = @(Get-ECDossierOverview -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDossierSections').ItemsSource = @(Get-ECDossierSectionSummary -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDossierMatrix').ItemsSource = @(Get-ECDocumentMatrix -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDossierFindings').ItemsSource = @(Get-ECDossierFindings -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    Sync-ECFindingCases -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId
    $breakdown=@(Get-ECReadinessBreakdown -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    (W 'GridDashboardBreakdown').ItemsSource=$breakdown
    (W 'GridReadinessBreakdown').ItemsSource=$breakdown
    Refresh-FindingWorkflow
    Refresh-AssetExplorer
    (W 'TxtStatus').Text = "Active: $($p.ProjectCode) | Assets: $($stats.Assets) | Findings: $($stats.Findings) | Database: $DatabasePath"
}


function Refresh-AssetExplorer {
    if($null -eq $script:CurrentProjectId){return}
    $tree=(W 'TreeAssets'); if($null -eq $tree){return}
    $tree.Items.Clear()
    $rows=@(Get-ECAssetTree -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
    $blockNodes=@{}; $assetNodes=@{}
    foreach($r in $rows){
        $block=[string]$r.Block
        if(-not $blockNodes.ContainsKey($block)){
            $bn=New-Object System.Windows.Controls.TreeViewItem
            $bn.Header=$block; $bn.FontWeight='SemiBold'; $bn.IsExpanded=$true; $bn.Tag="BLOCK::$block"
            $tree.Items.Add($bn)|Out-Null; $blockNodes[$block]=$bn
        }
        $item=New-Object System.Windows.Controls.TreeViewItem
        $item.Header=("{0}  [{1}]" -f $r.AssetCode,$r.AssetType)
        $item.Tag=[string]$r.AssetCode
        if(-not [string]::IsNullOrWhiteSpace([string]$r.ParentAssetCode) -and $assetNodes.ContainsKey([string]$r.ParentAssetCode)){
            $assetNodes[[string]$r.ParentAssetCode].Items.Add($item)|Out-Null
        } else {
            $blockNodes[$block].Items.Add($item)|Out-Null
        }
        $assetNodes[[string]$r.AssetCode]=$item
    }
}

function Show-AssetDetail([string]$AssetCode){
    if([string]::IsNullOrWhiteSpace($AssetCode) -or $AssetCode.StartsWith('BLOCK::')){return}
    $s=Get-ECAssetSummary -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -AssetCode $AssetCode
    if($null -eq $s){return}
    (W 'TxtAssetTitle').Text=("{0} - {1}" -f $s.AssetCode,$s.AssetType)
    (W 'TxtAssetPath').Text=[string]$s.Path
    (W 'TxtAssetMeta').Text=("Installation: {0} | Manufacturer: {1} | Model: {2} | Serial: {3} | Children: {4}" -f $s.InstallationStatus,$s.Manufacturer,$s.Model,$s.SerialNumber,$s.Children)
    (W 'TxtAssetState').Text=[string]$s.EngineeringState
    if([string]$s.EngineeringState -eq 'READY'){(W 'TxtAssetState').Foreground=[Windows.Media.Brushes]::DarkGreen}
    elseif([string]$s.EngineeringState -eq 'NOT READY'){(W 'TxtAssetState').Foreground=[Windows.Media.Brushes]::DarkRed}
    else{(W 'TxtAssetState').Foreground=[Windows.Media.Brushes]::DarkOrange}
    (W 'GridAssetMetrics').ItemsSource=@(Get-ECAssetEngineeringMetrics -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -AssetCode $AssetCode)
    (W 'GridAssetFindings').ItemsSource=@(Get-ECAssetCurrentFindings -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -AssetCode $AssetCode)
    (W 'GridAssetDiagnostics').ItemsSource=@(Get-ECDiagnosticsForAsset -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -AssetCode $AssetCode)
}

function Refresh-FindingWorkflow {
    if($null -eq $script:CurrentProjectId){return}
    (W 'GridFindingCases').ItemsSource=@(Get-ECFindingCases -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId)
}

function Load-SelectedFindingCase {
    $c=(W 'GridFindingCases').SelectedItem
    if($null -eq $c){
        (W 'TxtCaseSummary').Text='Select a finding case.'
        (W 'GridCaseHistory').ItemsSource=@()
        return
    }
    (W 'TxtCaseSummary').Text=("Case #{0} | {1} | {2} | {3} | {4}" -f $c.CaseId,$c.Severity,$c.Rule,$c.Block,$c.Asset)
    (W 'CmbCaseStatus').SelectedItem=[string]$c.Status
    (W 'TxtCaseAssigned').Text=[string]$c.AssignedTo
    (W 'TxtCaseRootCause').Text=[string]$c.RootCause
    (W 'TxtCaseAction').Text=[string]$c.CorrectiveAction
    (W 'TxtCaseRetest').Text=[string]$c.RetestResult
    (W 'GridCaseHistory').ItemsSource=@(Get-ECFindingCaseHistory -DatabasePath $DatabasePath -CaseId ([int]$c.CaseId))
}

function Show-NewProjectDialog {
    [xml]$dx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="New EnergizeCheck Project" Height="570" Width="560" WindowStartupLocation="CenterOwner" ResizeMode="NoResize" Background="#F5F7FA">
<Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="Create Project" FontSize="24" FontWeight="Bold" Margin="0,0,0,18"/>
<Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="155"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<Grid.RowDefinitions><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/><RowDefinition Height="45"/></Grid.RowDefinitions>
<TextBlock Text="Project code *" VerticalAlignment="Center"/><TextBox Name="DCode" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="1" Text="Project name *" VerticalAlignment="Center"/><TextBox Name="DName" Grid.Row="1" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="2" Text="Location" VerticalAlignment="Center"/><TextBox Name="DLocation" Grid.Row="2" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="3" Text="Project type" VerticalAlignment="Center"/><ComboBox Name="DType" Grid.Row="3" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="4" Text="PV capacity MWp" VerticalAlignment="Center"/><TextBox Name="DPV" Grid.Row="4" Grid.Column="1" Margin="0,6" Text="0"/>
<TextBlock Grid.Row="5" Text="BESS capacity MWh" VerticalAlignment="Center"/><TextBox Name="DBESS" Grid.Row="5" Grid.Column="1" Margin="0,6" Text="0"/>
<TextBlock Grid.Row="6" Text="Client" VerticalAlignment="Center"/><TextBox Name="DClient" Grid.Row="6" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="7" Text="EPC contractor" VerticalAlignment="Center"/><TextBox Name="DEPC" Grid.Row="7" Grid.Column="1" Margin="0,6"/>
<TextBlock Grid.Row="8" Text="Status" VerticalAlignment="Center"/><ComboBox Name="DStatus" Grid.Row="8" Grid.Column="1" Margin="0,6"/>
</Grid>
<StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0"><Button Name="DCancel" Content="Cancel" Width="90" Height="34" Margin="0,0,8,0"/><Button Name="DCreate" Content="Create Project" Width="120" Height="34"/></StackPanel>
</Grid></Window>
"@
    $dr = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [Windows.Markup.XamlReader]::Load($dr); $dlg.Owner=$window
    $dtype=$dlg.FindName('DType'); $dtype.ItemsSource=@('PV','BESS','HYBRID'); $dtype.SelectedIndex=0
    $dstatus=$dlg.FindName('DStatus'); $dstatus.ItemsSource=@('IN PROGRESS','CONSTRUCTION','COMMISSIONING','OPERATING'); $dstatus.SelectedIndex=0
    $dlg.FindName('DCancel').Add_Click({$dlg.DialogResult=$false})
    $dlg.FindName('DCreate').Add_Click({
        try {
            $pv=0.0; [double]::TryParse($dlg.FindName('DPV').Text.Replace(',','.'),[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$pv) | Out-Null
            $bess=0.0; [double]::TryParse($dlg.FindName('DBESS').Text.Replace(',','.'),[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$bess) | Out-Null
            $id=New-ECProject -DatabasePath $DatabasePath -ProjectCode $dlg.FindName('DCode').Text -ProjectName $dlg.FindName('DName').Text -Location $dlg.FindName('DLocation').Text -ProjectType ([string]$dtype.SelectedItem) -PvCapacityMWp $pv -BessCapacityMWh $bess -Client $dlg.FindName('DClient').Text -EpcContractor $dlg.FindName('DEPC').Text -Status ([string]$dstatus.SelectedItem)
            $dlg.Tag=$id; $dlg.DialogResult=$true
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Could not create project') | Out-Null }
    })
    if ($dlg.ShowDialog()) { $script:CurrentProjectId=[int]$dlg.Tag; Refresh-Projects; Show-Page 'PageDashboard' 'Dashboard' 'Project health, activity and commissioning status' }
}

function Build-MappingUI {
    (W 'PanelMappings').Children.Clear(); $script:MappingControls=@{}
    if (-not $script:CurrentCsvPath) { return }
    $type=[string](W 'CmbImportType').SelectedItem
    $definition=Get-ECImportDefinition -ImportType $type
    $auto=Get-ECAutoColumnMap -ImportType $type -Headers $script:CsvHeaders
    foreach($d in $definition) {
        $g=New-Object System.Windows.Controls.Grid; $g.Margin='0,3'
        $c1=New-Object System.Windows.Controls.ColumnDefinition; $c1.Width='220'
        $c2=New-Object System.Windows.Controls.ColumnDefinition; $c2.Width='*'
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $label=New-Object System.Windows.Controls.TextBlock; $label.VerticalAlignment='Center'; $label.Text=if($d.Required){"$($d.Field) *"}else{$d.Field}; $g.Children.Add($label) | Out-Null
        $cb=New-Object System.Windows.Controls.ComboBox; $cb.Height=28; $cb.Margin='8,0,0,0'; [System.Windows.Controls.Grid]::SetColumn($cb,1)
        $choices=@('<Not mapped>') + $script:CsvHeaders; $cb.ItemsSource=$choices
        if($auto.ContainsKey($d.Field)){$cb.SelectedItem=$auto[$d.Field]}else{$cb.SelectedIndex=0}
        $g.Children.Add($cb) | Out-Null; (W 'PanelMappings').Children.Add($g) | Out-Null; $script:MappingControls[$d.Field]=$cb
    }
}

function Current-ColumnMap {
    $m=@{}
    foreach($k in $script:MappingControls.Keys){$m[$k]=[string]$script:MappingControls[$k].SelectedItem}
    return $m
}

function Load-Csv([string]$Path) {
    $rows=@(Import-ECCsvFile -Path $Path)
    if($rows.Count -eq 0){throw 'CSV contains no data rows.'}
    $script:CurrentCsvPath=$Path; $script:PreviewRows=$rows; $script:CsvHeaders=@($rows[0].PSObject.Properties.Name)
    (W 'TxtCsvPath').Text=$Path; (W 'GridPreview').ItemsSource=@($rows | Select-Object -First 50)
    (W 'TxtImportStatus').Text="Rows: $($rows.Count) | Previewing first $([Math]::Min(50,$rows.Count))"
    Build-MappingUI
}

(W 'NavProjects').Add_Click({Show-Page 'PageProjects' 'Projects' 'Create and open PV/BESS projects'})
(W 'NavDashboard').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageDashboard' 'Dashboard' 'Project health, activity and commissioning status'}})
(W 'NavImports').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageImports' 'Imports' 'Map and import real project CSV data'}})
(W 'NavAssetExplorer').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageAssetExplorer' 'Asset Explorer' 'Electrical hierarchy, asset metrics and diagnostic guidance'}})
(W 'NavEngineeringData').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageEngineeringData' 'Engineering Data' 'Calculated string, inverter and cable acceptance checks'}})
(W 'NavBessIntelligence').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageBessIntelligence' 'BESS Intelligence' 'Battery rack health, PCS configuration, safety systems and control-interface commissioning'}})
(W 'NavGridIntelligence').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageGridIntelligence' 'Grid & Protection Intelligence' 'POI, protection, MV switchgear, transformer and PPC/grid-response commissioning'}})
(W 'NavDossierIntelligence').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageDossierIntelligence' 'Dossier & Document Intelligence' 'Evidence completeness, revision control, approvals and handover readiness'}})
(W 'NavValidation').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageValidation' 'Validation' 'Engineering and data-integrity rule findings'}})
(W 'NavFindingWorkflow').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageFindingWorkflow' 'Finding Workflow' 'Persistent investigation, corrective-action and retest lifecycle'}})
(W 'NavReadiness').Add_Click({if(Require-Project){Refresh-CurrentProject;Show-Page 'PageReadiness' 'Readiness' 'Block-level energization readiness'}})
(W 'NavReports').Add_Click({if(Require-Project){Show-Page 'PageReports' 'Reports' 'Generate auditable project readiness reports'}})

(W 'BtnNewProject').Add_Click({Show-NewProjectDialog})
(W 'BtnOpenProject').Add_Click({$s=(W 'GridProjects').SelectedItem;if($s){$script:CurrentProjectId=[int]$s.ProjectId;Refresh-Projects;Show-Page 'PageDashboard' 'Dashboard' 'Project health, activity and commissioning status'}})
(W 'GridProjects').Add_MouseDoubleClick({$s=(W 'GridProjects').SelectedItem;if($s){$script:CurrentProjectId=[int]$s.ProjectId;Refresh-Projects;Show-Page 'PageDashboard' 'Dashboard' 'Project health, activity and commissioning status'}})
(W 'CmbProject').Add_SelectionChanged({if(-not $script:LoadingProjects){$s=(W 'CmbProject').SelectedItem;if($s){$script:CurrentProjectId=[int]$s.ProjectId;Refresh-CurrentProject}}})


(W 'TreeAssets').Add_SelectedItemChanged({
    $sel=(W 'TreeAssets').SelectedItem
    if($null -ne $sel -and $null -ne $sel.Tag){Show-AssetDetail ([string]$sel.Tag)}
})

$caseStatuses=@('OPEN','ACKNOWLEDGED','UNDER INVESTIGATION','CORRECTIVE ACTION','READY FOR RETEST','CLOSED','REOPENED')
(W 'CmbCaseStatus').ItemsSource=$caseStatuses
(W 'GridFindingCases').Add_SelectionChanged({Load-SelectedFindingCase})
(W 'BtnSaveCase').Add_Click({
    $c=(W 'GridFindingCases').SelectedItem
    if($null -eq $c){return}
    try{
        Update-ECFindingCase -DatabasePath $DatabasePath -CaseId ([int]$c.CaseId) -Status ([string](W 'CmbCaseStatus').SelectedItem) -AssignedTo (W 'TxtCaseAssigned').Text -RootCause (W 'TxtCaseRootCause').Text -CorrectiveAction (W 'TxtCaseAction').Text -RetestResult (W 'TxtCaseRetest').Text
        Refresh-FindingWorkflow
        [System.Windows.MessageBox]::Show('Finding case updated.','EnergizeCheck')|Out-Null
    }catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Case Update Error')|Out-Null}
})

$importTypes=@('Plant Structure','String Schedule','Documents','Installed Equipment','Delivery Register','Materials','Tests','NCR / Punch List')
(W 'CmbImportType').ItemsSource=$importTypes; (W 'CmbImportType').SelectedIndex=0
(W 'CmbImportType').Add_SelectionChanged({if($script:CurrentCsvPath){Build-MappingUI}})
(W 'BtnBrowseCsv').Add_Click({
    if(-not (Require-Project)){return}
    $ofd=New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter='CSV files (*.csv)|*.csv|All files (*.*)|*.*'; $ofd.Title='Select project CSV'
    if($ofd.ShowDialog()) { try{Load-Csv $ofd.FileName}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'CSV Error')|Out-Null} }
})
(W 'BtnValidateImport').Add_Click({
    if(-not (Require-Project) -or -not $script:CurrentCsvPath){return}
    try{$m=Current-ColumnMap;$r=Test-ECImportData -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -ImportType ([string](W 'CmbImportType').SelectedItem) -CsvPath $script:CurrentCsvPath -ColumnMap $m;(W 'TxtImportStatus').Text="Validation: $($r.Valid) valid | $($r.Invalid) invalid | $($r.Total) total";if($r.Errors.Count -gt 0){$msg=($r.Errors|Select-Object -First 8|ForEach-Object{"Row $($_.Row) [$($_.Field)]: $($_.Message)"}) -join "`n";[System.Windows.MessageBox]::Show($msg,'Import validation')|Out-Null}else{[System.Windows.MessageBox]::Show('Validation passed. No format errors detected.','Import validation')|Out-Null}}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Validation Error')|Out-Null}
})
(W 'BtnImport').Add_Click({
    if(-not (Require-Project) -or -not $script:CurrentCsvPath){return}
    try{$m=Current-ColumnMap;$r=Import-ECProjectData -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId -ImportType ([string](W 'CmbImportType').SelectedItem) -CsvPath $script:CurrentCsvPath -ColumnMap $m;(W 'TxtImportStatus').Text="Imported: $($r.Imported) | Failed: $($r.Failed) | Total: $($r.Total)";Refresh-CurrentProject;[System.Windows.MessageBox]::Show("Import complete.`nImported: $($r.Imported)`nFailed: $($r.Failed)",'EnergizeCheck')|Out-Null}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Import Error')|Out-Null}
})

(W 'BtnRunValidation').Add_Click({if(Require-Project){try{Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId|Out-Null;Refresh-CurrentProject;(W 'TxtStatus').Text="Validation complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'Validation Error')|Out-Null}}})
(W 'BtnGenerateReport').Add_Click({if(Require-Project){$p=Export-ECReport -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId;(W 'TxtReportPath').Text=$p}})
(W 'BtnOpenReport').Add_Click({if(Require-Project){$p=Export-ECReport -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId;(W 'TxtReportPath').Text=$p;Start-Process $p}})
(W 'BtnGenerateDossier').Add_Click({if(Require-Project){$p=Export-ECDossier -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId;(W 'TxtDossierPath').Text=$p}})
(W 'BtnOpenDossier').Add_Click({if(Require-Project){$p=Export-ECDossier -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId;(W 'TxtDossierPath').Text=$p;Start-Process $p}})

Refresh-Projects
if($script:CurrentProjectId){Invoke-ECValidation -DatabasePath $DatabasePath -ProjectId $script:CurrentProjectId|Out-Null;Refresh-CurrentProject}
Show-Page 'PageProjects' 'Projects' 'Create and open PV/BESS projects'
$window.ShowDialog() | Out-Null
