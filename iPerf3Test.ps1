<#
iperf3 Windows Suite (PowerShell)
- Reachability (ICMP v4/v6, TCP port)
- Optional MTU payload probe (IPv4 DF, IPv6 payload)
- TCP/UDP matrix incl. DSCP via -S (ToS/TClass)
- Robust JSON parsing with ConvertFrom-Json
- CSV/JSON artifacts + summary/report outputs

NOTE:
- This script avoids cmd.exe string invocation for ping to reduce injection risk.
- CSV is produced via Export-Csv to guarantee consistent columns/quoting.
- Defaults are taken from the module (single source); only explicitly passed parameters override.
- Run as script (pwsh -File). Do not dot-source to avoid leaking StrictMode/ErrorActionPreference.
#>
[CmdletBinding()]
param(
  [string]$Target,

  [ValidateRange(1, 65535)]
  [int]$Port,

  [ValidateRange(1, 3600)]
  [int]$Duration,

  [ValidateRange(0, 60)]
  [int]$Omit,

  [ValidateRange(1, 32)]
  [int]$MaxJobs,

  [ValidateNotNullOrEmpty()]
  [string]$OutDir,

  [switch]$Quiet,

  [switch]$Progress,

  [switch]$Summary,

  [switch]$DisableMtuProbe,

  [switch]$SkipReachabilityCheck,

  [ValidateNotNullOrEmpty()]
  [int[]]$MtuSizes,

  [ValidateRange(1000, 300000)]
  [int]$ConnectTimeoutMs,

  [ValidateNotNullOrEmpty()]
  [string]$UdpStart,

  [ValidateNotNullOrEmpty()]
  [string]$UdpMax,

  [ValidateNotNullOrEmpty()]
  [string]$UdpStep,

  [ValidateRange(0, 100)]
  [double]$UdpLossThreshold,

  [ValidateNotNullOrEmpty()]
  [int[]]$TcpStreams,

  [ValidateNotNullOrEmpty()]
  [string[]]$TcpWindows,

  [ValidateNotNullOrEmpty()]
  [string[]]$DscpClasses,

  [ValidateSet('IPv4', 'IPv6', 'Auto')]
  [string]$IpVersion,

  [switch]$Force,

  [switch]$WhatIf,

  [ValidateSet('TCP', 'UDP', 'Both')]
  [string]$Protocol,

  [switch]$SingleTest,

  [string]$ConfigurationPath,

  [string]$ProfileName,

  [string]$ProfilesFile,

  [switch]$SaveProfile,

  [switch]$ListProfiles,

  [string]$DeleteProfile,

  [switch]$StrictConfiguration,

  [switch]$PassThru,

  [switch]$OpenOutputFolder
)

if ($MyInvocation.InvocationName -eq '.') {
  Write-Error "This script should not be dot-sourced. Please run it as a script file (e.g., pwsh -File iPerf3Test.ps1)."
  return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ExitCodeFromException {
  [CmdletBinding()]
  [OutputType([int])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.ErrorRecord]$ErrorRecord
  )
  $msg = [string]$ErrorRecord.Exception.Message
  $fqid = [string]$ErrorRecord.FullyQualifiedErrorId
  if ($fqid -match 'Iperf3TestSuite\.InputValidation') { return 11 }
  if ($fqid -match 'Iperf3TestSuite\.Prerequisite') { return 12 }
  if ($fqid -match 'Iperf3TestSuite\.Connectivity') { return 13 }
  if ($fqid -match 'Iperf3TestSuite\.Internal') { return 16 }
  if (
    $ErrorRecord.Exception -is [System.Management.Automation.ParameterBindingException] -or
    $fqid -match 'ParameterArgumentValidationError|ParameterBinding' -or
    $msg -match 'Cannot validate argument on parameter|Cannot bind parameter|Configuration path|Invalid value for key|Target is required|Invalid Target|ProfileName is required|Unknown configuration key|Profiles file path must be under|Profile .+ not found|At least one DSCP class is required'
  ) { return 11 }
  if ($msg -match 'iperf3.*required|only supported on Windows|ping.exe is required|profiles file is invalid') { return 12 }
  if ($msg -match 'ICMP reachability|TCP port') { return 13 }
  return 16
}

. (Join-Path $PSScriptRoot 'scripts/PathHelpers.ps1')
$modulePath = Join-Path $PSScriptRoot 'src/Iperf3TestSuite.psd1'
Import-Module $modulePath -Force

if ($DeleteProfile -and ($SaveProfile -or $ListProfiles)) {
  Write-Error -Message 'DeleteProfile cannot be combined with SaveProfile or ListProfiles.' -ErrorAction Continue
  exit 11
}

# Default values come from the module (single source of truth); config file (if any) then explicitly passed parameters override.
$merged = Get-Iperf3TestSuiteDefaultParameterSet

