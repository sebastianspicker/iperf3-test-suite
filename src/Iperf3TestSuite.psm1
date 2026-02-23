Set-StrictMode -Version Latest

# Default parameter set for Invoke-Iperf3TestSuite (single source for CLI merge)
$script:DefaultInvokeIperf3TestSuiteParams = @{
  Port              = 5201
  Duration           = 10
  Omit               = 1
  MaxJobs            = 1
  OutDir             = $null  # set at runtime in Get-Iperf3TestSuiteDefaultParameterSet
  Quiet                 = $false
  Progress              = $false
  Summary               = $false
  DisableMtuProbe       = $false
  SkipReachabilityCheck = $false
  MtuSizes              = @(1400, 1472, 1600)
  ConnectTimeoutMs   = 60000
  UdpStart           = '1M'
  UdpMax             = '1G'
  UdpStep            = '10M'
  UdpLossThreshold   = 5.0
  TcpStreams         = @(1, 4, 8)
  TcpWindows         = @('default', '128K', '256K')
  DscpClasses         = @('CS0', 'AF11', 'CS5', 'EF', 'AF41')
  IpVersion          = 'Auto'
}

function Get-Iperf3TestSuiteDefaultParameterSet {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param()
  $h = $script:DefaultInvokeIperf3TestSuiteParams.Clone()
  if (-not $h['OutDir']) { $h['OutDir'] = Join-Path (Get-Location) 'logs' }
  return $h
}

function Test-ValidHostnameOrIP {
  <#
  .SYNOPSIS
  Validates that a string is a valid hostname or IP address.

  .DESCRIPTION
  Performs strict validation to prevent argument injection attacks by ensuring
  the input is a valid hostname, IPv4 address, or IPv6 address. This prevents
  passing flags like --config-file or other arguments that iperf3/ping might recognize.

  .PARAMETER Name
  The hostname or IP address string to validate.

  .OUTPUTS
  [bool] Returns $true if the input is a valid hostname or IP address, $false otherwise.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return $false
  }

  # Block any input that starts with a dash (could be a flag)
  if ($Name -match '^-') {
    return $false
  }

  # Valid hostname: alphanumeric, hyphens (not at start/end), dots for subdomains
  # Each label: 1-63 chars, starts/ends with alphanumeric
  if ($Name -match '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$') {
    return $true
  }

  # Valid IPv4: four octets 0-255 separated by dots
  if ($Name -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') {
    $octets = $Name.Split('.')
    foreach ($octet in $octets) {
      $val = [int]$octet
      if ($val -lt 0 -or $val -gt 255) {
        return $false
      }
    }
    return $true
  }

  # Valid IPv6: simplified pattern for common formats
  # Full form: 8 groups of 4 hex digits, or compressed form with ::
  # Also allow bracketed form [IPv6] used by some tools
  $ipv6Pattern = '^\[?([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,7}:?\]?$|^\[?:(:[0-9a-fA-F]{1,4}){1,7}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}\]?$|^\[?([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}\]?$|^\[?[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})\]?$|^\[?:((:[0-9a-fA-F]{1,4}){1,7}|:)\]?$|^\[?::(ffff(:0{1,4}){0,1}:){0,1}(\d{1,3}\.){3}\d{1,3}\]?$'
  if ($Name -match $ipv6Pattern) {
    return $true
  }

  # Also accept simple IPv6 patterns (e.g., ::1, fe80::1, full addresses)
  if ($Name -match '^\[?[0-9a-fA-F:]+\]?$' -and $Name -replace '\[|\]', '' -match ':') {
    # Basic validation: contains only hex digits and colons (and optional brackets)
    $cleanName = $Name -replace '\[|\]', ''
    # Must have at least one colon for IPv6
    if ($cleanName -match '^[0-9a-fA-F:]+$' -and $cleanName -match ':') {
      # Allow :: shorthand
      return $true
    }
  }

  return $false
}

function New-Iperf3Metric {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param()
  [pscustomobject]@{ TxMbps = $null; RxMbps = $null; Retr = $null; LossPct = $null; JitterMs = $null }
}

