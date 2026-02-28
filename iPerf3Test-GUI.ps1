<#
.SYNOPSIS
  Graphical UI for iperf3 Test Suite (Windows Forms).
.DESCRIPTION
  Launches a Windows Forms GUI to configure and run Invoke-Iperf3TestSuite.
  Requires Windows and PowerShell 7+. Run with: pwsh -File .\iPerf3Test-GUI.ps1
#>
#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'Start-Job receives arguments via -ArgumentList, not outer scope')]
param()

if (-not ($IsWindows -or $env:OS -match 'Windows')) {
  Write-Error 'GUI is only supported on Windows (System.Windows.Forms).'
  exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'scripts/PathHelpers.ps1')
$script:ModulePath = Join-Path $PSScriptRoot 'src/Iperf3TestSuite.psd1'
Import-Module $script:ModulePath -Force

$script:RunJob = $null
$script:LastRunSummary = $null

function Get-ParamHashFromRunTab {
  param([System.Windows.Forms.Form]$Form)
  $target = $Form.Controls.Find('txtTarget', $true) | Select-Object -First 1
  $port = $Form.Controls.Find('numPort', $true) | Select-Object -First 1
  $outDir = $Form.Controls.Find('txtOutDir', $true) | Select-Object -First 1
  $duration = $Form.Controls.Find('numDuration', $true) | Select-Object -First 1
  $protocol = $Form.Controls.Find('comboProtocol', $true) | Select-Object -First 1
  $ipVersion = $Form.Controls.Find('comboIpVersion', $true) | Select-Object -First 1
  $chkProgress = $Form.Controls.Find('chkProgress', $true) | Select-Object -First 1
  $chkSkipReach = $Form.Controls.Find('chkSkipReach', $true) | Select-Object -First 1
  $chkDisableMtu = $Form.Controls.Find('chkDisableMtu', $true) | Select-Object -First 1
  $chkSingleTest = $Form.Controls.Find('chkSingleTest', $true) | Select-Object -First 1
  $chkForce = $Form.Controls.Find('chkForce', $true) | Select-Object -First 1
  $chkStrict = $Form.Controls.Find('chkStrict', $true) | Select-Object -First 1
  $profilesFile = $Form.Controls.Find('txtProfilesFile', $true) | Select-Object -First 1

  return @{
    Target                = $target.Text.Trim()
    Port                  = [int]$port.Value
    OutDir                = $outDir.Text.Trim()
    Duration              = [int]$duration.Value
    Protocol              = $protocol.SelectedItem.ToString()
    IpVersion             = $ipVersion.SelectedItem.ToString()
    Progress              = $chkProgress.Checked
    SkipReachabilityCheck = $chkSkipReach.Checked
    DisableMtuProbe       = $chkDisableMtu.Checked
    SingleTest            = $chkSingleTest.Checked
    Force                 = $chkForce.Checked
    StrictConfiguration   = $chkStrict.Checked
    ProfilesFile          = $profilesFile.Text.Trim()
    Quiet                 = $false
  }
}

function Set-UiBusyState {
  param(
    [System.Windows.Forms.Form]$Form,
    [bool]$Busy
  )
  $btnRun = $Form.Controls.Find('btnRun', $true) | Select-Object -First 1
  $btnWhatIf = $Form.Controls.Find('btnWhatIf', $true) | Select-Object -First 1
  $btnCancel = $Form.Controls.Find('btnCancel', $true) | Select-Object -First 1
  $btnSaveProfile = $Form.Controls.Find('btnSaveProfile', $true) | Select-Object -First 1
  $btnLoadProfile = $Form.Controls.Find('btnLoadProfile', $true) | Select-Object -First 1
  $btnDeleteProfile = $Form.Controls.Find('btnDeleteProfile', $true) | Select-Object -First 1
  $btnRefreshProfiles = $Form.Controls.Find('btnRefreshProfiles', $true) | Select-Object -First 1

  foreach ($b in @($btnRun, $btnWhatIf, $btnSaveProfile, $btnLoadProfile, $btnDeleteProfile, $btnRefreshProfiles)) {
    if ($b) { $b.Enabled = -not $Busy }
  }
  if ($btnCancel) { $btnCancel.Enabled = $Busy }
}

