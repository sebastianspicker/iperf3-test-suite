# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- Profile system in module/CLI (`-ProfileName`, `-ProfilesFile`, `-SaveProfile`, `-ListProfiles`).
- CLI profile deletion (`-DeleteProfile`) and optional output-folder opener (`-OpenOutputFolder`, Windows).
- Strict configuration mode (`-StrictConfiguration`) with configurable unknown-key behavior.
- Pass-through execution summary (`-PassThru`) for automation consumers.
- Supplemental additive outputs:
  - `iperf3_summary_<TIMESTAMP>.json`
  - `iperf3_report_<TIMESTAMP>.md`
  - `iperf3_run_index.json`
- New private module layers:
  - `ConfigValidation.ps1`
  - `Profiles.ps1`
  - `Reporting.ps1`
  - `Orchestration.ps1`
- Shared script helper `scripts/PathHelpers.ps1` for path-safe resolution.
- Development guide: `DEVELOPMENT.md`.

### Changed
- `Invoke-Iperf3TestSuite` refactored to an orchestrated flow with plan/build/execute/finalize helper stages.
- Module error handling now emits classified `ErrorId` values for deterministic CLI mapping.
- CLI now uses deterministic exit codes for CI reliability.
- GUI redesigned to tab-based UX (`Run`, `Profiles`, `Reports`) with progress/status and profile workflows.
- GUI run flow now includes cancellation support for active jobs.
- Quality gates now run repo-wide ScriptAnalyzer (with settings), Pester, and secret scan in one command.
- Documentation streamlined to core set and updated for the new feature set.

### Removed
- Legacy issue aggregation document (`BUGS_AND_FIXES.md`).
- Tracked test artifact `testResults.xml`.
