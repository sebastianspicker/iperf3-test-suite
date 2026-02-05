[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = '1.24.0'
$PesterVersion = '5.7.1'

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

$repoRoot = Split-Path -Parent $PSScriptRoot
Invoke-ScriptAnalyzer -Path $repoRoot -Recurse
Invoke-Pester -Path $repoRoot