function Test-RunFormValid {
  param(
    [System.Windows.Forms.Form]$Form,
    [System.Windows.Forms.ErrorProvider]$ErrorProvider
  )
  $target = $Form.Controls.Find('txtTarget', $true) | Select-Object -First 1
  $outDir = $Form.Controls.Find('txtOutDir', $true) | Select-Object -First 1
  $profilesFile = $Form.Controls.Find('txtProfilesFile', $true) | Select-Object -First 1
  $ok = $true
  $ErrorProvider.SetError($target, '')
  $ErrorProvider.SetError($outDir, '')
  if ($profilesFile) { $ErrorProvider.SetError($profilesFile, '') }
  if (-not $target.Text.Trim()) {
    $ErrorProvider.SetError($target, 'Target is required.')
    $ok = $false
  }
  if (-not $outDir.Text.Trim()) {
    $ErrorProvider.SetError($outDir, 'Output directory is required.')
    $ok = $false
  }
  if ($profilesFile) {
    try {
      $null = Get-ProfilesFileFromForm -Form $Form
    }
    catch {
      $ErrorProvider.SetError($profilesFile, $_.Exception.Message)
      $ok = $false
    }
  }
  return $ok
}

function Start-SuiteJob {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'WhatIf is passed through to the module, not implemented here')]
  param(
    [hashtable]$ParamHash,
    [switch]$WhatIf,
    [string]$ModulePath
  )
  $hash = $ParamHash.Clone()
  if ($WhatIf) { $hash['WhatIf'] = $true }
  $hash['PassThru'] = $true
  return (Start-Job -ScriptBlock {
      param($modPath, $params)
      Import-Module $modPath -Force
      Invoke-Iperf3TestSuite @params *>&1
    } -ArgumentList $ModulePath, $hash)
}

function Update-LogAndStateFromJob {
  param(
    [System.Windows.Forms.Form]$Form,
    [System.Management.Automation.Job]$Job,
    [System.Windows.Forms.TextBox]$LogBox,
    [System.Windows.Forms.ProgressBar]$ProgressBar,
    [System.Windows.Forms.Label]$StatusLabel,
    [System.Windows.Forms.Timer]$Timer
  )
  if (-not $Job) { return $false }

  $output = Receive-Job -Job $Job
  if ($output) {
    foreach ($item in @($output)) {
      if ($item -and $item.PSObject -and $item.PSObject.Properties.Name -contains 'ExitCode' -and $item.PSObject.Properties.Name -contains 'Status') {
        $script:LastRunSummary = $item
        $summaryPathBox = $Form.Controls.Find('txtLastSummary', $true) | Select-Object -First 1
        $reportPathBox = $Form.Controls.Find('txtLastReport', $true) | Select-Object -First 1
        if ($summaryPathBox -and $item.Supplemental.SummaryJsonPath) { $summaryPathBox.Text = [string]$item.Supplemental.SummaryJsonPath }
        if ($reportPathBox -and $item.Supplemental.ReportMdPath) { $reportPathBox.Text = [string]$item.Supplemental.ReportMdPath }
        continue
      }
      $line = [string]$item
      if ($line) {
        $LogBox.AppendText($line + "`r`n")
        if ($line -match 'Running test\s+(\d+)/(\d+)') {
          $current = [int]$matches[1]
          $total = [math]::Max([int]$matches[2], 1)
          $pct = [math]::Min(100, [int](100 * $current / $total))
          $ProgressBar.Value = $pct
          $StatusLabel.Text = "Running $current/$total ($pct%)"
        }
      }
    }
    $LogBox.ScrollToCaret()
  }

  if ($Job.State -eq 'Completed' -or $Job.State -eq 'Failed') {
    $Timer.Stop()
    Set-UiBusyState -Form $Form -Busy $false
    $ProgressBar.Value = 100
    if ($script:LastRunSummary) {
      $StatusLabel.Text = "Done: $($script:LastRunSummary.Status) (ExitCode=$($script:LastRunSummary.ExitCode))"
    }
    else {
      $StatusLabel.Text = "Done: $($Job.State)"
    }
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    return $true
  }

  if ($Job.State -eq 'Stopped') {
    $Timer.Stop()
    Set-UiBusyState -Form $Form -Busy $false
    $StatusLabel.Text = 'Cancelled'
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    return $true
  }
  return $false
}

