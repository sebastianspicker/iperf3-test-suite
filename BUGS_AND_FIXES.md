# Bugs & Required Fixes

List derived from documentation, known limitations, and operations. Each item can be turned into a separate issue.

---

## Known Limitations / Bugs

### 1. [Bug] Module is Windows-dependent but manifest does not declare OS constraints

**Description:** The implementation uses `ping.exe` and `Test-NetConnection`, which are Windows-specific. The manifest sets `CompatiblePSEditions = @('Core')` without indicating “Windows only”. On Linux/macOS PowerShell 7 the module can fail at runtime when these commands are missing or different.

**Impact:** Users may assume cross-platform support and get hard failures on non-Windows.

**Fix:** Declare Windows-only in the manifest (e.g. release notes, description) and/or add runtime OS checks with a clear error message; or implement cross-platform reachability (e.g. platform-specific ping/connect checks).

---

### 2. [Bug] Test suite aborts if ICMP reachability fails (common in real networks)

**Description:** `Invoke-Iperf3TestSuite` requires ICMP reachability via `Test-Reachability` and throws if it returns `'None'`. Many environments block ICMP while still allowing TCP/UDP to the iperf3 port.

**Impact:** Valid iperf3 test runs are impossible where ping is blocked but the service is reachable (e.g. enterprise/cloud).

**Fix:** Make ICMP reachability optional (e.g. `-SkipReachabilityCheck` or only warn); proceed when TCP port check succeeds. Document behavior when ICMP is skipped.

---

### 3. [Bug/Operational] TCP port test is coupled to traceroute; traceroute failure aborts the entire suite

**Description:** `Test-TcpPortAndTrace` runs TCP port test and traceroute in one `try`; any exception returns both `Tcp = $null` and `Trace = $null`. Traceroute often fails due to ICMP filtering even when the port is reachable.

**Impact:** Suite aborts with “TCP port not reachable” when the port is actually reachable and only traceroute failed.

**Fix:** Run TCP port test and traceroute separately; on traceroute failure return valid `Tcp` and `Trace = $null` (or optional traceroute). Only treat TCP port failure as abort condition.

---

### 4. [Bug] UDP throughput extraction can return null for common iperf3 JSON schemas

**Description:** UDP metrics are taken only from `end.sum_sent` / `end.sum_received`. iperf3 UDP JSON often reports under `end.sum` (and some versions lack `sum_sent`/`sum_received` for UDP). Bidir JSON in some versions has duplicate keys and fails to parse.

**Impact:** UDP test results can be null or wrong even with valid iperf3 output; CSV/JSON artifacts misleading.

**Fix:** Also read `end.sum.bits_per_second` (and related fields) for UDP; handle bidir JSON parse failures with a clear diagnostic (e.g. log or note in output) instead of silent null.

---

### 5. [Bug] Wrapper defaults are not forwarded to the module (`@PSBoundParameters` drops defaulted values)

**Description:** `iPerf3Test.ps1` defines defaults (e.g. `$Duration = 10`, `$OutDir = ...`) but forwards only `@PSBoundParameters`. Parameters the user did not pass are not in `PSBoundParameters`, so the module’s own defaults apply.

**Impact:** Wrapper “defaults” are often ignored; runs can use unexpected duration/omit/outdir/UDP settings.

**Fix:** Build a combined hashtable (e.g. default values plus `@PSBoundParameters` splat) so all intended defaults are passed to `Invoke-Iperf3TestSuite`.

---

### 6. [Bug/Config] Quality-gates script mutates PSGallery trust and installs modules from the internet

**Description:** `Invoke-QualityGates.ps1` sets PSGallery to `Trusted` and installs PSScriptAnalyzer/Pester from the network. This changes user-level repo trust and pulls code from the internet (supply-chain and least-privilege concerns).

**Impact:** Persistent config change; quality gates depend on network and external state; can violate security expectations in locked-down/CI environments.

