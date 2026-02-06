# CI Overview

## Workflows
- `CI` (`.github/workflows/ci.yml`)
  - Triggers: `pull_request`, `push` to `main`, and `workflow_dispatch`
  - Runner: `windows-latest`
  - Checks: lightweight secret scan, PSScriptAnalyzer, Pester (offline unit tests)

## Local Run
Prerequisites:
- PowerShell 7+
- Access to PowerShell Gallery (`Install-Module`)
  - The script bootstraps PSGallery and the NuGet provider automatically.

Run the same checks as CI:

```bash
./scripts/ci-local.sh
```

Or directly in PowerShell:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-QualityGates.ps1
```

Optional version overrides (used by CI too):
- `PSSCRIPTANALYZER_VERSION`
- `PESTER_VERSION`

## Caching
The CI workflow caches PowerShell modules in the user module directory and keys the cache by:
- OS
- `PSSCRIPTANALYZER_VERSION`
- `PESTER_VERSION`

## Secrets and Repo Settings
- No secrets are required for the current CI.
- If future integration tests need secrets, add them at repo level and keep those jobs off fork PRs.

## Extending CI
- Add fast, deterministic checks to the existing `CI` workflow.
- For integration tests:
  - Use a separate workflow with `workflow_dispatch` and/or a schedule.
  - Prefer a self-hosted runner with `iperf3` installed and network access to the target server.
  - Never run those jobs on fork PRs.

## Optional: act
Local GitHub Actions emulation with `act` is possible, but Windows runners are not supported by default. Use it only for Linux/macOS checks or with a compatible runner image.
