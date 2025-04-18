#!/usr/bin/env bash
# iperf-tests-enhanced.sh v2.7 – iperf3 Industrial Suite
# Estimated runtime: ~1h45m
# Features:
# - TCP/UDP over IPv4/IPv6, DSCP, TLS, custom ports, window sizes
# - Reverse, bidirectional, parallel streams
# - Dynamic UDP saturation probe & MTU black-hole detection
# - Adaptive skipping of unreachable TCP hosts/ports
# - Real-time progress reporting
# - Graceful cleanup of child processes and tempfiles
# - Iterative JSON capture and CSV summary
# - Post-run max throughput and max loss summary via awk

# Ensure script runs under Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# Globals
tmpfiles=()
TOTAL_TESTS=0
COUNT=0

# Cleanup on exit
cleanup() {
  echo "[INFO] Cleaning up..."
  pkill -P $$ iperf3 &>/dev/null || true
  for f in "${tmpfiles[@]}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
  echo "[INFO] Cleanup done."
}
trap cleanup EXIT SIGINT SIGTERM

# 1) Configuration
LOG_DIR="$HOME/logs/iperf"
TS=$(date +'%Y%m%d_%H%M%S')
OUTPUT="$LOG_DIR/iperf_results_$TS.log"
SUMMARY_CSV="$LOG_DIR/iperf_summary_$TS.csv"
DURATION=10
UDP_RATE_START=10M
UDP_RATE_NUM=${UDP_RATE_START%M}
LOSS_THRESHOLD=5.0  # percent for saturation
WINDOWS=(64K 256K)
PORTS=(5201 80 443)
TLS_OPTS=("" "--tls")
PROTOS=(TCP4 TCP6 UDP4 UDP6)
declare -A DSCP_FLAGS=( [Standard]="" [CS5]="--dscp 40" [AF11]="--dscp 10" )
EXTRAS=(Normal Reverse BiDir Par4 Par8)
SERVERS4=(iperf4.example.com)
SERVERS6=(iperf6.example.com)

# 2) Count combinations
for dscp in "${!DSCP_FLAGS[@]}"; do
  for proto in "${PROTOS[@]}"; do
    for extra in "${EXTRAS[@]}"; do
      for wnd in "${WINDOWS[@]}"; do
        for port in "${PORTS[@]}"; do
          for tls in "${TLS_OPTS[@]}"; do
            ((TOTAL_TESTS++))
          done
        done
      done
    done
  done
done

# Prepare log and summary
mkdir -p "$LOG_DIR"
echo "Protocol,Server,Port,DSCP,Scenario,Window,Throughput_Mbps,LossPct,Jitter_ms,Retransmits" > "$SUMMARY_CSV"
touch "$OUTPUT"

# 3) Redirect output
echo "Logging to $OUTPUT"
exec > >(tee -a "$OUTPUT") 2>&1

# Logging helper
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 4) Host reachability (TCP only)
check_host() {
  local srv=$1 ipver=$2 port=$3
  local opts=( -c1 -W1 )
  if [[ "$ipver" == "6" ]]; then
    ping6 "${opts[@]}" "$srv" &>/dev/null || return 1
  else
    ping "${opts[@]}" "$srv" &>/dev/null || return 1
  fi
  nc -z -w2 "$srv" "$port" &>/dev/null || return 1
}

# 5) Record summary entry
# arguments: file proto srv port dscp extra wnd
record_summary() {
  local file=$1 proto=$2 srv=$3 port=$4 dscp=$5 extra=$6 wnd=$7
  local bw loss jit retr
  if [[ "$proto" == UDP* ]]; then
    bw=$(jq -r '.end.sum.bits_per_second/1e6' "$file")
    loss=$(jq -r '(.end.sum.lost_packets/.end.sum.packets)*100' "$file")
    jit=$(jq -r '.end.sum.jitter_ms' "$file")
    retr=0
  else
    bw=$(jq -r '.end.sum_sent.bits_per_second/1e6' "$file")
    retr=$(jq -r '.end.sum_sent.retransmits' "$file")
    loss=0; jit=0
  fi
  echo "$proto,$srv,$port,$dscp,$extra,$wnd,$bw,$loss,$jit,$retr" >> "$SUMMARY_CSV"
  ((COUNT++))
  printf "%3d/%3d %3.0f%% | %s %s:%s | win=%s | BW=%.2fMbps loss=%.1f%%\n" \
    "$COUNT" "$TOTAL_TESTS" "$(bc -l <<< "$COUNT*100/$TOTAL_TESTS")" \
    "$proto" "$srv" "$port" "$wnd" "$bw" "$loss"
}

