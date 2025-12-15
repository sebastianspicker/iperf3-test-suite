<# 
iperf3 Windows Suite (PowerShell)
- Reachability (ICMP v4/v6, TCP port)
- Optional MTU payload probe (IPv4 DF, IPv6 payload)
- TCP/UDP matrix incl. DSCP via -S (ToS/TClass)
- Robust JSON parsing with ConvertFrom-Json
- CSV/JSON artifacts

NOTE:
- This script avoids cmd.exe string invocation for ping to reduce injection risk.
- CSV is produced via Export-Csv to guarantee consistent columns/quoting.
#>

[CmdletBinding()]                                                         # Enables -Verbose/-Debug and advanced parameter binding.
param(                                                                    # Begin parameter declaration.
  [Parameter(Mandatory=$true)]                                            # Target is required.
  [ValidateNotNullOrEmpty()]                                              # Reject empty input.
  [string]$Target,                                                        # Hostname or IP address of iperf3 server.

  [ValidateRange(1,65535)]                                                # Port must be valid.
  [int]$Port = 5201,                                                      # Default iperf3 server port.

  [ValidateRange(1,3600)]                                                 # Prevent accidental very long runs.
  [int]$Duration = 10,                                                    # iperf3 -t duration.

  [ValidateRange(0,60)]                                                   # Omit can be 0..60.
  [int]$Omit = 1,                                                         # iperf3 -O omit seconds.

  [ValidateRange(1,32)]                                                   # Keep it bounded.
  [int]$MaxJobs = 1,                                                      # Reserved: script runs sequentially; enforced to 1 for safety.

  [ValidateNotNullOrEmpty()]                                              # Output directory must not be empty.
  [string]$OutDir = (Join-Path (Get-Location) 'logs'),                    # Output folder.

  [switch]$Quiet,                                                         # Suppress host output.

  [switch]$DisableMtuProbe,                                               # Skip MTU/payload probe.

  [ValidateNotNullOrEmpty()]                                              # Ensure list not null.
  [int[]]$MtuSizes = @(1400,1472,1600),                                   # Payload sizes for ping (-l).

  [ValidateRange(1000,300000)]                                            # Connect timeout bounds.
  [int]$ConnectTimeoutMs = 60000,                                         # iperf3 --connect-timeout in ms.

  [ValidateNotNullOrEmpty()]                                              # UDP start must not be empty.
  [string]$UdpStart = '1M',                                               # iperf3 -b start.

  [ValidateNotNullOrEmpty()]                                              # UDP max must not be empty.
  [string]$UdpMax = '1G',                                                 # iperf3 -b max.

  [ValidateNotNullOrEmpty()]                                              # UDP step must not be empty.
  [string]$UdpStep = '10M',                                               # Step size per loop.

  [ValidateRange(0,100)]                                                  # Loss threshold in percent.
  [double]$UdpLossThreshold = 5.0,                                        # Break saturation loop if loss exceeds threshold.

  [ValidateNotNullOrEmpty()]                                              # TCP streams list must not be empty.
  [int[]]$TcpStreams = @(1,4,8),                                          # iperf3 -P.

  [ValidateNotNullOrEmpty()]                                              # TCP windows list must not be empty.
  [string[]]$TcpWindows = @('default','128K','256K'),                     # iperf3 -w (if not default).

  [ValidateNotNullOrEmpty()]                                              # DSCP list must not be empty.
  [string[]]$DscpClasses = @('CS0','AF11','CS5','EF','AF41'),             # DSCP classes.

  [ValidateSet('IPv4','IPv6','Auto')]                                     # User choice.
  [string]$IpVersion = 'Auto'                                             # Default: probe IPv4 first, then IPv6.
)                                                                         # End param block.

Set-StrictMode -Version Latest                                            # Catch uninitialized variables and other issues early.
$ErrorActionPreference = 'Stop'                                           # Treat non-terminating errors as terminating.

# --- Preflight: required commands ---
$null = Get-Command iperf3 -ErrorAction Stop                              # Ensure iperf3 is available.
$null = Get-Command ConvertFrom-Json -ErrorAction Stop                    # Ensure JSON parser cmdlet exists.

# --- Output paths ---
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'                                  # Timestamp for artifact names.
$null = New-Item -ItemType Directory -Path $OutDir -Force                 # Create output folder if missing.
$jsonPath = Join-Path $OutDir "iperf3_results_$ts.json"                   # JSON artifact path.
$csvPath  = Join-Path $OutDir "iperf3_summary_$ts.csv"                    # CSV artifact path.

