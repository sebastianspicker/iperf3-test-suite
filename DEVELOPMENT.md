# Development

## Prerequisites
- PowerShell 7+
- Windows for full runtime coverage (CLI/GUI networking checks)
- `iperf3` client in `PATH` for integration runs

## Local quality gates
```powershell
pwsh -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```

This runs:
- PSScriptAnalyzer (repo-wide, with `PSScriptAnalyzerSettings.psd1`)
- Pester tests (`tests/`)
- Secret scan (`scripts/Invoke-SecretScan.ps1`)

## Manual smoke tests
1. CLI WhatIf preview:
```powershell
pwsh -File .\iPerf3Test.ps1 -Target 127.0.0.1 -WhatIf
```
2. Profile workflow:
```powershell
pwsh -File .\iPerf3Test.ps1 -Target 127.0.0.1 -ProfileName lab -SaveProfile -WhatIf
pwsh -File .\iPerf3Test.ps1 -ListProfiles
pwsh -File .\iPerf3Test.ps1 -DeleteProfile lab
```
3. GUI:
```powershell
pwsh -File .\iPerf3Test-GUI.ps1
```

## Notes
- Keep CLI/module parameters backward compatible.
- New outputs must be additive (do not remove existing CSV/JSON fields).
- Prefer updates in private helper files over growing the module entrypoint.
