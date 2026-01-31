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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src/Iperf3TestSuite.psd1'
Import-Module $modulePath -Force

Invoke-Iperf3TestSuite @PSBoundParameters
