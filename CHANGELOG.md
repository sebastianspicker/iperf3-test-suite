# Changelog

All notable changes to **iperf3 Test Suite**.

## [v3.1] – 2025-04-22

### Added
- Timestamp prefix (`[YYYY‑MM‑DD HH:MM:SS]`) to every MTU probe line and each test start/status line in both the summary log and per‑test TXT.
- Dual‐output of MTU probe results into `$SUMMARY` and `iperf3_results_<TIMESTAMP>.txt`.
- New CLI‐guided initialization order to ensure `$SUMMARY`, `$FN`, `BH` and `BH_FAIL_STR` are defined before any probes run.

### Changed
- Refactored `run_test()` to use `echo … | tee` exclusively (removed legacy `say` calls) and to emit both “start” and “status” lines with timestamps.
- Moved output‐file setup (`SUMMARY`, `CSV`, `FN`) above the MTU‑probe block to avoid unbound‐variable errors.
- Updated README and CSV header to reflect new timestamped logging and TXT output file naming.

### Fixed
- Corrected scope of `local` declarations: all `local` keywords now appear only inside functions to eliminate “`local: can only be used in a function`” errors.
- Initialized `BH=0` and `BH_FAIL_STR` before writing the initial summary line to avoid “unbound variable” errors.
- Ensured `$OUTDIR/iperf3_results_<FN>.txt` is created before any `tee -a` calls to prevent file‐not‐found errors.

---

## [v3.0] – 2025-04-21

### Changed
- Complete internal rework: refactored into modular helper functions (`h2m`, `spin`, `slot`, `csv`, `say`, etc.) with strict `set -euo pipefail` and cleanup traps.
- Unified JSON, CSV, and summary generation into a single, timestamped workflow with temporary-file management and proper cleanup of background jobs.
- Auto-detection and fallback for IPv4/IPv6, with pre-flight reachability check (`ping` + `nc`) and dynamic MTU black‑hole probing (configurable sizes, disable flag).
- Redesigned DSCP-to-TOS mapping using associative arrays, supporting CS0–CS7, EF, and AFxy classes.
- Enhanced UDP saturation ramp-up with configurable start/max/step/loss-threshold parameters and automatic loop-break on threshold breach.
- Improved parallelism: `-j` job pool, dynamic slot allocation, and live spinner (`-q` to suppress) for responsive CLI experience.
- Updated summary output to include Top‑10 throughput and per-protocol maxima directly in the summary log.

### Added
- Comprehensive CLI options for port (`-p`), duration (`-t`), omit (`-s`), DSCP classes (`-d`), UDP parameters (`-u`), timeout (`-T`), MTU disable (`-N`), parallel jobs (`-j`), quiet mode (`-q`), and output directory (`-o`).
- New CSV header and JSON schema with explicit field names (`test_no`, `protocol`, `direction`, `dscp`, `streams`, `window`, `bandwidth_mbps`, `throughput_*`, `jitter_ms`, `loss_percent`, `retransmits`, `status`).
- Safety checks: validated numeric inputs, default fallbacks for missing `timeout`, Apple/Linux `ping` compatibility, and fail-safe on missing prerequisites.
- Detailed `Known Bugs` section in `README.md` reflecting outstanding issues and future work.

### Removed
- Deprecated external Python report generator and previous summary scripts.
- Legacy `record_summary()` and double-counting progress logic.
- Hard-coded DSCP flags mapping; replaced by dynamic associative array.

### Fixed
- Eliminated JSON formatting error (no leading commas before objects).
- Corrected `valid()` arithmetic evaluation and parameter checks.
- Ensured proper reset of UDP loop variables and step fallback for non-positive values.
- Addressed spinner inversion logic to respect quiet mode correctly.
- Cleaned up temporary files in nested directories and improved trap handling.

## [v3.0] - 2025-04-21
### Changed
- Complete internal rework: refactored into modular helper functions (`h2m`, `spin`, `slot`, `csv`, `say`, etc.) with strict `set -euo pipefail` and cleanup traps.
- Unified JSON, CSV, and summary generation into a single, timestamped workflow with temporary-file management and proper cleanup of background jobs.
- Auto-detection and fallback for IPv4/IPv6, with pre-flight reachability check (`ping` + `nc`) and dynamic MTU black‑hole probing (configurable sizes, disable flag).
- Redesigned DSCP-to-TOS mapping using associative arrays, supporting CS0–CS7, EF, and AFxy classes.
- Enhanced UDP saturation ramp-up with configurable start/max/step/loss-threshold parameters and automatic loop-break on threshold breach.
- Improved parallelism: `-j` job pool, dynamic slot allocation, and live spinner (`-q` to suppress) for responsive CLI experience.
- Updated summary output to include Top‑10 throughput and per-protocol maxima directly in the summary log.

