# iperf3 Test Suite (PowerShell)

Windows-focused iperf3 client test runner written for PowerShell 7+. It runs a TCP/UDP test matrix (including DSCP marking), optional MTU payload probing, and writes timestamped CSV + JSON artifacts.

## Repo layout

- `iPerf3Test.ps1` – CLI entrypoint (wraps the module)
- `src/Iperf3TestSuite.psm1` – implementation module
- `tests/Iperf3TestSuite.Tests.ps1` – offline Pester tests (no iperf3/network required)

## Prerequisites

- PowerShell 7+ (`pwsh`)
- iperf3 client on the machine running the script
- A reachable iperf3 server (`iperf3 -s`) on the target host
- Windows networking cmdlets (`Test-NetConnection`) and `ping.exe` (the script is intended for Windows)

## Run

```powershell
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -Port 5201
```

Common options:

```powershell
# Override output dir
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -OutDir .\logs

# Force IPv4 (or IPv6)
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -IpVersion IPv4

# Disable MTU payload probe
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -DisableMtuProbe
```

## Output

By default outputs to `.\logs`:

- `iperf3_summary_<TIMESTAMP>.csv`
- `iperf3_results_<TIMESTAMP>.json`

## Test / Quality gates

If the modules are missing, install for the current user:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer,Pester -Scope CurrentUser -Force"
```

Run ScriptAnalyzer:

```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"
```

Run Pester:

```powershell
pwsh -NoProfile -Command "Invoke-Pester"
```

Or run both quality gates (auto-installs missing modules for the current user):

```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```
