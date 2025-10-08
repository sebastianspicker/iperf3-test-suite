<# iperf3 Windows Suite (PowerShell)
   - MTU probe (IPv4 DF, IPv6 payload)
   - Reachability (ICMP v4/v6, TCP port)
   - TCP/UDP matrix incl. DSCP via -S (ToS/TClass)
   - JSON parsing with ConvertFrom-Json
   - CSV/JSON artifacts
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Target,
  [int]$Port = 5201,
  [int]$Duration = 10,
  [int]$Omit = 1,
  [int]$MaxJobs = 1,
  [string]$OutDir = (Join-Path (Get-Location) 'logs'),
  [switch]$Quiet,
  [switch]$DisableMtuProbe,
  [int[]]$MtuSizes = @(1400,1472,1600),
  [int]$ConnectTimeoutMs = 60000,
  [string]$UdpStart = '1M',
  [string]$UdpMax = '1G',
  [string]$UdpStep = '10M',
  [double]$UdpLossThreshold = 5.0,
  [int[]]$TcpStreams = @(1,4,8),
  [string[]]$TcpWindows = @('default','128K','256K'),
  [string[]]$DscpClasses = @('CS0','AF11','CS5','EF','AF41'),
  [ValidateSet('IPv4','IPv6','Auto')][string]$IpVersion = 'Auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Prereqs
$null = Get-Command iperf3 -ErrorAction Stop
$null = Get-Command ConvertFrom-Json -ErrorAction Stop

# Output
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$null = New-Item -ItemType Directory -Path $OutDir -Force
$jsonPath = Join-Path $OutDir "iperf3_results_$ts.json"
$csvPath  = Join-Path $OutDir "iperf3_summary_$ts.csv"

# DSCP -> ToS/TClass
function Get-TosFromDscpClass {
  param([Parameter(Mandatory)][string]$Class)
  switch -Regex ($Class) {
    '^CS([0-7])$' { $cs=[int]$Matches[1]; $dscp=8*$cs; return ($dscp -shl 2) }
    '^EF$'        { return (46 -shl 2) }
    '^AF([1-4])([1-3])$' { $x=[int]$Matches[1]; $y=[int]$Matches[2]; $dscp=8*$x+2*$y; return ($dscp -shl 2) }
    default { return 0 }
  }
}

# Parse human bandwidth to Mbps
function Convert-ToMbps {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return 0 }
  $m = [regex]::Match($Value,'^(?<n>[0-9.]+)\s*(?<u>[kKmMgG])?$')
  if (-not $m.Success) { return 0 }
  $n = [double]$m.Groups['n'].Value
  switch ($m.Groups['u'].Value.ToLower()) {
    'g' { return [math]::Round($n*1000,2) }
    'k' { return [math]::Round($n/1000,3) }
    default { return [math]::Round($n,3) }
  }
}