# --- DSCP -> ToS/TClass (DSCP occupies the upper 6 bits of ToS/TClass; ECN lower 2 bits kept 0) ---
function Get-TosFromDscpClass {                                           # Convert DSCP class name to ToS/TClass byte value.
  [CmdletBinding()]                                                       # Make it advanced for consistency.
  param(
    [Parameter(Mandatory)]                                                # Require a class string.
    [string]$Class                                                        # DSCP class like CS0/AF11/EF.
  )
  switch -Regex ($Class) {                                                # Parse common DSCP strings.
    '^CS([0-7])$' {                                                       # Match CS0..CS7.
      $cs = [int]$Matches[1]                                              # Extract class selector number.
      $dscp = 8 * $cs                                                     # CSn maps to DSCP 8*n.
      return ($dscp -shl 2)                                               # Shift DSCP into ToS/TClass bits (leave ECN=0).
    }
    '^EF$' {                                                              # Expedited Forwarding.
      return (46 -shl 2)                                                  # EF uses DSCP 46.
    }
    '^AF([1-4])([1-3])$' {                                                # Match AFxy (x=class, y=drop precedence).
      $x = [int]$Matches[1]                                               # Extract x.
      $y = [int]$Matches[2]                                               # Extract y.
      $dscp = (8 * $x) + (2 * $y)                                         # AFxy mapping.
      return ($dscp -shl 2)                                               # Shift DSCP to ToS/TClass.
    }
    default {                                                             # Unknown class.
      return 0                                                            # Default ToS/TClass = 0.
    }
  }
}

# --- Parse human bandwidth to Mbps (supports K/M/G) ---
function Convert-ToMbps {                                                 # Convert "10M" / "1G" / "500K" to Mbps numeric.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Value required.
    [string]$Value                                                        # Bandwidth string.
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {                             # Handle empty input defensively.
    return 0                                                              # Return 0 Mbps.
  }

  $m = [regex]::Match($Value.Trim(), '^(?<n>[0-9]+(\.[0-9]+)?)\s*(?<u>[kKmMgG])?$')  # Parse number + unit.
  if (-not $m.Success) {                                                  # If format unknown...
    throw "Invalid bandwidth format: '$Value' (expected e.g. 500K, 10M, 1G)." # Fail fast with a clear message.
  }

  $n = [double]$m.Groups['n'].Value                                       # Numeric part.
  $u = $m.Groups['u'].Value.ToLowerInvariant()                            # Unit part (k/m/g or empty).

  switch ($u) {                                                           # Convert to Mbps.
    'g' { return [math]::Round($n * 1000, 3) }                            # 1G = 1000 Mbps.
    'k' { return [math]::Round($n / 1000, 3) }                            # 1000K = 1 Mbps.
    default { return [math]::Round($n, 3) }                               # M or empty treated as Mbps.
  }
}

