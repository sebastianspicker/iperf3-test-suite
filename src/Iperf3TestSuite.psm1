Set-StrictMode -Version Latest

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
      return 0
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

  switch ($u) {
    'g' { return [math]::Round($n * 1000, 3) }
    'k' { return [math]::Round($n / 1000, 3) }
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

  try {
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {
      if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -IPv4) {
        return 'IPv4'
      }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {
      if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -IPv6) {
        return 'IPv6'
      }
    }
  }
  catch {
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {
      $null = & ping.exe -4 -n 1 $ComputerName 2>$null
      if ($LASTEXITCODE -eq 0) {
        return 'IPv4'
      }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {
      $null = & ping.exe -6 -n 1 $ComputerName 2>$null
      if ($LASTEXITCODE -eq 0) {
        return 'IPv6'
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

  $tcp = Test-NetConnection -ComputerName $ComputerName -Port $Port -InformationLevel Detailed
  $trace = Test-NetConnection -ComputerName $ComputerName -TraceRoute -Hops $Hops -InformationLevel Detailed

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

  $fails = New-Object System.Collections.Generic.List[int]
  foreach ($sz in $Sizes) {
    if ($Stack -eq 'IPv4') {
      $null = & ping.exe -4 -n 1 -f -l $sz $ComputerName 2>$null
      $ok = ($LASTEXITCODE -eq 0)
    }
    else {
      $null = & ping.exe -6 -n 1 -l $sz $ComputerName 2>$null
      $ok = ($LASTEXITCODE -eq 0)
    }

    if (-not $ok) {
      [void]$fails.Add($sz)
    }
  }

  return $fails.ToArray()
}

function Get-Iperf3Capability {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param()

  $verText = (& iperf3 --version 2>&1 | Select-Object -First 1)
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

  $startMatches = [regex]::Matches($Text, '\{')
  $endMatches = [regex]::Matches($Text, '\}')

  if ($startMatches.Count -eq 0 -or $endMatches.Count -eq 0) {
    return $null
  }

  $starts = @($startMatches | ForEach-Object { $_.Index })
  $ends = @($endMatches | ForEach-Object { $_.Index })

  foreach ($s in $starts) {
    for ($i = $ends.Count - 1; $i -ge 0; $i--) {
      $e = $ends[$i]
      if ($e -le $s) { break }

      $candidate = $Text.Substring($s, ($e - $s + 1))
      try {
        $null = ConvertFrom-Json -InputObject $candidate -ErrorAction Stop
        return $candidate
      }
      catch {
        continue
      }
    }
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
    [pscustomobject]$Caps
  )

  $iperfArgs = @('-c', $Server, '-p', $Port, '-t', $Duration, '-O', $Omit, '-J', '--connect-timeout', $ConnectTimeoutMs)
  if ($Stack -eq 'IPv6') { $iperfArgs += '-6' }
  if ($Tos -gt 0) { $iperfArgs += @('-S', $Tos) }

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
    $iperfArgs += @('-u', '-b', $UdpBw)
    if ($Dir -eq 'RX') { $iperfArgs += '-R' }
    if ($Dir -eq 'BD') {
      if ($Caps.BidirSupported) { $iperfArgs += '--bidir' }
      else { throw "iperf3 does not support --bidir in this version: $($Caps.VersionText)" }
    }
  }

  $rawLines = & iperf3 @iperfArgs 2>&1
  $rawText = $rawLines | Out-String

  $jsonObj = $null
  $jsonText = Get-JsonSubstringOrNull -Text $rawText

  if ($null -ne $jsonText) {
    try {
      $jsonObj = ConvertFrom-Json -InputObject $jsonText
    }
    catch {
      $jsonObj = $null
    }
  }

  $exitCode = $LASTEXITCODE

  return [pscustomobject]@{
    Args     = $iperfArgs
    ExitCode = $exitCode
    RawLines = $rawLines
    RawText  = $rawText
    Json     = $jsonObj
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
    return [pscustomobject]@{ TxMbps = $null; RxMbps = $null; Retr = $null; LossPct = $null; JitterMs = $null }
  }

  $end = $Json.end
  if (-not $end) {
    return [pscustomobject]@{ TxMbps = $null; RxMbps = $null; Retr = $null; LossPct = $null; JitterMs = $null }
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
      if ($sumSent -and $sumSent.bits_per_second) {
        $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)
      }
      if ($sumRecv -and $sumRecv.bits_per_second) {
        $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)
      }
    }
    elseif ($Dir -eq 'RX') {
      if ($sumRecv -and $sumRecv.bits_per_second) {
        $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)
      }
      if ($sumSent -and $sumSent.bits_per_second) {
        $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)
      }
    }

    if ($sumSent -and ($sumSent.PSObject.Properties.Name -contains 'retransmits')) {
      $retr = [int]$sumSent.retransmits
    }

    return [pscustomobject]@{ TxMbps = $txMbps; RxMbps = $rxMbps; Retr = $retr; LossPct = $null; JitterMs = $null }
  }

  if ($sumSent -and $sumSent.bits_per_second) {
    $txMbps = [math]::Round(($sumSent.bits_per_second / 1e6), 2)
  }
  if ($sumRecv -and $sumRecv.bits_per_second) {
    $rxMbps = [math]::Round(($sumRecv.bits_per_second / 1e6), 2)
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

    [switch]$DisableMtuProbe,

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

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $jsonPath = Join-Path $OutDir "iperf3_results_$ts.json"
    $csvPath = Join-Path $OutDir "iperf3_summary_$ts.csv"

    if ($MaxJobs -ne 1) {
      Write-Warning "MaxJobs is currently enforced to 1 to avoid iperf3 server overload and complex job state."
      $MaxJobs = 1
    }

    $caps = Get-Iperf3Capability

    $stack = Test-Reachability -ComputerName $Target -Mode $IpVersion
    if ($stack -eq 'None') {
      throw "ICMP reachability to '$Target' failed; aborting."
    }

    $net = Test-TcpPortAndTrace -ComputerName $Target -Port $Port -Hops 5
    if (-not $net.Tcp.TcpTestSucceeded) {
      throw "TCP port $Port on '$Target' not reachable; aborting."
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

            $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
              -Tos $tos -Proto 'TCP' -Dir $dir -Streams $s -Win $w -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
            $m = Get-Iperf3Metric -Json $run.Json -Proto 'TCP' -Dir $dir

            $allResults.Add([pscustomobject]@{
              No       = $testNo
              Proto    = 'TCP'
              Dir      = $dir
              DSCP     = $dscp
              Tos      = $tos
              Streams  = $s
              Window   = $w
              Stack    = $stack
              Target   = $Target
              Port     = $Port
              ExitCode = $run.ExitCode
              Metrics  = $m
              Args     = $run.Args
              RawText  = $run.RawText
            }) | Out-Null

            $csvRows.Add(
              (ConvertTo-Iperf3CsvRow -No $testNo -Proto 'TCP' -Dir $dir -DSCP $dscp -Streams $s -Win $w `
                -ThrTxMbps $m.TxMbps -RetrTx $m.Retr -ThrRxMbps $m.RxMbps -LossTxPct $null -JitterMs $null -Role 'end')
            ) | Out-Null
          }
        }
      }

      foreach ($dir in @('TX', 'RX')) {
        $testNo++

        $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
          -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $UdpStart -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
        $m = Get-Iperf3Metric -Json $run.Json -Proto 'UDP' -Dir $dir

        $allResults.Add([pscustomobject]@{
          No       = $testNo
          Proto    = 'UDP'
          Dir      = $dir
          DSCP     = $dscp
          Tos      = $tos
          Streams  = 1
          Window   = ''
          UdpBw    = $UdpStart
          Stack    = $stack
          Target   = $Target
          Port     = $Port
          ExitCode = $run.ExitCode
          Metrics  = $m
          Args     = $run.Args
          RawText  = $run.RawText
        }) | Out-Null

        $csvRows.Add(
          (ConvertTo-Iperf3CsvRow -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Streams 1 -Win '' `
            -ThrTxMbps $m.TxMbps -RetrTx $null -ThrRxMbps $m.RxMbps -LossTxPct $m.LossPct -JitterMs $m.JitterMs -Role 'end')
        ) | Out-Null
      }

      $cur = ConvertTo-MbitPerSecond $UdpStart
      $max = ConvertTo-MbitPerSecond $UdpMax
      $step = [math]::Max((ConvertTo-MbitPerSecond $UdpStep), 1)
      if ($max -lt $cur) { $max = $cur }

      foreach ($dir in @('TX', 'RX')) {
        $bw = $cur
        while ($bw -le $max) {
          $testNo++
          $bwStr = '{0}M' -f $bw

          $run = Invoke-Iperf3 -Server $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit `
            -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $bwStr -ConnectTimeoutMs $ConnectTimeoutMs -Caps $caps
          $m = Get-Iperf3Metric -Json $run.Json -Proto 'UDP' -Dir $dir

          $allResults.Add([pscustomobject]@{
            No       = $testNo
            Proto    = 'UDP'
            Dir      = $dir
            DSCP     = $dscp
            Tos      = $tos
            Streams  = 1
            Window   = ''
            UdpBw    = $bwStr
            Stack    = $stack
            Target   = $Target
            Port     = $Port
            ExitCode = $run.ExitCode
            Metrics  = $m
            Args     = $run.Args
            RawText  = $run.RawText
          }) | Out-Null

          $csvRows.Add(
            (ConvertTo-Iperf3CsvRow -No $testNo -Proto 'UDP' -Dir $dir -DSCP $dscp -Streams 1 -Win '' `
              -ThrTxMbps $m.TxMbps -RetrTx $null -ThrRxMbps $m.RxMbps -LossTxPct $m.LossPct -JitterMs $m.JitterMs -Role 'end')
          ) | Out-Null

          if ($null -ne $m.LossPct -and [double]$m.LossPct -gt $UdpLossThreshold) {
            break
          }

          $bw += $step
        }
      }
    }

    $csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

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
        TraceRoute       = $net.Trace.TraceRoute
      }
      Results        = $allResults.ToArray()
    }

    $final | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

    if (-not $Quiet) {
      Write-Information -InformationAction Continue "CSV  : $csvPath"
      Write-Information -InformationAction Continue "JSON : $jsonPath"
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
  }
}

Export-ModuleMember -Function Invoke-Iperf3TestSuite
