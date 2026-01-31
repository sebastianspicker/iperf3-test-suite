[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
  Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -Confirm:$false
}

if (-not (Get-Module -ListAvailable -Name Pester)) {
  Install-Module Pester -Scope CurrentUser -Force -Confirm:$false
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Invoke-ScriptAnalyzer -Path $repoRoot -Recurse
Invoke-Pester -Path $repoRoot