# --- ICMP reachability + stack selection ---
function Test-Reachability {                                              # Returns 'IPv4', 'IPv6', or 'None'.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Host required.
    [string]$Host,                                                        # Host to test.
    [ValidateSet('Auto','IPv4','IPv6')]                                   # Mode.
    [string]$Mode                                                         # Requested mode.
  )

  # Prefer Test-Connection; if blocked, fall back to ping.exe exit code.
  try {                                                                   # Try modern cmdlet first.
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {                          # If IPv4 allowed...
      if (Test-Connection -ComputerName $Host -Count 1 -Quiet -IPv4) {    # ICMPv4 probe.
        return 'IPv4'                                                     # IPv4 reachable.
      }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {                          # If IPv6 allowed...
      if (Test-Connection -ComputerName $Host -Count 1 -Quiet -IPv6) {    # ICMPv6 probe.
        return 'IPv6'                                                     # IPv6 reachable.
      }
    }
  }
  catch {                                                                 # If Test-Connection fails (policy, remoting, etc.)...
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {                          # IPv4 fallback.
      $null = & ping.exe -4 -n 1 $Host 2>$null                            # Use ping.exe directly (no cmd.exe).
      if ($LASTEXITCODE -eq 0) {                                          # Exit code indicates success.
        return 'IPv4'                                                     # IPv4 reachable.
      }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {                          # IPv6 fallback.
      $null = & ping.exe -6 -n 1 $Host 2>$null                            # Use ping.exe directly.
      if ($LASTEXITCODE -eq 0) {                                          # Exit code indicates success.
        return 'IPv6'                                                     # IPv6 reachable.
      }
    }
  }

  return 'None'                                                           # Not reachable via tested ICMP method(s).
}

# --- TCP port check + optional traceroute (kept separate due to parameter sets) ---
function Test-TcpPortAndTrace {                                           # Returns object with Tcp + Trace results.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Host required.
    [string]$Host,                                                        # Target host.
    [Parameter(Mandatory)]                                                # Port required.
    [ValidateRange(1,65535)]                                              # Port range.
    [int]$Port,                                                           # TCP port.
    [ValidateRange(1,30)]                                                 # Reasonable hops.
    [int]$Hops = 5                                                        # Traceroute hop limit.
  )

  $tcp  = Test-NetConnection -ComputerName $Host -Port $Port -InformationLevel Detailed   # TCP port test.
  $trace = Test-NetConnection -ComputerName $Host -TraceRoute -Hops $Hops -InformationLevel Detailed # Separate traceroute.

  [pscustomobject]@{                                                      # Return composite object.
    Tcp   = $tcp                                                          # TCP test result.
    Trace = $trace                                                        # Traceroute result.
  }
}

# --- MTU/payload probe (IPv4 uses DF; IPv6 uses payload size only) ---
function Test-MtuPayloadSizes {                                           # Returns payload sizes that fail.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Host required.
    [string]$Host,                                                        # Host to probe.
    [Parameter(Mandatory)]                                                # Stack required.
    [ValidateSet('IPv4','IPv6')]                                          # Only these.
    [string]$Stack,                                                       # Which stack.
    [Parameter(Mandatory)]                                                # Sizes required.
    [int[]]$Sizes                                                         # Payload sizes.
  )

  $fails = New-Object System.Collections.Generic.List[int]                # List of failing sizes.
  foreach ($sz in $Sizes) {                                               # Iterate sizes.
    if ($Stack -eq 'IPv4') {                                              # IPv4 branch.
      $null = & ping.exe -4 -n 1 -f -l $sz $Host 2>$null                  # -f sets DF on IPv4; -l sets payload.
      $ok = ($LASTEXITCODE -eq 0)                                         # Interpret ping success.
    }
    else {                                                                # IPv6 branch.
      $null = & ping.exe -6 -n 1 -l $sz $Host 2>$null                     # IPv6 ping has no DF flag; this is payload probing.
      $ok = ($LASTEXITCODE -eq 0)                                         # Interpret ping success.
    }

    if (-not $ok) {                                                       # If ping failed...
      [void]$fails.Add($sz)                                               # Record failing payload size.
    }
  }

  return $fails                                                           # Return list of failed sizes.
}

# --- Detect iperf3 version and --bidir capability ---
function Get-Iperf3Capabilities {                                         # Returns object with VersionText and BidirSupported.
  [CmdletBinding()]                                                       # Advanced function.
  param()

  $verText = (& iperf3 --version 2>&1 | Select-Object -First 1)           # Read first line of version output.
  $m = [regex]::Match($verText, '\b([0-9]+)\.([0-9]+)\b')                 # Extract major.minor.

  $bidir = $false                                                         # Default: no.
  $maj = $null                                                            # Major placeholder.
  $min = $null                                                            # Minor placeholder.

  if ($m.Success) {                                                       # If version parsed...
    $maj = [int]$m.Groups[1].Value                                        # Major version.
    $min = [int]$m.Groups[2].Value                                        # Minor version.
    $bidir = ($maj -gt 3) -or ($maj -eq 3 -and $min -ge 7)                # --bidir introduced in iperf3 >= 3.7 (common builds).
  }

  [pscustomobject]@{                                                      # Return capabilities.
    VersionText     = [string]$verText                                    # Raw version line.
    Major           = $maj                                                # Parsed major.
    Minor           = $min                                                # Parsed minor.
    BidirSupported  = $bidir                                              # Boolean capability.
  }
}