# ICMP reachability + stack choice with fallback
function Test-Reachability {
  param([string]$Host,[ValidateSet('Auto','IPv4','IPv6')]$Mode)
  try {
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {
      if (Test-Connection -ComputerName $Host -Count 1 -Quiet -Ipv4) { return 'IPv4' }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {
      if (Test-Connection -ComputerName $Host -Count 1 -Quiet -Ipv6) { return 'IPv6' }
    }
  } catch {
    # Fallback using ping.exe for legacy environments
    if ($Mode -eq 'IPv4' -or $Mode -eq 'Auto') {
      if ((cmd /c "ping -4 -n 1 $Host" | Out-String) -notmatch '100% loss|Zielhost nicht erreichbar|Zeitüberschreitung|timed out') { return 'IPv4' }
    }
    if ($Mode -eq 'IPv6' -or $Mode -eq 'Auto') {
      if ((cmd /c "ping -6 -n 1 $Host" | Out-String) -notmatch '100% loss|Zielhost nicht erreichbar|Zeitüberschreitung|timed out') { return 'IPv6' }
    }
  }
  return 'None'
}

# TCP port check with trace
function Test-TcpPort {
  param([string]$Host,[int]$Port,[int]$Hops = 5)
  return Test-NetConnection -ComputerName $Host -Port $Port -TraceRoute -InformationLevel Detailed -Hops $Hops
}

# MTU multi-probe
function Test-MtuSizes {
  param([string]$Host,[string]$Stack,[int[]]$Sizes)
  $fails = New-Object System.Collections.Generic.List[int]
  foreach ($sz in $Sizes) {
    if ($Stack -eq 'IPv4') {
      $out = cmd /c "ping -4 -n 1 -f -l $sz $Host"
      $ok  = $LASTEXITCODE -eq 0
    } else {
      $out = cmd /c "ping -6 -n 1 -l $sz $Host"
      $ok  = $LASTEXITCODE -eq 0
    }
    if (-not $ok) { [void]$fails.Add($sz) }
  }
  return $fails
}

# iperf3 version and --bidir support
$verText  = (& iperf3 --version 2>&1 | Select-Object -First 1)
$verMatch = [regex]::Match($verText,'\b([0-9]+)\.([0-9]+)\b')
$bidir = $false
if ($verMatch.Success) {
  $maj = [int]$verMatch.Groups[1].Value
  $min = [int]$verMatch.Groups[2].Value
  $bidir = ($maj -gt 3) -or ($maj -eq 3 -and $min -ge 7)
}

# Reachability
$stack = Test-Reachability -Host $Target -Mode $IpVersion
if ($stack -eq 'None') { Write-Warning "ICMP reachability to $Target failed, aborting"; return }
$tcp = Test-TcpPort -Host $Target -Port $Port -Hops 5
if (-not $tcp.TcpTestSucceeded) { Write-Warning "TCP port $Port on $Target not reachable, aborting"; return }

# Optional MTU probe
$mtuFails = @()
if (-not $DisableMtuProbe) { $mtuFails = Test-MtuSizes -Host $Target -Stack $stack -Sizes $MtuSizes }

# CSV header and result list
"No,Proto,Dir,DSCP,Streams,Win,Thr_TX_Mbps,Retr_TX,Thr_RX_Mbps,Loss_TX_Pct,Jitter_ms,Role" | Set-Content -Path $csvPath -Encoding UTF8
$all = New-Object System.Collections.Generic.List[object]
$testNo = 0

# Invoke iperf3 and parse JSON
function Invoke-Iperf3 {
  param(
    [string]$Host,[int]$Port,[string]$Stack,[int]$Duration,[int]$Omit,
    [int]$Tos,[ValidateSet('TCP','UDP')]$Proto,[ValidateSet('TX','RX','BD')]$Dir,
    [int]$Streams = 1,[string]$Win = 'default',[string]$UdpBw = '1M',
    [int]$ConnectTimeoutMs = 60000
  )
  $args = @('-c',$Host,'-p',$Port,'-t',$Duration,'-O',$Omit,'-J','--connect-timeout',$ConnectTimeoutMs)
  if ($Stack -eq 'IPv6') { $args += '-6' }
  if ($Tos -gt 0) { $args += @('-S',$Tos) }
  if ($Proto -eq 'TCP') {
    if ($Dir -eq 'RX') { $args += '-R' }
    if ($Dir -eq 'BD' -and $bidir) { $args += '--bidir' }
    if ($Streams -gt 1) { $args += @('-P',$Streams) }
    if ($Win -ne 'default') { $args += @('-w',$Win) }
  } else {
    $args += @('-u','-b',$UdpBw)
    if ($Dir -eq 'RX') { $args += '-R' }
    if ($Dir -eq 'BD' -and $bidir) { $args += '--bidir' }
  }
  $raw = & iperf3 @args 2>&1
  $obj = $null
  try { $obj = $raw | ConvertFrom-Json } catch { }
  return @{ raw = $raw; json = $obj }
}

function Get-Metrics {
  param([object]$Json,[string]$Proto)
  if (-not $Json) { return [pscustomobject]@{ TxMbps=$null; Retr=$null; RxMbps=$null; LossPct=$null; JitterMs=$null } }
  $end = $Json.end
  $tx = $end.sum_sent
  $rx = $end.sum_received
  if ($Proto -eq 'TCP') {
    $txMbps = if ($tx) { [math]::Round($tx.bits_per_second/1e6,2) } else { $null }
    $rxMbps = if ($rx) { [math]::Round($rx.bits_per_second/1e6,2) } else { $null }
    $retr   = if ($tx.PSObject.Properties.Name -contains 'retransmits') { [int]$tx.retransmits } else { $null }
    return [pscustomobject]@{ TxMbps=$txMbps; Retr=$retr; RxMbps=$rxMbps; LossPct=$null; JitterMs=$null }
  } else {
    $sum = $end.sum
    $lossPct = $null; $jitter = $null
    if ($tx -and $tx.PSObject.Properties.Name -contains 'lost_percent') { $lossPct = [double]$tx.lost_percent }
    elseif ($sum -and $sum.PSObject.Properties.Name -contains 'lost_percent') { $lossPct = [double]$sum.lost_percent }
    if ($sum -and $sum.PSObject.Properties.Name -contains 'jitter_ms') { $jitter = [double]$sum.jitter_ms }
    $txMbps = if ($tx) { [math]::Round($tx.bits_per_second/1e6,2) } else { $null }
    $rxMbps = if ($rx) { [math]::Round($rx.bits_per_second/1e6,2) } else { $null }
    return [pscustomobject]@{ TxMbps=$txMbps; Retr=$null; RxMbps=$rxMbps; LossPct=$lossPct; JitterMs=$jitter }
  }
}

# Matrix execution
foreach ($dscp in $DscpClasses) {
  $tos = Get-TosFromDscpClass -Class $dscp

  # TCP
  foreach ($dir in @('TX','RX','BD')) {
    if ($dir -eq 'BD' -and -not $bidir) { continue }
    foreach ($s in $TcpStreams) {
      foreach ($w in $TcpWindows) {
        $testNo++
        $r = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit -Tos $tos -Proto 'TCP' -Dir $dir -Streams $s -Win $w -ConnectTimeoutMs $ConnectTimeoutMs
        $m = Get-Metrics -Json $r.json -Proto 'TCP'
        $all.Add([pscustomobject]@{ No=$testNo; Proto='TCP'; Dir=$dir; DSCP=$dscp; Streams=$s; Window=$w; TxMbps=$m.TxMbps; Retr=$m.Retr; RxMbps=$m.RxMbps; LossPct=$null; JitterMs=$null; Raw=$r.raw })
        ("{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f $testNo,'TCP',$dir,$dscp,$s,$w,($m.TxMbps),($m.Retr),($m.RxMbps),'','sender') | Add-Content -Path $csvPath -Encoding UTF8
        ("{0},{1},{2},{3},{4},{5},,,{6},,receiver" -f $testNo,'TCP',$dir,$dscp,$s,$w,($m.RxMbps)) | Add-Content -Path $csvPath -Encoding UTF8
      }
    }
  }

  # UDP normal (TX/RX)
  foreach ($dir in @('TX','RX')) {
    $testNo++
    $r = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $UdpStart -ConnectTimeoutMs $ConnectTimeoutMs
    $m = Get-Metrics -Json $r.json -Proto 'UDP'
    $all.Add([pscustomobject]@{ No=$testNo; Proto='UDP'; Dir=$dir; DSCP=$dscp; Streams=1; Window=''; TxMbps=$m.TxMbps; Retr=''; RxMbps=$m.RxMbps; LossPct=$m.LossPct; JitterMs=$m.JitterMs; Raw=$r.raw })
    ("{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f $testNo,'UDP',$dir,$dscp,1,'',($m.TxMbps),'',($m.RxMbps),($m.LossPct),'sender') | Add-Content -Path $csvPath -Encoding UTF8
  }

  # UDP saturation with early-break
  $cur  = Convert-ToMbps $UdpStart
  $max  = Convert-ToMbps $UdpMax
  $step = [math]::Max((Convert-ToMbps $UdpStep),1)
  if ($max -lt $cur) { $max = $cur }
  foreach ($dir in @('TX','RX')) {
    $bw = $cur
    while ($bw -le $max) {
      $testNo++
      $bwStr = "{0}M" -f $bw
      $r = Invoke-Iperf3 -Host $Target -Port $Port -Stack $stack -Duration $Duration -Omit $Omit -Tos $tos -Proto 'UDP' -Dir $dir -UdpBw $bwStr -ConnectTimeoutMs $ConnectTimeoutMs
      $m = Get-Metrics -Json $r.json -Proto 'UDP'
      $all.Add([pscustomobject]@{ No=$testNo; Proto='UDP'; Dir=$dir; DSCP=$dscp; Streams=1; Window=''; TxMbps=$m.TxMbps; Retr=''; RxMbps=$m.RxMbps; LossPct=$m.LossPct; JitterMs=$m.JitterMs; Raw=$r.raw })
      ("{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f $testNo,'UDP',$dir,$dscp,1,'',($m.TxMbps),'',($m.RxMbps),($m.LossPct),'sender') | Add-Content -Path $csvPath -Encoding UTF8
      if ($m.LossPct -ne $null -and [double]$m.LossPct -gt $UdpLossThreshold) { break }
      $bw += $step
    }
  }
}

# Persist results
$all | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
if (-not $Quiet) {
  Write-Host "CSV  : $csvPath"
  Write-Host "JSON : $jsonPath"
}