function Get-BitsPerSecondMbps {
  [CmdletBinding()]
  [OutputType([double])]
  param(
    [Parameter(Mandatory)]
    [object]$Obj
  )
  if (-not $Obj -or $Obj.PSObject.Properties.Name -notcontains 'bits_per_second') { return $null }
  [math]::Round(($Obj.bits_per_second / 1e6), 2)
}

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
    '^EF$' {
      return (46 -shl 2)
    }
    '^AF([1-4])([1-3])$' {
      $x = [int]$Matches[1]
      $y = [int]$Matches[2]
      $dscp = (8 * $x) + (2 * $y)
      return ($dscp -shl 2)
    }
    default {
      throw "Unknown DSCP class: '$Class'. Expected CS0-CS7, EF, or AFxy (e.g. AF11, AF41)."
    }
  }
}

function ConvertTo-MbitPerSecond {
  [CmdletBinding()]
  [OutputType([double])]
  param(
    [Parameter(Mandatory)]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return 0.0
  }

  $m = [regex]::Match($Value.Trim(), '^(?<n>[0-9]+(\.[0-9]+)?)\s*(?<u>[kKmMgG])?$')
  if (-not $m.Success) {
    throw "Invalid bandwidth format: '$Value' (expected e.g. 500K, 10M, 1G)."
  }

  $n = [double]$m.Groups['n'].Value
  $u = $m.Groups['u'].Value.ToLowerInvariant()

  # If unit is missing, we treat it as M (Mbit/s) to match iperf3-test-suite internal logic,
  # but we MUST ensure it's passed as such to iperf3 later.
  if ([string]::IsNullOrEmpty($u)) { $u = 'm' }

  switch ($u) {
    'g' { return [math]::Round($n * 1000, 3) }
    'k' { return [math]::Round($n / 1000, 3) }
    'm' { return [math]::Round($n, 3) }
    default { return [math]::Round($n, 3) }
  }
}

function Test-Reachability {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$ComputerName,
    [ValidateSet('Auto', 'IPv4', 'IPv6')]
    [Parameter(Mandatory)]
    [string]$Mode
  )

  if (-not $IsWindows) {
    throw "Test-Reachability is currently only supported on Windows due to dependency on ping.exe or Test-Connection behaviors."
  }

  $stacksToTry = switch ($Mode) {
    'IPv4' { @('IPv4') }
    'IPv6' { @('IPv6') }
    default { @('IPv4', 'IPv6') }
  }

  # Strict validation for ComputerName to prevent argument injection
  if (-not (Test-ValidHostnameOrIP -Name $ComputerName)) {
    throw "Invalid ComputerName: '$ComputerName'. Must be a valid hostname or IP address."
  }

  foreach ($stack in $stacksToTry) {
    try {
      if ($stack -eq 'IPv4' -and (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -IPv4 -ErrorAction Stop)) {
        return 'IPv4'
      }
      if ($stack -eq 'IPv6' -and (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -IPv6 -ErrorAction Stop)) {
        return 'IPv6'
      }
    }
    catch {
      try {
        $pingArgs = if ($stack -eq 'IPv4') { @('-4', '-n', 1, $ComputerName) } else { @('-6', '-n', 1, $ComputerName) }
        $null = & ping.exe @pingArgs 2>$null
        if ($LASTEXITCODE -eq 0) { return $stack }
      }
      catch {
        Write-Verbose "ping.exe failed for $stack; continuing to next stack."
      }
    }
  }

  return 'None'
}

function Test-TcpPortAndTrace {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [string]$ComputerName,
    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [int]$Port,
    [ValidateRange(1, 30)]
    [int]$Hops = 5
  )

  $tcp = $null
  $trace = $null

  try {
    $tcp = Test-NetConnection -ComputerName $ComputerName -Port $Port -InformationLevel Detailed -ErrorAction Stop
  }
  catch {
    Write-Verbose "TCP port $Port check failed: $($_.Exception.Message)"
  }

  try {
    $trace = Test-NetConnection -ComputerName $ComputerName -TraceRoute -Hops $Hops -InformationLevel Detailed -ErrorAction Stop
  }
  catch {
    Write-Verbose "Traceroute failed (e.g. ICMP filtered); TCP result still valid."
  }

  [pscustomobject]@{
    Tcp   = $tcp
    Trace = $trace
  }
}