# --- Extract JSON substring safely (helps if iperf3 prints banners/errors around JSON) ---
function Get-JsonSubstringOrNull {                                        # Returns JSON text or $null.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Input required.
    [string]$Text                                                         # Text possibly containing JSON.
  )

  $first = $Text.IndexOf('{')                                             # Find first JSON brace.
  $last  = $Text.LastIndexOf('}')                                         # Find last JSON brace.

  if ($first -ge 0 -and $last -gt $first) {                               # If braces found in correct order...
    return $Text.Substring($first, ($last - $first + 1))                  # Return the substring candidate.
  }

  return $null                                                            # No JSON braces found.
}

# --- Invoke iperf3 and parse JSON robustly ---
function Invoke-Iperf3 {                                                  # Runs iperf3 with -J and parses JSON.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory)]                                                # Host required.
    [string]$Host,                                                        # Target host.
    [Parameter(Mandatory)]                                                # Port required.
    [ValidateRange(1,65535)]                                              # Port range.
    [int]$Port,                                                           # Target port.
    [Parameter(Mandatory)]                                                # Stack required.
    [ValidateSet('IPv4','IPv6')]                                          # Valid stacks.
    [string]$Stack,                                                       # IPv4/IPv6.
    [Parameter(Mandatory)]                                                # Duration required.
    [ValidateRange(1,3600)]                                               # Duration range.
    [int]$Duration,                                                       # Duration.
    [Parameter(Mandatory)]                                                # Omit required.
    [ValidateRange(0,60)]                                                 # Omit range.
    [int]$Omit,                                                           # Omit seconds.

    [int]$Tos = 0,                                                        # ToS/TClass byte value; 0 = default.

    [Parameter(Mandatory)]                                                # Proto required.
    [ValidateSet('TCP','UDP')]                                            # Proto options.
    [string]$Proto,                                                       # TCP or UDP.

    [Parameter(Mandatory)]                                                # Direction required.
    [ValidateSet('TX','RX','BD')]                                         # Directions.
    [string]$Dir,                                                         # TX, RX (-R), or BD (--bidir if supported).

    [ValidateRange(1,128)]                                                # Streams bound.
    [int]$Streams = 1,                                                    # -P streams for TCP.

    [ValidateNotNullOrEmpty()]                                            # Window string not empty.
    [string]$Win = 'default',                                             # -w window size for TCP.

    [ValidateNotNullOrEmpty()]                                            # UDP bandwidth not empty.
    [string]$UdpBw = '1M',                                                # -b bandwidth for UDP.

    [ValidateRange(1000,300000)]                                          # Timeout bounds.
    [int]$ConnectTimeoutMs = 60000,                                       # iperf3 connect timeout.

    [Parameter(Mandatory)]                                                # Capability info required.
    [object]$Caps                                                        # Capabilities object from Get-Iperf3Capabilities.
  )

  $args = @('-c',$Host,'-p',$Port,'-t',$Duration,'-O',$Omit,'-J','--connect-timeout',$ConnectTimeoutMs) # Base args.
  if ($Stack -eq 'IPv6') { $args += '-6' }                                # Force IPv6 if needed.
  if ($Tos -gt 0) { $args += @('-S', $Tos) }                              # Apply ToS/TClass if requested.

  if ($Proto -eq 'TCP') {                                                 # TCP branch.
    if ($Dir -eq 'RX') { $args += '-R' }                                  # Reverse mode.
    if ($Dir -eq 'BD') {                                                  # Bidirectional requested.
      if ($Caps.BidirSupported) { $args += '--bidir' }                    # Add if supported.
      else { throw "iperf3 does not support --bidir in this version: $($Caps.VersionText)" } # Fail fast.
    }
    if ($Streams -gt 1) { $args += @('-P',$Streams) }                     # Parallel streams.
    if ($Win -ne 'default') { $args += @('-w',$Win) }                     # TCP window if not default.
  }
  else {                                                                  # UDP branch.
    $args += @('-u','-b',$UdpBw)                                          # UDP mode + bandwidth.
    if ($Dir -eq 'RX') { $args += '-R' }                                  # Reverse mode for UDP (supported).
    if ($Dir -eq 'BD') {                                                  # Bidirectional requested (not used by default loops).
      if ($Caps.BidirSupported) { $args += '--bidir' }                    # Add if supported.
      else { throw "iperf3 does not support --bidir in this version: $($Caps.VersionText)" } # Fail fast.
    }
  }

  $rawLines = & iperf3 @args 2>&1                                         # Capture both stdout/stderr lines.
  $rawText  = $rawLines | Out-String                                      # Convert to one string for JSON parsing.

  $jsonObj = $null                                                        # Default null JSON.
  $jsonText = Get-JsonSubstringOrNull -Text $rawText                      # Try to isolate JSON.

  if ($null -ne $jsonText) {                                              # If JSON substring found...
    try {                                                                 # Parse attempt.
      $jsonObj = ConvertFrom-Json -InputObject $jsonText                  # Robust parse: single text blob.
    } catch {                                                             # If parsing fails...
      $jsonObj = $null                                                    # Keep null.
    }
  }

  $exit = $LASTEXITCODE                                                   # Capture process exit code (best-effort).

  return [pscustomobject]@{                                               # Return result bundle.
    Args      = $args                                                     # Effective arguments.
    ExitCode  = $exit                                                     # Exit code.
    RawLines  = $rawLines                                                 # Raw output lines.
    RawText   = $rawText                                                  # Raw output as single string.
    Json      = $jsonObj                                                  # Parsed JSON (or null).
  }
}

