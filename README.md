# iperf3 Test Suite (PowerShell)

Windows-first iperf3 client test suite for PowerShell 7+.
It runs TCP/UDP matrices with DSCP, writes CSV/JSON artifacts, and now includes profile management, strict configuration mode, deterministic CLI exit codes, and supplemental run summaries/reports.

## Features
- TCP/UDP matrix execution with DSCP (`-S`) support
- Optional MTU payload probe
- IPv4/IPv6 auto or forced stack
- Profile system: save/load/list reusable run configurations
- CLI profile deletion (`-DeleteProfile`)
- Strict configuration validation (`-StrictConfiguration`)
- Deterministic CLI exit-code mapping for CI automation
- Additive supplemental outputs:
  - `iperf3_summary_<TIMESTAMP>.json`
  - `iperf3_report_<TIMESTAMP>.md`
  - `iperf3_run_index.json` (last-run pointer)
- Windows Forms GUI with tabs:
  - `Run`
  - `Profiles`
  - `Reports`

## Requirements
- PowerShell 7+ (`pwsh`)
- Windows host for full feature set (`Test-NetConnection`, `ping.exe`, WinForms GUI)
- iperf3 client 3.7+
- Reachable iperf3 server (`iperf3 -s`)

## Quickstart (CLI)
```powershell
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -Port 5201
```

### Useful options
```powershell
# Preview without execution
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -WhatIf

# Skip ICMP reachability check
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -SkipReachabilityCheck

# Strict config validation (unknown/invalid config keys become hard errors)
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -StrictConfiguration

# Open output folder after run/preview (Windows)
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -OpenOutputFolder
```

## Profiles
```powershell
# Save current parameters as profile "lab"
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -ProfileName lab -SaveProfile -WhatIf

# List profiles
pwsh -File .\iPerf3Test.ps1 -ListProfiles

# Delete a profile
pwsh -File .\iPerf3Test.ps1 -DeleteProfile lab

# Run with profile (CLI args override profile values)
pwsh -File .\iPerf3Test.ps1 -ProfileName lab -Target "iperf3.example.com"
```

Optional profile file override:
```powershell
pwsh -File .\iPerf3Test.ps1 -ListProfiles -ProfilesFile .\.iperf3\profiles.json
```

## Configuration file
Use `-ConfigurationPath` to merge JSON defaults before explicit CLI args.
Unknown keys are warnings by default, or hard errors with `-StrictConfiguration`.

## Outputs
Standard outputs (unchanged format/fields):
- `iperf3_summary_<TIMESTAMP>.csv`
- `iperf3_results_<TIMESTAMP>.json`

Supplemental additive outputs:
- `iperf3_summary_<TIMESTAMP>.json` (compact machine summary)
- `iperf3_report_<TIMESTAMP>.md` (human-readable report)
- `iperf3_run_index.json` (latest run metadata in output folder)

## CLI exit codes
- `0`: successful run / successful non-run mode (WhatIf/ListProfiles)
- `11`: input/config validation error
- `12`: prerequisite/environment error
- `13`: connectivity precheck error
- `14`: run completed with partial failures
- `15`: run completed with total failures
- `16`: internal/unclassified error

## GUI
```powershell
pwsh -File .\iPerf3Test-GUI.ps1
```

Capabilities:
- Run/WhatIf from `Run` tab
- Validation feedback via inline error indicators
- Profile save/load/delete/list in `Profiles` tab
- Quick-open summary/report/output paths in `Reports` tab
- Progress bar and status line during execution
- Cancel button for running jobs

## Development and quality
See [DEVELOPMENT.md](DEVELOPMENT.md) for local workflows.

One-command quality gate:
```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```

## Repository layout
- `iPerf3Test.ps1` — CLI entrypoint
- `iPerf3Test-GUI.ps1` — WinForms GUI
- `src/Iperf3TestSuite.psm1` — module entrypoint
- `src/Private/*.ps1` — private helpers (validation, profiles, reporting, orchestration, run logic)
- `tests/Iperf3TestSuite.Tests.ps1` — Pester tests
- `scripts/Invoke-QualityGates.ps1` — analyzer + tests + secret scan

## License
See [LICENSE](LICENSE).