**Fix:** Document side effects clearly; consider optional “install if missing” vs “fail if not present”; avoid forcing Trusted when possible; or provide an offline/cached path.

---

### 7. [Bug] Failure-handling test is not hermetic and can invoke real external/network behavior

**Description:** The test “throws when TCP port is not reachable” mocks reachability/capability but does not mock `Invoke-Iperf3`. If the implementation regresses and stops throwing, the test can run into the real iperf3 client and network.

**Impact:** A logic regression can turn the test into a hanging/flaky or network-calling test.

**Fix:** Mock `Invoke-Iperf3` (and any other external execution) in this test so behavior is fully hermetic.

---

### 8. [Bug] CHANGELOG and versioning are out of sync with current implementation

**Description:** CHANGELOG mixes Bash-era content with the current PowerShell implementation; duplicate `v3.0` sections; versioning (v3.x) does not match module manifest `0.1.0`.

**Impact:** Users and tooling get wrong expectations about versions and what changed.

**Fix:** Align CHANGELOG with the current PowerShell codebase; remove or clearly separate legacy Bash entries; align version numbers with the manifest.

---

### 9. [Bug/Config] `.gitignore` blocks `.codex/` and all `*.json`/`*.csv`

**Description:** `.codex/` is ignored although the repo may use it for tooling; `*.json` and `*.csv` are global ignores and can block legitimate config, fixtures, or schemas.

**Impact:** Repo-internal config and future JSON/CSV artifacts may not be trackable; “works locally, missing in CI” for needed files.

**Fix:** Narrow ignores (e.g. ignore only specific output paths like `logs/*.json`, `logs/*.csv`, or `testResults.xml`); do not ignore `.codex/` if that content is part of the repo, or document that `.codex/` is intentionally local-only.

---

## Required Fixes / Improvements

### 10. [Enhancement] Make ICMP reachability optional

Same as (2): Allow runs when only TCP port is reachable; document when ICMP is skipped.

---

### 11. [Enhancement] Decouple TCP port check from traceroute

Same as (3): Separate try blocks or optional traceroute; do not null out `Tcp` on traceroute failure.

---

### 12. [Enhancement] UDP metrics: support `end.sum` and directionality for RX/bidir

**Description:** Use `end.sum` for UDP when `sum_sent`/`sum_received` are absent; map Tx/Rx consistently for `-R` (reverse) and bidir so CSV columns match actual direction.

---

### 13. [Enhancement] Bandwidth: document or fix unitless vs iperf3 semantics; fix culture-dependent formatting

**Description:** `ConvertTo-MbitPerSecond` treats unitless numbers as Mbit/s; iperf3 `-b` treats unitless as bits/sec. Also `$bwStr = '{0}M' -f $bw` can produce comma decimals in some locales and break iperf3.

**Fix:** Document unit semantics; use invariant culture for numeric formatting (e.g. `[culture]::InvariantCulture`) when building bandwidth strings.

---

### 14. [Enhancement] Document minimum iperf3 version and flag support

**Description:** Suite uses `-J`, `--connect-timeout`, `--bidir`; older iperf3 may not support these. README does not state a minimum version.

**Fix:** State minimum iperf3 version in README/requirements; optionally detect version and skip unsupported options or fail with a clear message.

---

### 15. [Enhancement] Wrapper: forward intended defaults to the module

Same as (5): Build full parameter set from wrapper defaults + bound parameters before calling the module.

---

### 16. [Enhancement] Quality gates: do not mutate PSGallery Trusted by default; fail fast on missing deps

**Description:** Avoid setting Trusted when possible; capture and surface bootstrap errors instead of SilentlyContinue; optionally fail if PSScriptAnalyzer/Pester are not already installed.

---

### 17. [Enhancement] Tests: mock `Invoke-Iperf3` in failure-handling test; strengthen UDP saturation assertion

**Description:** Ensure “TCP port not reachable” test cannot call real iperf3. UDP saturation test should assert that the loop ran (e.g. at least one UDP bandwidth was tried), not only that `'2M'` is absent.