function Test-MtuPayload {
  [CmdletBinding()]
  [OutputType([int[]])]
  param(
    [Parameter(Mandatory)]
    [string]$ComputerName,
    [Parameter(Mandatory)]
    [ValidateSet('IPv4', 'IPv6')]
    [string]$Stack,
    [Parameter(Mandatory)]
    [int[]]$Sizes
  )

  if (-not $IsWindows) {
    throw "Test-MtuPayload is currently only supported on Windows due to dependency on ping.exe."
  }

  # Strict validation for ComputerName to prevent argument injection
  if (-not (Test-ValidHostnameOrIP -Name $ComputerName)) {
    throw "Invalid ComputerName: '$ComputerName'. Must be a valid hostname or IP address."
  }

  $fails = New-Object System.Collections.Generic.List[int]
  foreach ($sz in $Sizes) {
    $pingArgs = if ($Stack -eq 'IPv4') {
      @('-4', '-n', 1, '-f', '-l', $sz, $ComputerName)
    } else {
      @('-6', '-n', 1, '-l', $sz, $ComputerName)
    }
    $null = & ping.exe @pingArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
      [void]$fails.Add($sz)
    }
  }

  return $fails.ToArray()
}

function Get-Iperf3Capability {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param()

  # Capture $LASTEXITCODE immediately after native command, before any pipeline operations
  $verOutput = & iperf3 --version 2>&1
  $capExit = $LASTEXITCODE
  $verText = $verOutput | Select-Object -First 1
  if ($capExit -ne 0) {
    $verText = "iperf3 --version failed (exit code $capExit): $verText"
  }

  $m = [regex]::Match($verText, '\b([0-9]+)\.([0-9]+)\b')

  $bidir = $false
  $maj = $null
  $min = $null

  if ($m.Success) {
    $maj = [int]$m.Groups[1].Value
    $min = [int]$m.Groups[2].Value
    $bidir = ($maj -gt 3) -or ($maj -eq 3 -and $min -ge 7)
  }

  [pscustomobject]@{
    VersionText    = [string]$verText
    Major          = $maj
    Minor          = $min
    BidirSupported = $bidir
  }
}

function Get-JsonSubstringOrNull {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$Text
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
  }

  # Heuristic: Find first '{' and last '}'
  $first = $Text.IndexOf('{')
  $last = $Text.LastIndexOf('}')

  if ($first -ge 0 -and $last -gt $first) {
    $candidate = $Text.Substring($first, $last - $first + 1)
    try {
      $null = ConvertFrom-Json -InputObject $candidate -ErrorAction Stop
      return $candidate
    }
    catch {
      Write-Verbose "Broad JSON extraction failed; falling back to deep scan."
    }
  }

  $maxLen = 1MB
  if ($Text.Length -gt $maxLen) {
    $Text = $Text.Substring(0, $maxLen)
  }

  # Fallback: Nested brace scan for first valid JSON object
  $depth = 0
  $start = -1
  $inString = $false
  $escape = $false
  $quote = [char]0
  $i = 0
  while ($i -lt $Text.Length) {
    $c = $Text[$i]
    if ($inString) {
      if ($escape) { $escape = $false }
      elseif ($c -eq '\') { $escape = $true }  # Backslash escapes the next character in JSON strings
      elseif ($c -eq $quote) { $inString = $false }
      $i++
      continue
    }
    if ($c -eq '"' -or $c -eq "'") {
      $inString = $true
      $quote = $c
      $i++
      continue
    }
    if ($c -eq '{') {
      if ($depth -eq 0) { $start = $i }
      $depth++
      $i++
      continue
    }
    if ($c -eq '}') {
      $depth--
      if ($depth -eq 0 -and $start -ge 0) {
        $candidate = $Text.Substring($start, ($i - $start + 1))
        try {
          $null = ConvertFrom-Json -InputObject $candidate -ErrorAction Stop
          return $candidate
        }
        catch {
          # Keep searching
        }
      }
      $i++
      continue
    }
    $i++
  }

  return $null
}

