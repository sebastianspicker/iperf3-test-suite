# Common utility helpers (private to Iperf3TestSuite)

function ConvertTo-Iperf3HashtableFromObject {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Parameter(Mandatory)]
    [object]$InputObject
  )
  if ($InputObject -is [hashtable]) { return $InputObject }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $InputObject.Keys) { $h[[string]$k] = $InputObject[$k] }
    return $h
  }
  $h = @{}
  if ($null -eq $InputObject) { return $h }
  foreach ($p in $InputObject.PSObject.Properties) {
    $h[$p.Name] = $p.Value
  }
  return $h
}
