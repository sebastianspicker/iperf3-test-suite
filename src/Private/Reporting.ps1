# Report and summary helpers (private to Iperf3TestSuite)

function Build-RunSummary {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [object[]]$Results,
    [Parameter(Mandatory)]
    [int]$TestCount,
    [Parameter(Mandatory)]
    [int]$ParseErrorCount,
    [Parameter(Mandatory)]
    [string]$Target,
    [Parameter(Mandatory)]
    [int]$Port,
    [Parameter(Mandatory)]
    [string]$Stack,
    [Parameter(Mandatory)]
    [string]$Timestamp,
    [Parameter(Mandatory)]
    [string]$OutDir
  )
  $failed = @($Results | Where-Object { $_.ExitCode -ne 0 })
  $succeededCount = $TestCount - $failed.Count
  if ($succeededCount -lt 0) { $succeededCount = 0 }
  $status = if ($TestCount -eq 0 -or $failed.Count -eq $TestCount) { 'TotalFailure' } elseif ($failed.Count -gt 0) { 'PartialFailure' } else { 'Success' }
  $statusCode = switch ($status) {
    'Success' { 0 }
    'PartialFailure' { 14 }
    default { 15 }
  }
  $topFailures = @(
    $failed |
      Select-Object -First 10 |
      ForEach-Object {
        [pscustomobject]@{
          No             = $_.No
          Proto          = $_.Proto
          Dir            = $_.Dir
          DSCP           = $_.DSCP
          ExitCode       = $_.ExitCode
          JsonParseError = $_.JsonParseError
        }
      }
  )
  return [pscustomobject]@{
    SummaryVersion  = 1
    Timestamp       = $Timestamp
    OutDir          = $OutDir
    Target          = $Target
    Port            = $Port
    Stack           = $Stack
    Status          = $status
    ExitCode        = $statusCode
    Counts          = [pscustomobject]@{
      Total       = $TestCount
      Succeeded   = $succeededCount
      Failed      = $failed.Count
      ParseErrors = $ParseErrorCount
    }
    TopFailures     = $topFailures
    Supplemental    = [pscustomobject]@{
      SummaryJsonPath = $null
      ReportMdPath    = $null
      RunIndexPath    = $null
    }
  }
}

function Write-Iperf3SupplementalReports {
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$RunSummary,
    [Parameter(Mandatory)]
    [string]$OutDir,
    [Parameter(Mandatory)]
    [string]$Timestamp
  )
  $summaryPath = Join-Path -Path $OutDir -ChildPath "iperf3_summary_$Timestamp.json"
  $reportPath = Join-Path -Path $OutDir -ChildPath "iperf3_report_$Timestamp.md"

  $RunSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('# iperf3 Test Run Report')
  [void]$lines.Add('')
  [void]$lines.Add("Timestamp: $($RunSummary.Timestamp)")
  [void]$lines.Add("Target: $($RunSummary.Target):$($RunSummary.Port)")
  [void]$lines.Add("Stack: $($RunSummary.Stack)")
  [void]$lines.Add("Status: $($RunSummary.Status)")
  [void]$lines.Add('')
  [void]$lines.Add('## Counts')
  [void]$lines.Add("- Total: $($RunSummary.Counts.Total)")
  [void]$lines.Add("- Succeeded: $($RunSummary.Counts.Succeeded)")
  [void]$lines.Add("- Failed: $($RunSummary.Counts.Failed)")
  [void]$lines.Add("- JSON parse errors: $($RunSummary.Counts.ParseErrors)")
  [void]$lines.Add('')
  [void]$lines.Add('## Top failures')
  if (@($RunSummary.TopFailures).Count -eq 0) {
    [void]$lines.Add('No failed tests.')
  }
  else {
    foreach ($f in $RunSummary.TopFailures) {
      [void]$lines.Add("- #$($f.No) $($f.Proto)/$($f.Dir) DSCP=$($f.DSCP) ExitCode=$($f.ExitCode) ParseError=$($f.JsonParseError)")
    }
  }
  [void]$lines.Add('')
  [void]$lines.Add('## Files')
  [void]$lines.Add("- Summary JSON: $summaryPath")
  [void]$lines.Add("- This report: $reportPath")
  Set-Content -LiteralPath $reportPath -Encoding UTF8 -Value ($lines -join [Environment]::NewLine)

  return [pscustomobject]@{
    SummaryJsonPath = $summaryPath
    ReportMdPath    = $reportPath
  }
}

function Write-Iperf3RunIndex {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$OutDir,
    [Parameter(Mandatory)]
    [pscustomobject]$RunSummary,
    [Parameter(Mandatory)]
    [string]$CsvPath,
    [Parameter(Mandatory)]
    [string]$JsonPath,
    [Parameter(Mandatory)]
    [string]$SummaryJsonPath,
    [Parameter(Mandatory)]
    [string]$ReportMdPath
  )
  $indexPath = Join-Path -Path $OutDir -ChildPath 'iperf3_run_index.json'
  $index = [ordered]@{
    schemaVersion = 1
    updatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
    lastRun       = [ordered]@{
      timestamp       = $RunSummary.Timestamp
      status          = $RunSummary.Status
      exitCode        = $RunSummary.ExitCode
      target          = $RunSummary.Target
      port            = $RunSummary.Port
      stack           = $RunSummary.Stack
      csvPath         = $CsvPath
      jsonPath        = $JsonPath
      summaryJsonPath = $SummaryJsonPath
      reportMdPath    = $ReportMdPath
    }
  }
  $index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $indexPath -Encoding UTF8
  return $indexPath
}
