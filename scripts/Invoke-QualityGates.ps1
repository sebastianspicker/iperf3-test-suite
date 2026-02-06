[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = if ($env:PSSCRIPTANALYZER_VERSION) { $env:PSSCRIPTANALYZER_VERSION } else { '1.24.0' }
$PesterVersion = if ($env:PESTER_VERSION) { $env:PESTER_VERSION } else { '5.7.1' }

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

Install-RequiredModule -Name PSScriptAnalyzer -Version $PsscriptAnalyzerVersion
Install-RequiredModule -Name Pester -Version $PesterVersion

Get-InstalledModule PSScriptAnalyzer,Pester | Select-Object Name, Version, Repository | Format-Table -AutoSize

$repoRoot = Split-Path -Parent $PSScriptRoot
Invoke-ScriptAnalyzer -Path $repoRoot -Recurse
Invoke-Pester -Path $repoRoot -Output Detailed -CI
