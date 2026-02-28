# CSV row and result list helpers (private to Iperf3TestSuite)

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
      No             = $No
      Proto          = $Proto
      Dir            = $Dir
      DSCP           = $DSCP
      Tos            = $Tos
      Streams        = $Streams
      Window         = $Window
      UdpBw          = $UdpBw
      Stack          = $Stack
      Target         = $Target
      Port           = $Port
      ExitCode       = $Run.ExitCode
      Metrics        = $Metrics
      Args           = $Run.Args
      RawText        = $Run.RawText
      JsonParseError = if ($Run.PSObject.Properties.Name -contains 'JsonParseError') { $Run.JsonParseError } else { $null }
    })
  [void]$CsvRowsList.Add(
    (ConvertTo-Iperf3CsvRow -No $No -Proto $Proto -Dir $Dir -DSCP $DSCP -Streams $Streams -Win $Window `
      -ThrTxMbps $Metrics.TxMbps -RetrTx $Metrics.Retr -ThrRxMbps $Metrics.RxMbps -LossTxPct $Metrics.LossPct -JitterMs $Metrics.JitterMs -Role 'end')
  )
}
