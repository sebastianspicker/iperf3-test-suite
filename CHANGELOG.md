# Changelog

All notable changes to the **iperf3 Test Suite** (PowerShell) project.

## [Unreleased]

### Added
- PowerShell 7+ test runner: `iPerf3Test.ps1` (CLI) and `src/Iperf3TestSuite.psm1` (module).
- TCP/UDP test matrix with DSCP marking, optional MTU probe, CSV/JSON output.
- Offline Pester tests and CI quality gates (PSScriptAnalyzer + Pester).
- GitHub Actions CI on Windows (secret scan, ScriptAnalyzer, Pester).

### Notes
- Module version in manifest: `0.1.0`.
- For known issues and required fixes, see [BUGS_AND_FIXES.md](BUGS_AND_FIXES.md).
