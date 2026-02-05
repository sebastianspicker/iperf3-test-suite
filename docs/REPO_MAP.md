# REPO MAP

## Top-level
- `iPerf3Test.ps1`: CLI entrypoint that imports the module and forwards parameters.
- `src/`
  - `Iperf3TestSuite.psm1`: Implementation module (test matrix, helpers, iperf3 invocation).
  - `Iperf3TestSuite.psd1`: Module manifest.
- `tests/`
  - `Iperf3TestSuite.Tests.ps1`: Pester tests for helper functions and data shaping.
- `scripts/`
  - `Invoke-QualityGates.ps1`: Runs ScriptAnalyzer and Pester; installs modules if missing.
- `.github/workflows/ci.yml`: Windows CI running ScriptAnalyzer and Pester.

## Key Flows
- Entry flow: `iPerf3Test.ps1` -> `Invoke-Iperf3TestSuite` in `Iperf3TestSuite.psm1`.
- Reachability checks: `Test-Reachability` (ICMP v4/v6) and `Test-TcpPortAndTrace`.
- Test execution: `Invoke-Iperf3` builds args, runs `iperf3`, parses JSON output.
- Metrics extraction: `Get-Iperf3Metric` derives throughput, loss, jitter, retransmits.
- Output: CSV via `Export-Csv`; JSON via `ConvertTo-Json`.

## Hotspots / Risk Areas
- External process execution: `iperf3` and `ping.exe` invocation and JSON parsing.
- Input validation: parameters for bandwidth/DSCP/UDP settings.
- Output artifacts: CSV/JSON content correctness and stability.

## Module Boundary
- Public export: `Invoke-Iperf3TestSuite` only.
- Helpers are internal to the module and tested via `InModuleScope`.