if ($ConfigurationPath) {
  try {
    $resolvedConfigPath = Resolve-ConfigPath -Path $ConfigurationPath -BasePath (Get-Location).Path -RequireExistingFile
    $configHash = Get-Content -LiteralPath $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    foreach ($key in $configHash.Keys) {
      if ($merged.ContainsKey($key)) {
        $merged[$key] = $configHash[$key]
      }
      elseif ($StrictConfiguration) {
        throw "Unknown configuration key '$key'."
      }
      else {
        Write-Warning "Unknown configuration key '$key' ignored."
      }
    }
  }
  catch {
    Write-Error -Message "Failed to load configuration from '$ConfigurationPath': $($_.Exception.Message)" -ErrorAction Continue
    exit 11
  }
}

foreach ($key in $PSBoundParameters.Keys) {
  if ($key -ne 'ConfigurationPath' -and $merged.ContainsKey($key)) {
    $merged[$key] = $PSBoundParameters[$key]
  }
}

if ($DeleteProfile) {
  try {
    $removed = Remove-Iperf3Profile -ProfileName $DeleteProfile -ProfilesFile $merged['ProfilesFile'] -StrictConfiguration:([bool]$merged['StrictConfiguration'])
    if (-not $removed) {
      Write-Error -Message "Profile '$DeleteProfile' not found in '$($merged['ProfilesFile'])'." -ErrorAction Continue
      exit 11
    }
    if (-not $merged['Quiet']) {
      Write-Information -InformationAction Continue "Deleted profile '$DeleteProfile' from '$($merged['ProfilesFile'])'."
    }
    if ($PassThru) {
      [pscustomobject]@{
        Mode        = 'DeleteProfile'
        ProfileName = $DeleteProfile
        ProfilesFile = $merged['ProfilesFile']
        Removed     = $true
      }
    }
    exit 0
  }
  catch {
    $exitCode = Resolve-ExitCodeFromException -ErrorRecord $_
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit $exitCode
  }
}

$invokeParams = @{}
foreach ($key in $merged.Keys) {
  $invokeParams[$key] = $merged[$key]
}
$invokeParams['PassThru'] = $true

try {
  $runSummary = Invoke-Iperf3TestSuite @invokeParams
  $exitCode = 0
  if ($runSummary -and $runSummary.PSObject.Properties.Name -contains 'ExitCode') {
    $exitCode = [int]$runSummary.ExitCode
  }

  if (-not $merged['Quiet'] -and $runSummary) {
    $mode = if ($runSummary.PSObject.Properties.Name -contains 'Mode') { [string]$runSummary.Mode } else { 'Run' }
    if ($mode -eq 'Run' -or ($runSummary.PSObject.Properties.Name -contains 'Status')) {
      Write-Information -InformationAction Continue "Final status: $($runSummary.Status) (ExitCode=$exitCode)"
      if ($runSummary.Supplemental) {
        if ($runSummary.Supplemental.SummaryJsonPath) { Write-Information -InformationAction Continue "Summary JSON: $($runSummary.Supplemental.SummaryJsonPath)" }
        if ($runSummary.Supplemental.ReportMdPath) { Write-Information -InformationAction Continue "Report MD  : $($runSummary.Supplemental.ReportMdPath)" }
        if ($runSummary.Supplemental.RunIndexPath) { Write-Information -InformationAction Continue "Run index  : $($runSummary.Supplemental.RunIndexPath)" }
      }
    }
    elseif ($mode -eq 'WhatIf') {
      Write-Information -InformationAction Continue "WhatIf complete. Approx tests: $($runSummary.TotalApprox)"
      Write-Information -InformationAction Continue "CSV  : $($runSummary.CsvPath)"
      Write-Information -InformationAction Continue "JSON : $($runSummary.JsonPath)"
    }
  }

  if ($OpenOutputFolder) {
    $outDirToOpen = $null
    if ($runSummary -and $runSummary.PSObject.Properties.Name -contains 'OutDir') {
      $outDirToOpen = [string]$runSummary.OutDir
    }
    elseif ($runSummary -and $runSummary.PSObject.Properties.Name -contains 'EffectiveParameters' -and $runSummary.EffectiveParameters) {
      $outDirToOpen = [string]$runSummary.EffectiveParameters.OutDir
    }
    if (-not ($IsWindows -or $env:OS -match 'Windows')) {
      Write-Warning 'OpenOutputFolder is only supported on Windows.'
    }
    elseif ($outDirToOpen -and (Test-Path -LiteralPath $outDirToOpen -PathType Container)) {
      Start-Process explorer.exe -ArgumentList $outDirToOpen
    }
    else {
      Write-Warning "Output directory not found: $outDirToOpen"
    }
  }

  if ($PassThru) {
    $runSummary
  }
  exit $exitCode
}
catch {
  $exitCode = Resolve-ExitCodeFromException -ErrorRecord $_
  Write-Error -Message $_.Exception.Message -ErrorAction Continue
  exit $exitCode
}