function Invoke-Iperf3 {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [string]$Server,
    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [int]$Port,
    [Parameter(Mandatory)]
    [ValidateSet('IPv4', 'IPv6')]
    [string]$Stack,
    [Parameter(Mandatory)]
    [ValidateRange(1, 3600)]
    [int]$Duration,
    [Parameter(Mandatory)]
    [ValidateRange(0, 60)]
    [int]$Omit,
    [int]$Tos = 0,
    [Parameter(Mandatory)]
    [ValidateSet('TCP', 'UDP')]
    [string]$Proto,
    [Parameter(Mandatory)]
    [ValidateSet('TX', 'RX', 'BD')]
    [string]$Dir,
    [ValidateRange(1, 128)]
    [int]$Streams = 1,
    [ValidateNotNullOrEmpty()]
    [string]$Win = 'default',
    [ValidateNotNullOrEmpty()]
    [string]$UdpBw = '1M',
    [ValidateRange(1000, 300000)]
    [int]$ConnectTimeoutMs = 60000,
    [Parameter(Mandatory)]
    [pscustomobject]$Caps,
    [scriptblock]$Runner
  )

  # Strict validation for Server to prevent argument injection
  if (-not (Test-ValidHostnameOrIP -Name $Server)) {
    throw "Invalid Server: '$Server'. Must be a valid hostname or IP address."
  }

  $iperfArgs = @('-c', $Server, '-p', $Port, '-t', $Duration, '-O', $Omit, '-J', '--connect-timeout', $ConnectTimeoutMs)
  if ($Stack -eq 'IPv6') { $iperfArgs += '-6' }
  if ($Tos -gt 0) { $iperfArgs += @('-S', $Tos) }

  # Ensure bandwidth always has a unit for iperf3
  $udpBwStr = $UdpBw
  if ($udpBwStr -notmatch '[kKmMgG]$') {
    $udpBwStr = "${udpBwStr}M"
  }

  if ($Proto -eq 'TCP') {
    if ($Dir -eq 'RX') { $iperfArgs += '-R' }
    if ($Dir -eq 'BD') {
      if ($Caps.BidirSupported) { $iperfArgs += '--bidir' }
      else { throw "iperf3 does not support --bidir in this version: $($Caps.VersionText)" }
    }
    if ($Streams -gt 1) { $iperfArgs += @('-P', $Streams) }
    if ($Win -ne 'default') { $iperfArgs += @('-w', $Win) }
  }
  else {
    $iperfArgs += @('-u', '-b', $udpBwStr)
    if ($Dir -eq 'RX') { $iperfArgs += '-R' }
    if ($Dir -eq 'BD') {
      if ($Caps.BidirSupported) { $iperfArgs += '--bidir' }
      else { throw "iperf3 does not support --bidir in this version: $($Caps.VersionText)" }
    }
  }

  # Execute iperf3 or custom Runner.
  # NOTE: When using a custom Runner scriptblock, the Runner is responsible for setting
  # $global:LASTEXITCODE if it wraps a native command. Otherwise, $LASTEXITCODE may not
  # reflect the actual exit code of the iperf3 process.
  if ($null -ne $Runner) {
    $rawLines = & $Runner -IperfArgs $iperfArgs 2>&1
  }
  else {
    $rawLines = & iperf3 @iperfArgs 2>&1
  }
  # Capture $LASTEXITCODE immediately after native command, before any pipeline operations
  $exitCode = $LASTEXITCODE
  $rawText = $rawLines | Out-String

  $jsonObj = $null
  $jsonParseError = $null
  $jsonText = Get-JsonSubstringOrNull -Text $rawText

  if ($null -ne $jsonText) {
    try {
      $jsonObj = ConvertFrom-Json -InputObject $jsonText
    }
    catch {
      $jsonObj = $null
      $jsonParseError = $_.Exception.Message
    }
  }

  return [pscustomobject]@{
    Args           = $iperfArgs
    ExitCode       = $exitCode
    RawLines       = $rawLines
    RawText        = $rawText
    Json           = $jsonObj
    JsonParseError = $jsonParseError
  }
}