# --- Extract metrics from iperf3 JSON (best-effort) ---
function Get-Metrics {                                                    # Normalizes metrics into a consistent object.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [Parameter(Mandatory=$true)]                                          # JSON may be null but param passed.
    [object]$Json,                                                        # Parsed JSON (or $null).
    [Parameter(Mandatory)]                                                # Proto required.
    [ValidateSet('TCP','UDP')]                                            # Proto types.
    [string]$Proto,                                                       # TCP/UDP.
    [Parameter(Mandatory)]                                                # Direction required.
    [ValidateSet('TX','RX','BD')]                                         # Directions.
    [string]$Dir                                                          # Direction.
  )

  if (-not $Json) {                                                       # If JSON missing...
    return [pscustomobject]@{                                             # Return null metrics.
      TxMbps   = $null                                                    # No TX Mbps.
      RxMbps   = $null                                                    # No RX Mbps.
      Retr     = $null                                                    # No retransmits.
      LossPct  = $null                                                    # No loss.
      JitterMs = $null                                                    # No jitter.
    }
  }

  $end = $Json.end                                                        # iperf3 puts summary into .end.
  if (-not $end) {                                                        # If no end section...
    return [pscustomobject]@{ TxMbps=$null; RxMbps=$null; Retr=$null; LossPct=$null; JitterMs=$null } # Return null metrics.
  }

  # Common nodes across many builds:
  $sumSent = $end.sum_sent                                                # Sender summary (commonly present).
  $sumRecv = $end.sum_received                                            # Receiver summary (commonly present).
  $sumUdp  = $end.sum                                                     # UDP combined summary (commonly present for UDP).

  $txMbps = $null                                                         # Default.
  $rxMbps = $null                                                         # Default.
  $retr   = $null                                                         # Default.
  $loss   = $null                                                         # Default.
  $jit    = $null                                                         # Default.

  if ($Proto -eq 'TCP') {                                                 # TCP metrics.
    # Use bits_per_second if present; keep semantics stable by direction.
    if ($Dir -eq 'TX' -or $Dir -eq 'BD') {                                # For TX/BD, expose both summaries if available.
      if ($sumSent -and $sumSent.bits_per_second) {                       # Sender bps present.
        $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)      # Convert to Mbps.
      }
      if ($sumRecv -and $sumRecv.bits_per_second) {                       # Receiver bps present.
        $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)      # Convert to Mbps.
      }
    }
    elseif ($Dir -eq 'RX') {                                              # Reverse mode: primary metric is traffic toward client.
      if ($sumRecv -and $sumRecv.bits_per_second) {                       # Receiver summary bps.
        $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)      # Treat as RX Mbps (remote->local).
      }
      if ($sumSent -and $sumSent.bits_per_second) {                       # Sender summary may still exist.
        $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)      # Keep for completeness.
      }
    }

    if ($sumSent -and ($sumSent.PSObject.Properties.Name -contains 'retransmits')) { # Retransmits property may exist.
      $retr = [int]$sumSent.retransmits                                   # Retransmits count.
    }

    return [pscustomobject]@{                                             # Return TCP metrics.
      TxMbps   = $txMbps                                                  # TX Mbps.
      RxMbps   = $rxMbps                                                  # RX Mbps.
      Retr     = $retr                                                    # Retransmits.
      LossPct  = $null                                                    # Not a standard TCP summary metric.
      JitterMs = $null                                                    # Not a standard TCP summary metric.
    }
  }

  # UDP metrics (loss/jitter may live in different nodes depending on build/options).
  if ($sumSent -and $sumSent.bits_per_second) {                           # Sender bps.
    $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)          # TX Mbps.
  }
  if ($sumRecv -and $sumRecv.bits_per_second) {                           # Receiver bps.
    $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)          # RX Mbps.
  }

  if ($sumSent -and ($sumSent.PSObject.Properties.Name -contains 'lost_percent')) { # Loss on sender summary.
    $loss = [double]$sumSent.lost_percent                                 # Loss percent.
  }
  elseif ($sumUdp -and ($sumUdp.PSObject.Properties.Name -contains 'lost_percent')) { # Loss on combined UDP summary.
    $loss = [double]$sumUdp.lost_percent                                  # Loss percent.
  }

  if ($sumUdp -and ($sumUdp.PSObject.Properties.Name -contains 'jitter_ms')) { # Jitter on UDP summary.
    $jit = [double]$sumUdp.jitter_ms                                      # Jitter milliseconds.
  }

  return [pscustomobject]@{                                               # Return UDP metrics.
    TxMbps   = $txMbps                                                    # TX Mbps.
    RxMbps   = $rxMbps                                                    # RX Mbps.
    Retr     = $null                                                      # Not applicable.
    LossPct  = $loss                                                      # Loss percent.
    JitterMs = $jit                                                       # Jitter ms.
  }
}

