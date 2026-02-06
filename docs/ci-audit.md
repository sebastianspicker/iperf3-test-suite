# CI Audit

## Inventory
**Workflow:** `CI` (`.github/workflows/ci.yml`)
- **Triggers:** `push` to `main`, `pull_request` to `main`, `workflow_dispatch`
- **Jobs:**
  - `Quality Gates (Windows)` on `windows-latest`
- **Pinned actions:**
  - `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
  - `actions/cache@0400d5f644dc74513175e3cd8d07132dd4860809` (v4.2.4)
- **Permissions:** `contents: read`, `actions: write` (for cache save)
- **Caching:** PowerShell module cache keyed by OS + module versions
- **Toolchain:** PowerShell 7 (pwsh), Pester 5.7.1, PSScriptAnalyzer 1.24.0
- **Checks:** lightweight secret scan, ScriptAnalyzer, Pester (offline unit tests)

## Last Failed Runs
GitHub Actions API check on **2026-02-06** found **1** run and **0** failures.
- Latest run: `CI` on `push`, run id `21547825292`, conclusion `success` (2026-01-31T17:02:35Z)

## Failure Table
| Workflow | Failure(s) | Root Cause | Fix Plan | Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| CI | None observed | N/A | N/A | N/A | Latest run `21547825292` successful |