function Stop-CurrentRunJob {
  param(
    [System.Windows.Forms.Timer]$Timer,
    [System.Windows.Forms.Label]$StatusLabel
  )
  if (-not $script:RunJob) { return }
  try {
    Stop-Job -Job $script:RunJob -ErrorAction SilentlyContinue
    Remove-Job -Job $script:RunJob -Force -ErrorAction SilentlyContinue
  }
  finally {
    $script:RunJob = $null
    if ($Timer) { $Timer.Tag = $null; $Timer.Stop() }
    if ($StatusLabel) { $StatusLabel.Text = 'Cancelled' }
  }
}

function Get-ProfilesFileFromForm {
  param([System.Windows.Forms.Form]$Form)
  $tb = $Form.Controls.Find('txtProfilesFile', $true) | Select-Object -First 1
  $path = $tb.Text.Trim()
  if (-not $path) { $path = (Join-Path (Join-Path (Get-Location) '.iperf3') 'profiles.json') }
  return (Resolve-ConfigPath -Path $path -BasePath (Get-Location).Path)
}

function Show-GuiError {
  param(
    [string]$Message,
    [string]$Title = 'Error'
  )
  [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Update-ProfilesList {
  param([System.Windows.Forms.Form]$Form)
  try {
    $list = $Form.Controls.Find('listProfiles', $true) | Select-Object -First 1
    $profilesPath = Get-ProfilesFileFromForm -Form $Form
    $res = Invoke-Iperf3TestSuite -ListProfiles -ProfilesFile $profilesPath -PassThru -Quiet
    $list.Items.Clear()
    foreach ($n in @($res.Profiles)) { [void]$list.Items.Add($n) }
  }
  catch {
    Show-GuiError -Message $_.Exception.Message -Title 'Profiles'
  }
}

function Set-RunFormFromSelectedProfile {
  param([System.Windows.Forms.Form]$Form)
  try {
    $list = $Form.Controls.Find('listProfiles', $true) | Select-Object -First 1
    if (-not $list.SelectedItem) { return }
    $profileName = [string]$list.SelectedItem
    $profilesPath = Get-ProfilesFileFromForm -Form $Form
    $res = Invoke-Iperf3TestSuite -ProfileName $profileName -ProfilesFile $profilesPath -WhatIf -PassThru -Quiet
    $p = $res.EffectiveParameters
    if (-not $p) { return }

    ($Form.Controls.Find('txtTarget', $true) | Select-Object -First 1).Text = [string]$p.Target
    ($Form.Controls.Find('numPort', $true) | Select-Object -First 1).Value = [int]$p.Port
    ($Form.Controls.Find('txtOutDir', $true) | Select-Object -First 1).Text = [string]$p.OutDir
    ($Form.Controls.Find('numDuration', $true) | Select-Object -First 1).Value = [int]$p.Duration
    ($Form.Controls.Find('comboProtocol', $true) | Select-Object -First 1).SelectedItem = [string]$p.Protocol
    ($Form.Controls.Find('comboIpVersion', $true) | Select-Object -First 1).SelectedItem = [string]$p.IpVersion
    ($Form.Controls.Find('chkProgress', $true) | Select-Object -First 1).Checked = [bool]$p.Progress
    ($Form.Controls.Find('chkSkipReach', $true) | Select-Object -First 1).Checked = [bool]$p.SkipReachabilityCheck
    ($Form.Controls.Find('chkDisableMtu', $true) | Select-Object -First 1).Checked = [bool]$p.DisableMtuProbe
    ($Form.Controls.Find('chkSingleTest', $true) | Select-Object -First 1).Checked = [bool]$p.SingleTest
    ($Form.Controls.Find('chkForce', $true) | Select-Object -First 1).Checked = [bool]$p.Force
  }
  catch {
    Show-GuiError -Message $_.Exception.Message -Title 'Profiles'
  }
}

function Save-ProfileFromForm {
  param([System.Windows.Forms.Form]$Form)
  try {
    $nameBox = $Form.Controls.Find('txtProfileName', $true) | Select-Object -First 1
    $profileName = $nameBox.Text.Trim()
    if (-not $profileName) {
      [System.Windows.Forms.MessageBox]::Show('Profile name is required.', 'Validation', 'OK', 'Warning')
      return
    }
    $profilesPath = Get-ProfilesFileFromForm -Form $Form
    $p = Get-ParamHashFromRunTab -Form $Form
    $null = Invoke-Iperf3TestSuite @p -ProfilesFile $profilesPath -ProfileName $profileName -SaveProfile -WhatIf -PassThru -Quiet
    Update-ProfilesList -Form $Form
  }
  catch {
    Show-GuiError -Message $_.Exception.Message -Title 'Profiles'
  }
}

function Remove-SelectedProfile {
  param([System.Windows.Forms.Form]$Form)
  try {
    $list = $Form.Controls.Find('listProfiles', $true) | Select-Object -First 1
    if (-not $list.SelectedItem) { return }
    $profileName = [string]$list.SelectedItem
    $profilesPath = Get-ProfilesFileFromForm -Form $Form
    $strict = ($Form.Controls.Find('chkStrict', $true) | Select-Object -First 1).Checked
    $removed = Remove-Iperf3Profile -ProfileName $profileName -ProfilesFile $profilesPath -StrictConfiguration:$strict
    if (-not $removed) {
      [void][System.Windows.Forms.MessageBox]::Show("Profile '$profileName' was not found.", 'Profiles', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    Update-ProfilesList -Form $Form
  }
  catch {
    Show-GuiError -Message $_.Exception.Message -Title 'Profiles'
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'iperf3 Test Suite'
$form.Size = New-Object System.Drawing.Size(880, 700)
$form.StartPosition = 'CenterScreen'

$errorProvider = New-Object System.Windows.Forms.ErrorProvider
$errorProvider.BlinkStyle = 'NeverBlink'

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = 'Run'
$tabs.TabPages.Add($tabRun)

$tabProfiles = New-Object System.Windows.Forms.TabPage
$tabProfiles.Text = 'Profiles'
$tabs.TabPages.Add($tabProfiles)

$tabReports = New-Object System.Windows.Forms.TabPage
$tabReports.Text = 'Reports'
$tabs.TabPages.Add($tabReports)

# Run tab controls
$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = 'Target:'
$lblTarget.Location = New-Object System.Drawing.Point(12, 14)
$tabRun.Controls.Add($lblTarget)

$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Name = 'txtTarget'
$txtTarget.Location = New-Object System.Drawing.Point(100, 12)
$txtTarget.Size = New-Object System.Drawing.Size(220, 24)
$txtTarget.Text = '127.0.0.1'
$tabRun.Controls.Add($txtTarget)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = 'Port:'
$lblPort.Location = New-Object System.Drawing.Point(340, 14)
$tabRun.Controls.Add($lblPort)

$numPort = New-Object System.Windows.Forms.NumericUpDown
$numPort.Name = 'numPort'
$numPort.Location = New-Object System.Drawing.Point(380, 12)
$numPort.Minimum = 1
$numPort.Maximum = 65535
$numPort.Value = 5201
$tabRun.Controls.Add($numPort)

$lblOutDir = New-Object System.Windows.Forms.Label
$lblOutDir.Text = 'Out dir:'
$lblOutDir.Location = New-Object System.Drawing.Point(12, 48)
$tabRun.Controls.Add($lblOutDir)

$txtOutDir = New-Object System.Windows.Forms.TextBox
$txtOutDir.Name = 'txtOutDir'
$txtOutDir.Location = New-Object System.Drawing.Point(100, 46)
$txtOutDir.Size = New-Object System.Drawing.Size(440, 24)
$txtOutDir.Text = (Join-Path (Get-Location) 'logs')
$tabRun.Controls.Add($txtOutDir)

$btnBrowseOut = New-Object System.Windows.Forms.Button
$btnBrowseOut.Text = '...'
$btnBrowseOut.Location = New-Object System.Drawing.Point(548, 44)
$btnBrowseOut.Size = New-Object System.Drawing.Size(34, 26)
$btnBrowseOut.Add_Click({
  $folder = New-Object System.Windows.Forms.FolderBrowserDialog
  if ($folder.ShowDialog() -eq 'OK') { $txtOutDir.Text = $folder.SelectedPath }
})
$tabRun.Controls.Add($btnBrowseOut)

$lblDuration = New-Object System.Windows.Forms.Label
$lblDuration.Text = 'Duration (s):'
$lblDuration.Location = New-Object System.Drawing.Point(12, 82)
$tabRun.Controls.Add($lblDuration)

$numDuration = New-Object System.Windows.Forms.NumericUpDown
$numDuration.Name = 'numDuration'
$numDuration.Location = New-Object System.Drawing.Point(100, 80)
$numDuration.Minimum = 1
$numDuration.Maximum = 3600
$numDuration.Value = 10
$tabRun.Controls.Add($numDuration)

$lblProtocol = New-Object System.Windows.Forms.Label
$lblProtocol.Text = 'Protocol:'
$lblProtocol.Location = New-Object System.Drawing.Point(200, 82)
$tabRun.Controls.Add($lblProtocol)

$comboProtocol = New-Object System.Windows.Forms.ComboBox
$comboProtocol.Name = 'comboProtocol'
$comboProtocol.Location = New-Object System.Drawing.Point(260, 80)
$comboProtocol.DropDownStyle = 'DropDownList'
@('Both', 'TCP', 'UDP') | ForEach-Object { [void]$comboProtocol.Items.Add($_) }
$comboProtocol.SelectedIndex = 0
$tabRun.Controls.Add($comboProtocol)

$lblIpVersion = New-Object System.Windows.Forms.Label
$lblIpVersion.Text = 'IP version:'
$lblIpVersion.Location = New-Object System.Drawing.Point(360, 82)
$tabRun.Controls.Add($lblIpVersion)

$comboIpVersion = New-Object System.Windows.Forms.ComboBox
$comboIpVersion.Name = 'comboIpVersion'
$comboIpVersion.Location = New-Object System.Drawing.Point(430, 80)
$comboIpVersion.DropDownStyle = 'DropDownList'
@('Auto', 'IPv4', 'IPv6') | ForEach-Object { [void]$comboIpVersion.Items.Add($_) }
$comboIpVersion.SelectedIndex = 0
$tabRun.Controls.Add($comboIpVersion)

$chkProgress = New-Object System.Windows.Forms.CheckBox
$chkProgress.Name = 'chkProgress'
$chkProgress.Text = 'Show progress'
$chkProgress.Location = New-Object System.Drawing.Point(12, 114)
$chkProgress.Checked = $true
$tabRun.Controls.Add($chkProgress)

$chkSkipReach = New-Object System.Windows.Forms.CheckBox
$chkSkipReach.Name = 'chkSkipReach'
$chkSkipReach.Text = 'Skip reachability check'
$chkSkipReach.Location = New-Object System.Drawing.Point(140, 114)
$tabRun.Controls.Add($chkSkipReach)

$chkDisableMtu = New-Object System.Windows.Forms.CheckBox
$chkDisableMtu.Name = 'chkDisableMtu'
$chkDisableMtu.Text = 'Disable MTU probe'
$chkDisableMtu.Location = New-Object System.Drawing.Point(320, 114)
$tabRun.Controls.Add($chkDisableMtu)

$chkSingleTest = New-Object System.Windows.Forms.CheckBox
$chkSingleTest.Name = 'chkSingleTest'
$chkSingleTest.Text = 'Single test only'
$chkSingleTest.Location = New-Object System.Drawing.Point(470, 114)
$tabRun.Controls.Add($chkSingleTest)

$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Name = 'chkForce'
$chkForce.Text = 'Overwrite outputs'
$chkForce.Location = New-Object System.Drawing.Point(620, 114)
$tabRun.Controls.Add($chkForce)

$chkStrict = New-Object System.Windows.Forms.CheckBox
$chkStrict.Name = 'chkStrict'
$chkStrict.Text = 'Strict config'
$chkStrict.Location = New-Object System.Drawing.Point(620, 82)
$tabRun.Controls.Add($chkStrict)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Name = 'btnRun'
$btnRun.Text = 'Run'
$btnRun.Location = New-Object System.Drawing.Point(12, 148)
$btnRun.Size = New-Object System.Drawing.Size(90, 28)
$tabRun.Controls.Add($btnRun)

$btnWhatIf = New-Object System.Windows.Forms.Button
$btnWhatIf.Name = 'btnWhatIf'
$btnWhatIf.Text = 'WhatIf'
$btnWhatIf.Location = New-Object System.Drawing.Point(108, 148)
$btnWhatIf.Size = New-Object System.Drawing.Size(90, 28)
$tabRun.Controls.Add($btnWhatIf)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Name = 'btnCancel'
$btnCancel.Text = 'Cancel'
$btnCancel.Location = New-Object System.Drawing.Point(204, 148)
$btnCancel.Size = New-Object System.Drawing.Size(70, 28)
$btnCancel.Enabled = $false
$tabRun.Controls.Add($btnCancel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(282, 151)
$progressBar.Size = New-Object System.Drawing.Size(348, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$tabRun.Controls.Add($progressBar)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(640, 152)
$statusLabel.Size = New-Object System.Drawing.Size(210, 22)
$statusLabel.Text = 'Idle'
$tabRun.Controls.Add($statusLabel)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(12, 184)
$txtLog.Size = New-Object System.Drawing.Size(840, 430)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$tabRun.Controls.Add($txtLog)

# Profiles tab controls
$lblProfilesFile = New-Object System.Windows.Forms.Label
$lblProfilesFile.Text = 'Profiles file:'
$lblProfilesFile.Location = New-Object System.Drawing.Point(12, 14)
$tabProfiles.Controls.Add($lblProfilesFile)

$txtProfilesFile = New-Object System.Windows.Forms.TextBox
$txtProfilesFile.Name = 'txtProfilesFile'
$txtProfilesFile.Location = New-Object System.Drawing.Point(100, 12)
$txtProfilesFile.Size = New-Object System.Drawing.Size(560, 24)
$txtProfilesFile.Text = (Join-Path (Join-Path (Get-Location) '.iperf3') 'profiles.json')
$tabProfiles.Controls.Add($txtProfilesFile)

$btnRefreshProfiles = New-Object System.Windows.Forms.Button
$btnRefreshProfiles.Name = 'btnRefreshProfiles'
$btnRefreshProfiles.Text = 'Refresh'
$btnRefreshProfiles.Location = New-Object System.Drawing.Point(670, 10)
$btnRefreshProfiles.Size = New-Object System.Drawing.Size(90, 28)
$tabProfiles.Controls.Add($btnRefreshProfiles)

$listProfiles = New-Object System.Windows.Forms.ListBox
$listProfiles.Name = 'listProfiles'
$listProfiles.Location = New-Object System.Drawing.Point(12, 48)
$listProfiles.Size = New-Object System.Drawing.Size(380, 520)
$tabProfiles.Controls.Add($listProfiles)

$lblProfileName = New-Object System.Windows.Forms.Label
$lblProfileName.Text = 'Profile name:'
$lblProfileName.Location = New-Object System.Drawing.Point(410, 50)
$tabProfiles.Controls.Add($lblProfileName)

$txtProfileName = New-Object System.Windows.Forms.TextBox
$txtProfileName.Name = 'txtProfileName'
$txtProfileName.Location = New-Object System.Drawing.Point(500, 48)
$txtProfileName.Size = New-Object System.Drawing.Size(260, 24)
$tabProfiles.Controls.Add($txtProfileName)

$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Name = 'btnSaveProfile'
$btnSaveProfile.Text = 'Save current as profile'
$btnSaveProfile.Location = New-Object System.Drawing.Point(410, 84)
$btnSaveProfile.Size = New-Object System.Drawing.Size(170, 30)
$tabProfiles.Controls.Add($btnSaveProfile)

$btnLoadProfile = New-Object System.Windows.Forms.Button
$btnLoadProfile.Name = 'btnLoadProfile'
$btnLoadProfile.Text = 'Load selected profile'
$btnLoadProfile.Location = New-Object System.Drawing.Point(590, 84)
$btnLoadProfile.Size = New-Object System.Drawing.Size(170, 30)
$tabProfiles.Controls.Add($btnLoadProfile)

$btnDeleteProfile = New-Object System.Windows.Forms.Button
$btnDeleteProfile.Name = 'btnDeleteProfile'
$btnDeleteProfile.Text = 'Delete selected profile'
$btnDeleteProfile.Location = New-Object System.Drawing.Point(410, 120)
$btnDeleteProfile.Size = New-Object System.Drawing.Size(170, 30)
$tabProfiles.Controls.Add($btnDeleteProfile)

# Reports tab controls
$lblLastSummary = New-Object System.Windows.Forms.Label
$lblLastSummary.Text = 'Last summary JSON:'
$lblLastSummary.Location = New-Object System.Drawing.Point(12, 20)
$tabReports.Controls.Add($lblLastSummary)

$txtLastSummary = New-Object System.Windows.Forms.TextBox
$txtLastSummary.Name = 'txtLastSummary'
$txtLastSummary.Location = New-Object System.Drawing.Point(140, 18)
$txtLastSummary.Size = New-Object System.Drawing.Size(600, 24)
$txtLastSummary.ReadOnly = $true
$tabReports.Controls.Add($txtLastSummary)

$lblLastReport = New-Object System.Windows.Forms.Label
$lblLastReport.Text = 'Last report MD:'
$lblLastReport.Location = New-Object System.Drawing.Point(12, 54)
$tabReports.Controls.Add($lblLastReport)

$txtLastReport = New-Object System.Windows.Forms.TextBox
$txtLastReport.Name = 'txtLastReport'
$txtLastReport.Location = New-Object System.Drawing.Point(140, 52)
$txtLastReport.Size = New-Object System.Drawing.Size(600, 24)
$txtLastReport.ReadOnly = $true
$tabReports.Controls.Add($txtLastReport)

$btnOpenSummary = New-Object System.Windows.Forms.Button
$btnOpenSummary.Text = 'Open summary'
$btnOpenSummary.Location = New-Object System.Drawing.Point(140, 86)
$btnOpenSummary.Size = New-Object System.Drawing.Size(120, 30)
$btnOpenSummary.Add_Click({
  if ($txtLastSummary.Text -and (Test-Path -LiteralPath $txtLastSummary.Text -PathType Leaf)) {
    Start-Process explorer.exe -ArgumentList $txtLastSummary.Text
  }
})
$tabReports.Controls.Add($btnOpenSummary)

$btnOpenReport = New-Object System.Windows.Forms.Button
$btnOpenReport.Text = 'Open report'
$btnOpenReport.Location = New-Object System.Drawing.Point(270, 86)
$btnOpenReport.Size = New-Object System.Drawing.Size(120, 30)
$btnOpenReport.Add_Click({
  if ($txtLastReport.Text -and (Test-Path -LiteralPath $txtLastReport.Text -PathType Leaf)) {
    Start-Process explorer.exe -ArgumentList $txtLastReport.Text
  }
})
$tabReports.Controls.Add($btnOpenReport)

$btnOpenOutDir = New-Object System.Windows.Forms.Button
$btnOpenOutDir.Text = 'Open output folder'
$btnOpenOutDir.Location = New-Object System.Drawing.Point(400, 86)
$btnOpenOutDir.Size = New-Object System.Drawing.Size(130, 30)
$btnOpenOutDir.Add_Click({
  $dir = $txtOutDir.Text.Trim()
  if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
    Start-Process explorer.exe -ArgumentList $dir
  }
})
$tabReports.Controls.Add($btnOpenOutDir)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
  if ($timer.Tag) {
    $done = Update-LogAndStateFromJob -Form $form -Job $timer.Tag -LogBox $txtLog -ProgressBar $progressBar -StatusLabel $statusLabel -Timer $timer
    if ($done) { $timer.Tag = $null }
  }
})

$btnRun.Add_Click({
  if (-not (Test-RunFormValid -Form $form -ErrorProvider $errorProvider)) { return }
  Set-UiBusyState -Form $form -Busy $true
  $progressBar.Value = 0
  $statusLabel.Text = 'Starting run...'
  $txtLog.Clear()
  $script:LastRunSummary = $null
  $params = Get-ParamHashFromRunTab -Form $form
  $script:RunJob = Start-SuiteJob -ParamHash $params -ModulePath $script:ModulePath
  $timer.Tag = $script:RunJob
  $timer.Start()
})

$btnWhatIf.Add_Click({
  if (-not (Test-RunFormValid -Form $form -ErrorProvider $errorProvider)) { return }
  Set-UiBusyState -Form $form -Busy $true
  $progressBar.Value = 0
  $statusLabel.Text = 'WhatIf preview...'
  $txtLog.Clear()
  $script:LastRunSummary = $null
  $params = Get-ParamHashFromRunTab -Form $form
  $script:RunJob = Start-SuiteJob -ParamHash $params -WhatIf -ModulePath $script:ModulePath
  $timer.Tag = $script:RunJob
  $timer.Start()
})

$btnCancel.Add_Click({
  Stop-CurrentRunJob -Timer $timer -StatusLabel $statusLabel
  $progressBar.Value = 0
  Set-UiBusyState -Form $form -Busy $false
})

$btnRefreshProfiles.Add_Click({ Update-ProfilesList -Form $form })
$btnLoadProfile.Add_Click({ Set-RunFormFromSelectedProfile -Form $form })
$btnSaveProfile.Add_Click({ Save-ProfileFromForm -Form $form })
$btnDeleteProfile.Add_Click({ Remove-SelectedProfile -Form $form })

$listProfiles.Add_SelectedIndexChanged({
  if ($listProfiles.SelectedItem) {
    $txtProfileName.Text = [string]$listProfiles.SelectedItem
  }
})

Update-ProfilesList -Form $form
[void]$form.ShowDialog()

if ($script:RunJob) {
  Stop-Job -Job $script:RunJob -ErrorAction SilentlyContinue
  Remove-Job -Job $script:RunJob -Force -ErrorAction SilentlyContinue
}
if ($timer) { $timer.Stop() }