# 6) Probe UDP saturation
# arguments: srv port dscp extra wnd proto
probe_udp() {
  local srv=$1 port=$2 dscp=$3 extra=$4 wnd=$5 proto=$6
  local rate_num=$UDP_RATE_NUM
  while :; do
    local rate="${rate_num}M"
    local tmp=$(mktemp)
    tmpfiles+=("$tmp")
    echo "Probing UDP rate $rate to $srv:$port"
    iperf3 -u -c "$srv" -p "$port" -b "$rate" -t 5 $dscp --json > "$tmp" 2>&1
    local loss=$(jq -r '(.end.sum.lost_packets/.end.sum.packets)*100' "$tmp")
    if (( loss > LOSS_THRESHOLD )); then
      echo "Saturation at $rate (loss=${loss}%)"
      record_summary "$tmp" "$proto" "$srv" "$port" "$dscp" "$extra" "$wnd"
      break
    fi
    rate_num=$(( rate_num * 2 ))
    (( rate_num > UDP_RATE_NUM * 16 )) && rate_num=$UDP_RATE_NUM
  done
}

# 7) MTU black-hole detection
# arguments: srv port
probe_mtu() {
  local srv=$1 port=$2
  for size in 1400 1500 1600; do
    echo "Probing MTU size $size for $srv:$port"
    if ! iperf3 -c "$srv" -p "$port" -t 1 -M "$size" --json &>/dev/null; then
      echo "MTU black-hole at size $size for $srv:$port"
      return
    fi
  done
  echo "No MTU issues up to 1600 bytes for $srv:$port"
}

# 8) Main execution loop
log "Starting iperf3 suite (~$((TOTAL_TESTS*DURATION/60))m runtime)"
for dscp in "${!DSCP_FLAGS[@]}"; do
  dsopt="${DSCP_FLAGS[$dscp]}"
  log "DSCP: $dscp"
  for proto in "${PROTOS[@]}"; do
    log "Protocol: $proto"
    flags=( -c )
    [[ "$proto" == *4 ]] && flags+=( -4 )
    [[ "$proto" == *6 ]] && flags+=( -6 )
    is_udp=0; [[ "$proto" == UDP* ]] && is_udp=1
    if [[ "$proto" == *6 ]]; then
      servers=( "${SERVERS6[@]}" ); ipver=6
    else
      servers=( "${SERVERS4[@]}" ); ipver=4
    fi

    for srv in "${servers[@]}"; do
      probe_mtu "$srv" "${PORTS[0]}"
    done

    for extra in "${EXTRAS[@]}"; do
      exopt="${extra/Normal/}"
      for wnd in "${WINDOWS[@]}"; do
        for port in "${PORTS[@]}"; do
          for tls in "${TLS_OPTS[@]}"; do
            for srv in "${servers[@]}"; do
              if (( is_udp == 0 )); then
                if ! check_host "$srv" "$ipver" "$port"; then
                  log "Skipping unreachable $srv:$port"
                  continue
                fi
              fi
              if (( is_udp )); then
                probe_udp "$srv" "$port" "$dsopt" "$extra" "$wnd" "$proto"
              else
                local tmp=$(mktemp)
                tmpfiles+=("$tmp")
                echo "Running: iperf3 ${flags[@]} -p $port -t $DURATION -i 1 -w $wnd $dsopt $exopt $tls --json -c $srv"
                iperf3 "${flags[@]}" -p "$port" -t "$DURATION" -i 1 -w "$wnd" $dsopt $exopt $tls --json -c "$srv" > "$tmp" 2>&1
                record_summary "$tmp" "$proto" "$srv" "$port" "$dscp" "$extra" "$wnd"
              fi
            done
          done
        done
      done
    done
  done
done

# 9) Post-run summary
echo -e "\n=== SUMMARY DASHBOARD (first 10 rows) ==="
column -t -s, "$SUMMARY_CSV" | head -n 10

echo -e "\n=== MAX THROUGHPUT per Protocol ==="
awk -F, 'NR>1{if($7>m[$1]) m[$1]=$7}END{for(p in m) printf "%s: %.2f Mbps\n", p, m[p]}' "$SUMMARY_CSV"

echo -e "\n=== MAX LOSS per Protocol ==="
awk -F, 'NR>1{if($8>m[$1]) m[$1]=$8}END{for(p in m) printf "%s: %.1f%%\n", p, m[p]}' "$SUMMARY_CSV"
```
