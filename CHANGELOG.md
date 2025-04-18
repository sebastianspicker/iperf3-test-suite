# Changelog

All notable changes to **iperf3 Test Suite**.

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

