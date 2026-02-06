# CI Decision

## Decision
**LIGHT CI** for PRs and `main` pushes.

## Rationale
- The repo is a PowerShell module with offline Pester tests and static analysis. These checks are fast, deterministic, and safe to run on untrusted PRs.
- Full integration tests require a reachable `iperf3` server and environment-specific networking. That is not reliably reproducible on GitHub-hosted runners.
- No secrets are required for the current checks; therefore PRs can run safely with least-privilege tokens.

## What Runs Where
- **Pull requests (fork-safe):** Secret scan (lightweight), PSScriptAnalyzer, Pester (offline unit tests).
- **Pushes to `main`:** Same as PRs.
- **Manual (`workflow_dispatch`):** Same as PRs, used for ad‑hoc validation.

## Threat Model (CI)
- **Untrusted code in fork PRs:** We run only offline checks and no secrets are injected.
- **No `pull_request_target`:** Avoids elevated permissions on untrusted code.
- **Least privilege token:** `contents: read` and `actions: write` (needed only for caching).
- **Supply chain risk:** PowerShell modules are pinned to exact versions; cache is keyed to versions.

## If We Later Want FULL CI
We would need:
- A **self-hosted Windows runner** (or other controlled environment) with `iperf3` installed.
- **Network access** to a stable `iperf3` server and agreed test data paths/ports.
- Optional secrets/config for target endpoints (if private infra is used).
- A separate integration workflow (manual/scheduled) that never runs on fork PRs.
