# DSCP and bandwidth conversion helpers (private to Iperf3TestSuite)

function Get-TosFromDscpClass {
  [CmdletBinding()]
  [OutputType([int])]
  param(
    [Parameter(Mandatory)]
    [string]$Class
  )
  switch -Regex ($Class) {
    '^CS([0-7])$' {
      $cs = [int]$Matches[1]
      $dscp = 8 * $cs
      return ($dscp -shl 2)
    }
    '^EF$' { return (46 -shl 2) }
    '^AF([1-4])([1-3])$' {
      $x = [int]$Matches[1]
      $y = [int]$Matches[2]
      $dscp = (8 * $x) + (2 * $y)
      return ($dscp -shl 2)
    }
    default { throw "Unknown DSCP class: '$Class'. Expected CS0-CS7, EF, or AFxy (e.g. AF11, AF41)." }
  }
}

function ConvertTo-MbitPerSecond {
  [CmdletBinding()]
  [OutputType([double])]
  param(
    [Parameter(Mandatory)]
    [string]$Value
  )
  if ([string]::IsNullOrWhiteSpace($Value)) { return 0.0 }
  $m = [regex]::Match($Value.Trim(), '^(?<n>[0-9]+(\.[0-9]+)?)\s*(?<u>[kKmMgG])?$')
  if (-not $m.Success) {
    throw "Invalid bandwidth format: '$Value' (expected e.g. 500K, 10M, 1G)."
  }
  $n = [double]$m.Groups['n'].Value
  $u = $m.Groups['u'].Value.ToLowerInvariant()
  if ([string]::IsNullOrEmpty($u)) { $u = 'm' }
  switch ($u) {
    'g' { return [math]::Round($n * 1000, 3) }
    'k' { return [math]::Round($n / 1000, 3) }
    'm' { return [math]::Round($n, 3) }
    default { return [math]::Round($n, 3) }
  }
}
