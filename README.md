# iperf3 Test Suite

**iperf_tests.sh** is a comprehensive Bash script for automated iperf3 performance benchmarking in demanding network environments. It supports TCP/UDP tests, DSCP marking, MTU probing, UDP saturation ramp-up, IPv4/IPv6 auto-detection, and outputs results in JSON, CSV, and console summaries.

---

## Table of Contents

1. [Features](#features)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Output Files](#output-files)
7. [Troubleshooting](#troubleshooting)
8. [Known Bugs](#known-bugs)

---

## Features

- **Transport & Addressing**: TCP TX/RX/BIDIR and UDP TX/RX over IPv4/IPv6 (auto-detect with fallback).
- **DSCP Classes**: Support for CS0–CS7, EF, AFxy via the `-d` option.
- **MTU Black‑Hole Detection**: Multiple probes (default sizes: 1400, 1472, 1600 bytes; disable with `-N`).
- **UDP Saturation Ramp-Up**: Configurable start, max, step, and loss-threshold for UDP bandwidth (`-u`).
- **Parallel & Bi-directional Tests**: Control via `-j` for concurrent jobs; bidirectional TCP streams require iperf3 ≥ 3.7.
- **Live Spinner**: Visual spinner during iperf runs, suppressible with `-q`.
- **Pre-flight Reachability**: Automatic `ping` and `nc` checks for host and port availability.
- **Runtime Options**: Customize port (`-p`), duration (`-t`), omit seconds (`-s`), timeout (`-T`), output directory (`-o`), and more.
- **Results**:
  - **JSON**: Raw iperf3 JSON logs aggregated.
  - **CSV**: Key metrics (throughput, jitter, packet loss, retransmits).
  - **Console**: Top‑10 throughput and per-protocol maxima via `awk`.
- **Safety Measures**: `set -euo pipefail`, strict quoting, cleanup traps for temp files and background jobs.

---

## Prerequisites

- **Bash** ≥ 4.0
- **iperf3** (bidirectional support in ≥ 3.7)
- **jq**, **awk**, **ping**/`ping6`, **nc** (netcat)
- **timeout** (GNU coreutils; if missing, script disables timeouts)
- **column**, **tee**

---

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/<your-org>/iperf3-suite.git
   cd iperf3-suite
   ```

2. Make the script executable:

   ```bash
   chmod +x iperf_tests.sh
   ```

3. Install dependencies (Debian/Ubuntu example):

   ```bash
   sudo apt-get update
   sudo apt-get install iperf3 jq netcat gawk coreutils moreutils
   ```

---

## Configuration

Adjust the default variables at the top of the script or override them via CLI options:

| Variable               | Description                                            | Default           |
|------------------------|--------------------------------------------------------|-------------------|
| `DURATION`             | Test duration in seconds                              | 10                |
| `OMIT`                 | Seconds to omit at start                              | 1                 |
| `PORT`                 | Target port                                           | 5201              |
| `MAX_JOBS`             | Maximum parallel jobs                                 | 1                 |
| `UDP_START_BW`         | UDP start bandwidth (e.g., `1M`)                     | 1M                |
| `UDP_MAX_BW`           | UDP max bandwidth (e.g., `1G`)                       | 1G                |
| `UDP_BW_STEP`          | UDP step increment (e.g., `10M`)                     | 10M               |
| `UDP_LOSS_THRESHOLD`   | UDP loss threshold (%)                                | 5.0               |
| `TCP_PARALLEL_STREAMS` | Array of TCP parallel streams (e.g., `1 4 8`)         | `(1 4 8)`         |
| `TCP_WINDOW_SIZES`     | Array of TCP window sizes (e.g., `default 128K 256K`)| `(default 128K 256K)` |
| `DSCP_CLASSES`         | Array of DSCP labels (e.g., `CS0 AF11 CS5 EF AF41`)   | `CS0 AF11 CS5 EF AF41` |
| `MTU_SIZES`            | Array of MTU probe sizes                              | `(1400 1472 1600)`|
| `MTU_CHECK`            | Enable MTU checks (1 = yes, 0 = no)                   | 1                 |

### CLI Options

```text
-p <port>       TCP/UDP port (1–65535)
-j <jobs>       Parallel job count
-t <duration>   Test duration in seconds
-s <omit>       Omit initial seconds of each test
-d <list>       Comma-separated DSCP classes
-u <A,B,C,D>    UDP: start,max,step,loss-threshold
-o <dir>        Output directory
-T <timeout>    iperf3 timeout in seconds
-N              Disable MTU probing
-q              Quiet mode (suppress spinner)
-h              Display usage help
```

---

## Usage

```bash
./iperf_tests.sh -p 5201 -j 4 -t 15 -d CS0,EF -u 5M,500M,5M,2 -o ./results target.host.com
```

- The script creates a timestamped subfolder in `./results` (or the specified output directory).
- Live spinner and logs are printed to the console.
- On completion, the summary log shows Top-10 throughput and per-protocol maximums.

---

## Output Files

- **`summary_<TIMESTAMP>.log`** – Combined summary and raw JSON output.
- **`results_<TIMESTAMP>.csv`** – CSV file with columns: `No,Proto,Dir,DSCP,S,W,BW,Thpt,Up,Down,Jit,Loss,Retr,Stat`.
- **`results_<TIMESTAMP>.json`** – JSON array of all test result objects.

---

## Troubleshooting

- **Missing command**: Script exits with an error like `jq missing` → install via package manager.
- **Timeout behavior**: If `timeout` is not found, timeouts are disabled automatically.
- **Ping compatibility**: Detects Apple/Linux ping syntax and adjusts accordingly.
- **Script stops unexpectedly**: `set -euo pipefail` will abort on errors—check the summary log for details.

---

## Known Bugs

1. **`valid()` function syntax**: The arithmetic test `(( $2 $3 ))` may cause unexpected exits due to incorrect evaluation.
2. **DSCP mapping error**: Bit-shifting logic in the `TOS` array may apply the shift twice, resulting in incorrect TOS values.
3. **JSON formatting issue**: The leading comma before the last JSON object can produce invalid JSON.
4. **Spinner logic inverted**: The `spin()` function conditionally waits on `QUIET`, but the inversion may disable the spinner incorrectly.
5. **UDP step reset**: Negative or zero step sizes (`UDP_BW_STEP`) may not trigger the fallback to a step of 1 Mbps.
6. **Bidirectional detection**: `BIDIR` is only set for iperf3 ≥ 3.7, but there is no warning when running older versions.
7. **Job slot management**: `slot()` counts background jobs but does not handle zombie processes, which can accumulate.
8. **MTU disable flag**: The `-N` option may not always disable MTU checks if `timeout` is missing.
9. **Temp file cleanup**: `cleanup()` may fail to remove files in nested directories due to `TMP_FILES` path handling.
10. **Help output incomplete**: The `-h` option does not list all available flags (e.g., missing description for `-N`).

---

*Last updated: April 2025*

