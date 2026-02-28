<#
.SYNOPSIS
Returns the repository root directory (directory that contains the scripts/ folder).
.DESCRIPTION
When run from repo root, returns current directory. When run from scripts/, returns parent directory.
Dot-source this script and call Get-RepoRoot to get the path.
#>
function Get-RepoRoot {
  $current = (Get-Location).Path
  if (Test-Path -LiteralPath (Join-Path $current 'scripts')) {
    return $current
  }
  if ($PSScriptRoot) {
    return (Get-Item $PSScriptRoot).Parent.FullName
  }
  return $current
}