# --- CSV row builder (consistent columns) ---
function New-CsvRow {                                                     # Creates an ordered row object for Export-Csv.
  [CmdletBinding()]                                                       # Advanced function.
  param(
    [int]$No,                                                             # Test number.
    [string]$Proto,                                                       # TCP/UDP.
    [string]$Dir,                                                         # TX/RX/BD.
    [string]$DSCP,                                                        # DSCP class.
    [int]$Streams,                                                        # Parallel streams.
    [string]$Win,                                                         # Window size.
    [nullable[double]]$ThrTxMbps,                                         # TX throughput.
    [nullable[int]]$RetrTx,                                               # Retransmits.
    [nullable[double]]$ThrRxMbps,                                         # RX throughput.
    [nullable[double]]$LossTxPct,                                         # UDP loss.
    [nullable[double]]$JitterMs,                                          # UDP jitter.
    [string]$Role                                                         # Role label.
  )

  return [pscustomobject][ordered]@{                                      # Ordered properties = stable CSV column order.
    No           = $No                                                    # Test number.
    Proto        = $Proto                                                 # Protocol.
    Dir          = $Dir                                                   # Direction.
    DSCP         = $DSCP                                                  # DSCP class.
    Streams      = $Streams                                               # Stream count.
    Win          = $Win                                                   # TCP window.
    Thr_TX_Mbps  = $ThrTxMbps                                             # TX throughput.
    Retr_TX      = $RetrTx                                                # TX retransmits.
    Thr_RX_Mbps  = $ThrRxMbps                                             # RX throughput.
    Loss_TX_Pct  = $LossTxPct                                             # TX loss percent (UDP).
    Jitter_ms    = $JitterMs                                              # Jitter ms (UDP).
    Role         = $Role                                                  # Role marker.
  }
}

# --- MAIN ---
if ($MaxJobs -ne 1) {                                                     # Script currently runs sequentially.
  Write-Warning "MaxJobs is currently enforced to 1 to avoid iperf3 server overload and complex job state." # User-facing notice.
  $MaxJobs = 1                                                            # Enforce.
}

$caps = Get-Iperf3Capabilities                                            # Determine iperf3 version/capabilities.

$stack = Test-Reachability -Host $Target -Mode $IpVersion                 # Decide IPv4/IPv6 based on reachability.
if ($stack -eq 'None') {                                                  # If unreachable...
  Write-Warning "ICMP reachability to '$Target' failed; aborting."         # Warn and stop.
  return                                                                  # Abort.
}

$net = Test-TcpPortAndTrace -Host $Target -Port $Port -Hops 5             # Run TCP test + traceroute (separately).
if (-not $net.Tcp.TcpTestSucceeded) {                                     # If port closed/unreachable...
  Write-Warning "TCP port $Port on '$Target' not reachable; aborting."     # Warn and stop.
  return                                                                  # Abort.
}