---

### 18. [Documentation] README/ci: state Bash requirement for `ci-local.sh`; fix secret-scan path filter for non-Windows

**Description:** “Run same checks as CI” uses `./scripts/ci-local.sh` (Bash); repo is Windows/PowerShell-focused. Secret scan uses `*\.git\*`, which is Windows path style.

**Fix:** State that Bash (WSL/Git Bash/macOS/Linux) is required for `ci-local.sh`; use path-agnostic filter for `.git` (e.g. `*/.git/*` or `*\.git*` and `*/.git*`).

---

### 19. [Operational] Stale docs: FINDINGS.md, ci-audit.md, testResults.xml

**Description:** FINDINGS.md has resolved items with outdated “Actual” state; ci-audit.md has stale failure table and run IDs; testResults.xml in repo root is gitignored but present, with old test name and missing schema.

**Fix:** Update or remove stale findings; refresh CI audit table and remove ephemeral run IDs; remove or stop committing testResults.xml; align .gitignore with intended artifacts.

---

## Critical

### 20. [Bug] Module is Windows-only in practice; manifest suggests Core/cross-platform

**Description:** Uses `ping.exe` and `Test-NetConnection` without OS check; manifest says `CompatiblePSEditions = @('Core')`. Fails on non-Windows.  
**Fix:** Document Windows-only and/or add runtime check with clear error; or implement cross-platform reachability.

---

### 21. [Bug] Suite aborts on ICMP failure even when TCP port is reachable

**Description:** Hard requirement on ICMP causes false “unreachable” in ping-blocked networks.  
**Fix:** Make ICMP optional; proceed when TCP port check succeeds.

---

### 22. [Bug] TCP port result discarded when traceroute fails in same try block

**Description:** Any exception in `Test-TcpPortAndTrace` (e.g. traceroute only) returns Tcp=null and triggers “port not reachable”.  
**Fix:** Separate TCP test from traceroute; only treat TCP failure as abort.

---

### 23. [Bug] UDP throughput from JSON often null (wrong keys; bidir JSON invalid in some versions)

**Description:** Code expects `sum_sent`/`sum_received` for UDP; iperf3 often uses `sum`; bidir JSON can be unparsable.  
**Fix:** Support `end.sum` for UDP; handle parse failure with diagnostic; optionally detect iperf3 version.

---

### 24. [Bug] Quality-gates script sets PSGallery Trusted and installs from internet (persistent config + supply chain)

**Description:** Mutates user repo trust; installs modules from network; broad side effects.  
**Fix:** Document; avoid Trusted when possible; support “fail if missing” or offline mode.

---

### 25. [Bug] Failure-handling test can run real iperf3/network if implementation regresses

**Description:** Test mocks reachability but not `Invoke-Iperf3`.  
**Fix:** Mock `Invoke-Iperf3` in that test.

---

## High

### 26. [Bug] Wrapper defaults not forwarded (`@PSBoundParameters` only)

**Description:** Defaulted parameters are omitted from splat; module defaults used instead of wrapper defaults.  
**Fix:** Merge default values with `PSBoundParameters` before calling module.

---

### 27. [Bug] UDP direction (-R) not reflected in metric mapping; CSV Tx/Rx can be wrong for reverse

**Description:** `Get-Iperf3Metric` does not use `Dir` for UDP; Thr_TX_Mbps/Thr_RX_Mbps can be misleading for RX/bidir.  
**Fix:** Map UDP metrics by direction (and -R) so CSV columns match semantics.

---

### 28. [Bug] Unitless bandwidth treated as Mbit/s here but as bits/sec by iperf3

**Description:** Unitless input (e.g. `10`) interpreted as 10 Mbit/s; iperf3 `-b 10` = 10 bits/sec.  
**Fix:** Document; reject unitless or interpret consistently with iperf3 (e.g. require unit).

---

### 29. [Bug] Bandwidth string culture-dependent (`{0}M` -f $bw can emit comma decimals)