### Added
- Comprehensive CLI options for port (`-p`), duration (`-t`), omit (`-s`), DSCP classes (`-d`), UDP parameters (`-u`), timeout (`-T`), MTU disable (`-N`), parallel jobs (`-j`), quiet mode (`-q`), and output directory (`-o`).
- New CSV header and JSON schema with explicit field names (`test_no`, `protocol`, `direction`, `dscp`, `streams`, `window`, `bandwidth_mbps`, `throughput_*`, `jitter_ms`, `loss_percent`, `retransmits`, `status`).
- Safety checks: validated numeric inputs, default fallbacks for missing `timeout`, Apple/Linux `ping` compatibility, and fail-safe on missing prerequisites.
- Detailed `Known Bugs` section in `README.md` reflecting outstanding issues and future work.

### Removed
- Deprecated external Python report generator and previous summary scripts.
- Legacy `record_summary()` and double-counting progress logic.
- Hard-coded DSCP flags mapping; replaced by dynamic associative array.

### Fixed
- Eliminated JSON formatting error (no leading commas before objects).
- Corrected `valid()` arithmetic evaluation and parameter checks.
- Ensured proper reset of UDP loop variables and step fallback for non-positive values.
- Addressed spinner inversion logic to respect quiet mode correctly.
- Cleaned up temporary files in nested directories and improved trap handling.

---

## [v2.7] - 2025-04-18
### Fixed
- Corrected `record_summary()` function signature and removed stray backslashes.
- Restored full script content after accidental deletion.
- Ensured DSCP flags (`--dscp 40`, `--dscp 10`) applied via `DSCP_FLAGS` mapping.
- Cleanly quoted `${flags[@]}` in echo and iperf3 command lines.
- Passed `proto` into `probe_udp()` to accurately label CSV entries.
- Ensured `COUNT` only increments for actual recorded test results.
- Validated UDP rate doubling is purely numeric without string comparisons.

## [v2.6] - 2025-04-17
### Added
- Introduced DSCP mapping as an associative array to support QoS rounds.
- Unified `record_summary()` `printf` format to include a trailing newline.
### Changed
- Improved `probe_udp()` to accept `proto` argument and properly record labels.
- Simplified progress counter logic to avoid double counting when skipping.

## [v2.5] - 2025-04-16
### Changed
- Fixed `exec` redirection and standardized `log()` helper.
- Correct server-selection logic via `if/else` for IPv4/IPv6 arrays.
- Implemented MTU black‑hole detection with `--len` and `-M` probes.
- Added high-level summaries for max throughput and max loss via `awk`.
- Simplified `TOTAL_TESTS` counting structure.

## [v2.4] - 2025-04-14
### Added
- MTU probing function: tests packet sizes (1400, 1500, 1600 bytes).
- Dynamic UDP saturation probe: doubles rate until loss threshold crossed.
### Changed
- Reorganized script to handle missing DSCP flags correctly.

## [v2.3] - 2025-04-12
### Changed
- Removed Python dependency; all reporting done via `jq`, `column`, `awk`.
- Added progress reporting (X/Y, percent complete).
- Improved adaptive skipping: ping & port-check for TCP; skip UDP always.

## [v2.2] - 2025-04-10
### Changed
- Fixed `dexec` typo to `exec`.
- Replaced bash ternary server loop with proper `if/else`.
- Added dynamic test profiling for UDP and MTU.
- Added summary dashboard and external Python chart generator.

## [v2.1] - 2025-04-08
### Added
- Graceful shutdown and cleanup on SIGINT/SIGTERM.
- Adaptive skipping of unreachable hosts and ports.
- CSV summary output alongside JSON logs.
- External Python script for HTML report generation with charts.

## [v2.0] - 2025-04-06
### Added
- Comprehensive iperf3 feature coverage: reverse, bidirectional, parallel, DSCP, TLS.
- Full test matrix automation with nested loops over protocols, ports, windows, etc.
- Human-readable per-interval and summary tables.

## [v1.0] - April 2025
### Initial Release
- Basic automation of iperf3 TCP & UDP tests.
- JSON logging and simple console summaries.

