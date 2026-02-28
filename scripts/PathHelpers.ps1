<#
.SYNOPSIS
Shared path helper utilities for CLI/GUI scripts.
#>

function Test-PathUnderBase {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$BasePath,
    [Parameter(Mandatory)]
    [string]$CandidatePath
  )
  $baseFull = [System.IO.Path]::GetFullPath($BasePath)
  $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
  $separators = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $baseWithSeparator = $baseFull.TrimEnd($separators) + [System.IO.Path]::DirectorySeparatorChar
  $comparison = if ($IsWindows -or $env:OS -match 'Windows') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $candidateFull.Equals($baseFull, $comparison) -or $candidateFull.StartsWith($baseWithSeparator, $comparison)
}

function Resolve-ConfigPath {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$Path,
    [string]$BasePath = (Get-Location).Path,
    [switch]$RequireExistingFile
  )
  $base = [System.IO.Path]::GetFullPath($BasePath)
  $resolved = if ([System.IO.Path]::IsPathRooted($Path)) {
    [System.IO.Path]::GetFullPath($Path)
  }
  else {
    $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $Path))
    if (-not (Test-PathUnderBase -BasePath $base -CandidatePath $candidate)) {
      throw "Configuration path must be under the current directory. Resolved: $candidate"
    }
    $candidate
  }
  if ($RequireExistingFile -and -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Configuration path is not a file: $resolved"
  }
  return $resolved
}