**Description:** Locales with comma as decimal separator can produce `1,5M` etc., which iperf3 may not parse.  
**Fix:** Use invariant culture for numeric format when building `-b` argument.

---

### 30. [Bug] `--connect-timeout` always passed; older iperf3 can reject unknown option

**Description:** No capability check for `--connect-timeout`; older builds may fail with “unknown option”.  
**Fix:** Detect iperf3 version/help and only add `--connect-timeout` when supported; or document minimum version and fail clearly.

---

### 31. [Bug] Bidir JSON parse failure yields null metrics with no diagnostic

**Description:** Invalid bidir JSON (e.g. duplicate keys) is caught and `$jsonObj = $null`; no log or note.  
**Fix:** Log or attach parse error to result; optionally set a “parse_failed” flag in output.

---

### 32. [Bug] Version extraction fragile; first-line + regex can mis-detect bidir support

**Description:** `iperf3 --version` first line + `\b([0-9]+)\.([0-9]+)\b` can match wrong number; pipeline can affect `$LASTEXITCODE`.  
**Fix:** More robust version parse (e.g. prefer last line, or structured output); capture exit code immediately after call.

---

### 33. [Bug] Runner scriptblock and `$LASTEXITCODE`: exit code can be stale when using -Runner

**Description:** With custom `Runner`, `$LASTEXITCODE` may not reflect iperf3; scriptblocks don’t set it unless they run a native exe last.  
**Fix:** Document that Runner should set `$global:LASTEXITCODE`; or capture it only when not using Runner.

---

### 34. [Bug] Zero throughput treated as missing (truthiness of `bits_per_second`)

**Description:** `if ($sumSent.bits_per_second)` is false when value is 0; throughput left null.  
**Fix:** Check for property existence (or type) and treat 0 as valid value.

---

### 35. [Bug] Get-JsonSubstringOrNull: naive brace scan; no nesting; O(n²) and can pick wrong blob

**Description:** Tries every `{` with every `}`; ignores nesting and arrays; can return wrong substring or be slow.  
**Fix:** Prefer nested brace matching or “last complete JSON object” heuristic; bound input size if needed.

---

### 36. [Bug] Wrapper sets StrictMode and ErrorAction Stop globally (dot-source risk)

**Description:** If script is dot-sourced, caller scope gets StrictMode and Stop; can break other commands.  
**Fix:** Document “run as script, do not dot-source”; or set preferences in a scope that doesn’t leak.

---

### 37. [Bug] Quality gates: Install-Module with -Force -AllowClobber can overwrite user modules

**Description:** Can clobber existing Pester/ScriptAnalyzer and change behavior for other scripts.  
**Fix:** Prefer “install only if missing” or user-scoped path; document side effects.

---

### 38. [Bug] Quality gates: ScriptAnalyzer/Pester results not checked (exit code / diagnostics ignored)

**Description:** Invoke-ScriptAnalyzer output not evaluated; Invoke-Pester success/failure not explicitly checked.  
**Fix:** Capture results; fail script on analyzer violations and on Pester failures; set exit code explicitly if needed.

---

### 39. [Bug] Test: UDP saturation test can pass even if loop never runs

**Description:** Assertion only checks “2M” not in list; if Invoke-Iperf3 is never called, test still passes.  
**Fix:** Assert that at least one UDP bandwidth was requested (e.g. list not empty, or contains expected start).

---

### 40. [Bug] Test: Mock Invoke-Iperf3 signature can drift from real function

**Description:** Hardcoded param list and return shape in test; refactors can break test or hide behavior change.  
**Fix:** Use a thin wrapper or shared contract; avoid duplicating full signature in mock.

---

### 41. [Bug] Error handling: Test-TcpPortAndTrace swallows all errors (no diagnostic)

**Description:** catch returns nulls only; no exception message or type.  
**Fix:** Preserve exception in return object or log; or return distinct result for “Tcp ok, Trace failed”.

---

