# RUNBOOK

## Overview
This repository is a PowerShell 7+ test runner for iperf3 on Windows. It includes an entrypoint script, a PowerShell module, and Pester tests.

## Prerequisites
- PowerShell 7+ (`pwsh`)
- Windows host with networking tools (`Test-NetConnection`, `ping.exe`)
- iperf3 client installed on the host running the suite
- Reachable iperf3 server (`iperf3 -s`) on the target

## Setup
No local build step. Install quality gate modules if needed:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Force; Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force"
```

## Fast Loop (local)
Run ScriptAnalyzer and Pester tests:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```

## Lint / Static Analysis (SAST)

```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"
```

## Tests

```powershell
pwsh -NoProfile -Command "Invoke-Pester"
```

## Build
Not applicable (PowerShell module + script only).

## Run (example)

```powershell
pwsh -File .\iPerf3Test.ps1 -Target "iperf3.example.com" -Port 5201
```

## Security Minimum
- Secret scan (lightweight, local):

```powershell
$patterns = @(
  '-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----',
  'AKIA[0-9A-Z]{16}',
  'ASIA[0-9A-Z]{16}',
  'ghp_[A-Za-z0-9]{36}',
  'github_pat_[A-Za-z0-9_]{22,}',
  'xox[baprs]-[A-Za-z0-9-]{10,48}'
)
$files = Get-ChildItem -Recurse -File -Force | Where-Object { $_.FullName -notlike '*\.git\*' }
$hitCount = 0
foreach ($pattern in $patterns) {
  $hits = $files | Select-String -Pattern $pattern
  if ($hits) { $hitCount += $hits.Count }
}
if ($hitCount -gt 0) {
  Write-Error "Potential secrets detected. Review locally; output suppressed."
}
```

- SAST: `Invoke-ScriptAnalyzer` (see above)
- SCA/Deps: No package manifest/lockfile is present; dependencies are runtime modules (`Pester`, `PSScriptAnalyzer`) installed via PowerShell Gallery. Record the installed module inventory:

```powershell
pwsh -NoProfile -Command "Get-InstalledModule PSScriptAnalyzer,Pester | Select-Object Name, Version, Repository | Format-Table -AutoSize"
```

## Full Loop
Run lint + tests + basic secret scan:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
$patterns = @(
  '-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----',
  'AKIA[0-9A-Z]{16}',
  'ASIA[0-9A-Z]{16}',
  'ghp_[A-Za-z0-9]{36}',
  'github_pat_[A-Za-z0-9_]{22,}',
  'xox[baprs]-[A-Za-z0-9-]{10,48}'
)
$files = Get-ChildItem -Recurse -File -Force | Where-Object { $_.FullName -notlike '*\.git\*' }
$hitCount = 0
foreach ($pattern in $patterns) {
  $hits = $files | Select-String -Pattern $pattern
  if ($hits) { $hitCount += $hits.Count }
}
if ($hitCount -gt 0) {
  Write-Error "Potential secrets detected. Review locally; output suppressed."
}
```

## Troubleshooting
- If `Invoke-Pester` fails to find tests, ensure PowerShell 7+ is used and the module can be imported from `src/Iperf3TestSuite.psd1`.
- If ScriptAnalyzer fails on Windows-only cmdlets, run on Windows or adjust rules per environment.
