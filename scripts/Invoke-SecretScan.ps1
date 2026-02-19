<#
.SYNOPSIS
Lightweight secret scan over the repository (no output of matches).

.DESCRIPTION
Scans files for common secret patterns. Excludes .git directory (path-agnostic).
Use in CI and locally; exits with 1 if any pattern is found.
#>
[CmdletBinding()]
param(
  [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) '.')
)

$ErrorActionPreference = 'Stop'

$patterns = @(
  '-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----',
  'AKIA[0-9A-Z]{16}',
  'ASIA[0-9A-Z]{16}',
  'ghp_[A-Za-z0-9]{36}',
  'github_pat_[A-Za-z0-9_]{22,}',
  'xox[baprs]-[A-Za-z0-9-]{10,48}'
)

$hitCount = 0
$files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object {
    $full = $_.FullName
    $parts = $full -split [IO.Path]::DirectorySeparatorChar
    $parts -notcontains '.git'
  }

foreach ($pattern in $patterns) {
  $hits = $files | Select-String -Pattern $pattern
  if ($hits) {
    $hitCount += $hits.Count
  }
}

if ($hitCount -gt 0) {
  Write-Error "Potential secrets detected ($hitCount). Review locally; output suppressed."
  exit 1
}
Write-Verbose "Secret scan: no matches."