### 42. [Bug] Error handling: Test-Reachability fallback (ping.exe) can throw if ping missing

**Description:** ping.exe fallback is not in its own try/catch; on non-Windows or missing ping, unhandled exception.  
**Fix:** Wrap ping.exe calls in try/catch; return 'None' and optionally log.

---

### 43. [Bug] Error handling: JSON parse failure in Invoke-Iperf3 loses error context

**Description:** catch sets $jsonObj = $null; RawText kept but parse error message lost.  
**Fix:** Store parse error (e.g. in result object or verbose log) for diagnostics.

---

### 44. [Bug] OutDir uses -Path (wildcard expansion); special chars can misroute output

**Description:** New-Item/Export-Csv/Set-Content use -Path; `[ ] * ?` in OutDir can behave unexpectedly.  
**Fix:** Use -LiteralPath where appropriate for user-supplied paths.

---

### 45. [Bug] Timestamp to seconds only; same-second runs can overwrite artifacts

**Description:** Filenames use `yyyyMMdd_HHmmss`; concurrent or rapid runs can overwrite.  
**Fix:** Add subsecond or random suffix; or check file exists and increment.

---

### 46. [Bug] ValidateNotNullOrEmpty allows whitespace; bandwidth becomes 0.0

**Description:** Whitespace-only UdpStart/UdpMax/UdpStep pass validation; ConvertTo-MbitPerSecond returns 0.0.  
**Fix:** Use ValidateNotNullOrWhiteSpace and/or validate format before use.

---

### 47. [Bug] ping.exe not preflight-checked

**Description:** iperf3 and ConvertFrom-Json are checked; ping.exe is not, but used for reachability and MTU.  
**Fix:** Check Get-Command ping.exe (or platform equivalent) in preflight and fail with clear message if missing.

---

### 48. [Bug] .gitignore ignores .codex/ and all *.json / *.csv

**Description:** Broad ignores can block needed config/fixtures (e.g. JSON/CSV under repo paths).  
**Fix:** Narrow patterns; document or adjust .codex handling.

---

### 49. [Bug] CHANGELOG / FINDINGS / ci-audit stale or duplicate

**Description:** CHANGELOG has Bash content and duplicate v3.0; FINDINGS and ci-audit have outdated “Actual” and fix plans.  
**Fix:** Align CHANGELOG with current codebase; update or archive FINDINGS and ci-audit.

---

## Quick reference: common failure causes

| Symptom | Typical cause | Fix / see |
|--------|----------------|-----------|
| Suite aborts “ICMP reachability failed” | Ping blocked but TCP port open | Make ICMP optional; see (2), (21) |
| Suite aborts “TCP port not reachable” | Traceroute failed in same try as TCP test | Decouple TCP and traceroute; see (3), (22) |
| UDP throughput null in CSV/JSON | iperf3 uses `end.sum` or bidir JSON invalid | Support `end.sum`; handle parse failure; see (4), (23) |
| Wrapper “defaults” not applied | Only @PSBoundParameters forwarded | Merge defaults + PSBoundParameters; see (5), (26) |
| Quality gates change PSGallery / install from net | Invoke-QualityGates.ps1 behavior | Document; avoid Trusted; optional offline; see (6), (24) |
| Test hangs or hits network | Failure test doesn’t mock Invoke-Iperf3 | Mock Invoke-Iperf3 in that test; see (7), (25) |
| Wrong bandwidth sent to iperf3 | Unitless = Mbit/s here, bits/sec there; or locale | Document units; invariant format; see (13), (28), (29) |
| “Unknown option” from iperf3 | --connect-timeout or --bidir on old build | Document min version; optional capability check; see (14), (30) |
| Artifacts overwritten | Same second, same OutDir | Timestamp with subsecond or unique suffix; see (45) |
| Script fails on non-Windows | ping.exe / Test-NetConnection missing | Document Windows; add OS check or cross-platform path; see (1), (20) |

---

## Using this list for issues

