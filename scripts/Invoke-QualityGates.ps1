[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = if ($env:PSSCRIPTANALYZER_VERSION) { $env:PSSCRIPTANALYZER_VERSION } else { '1.24.0' }
$PesterVersion = if ($env:PESTER_VERSION) { $env:PESTER_VERSION } else { '5.7.1' }

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

  $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
  if (-not $psgallery) {
    Register-PSRepository -Default
    $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
  }

  if ($psgallery -and $psgallery.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  }
}

function Install-RequiredModule {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string]$Version
  )

  $installed = Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -eq [version]$Version }
  if (-not $installed) {
    Install-Module $Name -RequiredVersion $Version -Scope CurrentUser -Force -Confirm:$false
  }
}

Initialize-PowerShellGallery
Install-RequiredModule -Name PSScriptAnalyzer -Version $PsscriptAnalyzerVersion
Install-RequiredModule -Name Pester -Version $PesterVersion

Get-InstalledModule PSScriptAnalyzer,Pester | Select-Object Name, Version, Repository | Format-Table -AutoSize

$repoRoot = Split-Path -Parent $PSScriptRoot
Invoke-ScriptAnalyzer -Path $repoRoot -Recurse
Invoke-Pester -Path $repoRoot -Output Detailed -CI
