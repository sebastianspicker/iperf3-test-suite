# iperf3 Test Suite

**ipferf3-test.sh** is a comprehensive Bash script for automated iperf3 performance benchmarking in industrial or enterprise environments. It covers TCP/UDP over IPv4 and IPv6, DSCP marking, MTU probing, UDP saturation testing, and produces live console output as well as JSON, CSV, and summary reports.

---

## Features

- **Transport & Addressing**: TCP and UDP tests over IPv4/IPv6.
- **DSCP Marking**: Simulate QoS with configurable DSCP flags (CS5, AF11).
- **MTU Black‑Hole Detection**: Probe different MTU sizes (1400, 1500, 1600) to identify path MTU issues.
- **UDP Saturation Probing**: Automatically increase UDP bandwidth until packet loss exceeds a threshold.
- **Reverse & Bidir**: Support for reverse (`-R`) and bidirectional (`-d`) flows.
- **Parallel Streams**: Configure multiple TCP streams via `-P`.
- **Custom Ports & TLS**: Test non–standard ports and TLS-encrypted connections.
- **Adaptive Skipping**: Pre-flight TCP reachability checks to skip unreachable targets.
- **Real-Time Progress**: Live progress counters and percentage completion.
- **Graceful Cleanup**: `trap` handlers to kill child iperf3 processes and remove temp files.
- **Logging & Reporting**:
  - **JSON**: Raw iperf3 JSON is captured in the main log.
  - **CSV**: Key metrics (throughput, loss, jitter, retransmits) aggregated.
  - **Console Dashboard**: Top-10 summary and per-protocol max metrics via `awk`.

---

## Requirements

- **Bash** ≥ 4.0
- **iperf3**
- **jq**
- **netcat (nc)**
- **ping** / `ping6`
- **column**
- **bc**
- **tee**

All are typically available on modern Linux distributions.

---

## Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/<your-org>/iperf3-industrial-suite.git
   cd iperf3-industrial-suite
   ```

2. **Make the script executable**:
   ```bash
   chmod +x iperf-tests-enhanced.sh
   ```

3. **Ensure `jq` and `iperf3` are installed**:
   ```bash
   sudo apt-get install iperf3 jq netcat bc
   ```

---

## ⚙Configuration

Edit the top of `iperf-tests-enhanced.sh` to configure:

- **`SERVERS4` / `SERVERS6`**: Your iperf3 server hostnames or IPs for IPv4/IPv6.
- **`PORTS`**: Ports to test (default: 5201, 80, 443).
- **`WINDOWS`**: TCP window sizes (default: 64K, 256K).
- **`DSCP_FLAGS`**: Map of DSCP labels to iperf3 `--dscp` flags.
- **`DURATION`**: Test duration in seconds (default: 10s).
- **`UDP_RATE_START`**: Starting UDP bandwidth (default: 10M).
- **`LOSS_THRESHOLD`**: Saturation threshold % (default: 5%).

---

## Usage

Run the script directly:

```bash
./iperf-tests-enhanced.sh
```

- The script will print live progress and log to `$HOME/logs/iperf/iperf_results_<timestamp>.log`.
- A CSV summary is saved at `$HOME/logs/iperf/iperf_summary_<timestamp>.csv`.
- Upon completion, a console dashboard shows the first 10 results and per-protocol max throughput/loss.

---

## Output Files

All outputs are stored under `~/logs/iperf/` by default:

- **`iperf_results_<TS>.log`**: Full console + raw iperf3 JSON.
- **`iperf_summary_<TS>.csv`**: CSV with columns:
  `Protocol,Server,Port,DSCP,Scenario,Window,Throughput_Mbps,LossPct,Jitter_ms,Retransmits`

---

## 🛠Troubleshooting

- **`command not found: jq`**: Install `jq` via your package manager.
- **Permission errors**: Ensure the script is executable and you have write access to `~/logs/iperf`.
- **Unreachable hosts**: Check network connectivity or disable adaptive skipping.
- **ShellCheck warnings**: This script has been tested with Bash 4+; minor ShellCheck warnings may be safely ignored.