function Get-Iperf3Metric {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [object]$Json,
    [Parameter(Mandatory)]
    [ValidateSet('TCP', 'UDP')]
    [string]$Proto,
    [Parameter(Mandatory)]
    [ValidateSet('TX', 'RX', 'BD')]
    [string]$Dir
  )

  if (-not $Json) {
    return New-Iperf3Metric
  }

  $end = $Json.end
  if (-not $end) {
    return New-Iperf3Metric
  }

  $sumSent = $null
  $sumRecv = $null
  $sumUdp = $null

  if ($end.PSObject.Properties.Name -contains 'sum_sent') { $sumSent = $end.sum_sent }
  if ($end.PSObject.Properties.Name -contains 'sum_received') { $sumRecv = $end.sum_received }
  if ($end.PSObject.Properties.Name -contains 'sum') { $sumUdp = $end.sum }

  $txMbps = $null
  $rxMbps = $null
  $retr = $null
  $loss = $null
  $jit = $null

  if ($Proto -eq 'TCP') {
    if ($Dir -eq 'TX' -or $Dir -eq 'BD') {
      $txMbps = Get-BitsPerSecondMbps -Obj $sumSent
      $rxMbps = Get-BitsPerSecondMbps -Obj $sumRecv
    }
    elseif ($Dir -eq 'RX') {
      $rxMbps = Get-BitsPerSecondMbps -Obj $sumRecv
      $txMbps = Get-BitsPerSecondMbps -Obj $sumSent
    }

    if ($sumSent -and ($sumSent.PSObject.Properties.Name -contains 'retransmits')) {
      $retr = [int]$sumSent.retransmits
    }

    return [pscustomobject]@{ TxMbps = $txMbps; RxMbps = $rxMbps; Retr = $retr; LossPct = $null; JitterMs = $null }
  }

  # UDP: support end.sum when sum_sent/sum_received missing; map by Dir; 0 throughput is valid
  $sentBps = $sumSent
  $recvBps = $sumRecv
  if (-not $sentBps -and $sumUdp -and ($sumUdp.PSObject.Properties.Name -contains 'bits_per_second')) {
    $sentBps = $sumUdp
  }
  if (-not $recvBps -and $sumUdp) {
    $recvBps = $sumUdp
  }
  if ($Dir -eq 'TX') {
    $txMbps = Get-BitsPerSecondMbps -Obj $sentBps
    $rxMbps = Get-BitsPerSecondMbps -Obj $recvBps
  }
  elseif ($Dir -eq 'RX') {
    $txMbps = Get-BitsPerSecondMbps -Obj $recvBps
    $rxMbps = Get-BitsPerSecondMbps -Obj $sentBps
  }
  else {
    $txMbps = Get-BitsPerSecondMbps -Obj $sentBps
    $rxMbps = Get-BitsPerSecondMbps -Obj $recvBps
  }

  if ($sumSent -and ($sumSent.PSObject.Properties.Name -contains 'lost_percent')) {
    $loss = [double]$sumSent.lost_percent
  }
  elseif ($sumUdp -and ($sumUdp.PSObject.Properties.Name -contains 'lost_percent')) {
    $loss = [double]$sumUdp.lost_percent
  }

  if ($sumUdp -and ($sumUdp.PSObject.Properties.Name -contains 'jitter_ms')) {
    $jit = [double]$sumUdp.jitter_ms
  }

  return [pscustomobject]@{ TxMbps = $txMbps; RxMbps = $rxMbps; Retr = $null; LossPct = $loss; JitterMs = $jit }
}