$mtuFails = @()                                                           # Default empty.
if (-not $DisableMtuProbe) {                                              # If probe enabled...
  $mtuFails = Test-MtuPayloadSizes -Host $Target -Stack $stack -Sizes $MtuSizes # Run payload probe.
}

# Lists for artifacts
$allResults = New-Object System.Collections.Generic.List[object]          # Full JSON-friendly results list.
$csvRows    = New-Object System.Collections.Generic.List[object]          # CSV rows list.

$testNo = 0                                                                # Initialize test counter.

foreach ($dscp in $DscpClasses) {                                         # Iterate DSCP classes.
  $tos = Get-TosFromDscpClass -Class $dscp                                # Convert DSCP class to ToS/TClass value.

  # --- TCP matrix ---
  foreach ($dir in @('TX','RX','BD')) {                                   # Iterate directions.
    if ($dir -eq 'BD' -and -not $caps.BidirSupported) { continue }        # Skip BD if not supported.
    foreach ($s in $TcpStreams) {                                         # Iterate stream counts.
      foreach ($w in $TcpWindows) {                                       # Iterate window sizes.
        $testNo++                                                         # Increment test number.

        $run = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
              -Tos $tos -Proto 'TCP' -Dir $dir -Streams $s -Win $w -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps # Run iperf3.
        $m = Get-Metrics -Json $run.Json -Proto 'TCP' -Dir $dir           # Extract metrics.

        $allResults.Add([pscustomobject]@{                                # Add to JSON list.
          No        = $testNo                                             # Test number.
          Proto     = 'TCP'                                               # Protocol.
          Dir       = $dir                                                # Direction.
          DSCP      = $dscp                                               # DSCP class.
          Tos       = $tos                                                # ToS value.
          Streams   = $s                                                  # Streams.
          Window    = $w                                                  # Window.
          Stack     = $stack                                              # IPv4/IPv6.
          Target    = $Target                                             # Target.
          Port      = $Port                                               # Port.
          ExitCode  = $run.ExitCode                                       # Exit code.
          Metrics   = $m                                                  # Metrics object.
          Args      = $run.Args                                           # Args used.
          RawText   = $run.RawText                                        # Raw output.
        }) | Out-Null                                                     # Suppress return.

        $csvRows.Add(                                                     # Add one consistent CSV row per test.
          (New-CsvRow -No $testNo -Proto 'TCP' -Dir $dir -DSCP $dscp -Streams $s -Win $w `
            -ThrTxMbps $m.TxMbps -RetrTx $m.Retr -ThrRxMbps $m.RxMbps -LossTxPct $null -JitterMs $null -Role 'end')
        ) | Out-Null                                                      # Suppress return.
      }
    }
  }

  # --- UDP normal (TX/RX) ---
  foreach ($dir in @('TX','RX')) {                                        # Only TX and RX for normal UDP.
    $testNo++                                                             # Increment test number.

    $run = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
          -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $UdpStart -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps # Run iperf3.
    $m = Get-Metrics -Json $run.Json -Proto 'UDP' -Dir $dir               # Extract metrics.

    $allResults.Add([pscustomobject]@{                                    # Add to JSON list.
      No        = $testNo                                                 # Test number.
      Proto     = 'UDP'                                                   # Protocol.
      Dir       = $dir                                                    # Direction.
      DSCP      = $dscp                                                   # DSCP class.
      Tos       = $tos                                                    # ToS value.
      Streams   = 1                                                       # Streams.
      Window    = ''                                                      # N/A for UDP.
      UdpBw     = $UdpStart                                               # Requested UDP bandwidth.
      Stack     = $stack                                                  # IPv4/IPv6.
      Target    = $Target                                                 # Target.
      Port      = $Port                                                   # Port.
      ExitCode  = $run.ExitCode                                           # Exit code.
      Metrics   = $m                                                      # Metrics object.
      Args      = $run.Args                                               # Args used.
      RawText   = $run.RawText                                            # Raw output.
    }) | Out-Null                                                         # Suppress return.

    $csvRows.Add(                                                         # Add CSV row.
      (New-CsvRow -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Streams 1 -Win '' `
        -ThrTxMbps $m.TxMbps -RetrTx $null -ThrRxMbps $m.RxMbps -LossTxPct $m.LossPct -JitterMs $m.JitterMs -Role 'end')
    ) | Out-Null                                                          # Suppress return.
  }

  # --- UDP saturation with early-break ---
  $cur  = Convert-ToMbps $UdpStart                                        # Convert start to Mbps.
  $max  = Convert-ToMbps $UdpMax                                          # Convert max to Mbps.
  $step = [math]::Max((Convert-ToMbps $UdpStep), 1)                       # Convert step to Mbps; ensure >=1.
  if ($max -lt $cur) { $max = $cur }                                      # Ensure sane bounds.

  foreach ($dir in @('TX','RX')) {                                        # Iterate direction.
    $bw = $cur                                                           # Start bandwidth.
    while ($bw -le $max) {                                               # Loop until max.
      $testNo++                                                          # Increment test number.
      $bwStr = "{0}M" -f $bw                                             # Convert numeric Mbps to iperf3 string.

      $run = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
            -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $bwStr -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps # Run iperf3.
      $m = Get-Metrics -Json $run.Json -Proto 'UDP' -Dir $dir            # Extract metrics.

      $allResults.Add([pscustomobject]@{                                 # Add to JSON list.
        No        = $testNo                                              # Test number.
        Proto     = 'UDP'                                                # Protocol.
        Dir       = $dir                                                 # Direction.
        DSCP      = $dscp                                                # DSCP class.
        Tos       = $tos                                                 # ToS value.
        Streams   = 1                                                    # Streams.
        Window    = ''                                                   # N/A for UDP.
        UdpBw     = $bwStr                                               # Requested UDP bandwidth.
        Stack     = $stack                                               # IPv4/IPv6.
        Target    = $Target                                              # Target.
        Port      = $Port                                                # Port.
        ExitCode  = $run.ExitCode                                        # Exit code.
        Metrics   = $m                                                   # Metrics object.
        Args      = $run.Args                                            # Args used.
        RawText   = $run.RawText                                         # Raw output.
      }) | Out-Null                                                      # Suppress return.

      $csvRows.Add(                                                      # Add CSV row.
        (New-CsvRow -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Streams 1 -Win '' `
          -ThrTxMbps $m.TxMbps -RetrTx $null -ThrRxMbps $m.RxMbps -LossTxPct $m.LossPct -JitterMs $m.JitterMs -Role 'end')
      ) | Out-Null                                                       # Suppress return.

      if ($null -ne $m.LossPct -and [double]$m.LossPct -gt $UdpLossThreshold) { # Early break on loss.
        break                                                            # Stop saturation for this direction.
      }

      $bw += $step                                                       # Increase bandwidth.
    }
  }
}

# --- Persist artifacts ---
# CSV first (stable schema with Export-Csv)
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8    # Export CSV reliably (quotes/columns handled).

# JSON metadata + results (include preflight info and MTU probe)
$final = [pscustomobject]@{                                               # Build final JSON object.
  Timestamp      = $ts                                                    # Timestamp.
  Target         = $Target                                                # Target host.
  Port           = $Port                                                  # Target port.
  Stack          = $stack                                                 # IPv4/IPv6 selection.
  Iperf3Version  = $caps.VersionText                                      # iperf3 version line.
  BidirSupported = $caps.BidirSupported                                   # Capability flag.
  MtuProbe       = [pscustomobject]@{                                     # MTU/payload probe info.
    Enabled      = (-not $DisableMtuProbe)                                # Whether probe was enabled.
    Sizes        = $MtuSizes                                              # Sizes tested.
    FailedSizes  = @($mtuFails)                                           # Sizes that failed.
  }
  NetConnection  = [pscustomobject]@{                                     # Store TCP/trace snapshot.
    TcpTestSucceeded = $net.Tcp.TcpTestSucceeded                          # TCP test result.
    RemoteAddress    = $net.Tcp.RemoteAddress                             # Resolved remote address.
    PingSucceeded    = $net.Tcp.PingSucceeded                             # Ping flag from Test-NetConnection object.
    TraceRoute       = $net.Trace.TraceRoute                              # Trace route hops (if available).
  }
  Results        = @($allResults)                                         # All test results.
}

$final | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8 # Persist JSON with sufficient depth.

if (-not $Quiet) {                                                        # If not quiet...
  Write-Host "CSV  : $csvPath"                                            # Print CSV path.
  Write-Host "JSON : $jsonPath"                                           # Print JSON path.
}
