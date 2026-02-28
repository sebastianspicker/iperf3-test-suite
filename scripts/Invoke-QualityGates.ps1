<#
.SYNOPSIS
Runs PSScriptAnalyzer and Pester for the repository.
.DESCRIPTION
Installs PSScriptAnalyzer and Pester from PSGallery if missing, then runs analyzer and tests.
If the required modules are already installed (matching version), no install is attempted.
The script fails if modules are missing after the install attempt (no skip-install option).
NOTE: Install-Module -Force -AllowClobber may overwrite existing Pester/PSScriptAnalyzer versions
in CurrentUser scope. Use a dedicated environment or accept overwrite when running this script.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = if ($env:PSSCRIPTANALYZER_VERSION) { $env:PSSCRIPTANALYZER_VERSION } else { '1.24.0' }
$PesterVersion = if ($env:PESTER_VERSION) { $env:PESTER_VERSION } else { '5.7.1' }

function Test-RequiredModuleInstalled {
  param([string]$Name, [string]$Version)
  $m = Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -eq [version]$Version }
  [bool]$m
}

function Initialize-PowerShellGallery {
  $ErrorActionPreference = 'Stop'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch {
    Write-Verbose "TLS 1.2 setting not supported on this platform."
  }
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
  }
  Import-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue | Out-Null
  $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
  if (-not $psgallery) {
    Register-PSRepository -Default
    $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
  }
  # Only notify when we need to install; avoid mutating repo policy
  if ($psgallery -and $psgallery.InstallationPolicy -ne 'Trusted') {
    $needInstall = (-not (Test-RequiredModuleInstalled -Name PSScriptAnalyzer -Version $PsscriptAnalyzerVersion)) -or
                   (-not (Test-RequiredModuleInstalled -Name Pester -Version $PesterVersion))
    if ($needInstall) {
      Write-Verbose "PSGallery is not trusted. Installation might require confirmation or fail in non-interactive sessions."
    }
  }
}

function Install-RequiredModule {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string]$Version
  )
  if (Test-RequiredModuleInstalled -Name $Name -Version $Version) {
    return
  }
  Install-Module $Name -RequiredVersion $Version -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -AcceptLicense -Confirm:$false
}

Initialize-PowerShellGallery
Install-RequiredModule -Name PSScriptAnalyzer -Version $PsscriptAnalyzerVersion
Install-RequiredModule -Name Pester -Version $PesterVersion

$installedModules = Get-Module -ListAvailable -Name PSScriptAnalyzer, Pester |
  Sort-Object Name, Version -Unique |
  Select-Object Name, Version, Path

if (-not $installedModules -or ($installedModules | Where-Object { $_.Name -eq 'PSScriptAnalyzer' }).Count -eq 0 -or ($installedModules | Where-Object { $_.Name -eq 'Pester' }).Count -eq 0) {
  throw 'Required modules not found after installation attempt.'
}

$installedModules | Format-Table -AutoSize

. (Join-Path $PSScriptRoot 'Get-RepoRoot.ps1')
$repoRoot = Get-RepoRoot

$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$analyzerResult = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings $settingsPath
if ($analyzerResult -and $analyzerResult.Count -gt 0) {
  $analyzerResult | Format-Table -AutoSize
  Write-Error "PSScriptAnalyzer reported $($analyzerResult.Count) finding(s)."
  exit 1
}

$pesterOutputDir = Join-Path $repoRoot 'artifacts'
if (-not (Test-Path -LiteralPath $pesterOutputDir -PathType Container)) {
  $null = New-Item -ItemType Directory -Path $pesterOutputDir -Force
}
$pesterResultPath = Join-Path $pesterOutputDir 'testResults.xml'

$pesterConfiguration = [PesterConfiguration]::Default
$pesterConfiguration.Run.Path = $repoRoot
$pesterConfiguration.Run.Exit = $false
$pesterConfiguration.Run.PassThru = $true
$pesterConfiguration.Output.Verbosity = 'Detailed'
$pesterConfiguration.TestResult.Enabled = $true
$pesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
$pesterConfiguration.TestResult.OutputPath = $pesterResultPath
$pesterConfiguration.Should.ErrorAction = 'Stop'

$pesterResult = Invoke-Pester -Configuration $pesterConfiguration
if (-not $pesterResult -or $pesterResult.FailedCount -gt 0) {
  Write-Error "Pester reported $($pesterResult.FailedCount) failed test(s)."
  exit 1
}

& (Join-Path $repoRoot 'scripts/Invoke-SecretScan.ps1') -Path $repoRoot