function ConvertTo-Iperf3CsvRow {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [int]$No,
    [string]$Proto,
    [string]$Dir,
    [string]$DSCP,
    [int]$Streams,
    [string]$Win,
    [nullable[double]]$ThrTxMbps,
    [nullable[int]]$RetrTx,
    [nullable[double]]$ThrRxMbps,
    [nullable[double]]$LossTxPct,
    [nullable[double]]$JitterMs,
    [string]$Role
  )

  return [pscustomobject][ordered]@{
    No          = $No
    Proto       = $Proto
    Dir         = $Dir
    DSCP        = $DSCP
    Streams     = $Streams
    Win         = $Win
    Thr_TX_Mbps = $ThrTxMbps
    Retr_TX     = $RetrTx
    Thr_RX_Mbps = $ThrRxMbps
    Loss_TX_Pct = $LossTxPct
    Jitter_ms   = $JitterMs
    Role        = $Role
  }
}

function Add-Iperf3TestResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[object]]$AllResultsList,
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[object]]$CsvRowsList,
    [Parameter(Mandatory)]
    [int]$No,
    [Parameter(Mandatory)]
    [ValidateSet('TCP', 'UDP')]
    [string]$Proto,
    [Parameter(Mandatory)]
    [ValidateSet('TX', 'RX', 'BD')]
    [string]$Dir,
    [Parameter(Mandatory)]
    [string]$DSCP,
    [Parameter(Mandatory)]
    [int]$Tos,
    [int]$Streams = 1,
    [string]$Window = '',
    [string]$UdpBw = '',
    [Parameter(Mandatory)]
    [string]$Stack,
    [Parameter(Mandatory)]
    [string]$Target,
    [Parameter(Mandatory)]
    [int]$Port,
    [Parameter(Mandatory)]
    [object]$Run,
    [Parameter(Mandatory)]
    [pscustomobject]$Metrics
  )

  [void]$AllResultsList.Add([pscustomobject]@{
      No       = $No
      Proto    = $Proto
      Dir      = $Dir
      DSCP     = $DSCP
      Tos      = $Tos
      Streams  = $Streams
      Window   = $Window
      UdpBw    = $UdpBw
      Stack    = $Stack
      Target   = $Target
      Port     = $Port
      ExitCode = $Run.ExitCode
      Metrics  = $Metrics
      Args     = $Run.Args
      RawText  = $Run.RawText
    })

  [void]$CsvRowsList.Add(
    (ConvertTo-Iperf3CsvRow -No $No -Proto $Proto -Dir $Dir -DSCP $DSCP -Streams $Streams -Win $Window `
      -ThrTxMbps $Metrics.TxMbps -RetrTx $Metrics.Retr -ThrRxMbps $Metrics.RxMbps -LossTxPct $Metrics.LossPct -JitterMs $Metrics.JitterMs -Role 'end')
  )
}

function Invoke-Iperf3TestSuite {
  <#
  .SYNOPSIS
  Runs a TCP/UDP iperf3 test matrix and writes CSV/JSON artifacts.

  .DESCRIPTION
  Executes a DSCP-marked TCP and UDP test suite (including optional MTU payload probing) against
  an iperf3 server and writes timestamped CSV and JSON outputs to the configured output folder.

  .PARAMETER Target
  Hostname or IP address of the iperf3 server.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [ValidateRange(1, 65535)]
    [int]$Port = 5201,

    [ValidateRange(1, 3600)]
    [int]$Duration = 10,

    [ValidateRange(0, 60)]
    [int]$Omit = 1,

    [ValidateRange(1, 32)]
    [int]$MaxJobs = 1,

    [ValidateNotNullOrEmpty()]
    [string]$OutDir = (Join-Path (Get-Location) 'logs'),

    [switch]$Quiet,

    [switch]$Progress,

    [switch]$Summary,

    [switch]$DisableMtuProbe,

    [switch]$SkipReachabilityCheck,

    [ValidateNotNullOrEmpty()]
    [int[]]$MtuSizes = @(1400, 1472, 1600),

    [ValidateRange(1000, 300000)]
    [int]$ConnectTimeoutMs = 60000,

    [ValidateNotNullOrEmpty()]
    [string]$UdpStart = '1M',

    [ValidateNotNullOrEmpty()]
    [string]$UdpMax = '1G',

    [ValidateNotNullOrEmpty()]
    [string]$UdpStep = '10M',

    [ValidateRange(0, 100)]
    [double]$UdpLossThreshold = 5.0,

    [ValidateNotNullOrEmpty()]
    [int[]]$TcpStreams = @(1, 4, 8),

    [ValidateNotNullOrEmpty()]
    [string[]]$TcpWindows = @('default', '128K', '256K'),

    [ValidateNotNullOrEmpty()]
    [string[]]$DscpClasses = @('CS0', 'AF11', 'CS5', 'EF', 'AF41'),

    [ValidateSet('IPv4', 'IPv6', 'Auto')]
    [string]$IpVersion = 'Auto'
  )

  $oldEap = $ErrorActionPreference
  $ErrorActionPreference = 'Stop'

  try {
    $null = Get-Command iperf3 -ErrorAction Stop
    $null = Get-Command ConvertFrom-Json -ErrorAction Stop
    # ping.exe is required if either reachability check or MTU probe is enabled
    if ((-not ($SkipReachabilityCheck -and $DisableMtuProbe)) -and ($IsWindows -or $env:OS -match 'Windows')) {
      $pingCmd = Get-Command ping.exe -ErrorAction SilentlyContinue
      if (-not $pingCmd) {
        throw "ping.exe is required for reachability check or MTU probe but was not found. Use -SkipReachabilityCheck and -DisableMtuProbe to run without it (Windows only)."
      }
    }

    if (-not $IsWindows) {
      throw "Invoke-Iperf3TestSuite is currently only supported on Windows due to platform-specific tool dependencies (ping.exe, Test-NetConnection)."
    }

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $null = New-Item -ItemType Directory -LiteralPath $OutDir -Force
    $jsonPath = Join-Path -Path $OutDir -ChildPath "iperf3_results_$ts.json"
    $csvPath = Join-Path -Path $OutDir -ChildPath "iperf3_summary_$ts.csv"

    if ($MaxJobs -ne 1) {
      Write-Warning "MaxJobs is currently enforced to 1 to avoid iperf3 server overload and complex job state."
      $MaxJobs = 1
    }

    $caps = Get-Iperf3Capability

    $stack = Test-Reachability -ComputerName $Target -Mode $IpVersion
    if ($stack -eq 'None') {
      if (-not $SkipReachabilityCheck) {
        throw "ICMP reachability to '$Target' failed; aborting. Use -SkipReachabilityCheck to proceed when only TCP is reachable."
      }
      Write-Verbose "ICMP reachability failed; proceeding with TCP port check only."
    }

    $net = Test-TcpPortAndTrace -ComputerName $Target -Port $Port -Hops 5
    if (-not $net -or -not $net.Tcp -or -not $net.Tcp.TcpTestSucceeded) {
      throw "TCP port $Port on '$Target' not reachable; aborting."
    }

    if ($stack -eq 'None') {
      $stack = if ($net.Tcp.RemoteAddress -match ':') { 'IPv6' } else { 'IPv4' }
      Write-Verbose "Using stack $stack from TCP connection."
    }

    $mtuFails = @()
    if (-not $DisableMtuProbe) {
      $mtuFails = Test-MtuPayload -ComputerName $Target -Stack $stack -Sizes $MtuSizes
    }

    $allResults = New-Object System.Collections.Generic.List[object]
    $csvRows = New-Object System.Collections.Generic.List[object]

    $testNo = 0

    foreach ($dscp in $DscpClasses) {
      $tos = Get-TosFromDscpClass -Class $dscp

      foreach ($dir in @('TX', 'RX', 'BD')) {
        if ($dir -eq 'BD' -and -not $caps.BidirSupported) { continue }
        foreach ($s in $TcpStreams) {
          foreach ($w in $TcpWindows) {
            $testNo++
            if ($Progress) { Write-Information -InformationAction Continue "Running test $testNo (TCP $dir $dscp P=$s w=$w)..." }

            $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
              -Tos $tos -Proto 'TCP' -Dir $dir -Streams $s -Win $w -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
            $m = Get-Iperf3Metric -Json $run.Json -Proto 'TCP' -Dir $dir
            Add-Iperf3TestResult -AllResultsList $allResults -CsvRowsList $csvRows -No $testNo -Proto 'TCP' -Dir $dir -DSCP $dscp -Tos $tos -Streams $s -Window $w -Stack $stack -Target $Target -Port $Port -Run $run -Metrics $m
          }
        }
      }

      foreach ($dir in @('TX', 'RX')) {
        $testNo++
        if ($Progress) { Write-Information -InformationAction Continue "Running test $testNo (UDP $dir $dscp)..." }

        $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
          -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $UdpStart -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
        $m = Get-Iperf3Metric -Json $run.Json -Proto 'UDP' -Dir $dir
        Add-Iperf3TestResult -AllResultsList $allResults -CsvRowsList $csvRows -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Tos $tos -Window '' -UdpBw $UdpStart -Stack $stack -Target $Target -Port $Port -Run $run -Metrics $m
      }

      $cur = ConvertTo-MbitPerSecond $UdpStart
      $max = ConvertTo-MbitPerSecond $UdpMax
      $step = [math]::Max((ConvertTo-MbitPerSecond $UdpStep), 1)
      if ($max -lt $cur) { $max = $cur }
      # Safety limit: maximum UDP saturation iterations to prevent infinite loops
      # even if loss threshold is never reached (e.g., due to parse failures)
      $maxUdpIterations = 1000

      foreach ($dir in @('TX', 'RX')) {
        $bw = $cur
        $iterations = 0
        while ($bw -le $max -and $iterations -lt $maxUdpIterations) {
          $iterations++
          $testNo++
          if ($Progress) { Write-Information -InformationAction Continue "Running test $testNo (UDP saturation $dir $dscp $bw Mbit/s)..." }
          $bwStr = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}M', $bw)

          $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
            -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $bwStr -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
          $m = Get-Iperf3Metric -Json $run.Json -Proto 'UDP' -Dir $dir
          Add-Iperf3TestResult -AllResultsList $allResults -CsvRowsList $csvRows -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Tos $tos -Window '' -UdpBw $bwStr -Stack $stack -Target $Target -Port $Port -Run $run -Metrics $m

          if ($run.ExitCode -ne 0 -and $null -eq $run.Json) {
            break
          }
          if ($null -ne $m.LossPct -and [double]$m.LossPct -gt $UdpLossThreshold) {
            break
          }

          $bw += $step
        }
      }
    }

    $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $final = [pscustomobject]@{
      Timestamp      = $ts
      Target         = $Target
      Port           = $Port
      Stack          = $stack
      Iperf3Version  = $caps.VersionText
      BidirSupported = $caps.BidirSupported
      MtuProbe       = [pscustomobject]@{
        Enabled     = (-not $DisableMtuProbe)
        Sizes       = $MtuSizes
        FailedSizes = @($mtuFails)
      }
      NetConnection  = [pscustomobject]@{
        TcpTestSucceeded = $net.Tcp.TcpTestSucceeded
        RemoteAddress    = $net.Tcp.RemoteAddress
        PingSucceeded    = $net.Tcp.PingSucceeded
        TraceRoute       = if ($net.Trace) { $net.Trace.TraceRoute } else { $null }
      }
      Results        = $allResults.ToArray()
    }

    $final | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    if (-not $Quiet) {
      Write-Information -InformationAction Continue "CSV  : $csvPath"
      Write-Information -InformationAction Continue "JSON : $jsonPath"
      if ($Summary) {
        Write-Information -InformationAction Continue "Tests: $testNo total"
      }
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
  }
}

Export-ModuleMember -Function Invoke-Iperf3TestSuite