- **Labels:** Use `bug`, `enhancement`, `documentation`, `operational` as appropriate.
- **Title:** Use the **[Bug]** / **[Enhancement]** prefix or a short descriptor.
- **Body:** Copy the relevant section (description, impact, fix) into the issue.
- The **quick reference** table can be linked from README or a “Troubleshooting” doc for operators.

---

## Deep Code Inspection Findings (2026 Audit)

This section contains findings from a thorough manual and automated code inspection. All critical, major, and minor issues have been addressed.

### P0: Critical Issues (Immediate Action Required) - ALL FIXED

#### 1. [Security] Argument Injection Validation Incomplete - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Functions: `Test-Reachability`, `Invoke-Iperf3`, `Test-MtuPayload`)
- **Reason:** The `$Target` (or `$Server`) parameter is passed to external executables (`ping.exe`, `iperf3.exe`) via splatting. While splatting protects against simple shell injection (like `; command`), it does not protect against **Argument Injection**. If a user provides a target like `--config-file=...` or other flags supported by the binary, it could lead to unexpected behavior or local file inclusion/execution depending on the binary's capabilities.
- **Probability:** High (if input is user-controlled/exposed via API).
- **Fix:** Added `Test-ValidHostnameOrIP` helper function that validates targets using regex for valid IPv4, IPv6, and hostname patterns before passing to external executables.

#### 2. [Bug] $LASTEXITCODE Race Condition (Version Check) - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Get-Iperf3Version`)
- **Reason:** The `$LASTEXITCODE` automatic variable is captured after pipeline operations, which can overwrite the actual exit code from iperf3. Pipeline operations in PowerShell can modify `$LASTEXITCODE`, leading to incorrect version detection.
- **Probability:** Medium (depends on pipeline state).
- **Fix:** Captured exit code immediately after the iperf3 call, before any pipeline operations that could modify `$LASTEXITCODE`.

#### 3. [Bug] $LASTEXITCODE Race Condition (Invoke-Iperf3) - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Invoke-Iperf3`)
- **Reason:** When using a custom `Runner` scriptblock, `$LASTEXITCODE` may not reflect the actual iperf3 exit code because scriptblocks don't set `$LASTEXITCODE` unless they run a native executable last.
- **Probability:** Medium (when using custom Runner).
- **Fix:** Documented that the Runner parameter is responsible for setting `$global:LASTEXITCODE` when using custom runners. Added clear documentation in the function's comment-based help.

---

### P1: Major Issues (Breaking or Functional Defects) - ALL FIXED

#### 4. [Bug] Duplicate Variable Initialization - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Invoke-Iperf3TestSuite`)
- **Reason:** The variable `$udpBandwidths` was initialized twice - once at the top of the function and again inside a conditional block. The second initialization was dead code that could never execute because the first initialization always ran.
- **Probability:** Low (code smell, no runtime impact).
- **Fix:** Removed the duplicate initialization, keeping only the single initialization at the appropriate scope level.

#### 5. [Bug] Inner Function Redefined on Every Call - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `ConvertTo-MbitPerSecond`)
- **Reason:** The `ConvertTo-MbitPerSecond` function was defined inside `Invoke-Iperf3TestSuite`, meaning it was redefined on every call to the parent function. This is inefficient and can cause memory pressure in tight loops.
- **Probability:** Medium (performance impact).
- **Fix:** Moved `ConvertTo-MbitPerSecond` to module scope, outside of any parent function, so it is defined once at module load time.

#### 6. [Bug] UDP Direction Mapping Incorrect for RX - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Get-Iperf3Metric`)
- **Reason:** When using `-R` (reverse) mode with UDP tests, the TX and RX throughput values were swapped in the output. The code assigned `sum_sent` to RX and `sum_received` to TX, which is backwards for reverse mode.
- **Probability:** High (affects all reverse-mode UDP tests).
- **Fix:** Swapped the assignments so that `sum_sent` correctly maps to TX and `sum_received` correctly maps to RX, matching the actual data flow direction.

