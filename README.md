# iperf3 Test Suite

**iperf3-test.sh** is a comprehensive Bash script for automated performance benchmarking using iperf3. It supports TCP/UDP tests with DSCP marking, MTU‑blackhole probing, IPv4/IPv6 auto‑detection, UDP saturation ramp‑up, and outputs timestamped logs, TXT and CSV summaries.

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

- **Transport & Direction**  
  - TCP TX/RX/BIDIR (bidirectional requires iperf3 ≥ 3.7)  
  - UDP TX/RX with automatic loss‑threshold ramp‑up (“sat” mode)  

- **DSCP Classes**  
  - CS0–CS7, EF, AFxy via `-d`  

- **MTU Black‑Hole Detection**  
  - Probes at multiple packet sizes (default: 1400, 1472, 1600 bytes)  
  - Timestamped start and result for each probe  
  - Disable with `-N`  

- **UDP Saturation Ramp‑Up**  
  - Configurable start, max, step, and loss‑threshold (`-u`)  

- **IPv4/IPv6 Auto‑Detection**  
  - Ping‑based reachability checks  
  - TCP port check via netcat  

- **Parallel Jobs & Slotting**  
  - Control concurrency with `-j`  
  - Waits for a free slot if limit reached  

- **Live Logging & Timestamps**  
  - Every major event and result is prefixed `[YYYY‑MM‑DD HH:MM:SS]`  
  - Outputs to console, `summary_<TIMESTAMP>.log`, `iperf3_results_<TIMESTAMP>.txt`, and `results_<TIMESTAMP>.csv`  

- **Robust Shell**  
  - `set -euo pipefail`  
  - Cleanup trap for temporary files and background jobs  

---

## Prerequisites

- **Bash** ≥ 4.0  
- **iperf3** (bidirectional tests require ≥ 3.7)  
- **jq**, **awk**, **ping**/`ping6`, **nc** (netcat)  
- **column**, **tee**, **stdbuf**  

---

## Installation

```bash
git clone https://github.com/<your-org>/iperf3-suite.git
cd iperf3-suite
chmod +x iperf3-test.sh
```

_On Debian/Ubuntu you may install dependencies with:_

```bash
sudo apt-get update
sudo apt-get install iperf3 jq gawk netcat moreutils
```


## Configuration

Defaults are defined at the top of the script but can be overridden via CLI options:

| Variable               | Description                                        | Default               |
|------------------------|----------------------------------------------------|-----------------------|
| `DURATION`             | Test duration (seconds)                            | `10`                  |
| `OMIT`                 | Seconds to omit at test start                      | `1`                   |
| `PORT`                 | iperf3 TCP/UDP port                                | `5201`                |
| `MAX_JOBS`             | Maximum parallel tests                             | `1`                   |
| `UDP_START_BW`         | UDP start bandwidth (e.g. `1M`)                    | `1M`                  |
| `UDP_MAX_BW`           | UDP max bandwidth (e.g. `1G`)                      | `1G`                  |
| `UDP_BW_STEP`          | UDP ramp‑up step (e.g. `10M`)                      | `10M`                 |
| `UDP_LOSS_THRESHOLD`   | UDP loss threshold (%)                             | `5.0`                 |
| `TCP_PARALLEL_STREAMS` | Array of parallel TCP streams (e.g. `1 4 8`)       | `(1 4 8)`             |
| `TCP_WINDOW_SIZES`     | Array of TCP window sizes (e.g. `default 128K`)    | `(default 128K 256K)` |
| `DSCP_CLASSES`         | Array of DSCP labels (e.g. `CS0 AF11 EF`)          | `(CS0 AF11 CS5 EF AF41)` |
| `MTU_SIZES`            | Array of MTU probe sizes                           | `(1400 1472 1600)`    |
| `MTU_CHECK`            | Enable MTU probing (1 = yes, 0 = no)               | `1`                   |

### CLI Options

```text
-p <port>        TCP/UDP port (1–65535)
-j <jobs>        Parallel job count
-t <duration>    Test duration in seconds
-s <omit>        Omit initial seconds of each test
-d <list>        Comma-separated DSCP classes
-u <A,B,C,D>     UDP: start,max,step,loss_threshold
-o <dir>         Output directory
-T <timeout>     iperf3 timeout (seconds)
-N               Disable MTU probing
-q               Quiet mode (suppress non‑critical output)
-h               Show help
```


## Usage

```bash
./iperf3-test.sh \
  -p 5201 \
  -j 4 \
  -t 15 \
  -d CS0,EF \
  -u 5M,500M,5M,2.0 \
  -o ./results \
  target.host.com
```

- Creates a timestamped folder under `./results`  
- Prints live progress and writes detailed logs  


## Output Files

- `summary_<TIMESTAMP>.log`  
  - Combined summary of test parameters, MTU probe results, and per‑test JSON output  

- `iperf3_results_<TIMESTAMP>.txt`  
  - Plain‑text, timestamped record of every probe and test run  

- `results_<TIMESTAMP>.csv`  
  - CSV summary with columns:  
    `No,Proto,Dir,DSCP,Streams,Win,Thr_s(Mb/s),Retr_s,Thr_r(Mb/s),Role`


## Troubleshooting

- **Missing command**  
  - Script will exit with `<cmd> missing`. Install via your package manager.  
- **Permission denied**  
  - Ensure `iperf3-test.sh` is executable (`chmod +x`).  
- **Unexpected exit**  
  - `set -euo pipefail` causes exit on any error—inspect the last console output or `summary_*.log`.  
- **MTU probe failures**  
  - Network may drop ICMP; disable with `-N` if not needed.  


## Known Bugs

1. **`valid()` arithmetic test** may misinterpret floating‑point bounds.  
2. **DSCP bit‑shift logic** can double‑shift in some Bash versions.  
3. **Missing `$BH_FAIL_STR`** initialisation order can trigger unbound‑variable if MTU disabled.  
4. **Slot counting** does not clear stale PIDs—zombie jobs may block new slots.  
5. **IPv6 ping command** may differ on non‑Linux systems.  
6. **Quiet mode inversion**: some informational lines still appear.  
7. **Loss of per‑test JSON**: aggregated JSON output not yet implemented.  

*Last updated: April 2025*  
