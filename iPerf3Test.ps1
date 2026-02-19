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
- Defaults are taken from the module (single source); only explicitly passed parameters override.
- Run as script (pwsh -File). Do not dot-source to avoid leaking StrictMode/ErrorActionPreference.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$Target,

  [ValidateRange(1, 65535)]
  [int]$Port,

  [ValidateRange(1, 3600)]
  [int]$Duration,

  [ValidateRange(0, 60)]
  [int]$Omit,

  [ValidateRange(1, 32)]
  [int]$MaxJobs,

  [ValidateNotNullOrEmpty()]
  [string]$OutDir,

  [switch]$Quiet,

  [switch]$Progress,

  [switch]$Summary,

  [switch]$DisableMtuProbe,

  [switch]$SkipReachabilityCheck,

  [ValidateNotNullOrEmpty()]
  [int[]]$MtuSizes,

  [ValidateRange(1000, 300000)]
  [int]$ConnectTimeoutMs,

  [ValidateNotNullOrEmpty()]
  [string]$UdpStart,

  [ValidateNotNullOrEmpty()]
  [string]$UdpMax,

  [ValidateNotNullOrEmpty()]
  [string]$UdpStep,

  [ValidateRange(0, 100)]
  [double]$UdpLossThreshold,

  [ValidateNotNullOrEmpty()]
  [int[]]$TcpStreams,

  [ValidateNotNullOrEmpty()]
  [string[]]$TcpWindows,

  [ValidateNotNullOrEmpty()]
  [string[]]$DscpClasses,

  [ValidateSet('IPv4', 'IPv6', 'Auto')]
  [string]$IpVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src/Iperf3TestSuite.psd1'
Import-Module $modulePath -Force

$merged = Get-Iperf3TestSuiteDefaultParameterSet
foreach ($key in $PSBoundParameters.Keys) {
  $merged[$key] = $PSBoundParameters[$key]
}
Invoke-Iperf3TestSuite @merged