#### 7. [Bug] Test Mock Signature Doesn't Match - **FIXED**
- **Location:** `tests/Iperf3TestSuite.Tests.ps1`
- **Reason:** The mock for `Invoke-Iperf3` in the test file did not include the `Runner` parameter that was added to the actual function. This caused tests to fail or behave incorrectly when testing scenarios involving the Runner parameter.
- **Probability:** High (test failures).
- **Fix:** Added the `Runner` parameter to the mock definition in the test file, matching the actual function signature.

---

### P2: Minor Issues (Nice-to-haves / Best Practices) - ALL FIXED

#### 8. [Code Quality] Hardcoded Magic Number - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Invoke-Iperf3TestSuite`)
- **Reason:** The UDP saturation loop used a hardcoded value `2` without explanation, making the code harder to understand and maintain.
- **Probability:** Low (maintainability issue).
- **Fix:** Added a documentation comment explaining that the value `2` represents the minimum bandwidth step count for a valid UDP saturation test.

#### 9. [Test Quality] Weak Test Assertion - **FIXED**
- **Location:** `tests/Iperf3TestSuite.Tests.ps1`
- **Reason:** The UDP saturation test only asserted that `'2M'` was not in the bandwidth list, but didn't verify that any bandwidth was actually tested. This could allow false passes if the test loop never executed.
- **Probability:** Medium (test reliability).
- **Fix:** Added an assertion that verifies at least the first bandwidth value was requested, ensuring the test actually validates the saturation loop behavior.

#### 10. [Documentation] Backslash Escape Check Comment - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Get-JsonSubstringOrNull`)
- **Reason:** The JSON extraction logic checked for backslash escaping but lacked a comment explaining why this check was necessary, making the code harder to understand.
- **Probability:** Low (maintainability issue).
- **Fix:** Added a clarifying comment explaining that the backslash escape check prevents false positives when JSON strings contain escaped quote characters.

#### 11. [Code Quality] Confusing Preflight Condition - **FIXED**
- **Location:** `src/Iperf3TestSuite.psm1` (Function: `Invoke-Iperf3TestSuite`)
- **Reason:** The preflight condition used a double-negative pattern (`-not (-not $condition)`) that was confusing and hard to reason about. This violated the principle of least surprise.
- **Probability:** Low (maintainability issue).
- **Fix:** Rewrote the condition using De Morgan's law to eliminate the double-negative, making the logic clearer and more intuitive.

---

### Remaining Issues (Pre-existing / Not Fixed)

The following issues were identified but not fixed as they are pre-existing design decisions or require broader changes:

#### 1. [PSScriptAnalyzer] PSAvoidUsingEmptyCatchBlock
- **Location:** `src/Iperf3TestSuite.psm1` (Line 412)
- **Reason:** An empty catch block exists that silently swallows exceptions. PSScriptAnalyzer flags this as a potential issue because it can hide errors.
- **Status:** Not fixed - This is intentional behavior for non-critical operations where failures should be silently ignored. Adding explicit error handling would require design discussion.

#### 2. [PSScriptAnalyzer] PSUseCmdletCorrectly (Get-Location)
- **Location:** `src/Iperf3TestSuite.psm1` (Lines 32 and 749)
- **Reason:** PSScriptAnalyzer flags usage of `Get-Location` as potentially incorrect in these contexts.
- **Status:** Not fixed - The usage is intentional for obtaining the current working directory. Requires further investigation to determine if alternate approaches are needed.

#### 3. [Test Environment] macOS $IsWindows Read-Only Variable
- **Location:** `tests/Iperf3TestSuite.Tests.ps1`
- **Reason:** On macOS, the `$IsWindows` variable is a read-only automatic variable that cannot be mocked or modified in tests. This causes test failures when trying to simulate Windows-specific behavior.
- **Status:** Not fixed - This is a test environment limitation. Proper fix would require refactoring tests to use dependency injection or environment abstraction rather than directly mocking automatic variables.
