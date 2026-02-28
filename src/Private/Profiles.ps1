# Profile storage helpers (private to Iperf3TestSuite)

function Get-DefaultProfilesFilePath {
  [CmdletBinding()]
  [OutputType([string])]
  param()
  return (Join-Path (Join-Path (Get-Location) '.iperf3') 'profiles.json')
}

function Test-Iperf3PathUnderBase {
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

function Resolve-ProfilesFilePath {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [string]$ProfilesFile
  )
  if ([string]::IsNullOrWhiteSpace($ProfilesFile)) {
    return (Get-DefaultProfilesFilePath)
  }
  if ([System.IO.Path]::IsPathRooted($ProfilesFile)) {
    return [System.IO.Path]::GetFullPath($ProfilesFile)
  }
  $base = (Get-Location).Path
  $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $ProfilesFile))
  if (-not (Test-Iperf3PathUnderBase -BasePath $base -CandidatePath $candidate)) {
    throw "Profiles file path must be under the current directory. Resolved: $candidate"
  }
  return $candidate
}

function Get-Iperf3ProfileStorableKeys {
  [CmdletBinding()]
  [OutputType([string[]])]
  param()
  return [string[]]@(
    'Target', 'Port', 'Duration', 'Omit', 'MaxJobs', 'OutDir', 'Quiet', 'Progress', 'Summary',
    'DisableMtuProbe', 'SkipReachabilityCheck', 'Force', 'Protocol', 'SingleTest', 'MtuSizes',
    'ConnectTimeoutMs', 'UdpStart', 'UdpMax', 'UdpStep', 'UdpLossThreshold',
    'TcpStreams', 'TcpWindows', 'DscpClasses', 'IpVersion'
  )
}

function Read-Iperf3ProfilesStore {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Parameter(Mandatory)]
    [string]$ProfilesFile,
    [switch]$StrictConfiguration
  )
  if (-not (Test-Path -LiteralPath $ProfilesFile -PathType Leaf)) {
    return @{
      version    = 1
      updatedUtc = (Get-Date).ToUniversalTime().ToString('o')
      profiles   = @{}
    }
  }
  $raw = Get-Content -LiteralPath $ProfilesFile -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @{
      version    = 1
      updatedUtc = (Get-Date).ToUniversalTime().ToString('o')
      profiles   = @{}
    }
  }
  try {
    $obj = ConvertFrom-Json -InputObject $raw -AsHashtable -ErrorAction Stop
  }
  catch {
    if ($StrictConfiguration) { throw "Profiles file is invalid JSON: $ProfilesFile" }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $backupPath = "$ProfilesFile.corrupt.$stamp.bak"
    try {
      Copy-Item -LiteralPath $ProfilesFile -Destination $backupPath -Force
      Write-Warning "Profiles file is invalid JSON: $ProfilesFile. Backed up to '$backupPath'. Starting with empty profile store."
    }
    catch {
      Write-Warning "Profiles file is invalid JSON: $ProfilesFile. Starting with empty profile store."
    }
    return @{
      version    = 1
      updatedUtc = (Get-Date).ToUniversalTime().ToString('o')
      profiles   = @{}
    }
  }
  $store = ConvertTo-Iperf3HashtableFromObject -InputObject $obj
  if (-not $store.ContainsKey('profiles')) { $store['profiles'] = @{} }
  $store['profiles'] = ConvertTo-Iperf3HashtableFromObject -InputObject $store['profiles']
  if (-not $store.ContainsKey('version')) { $store['version'] = 1 }
  if (-not $store.ContainsKey('updatedUtc')) { $store['updatedUtc'] = (Get-Date).ToUniversalTime().ToString('o') }
  return $store
}

function Write-Iperf3ProfilesStore {
  [CmdletBinding()]
  [OutputType([void])]
  param(
    [Parameter(Mandatory)]
    [string]$ProfilesFile,
    [Parameter(Mandatory)]
    [hashtable]$Store
  )
  $dir = Split-Path -Parent $ProfilesFile
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    $null = New-Item -ItemType Directory -Path $dir -Force
  }
  $Store['updatedUtc'] = (Get-Date).ToUniversalTime().ToString('o')
  $Store | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProfilesFile -Encoding UTF8
}

function Get-Iperf3ProfileNames {
  [CmdletBinding()]
  [OutputType([string[]])]
  param(
    [string]$ProfilesFile,
    [switch]$StrictConfiguration
  )
  $path = Resolve-ProfilesFilePath -ProfilesFile $ProfilesFile
  $store = Read-Iperf3ProfilesStore -ProfilesFile $path -StrictConfiguration:$StrictConfiguration
  return [string[]]@($store['profiles'].Keys | Sort-Object)
}

function Get-Iperf3ProfileParameters {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Parameter(Mandatory)]
    [string]$ProfileName,
    [string]$ProfilesFile,
    [switch]$StrictConfiguration
  )
  $path = Resolve-ProfilesFilePath -ProfilesFile $ProfilesFile
  $store = Read-Iperf3ProfilesStore -ProfilesFile $path -StrictConfiguration:$StrictConfiguration
  if (-not $store['profiles'].ContainsKey($ProfileName)) {
    throw "Profile '$ProfileName' not found in '$path'."
  }
  $rawParams = ConvertTo-Iperf3HashtableFromObject -InputObject $store['profiles'][$ProfileName]
  $allowed = Get-Iperf3ProfileStorableKeys
  $normalized = ConvertTo-Iperf3NormalizedParameterSet -InputParameters $rawParams -AllowedKeys $allowed -StrictConfiguration:$StrictConfiguration
  return $normalized.Parameters
}

function Save-Iperf3Profile {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [string]$ProfileName,
    [Parameter(Mandatory)]
    [hashtable]$Parameters,
    [string]$ProfilesFile,
    [switch]$StrictConfiguration
  )
  if ([string]::IsNullOrWhiteSpace($ProfileName)) {
    throw "ProfileName is required when using -SaveProfile."
  }
  $path = Resolve-ProfilesFilePath -ProfilesFile $ProfilesFile
  $store = Read-Iperf3ProfilesStore -ProfilesFile $path -StrictConfiguration:$StrictConfiguration
  $allowed = Get-Iperf3ProfileStorableKeys
  $toStore = @{}
  foreach ($k in $allowed) {
    if ($Parameters.ContainsKey($k)) { $toStore[$k] = $Parameters[$k] }
  }
  $normalized = ConvertTo-Iperf3NormalizedParameterSet -InputParameters $toStore -AllowedKeys $allowed -StrictConfiguration:$StrictConfiguration
  foreach ($w in $normalized.Warnings) { Write-Warning $w }
  $store['profiles'][$ProfileName] = $normalized.Parameters
  Write-Iperf3ProfilesStore -ProfilesFile $path -Store $store
  return [pscustomobject]@{
    ProfileName = $ProfileName
    ProfilesFile = $path
  }
}

function Remove-Iperf3Profile {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$ProfileName,
    [string]$ProfilesFile,
    [switch]$StrictConfiguration
  )
  $path = Resolve-ProfilesFilePath -ProfilesFile $ProfilesFile
  $store = Read-Iperf3ProfilesStore -ProfilesFile $path -StrictConfiguration:$StrictConfiguration
  if (-not $store['profiles'].ContainsKey($ProfileName)) { return $false }
  $store['profiles'].Remove($ProfileName) | Out-Null
  Write-Iperf3ProfilesStore -ProfilesFile $path -Store $store
  return $true
}
