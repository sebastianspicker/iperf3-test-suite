# iperf3 Test Suite (PowerShell)

Windows-focused iperf3 client test runner for PowerShell 7+. It executes a TCP/UDP test matrix (with DSCP marking), optional MTU payload probing, and writes timestamped CSV + JSON artifacts.

## Features
- TCP/UDP test matrix with DSCP marking (`-S` / ToS/TClass)
- Optional MTU payload probe via `ping.exe`
- IPv4/IPv6 auto-detection or forced stack
- CSV + JSON output artifacts with consistent columns
- Offline Pester tests (no iperf3/network required)

## Requirements
- PowerShell 7+ (`pwsh`)
- Windows host with networking tools (`Test-NetConnection`, `ping.exe`) unless using `-SkipReachabilityCheck` and `-DisableMtuProbe`
- iperf3 client **3.7+** (for `-J`, `--connect-timeout`; `--bidir` needs 3.7+)
- Reachable iperf3 server (`iperf3 -s`) on the target

Run the CLI with `pwsh -File`; do not dot-source the script (to avoid leaking `StrictMode`/`ErrorActionPreference` into the caller).

## Repo layout
- `iPerf3Test.ps1` — CLI entrypoint (wraps the module)
- `src/Iperf3TestSuite.psm1` — implementation module
- `src/Iperf3TestSuite.psd1` — module manifest
- `tests/Iperf3TestSuite.Tests.ps1` — offline Pester tests
- `scripts/Invoke-QualityGates.ps1` — ScriptAnalyzer + Pester
- `scripts/ci-local.sh` — run same checks as CI (requires Bash: WSL, Git Bash, or macOS/Linux)
- `BUGS_AND_FIXES.md` — known issues and required fixes (use for opening GitHub issues)
- `CHANGELOG.md` — version history

## Quickstart

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

# Skip ICMP reachability (proceed when only TCP port is open)
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -SkipReachabilityCheck
```

## Configuration (Key Parameters)
This list is not exhaustive; see the script help for all options.

- `-Target` (required): iperf3 server hostname or IP.
- `-Port` (default `5201`): iperf3 server port.
- `-Duration` (default `10`): test duration per run.
- `-Omit` (default `1`): omit seconds at test start.
- `-IpVersion` (`Auto|IPv4|IPv6`): network stack selection.
- `-DisableMtuProbe`: skip MTU payload probing.
- `-SkipReachabilityCheck`: skip ICMP; proceed when TCP port check succeeds (useful when ping is blocked).
- `-DscpClasses`: DSCP classes to test (e.g., `CS0`, `AF11`, `EF`).
- `-TcpStreams`, `-TcpWindows`: TCP stream/window matrices.
- `-UdpStart`, `-UdpMax`, `-UdpStep`: UDP bandwidth sweep (Mbit/s, `K/M/G`).
- `-UdpLossThreshold`: break UDP sweep on loss percentage.
- `-OutDir`: output directory for CSV/JSON.
- `-Progress`: print per-test progress (e.g. "Running test N ...").
- `-Summary`: print total test count at the end (with CSV/JSON paths).

## Output
By default outputs to `./logs` (timestamp includes subsecond to avoid overwrites):
- `iperf3_summary_<TIMESTAMP>.csv`
- `iperf3_results_<TIMESTAMP>.json`

## Development
Import the module directly:

```powershell
pwsh -NoProfile -Command "Import-Module .\src\Iperf3TestSuite.psd1 -Force"
```

Run quality gates (installs missing modules for the current user):

```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```

## Testing / Quality Gates
If the modules are missing, install pinned versions for the current user:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Force; Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force"
```

Run ScriptAnalyzer:

```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"
```

Run Pester:

```powershell
pwsh -NoProfile -Command "Invoke-Pester"
```

## Security
Lightweight secret scan (no output of matches); path-agnostic .git exclusion:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SecretScan.ps1
```

Dependency inventory (PowerShell modules):

```powershell
pwsh -NoProfile -Command "Get-InstalledModule PSScriptAnalyzer,Pester | Select-Object Name, Version, Repository | Format-Table -AutoSize"
```

## Validation (build / run / test)
No build step (PowerShell module + script only). Use these to verify the repo:

| Action | Command |
|--------|---------|
| **Lint** | `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"` |
| **Tests** | `pwsh -NoProfile -Command "Invoke-Pester"` |
| **Quality gates** (lint + tests; installs modules if missing) | `pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1` |
| **Same as CI** (Bash) | `./scripts/ci-local.sh` |
| **Run suite** (requires iperf3 server) | `pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -Port 5201` |

See [BUGS_AND_FIXES.md](BUGS_AND_FIXES.md) for known limitations and troubleshooting.

## Troubleshooting
- `iperf3` not found: Ensure the iperf3 client is installed and in `PATH`.
- Reachability failures: By default ICMP must succeed; use `-SkipReachabilityCheck` when only TCP is open. Verify firewall and server.
- ScriptAnalyzer warnings on non-Windows: Run checks on Windows or adjust rules for your environment.
- Missing JSON output: Confirm iperf3 supports `-J` and check for stderr output in `RawText`.

## License
See [LICENSE](LICENSE).
