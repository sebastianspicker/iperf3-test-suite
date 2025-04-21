#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# iperf_tests.sh  —  All‑in‑one iperf3 automation        (2025‑05‑hotfix)
#-------------------------------------------------------------------------------
#  • TCP  TX/RX/BIDIR  – streams & windows
#  • UDP  TX/RX        – fixed‑rate + saturation ramp‑up (loss‑threshold)
#  • DSCP classes      – CSx / AFxx / EF
#  • IPv4 / IPv6       – auto‑detect, fallback
#  • MTU black‑hole    – multi‑probe 1400/1472/1600 B (‑N disables)
#  • Reachability      – ping + nc   pre‑flight
#  • Parallel pool     – ‑j <jobs>
#  • Live spinner      – quiet mode with ‑q
#  • Output dir        – ‑o <dir>
#  • Results           – CSV, JSON, console Top‑10 / protocol maxima
#  • Safety            – strict mode, quoting, cleanup trap, iperf timeout
#-------------------------------------------------------------------------------

set -euo pipefail
shopt -s lastpipe

###############################################################################
# Defaults                                                                     #
###############################################################################
DURATION=10  OMIT=1  PORT=5201  MAX_JOBS=1
OUTDIR="$(pwd)"  QUIET=0
MTU_CHECK=1   MTU_SIZES=(1400 1472 1600)
IPERF_TIMEOUT=60
UDP_START_BW="1M"  UDP_MAX_BW="1G"  UDP_BW_STEP="10M"  UDP_LOSS_THRESHOLD=5.0
TCP_PARALLEL_STREAMS=(1 4 8)
TCP_WINDOW_SIZES=("default" "128K" "256K")
DSCP_CLASSES=(CS0 AF11 CS5 EF AF41)

###############################################################################
# Cleanup trap                                                                 #
###############################################################################
TMP_FILES=(); EXIT_STATUS=0
cleanup() {
  local ec=$?
  for f in "${TMP_FILES[@]:-}"; do [[ -e $f ]] && rm -f "$f"; done
  jobs -pr | xargs -r kill 2>/dev/null || true
  exit "${EXIT_STATUS:-$ec}"
}
trap cleanup EXIT INT TERM

###############################################################################
# CLI                                                                          #
###############################################################################
usage() {
  grep -E '^#  •' "$0" | sed 's/^# \?//'
  echo -e "\nUsage: $0 [opts] <target>\n  -p port   -j jobs  -t dur  -s omit  -d DSCPs  -u 1M,1G,10M,5  -o DIR  -T sec  -N  -q"
  exit 0
}
valid() { [[ $2 =~ ^[0-9]+$ ]] && (( $2 $3 )) || { echo "Bad $1=$2" >&2; exit 2; }; }

while getopts "p:j:t:s:d:u:o:T:Nqh" o; do
  case $o in
    p) valid port "$OPTARG" '>=1&&OPTARG<=65535'; PORT=$OPTARG ;;
    j) valid jobs "$OPTARG" '>=1'; MAX_JOBS=$OPTARG ;;
    t) valid dur  "$OPTARG" '>=1'; DURATION=$OPTARG ;;
    s) valid omit "$OPTARG" '>=0'; OMIT=$OPTARG ;;
    d) IFS=',' read -ra DSCP_CLASSES <<< "$OPTARG" ;;
    u) IFS=',' read -r UDP_START_BW UDP_MAX_BW UDP_BW_STEP UDP_LOSS_THRESHOLD <<< "$OPTARG" ;;
    o) OUTDIR=$OPTARG ;;
    T) valid timeout "$OPTARG" '>=0'; IPERF_TIMEOUT=$OPTARG ;;
    N) MTU_CHECK=0 ;;
    q) QUIET=1 ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND-1))
[[ $# -lt 1 ]] && usage
TARGET=$1; mkdir -p "$OUTDIR"

###############################################################################
# Prerequisites                                                                #
###############################################################################
for c in iperf3 jq awk ping nc; do command -v "$c" >/dev/null || { echo "$c missing"; exit 1; }; done
command -v timeout >/dev/null || IPERF_TIMEOUT=0

###############################################################################
# iperf version                                                                #
###############################################################################
IPERF_VERSION=$(iperf3 --version 2>&1 | awk 'NR==1{print $2}')
IPERF_MAJOR=${IPERF_VERSION%%.*}
IPERF_MINOR=${IPERF_VERSION#*.}; IPERF_MINOR=${IPERF_MINOR%%.*}
BIDIR=$(( IPERF_MAJOR>3 || (IPERF_MAJOR==3 && IPERF_MINOR>=7) ))

###############################################################################
# DSCP → TOS map                                                              #
###############################################################################
declare -A TOS
for i in {0..7}; do TOS[CS$i]=$((i*8<<2)); done
TOS[EF]=$((46<<2))
for k in 1 2 3 4; do for j in 1 2 3; do d=$(( (k+1)*8 + (j-1)*2 )); TOS[AF${k}${j}]=$((d<<2)); done; done

###############################################################################
# Helpers                                                                      #
###############################################################################

# human‑readable Bandbreite → Mbit/s (Ganzzahl/Floats)
h2m() {
  [[ -z $1 ]] && { echo 0; return; }

  local num unit
  num=$(echo "$1" | sed 's/[^0-9.]//g')
  unit=$(echo "$1" | sed 's/[0-9.]//g' | tr '[:upper:]' '[:lower:]')

  case "$unit" in
    g) awk -v n="$num" 'BEGIN{printf "%.0f", n*1000}' ;;
    k) awk -v n="$num" 'BEGIN{printf "%.0f", n/1000}' ;;
    m|"") awk -v n="$num" 'BEGIN{printf "%.0f", n}' ;;
    *) echo 0 ;;
  esac
}

# Live‑Spinner (unterdrückbar mit -q)          ★ Semikolon hinzugefügt
spin() {
  (( QUIET )) && { wait "$1"; return; }
  local pid=$1 s='|/-\' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%c' "${s:i++%4:1}"
    sleep .1
  done
  wait "$pid"
  printf '\r'
}

# Job‑Pool: blockiert bis unter MAX_JOBS
slot() { while (( $(jobs -pr | wc -l) >= MAX_JOBS )); do sleep .1; done; }

# CSV‑Feld mit sicherem Quoting
csv() {
  local v=$1
  if [[ $v == *","* || $v == *$'\n'* || $v == *\"* ]]; then
    printf '"%s"' "${v//\"/\"\"}"
  else
    printf '%s' "$v"
  fi
}

# Info‑Ausgabe (quiet‑aware)
say() { (( QUIET )) || echo -e "$*" >&2; }


###############################################################################
# Reachability                                                                 #
###############################################################################
PING4="ping -c1 -W1"; PING6="ping -6 -c1 -W1"
ping -h 2>&1 | grep -qi apple && { PING4="ping -c1 -t1"; PING6="ping6 -c1"; }
ipv=4; [[ $TARGET == *:* ]] && ipv=6
{ [[ $ipv == 4 ]] && $PING4 "$TARGET" || $PING6 "$TARGET"; } >/dev/null 2>&1 || { echo ping fail; exit 0; }
nc -${ipv} -z -w2 "$TARGET" "$PORT" >/dev/null 2>&1 || { echo "port $PORT closed"; exit 0; }

###############################################################################
# MTU multi‑probe                                                              #
###############################################################################
BH=0; BH_FAIL=()
if (( MTU_CHECK )); then
  P4="ping -c1 -M do"; [[ $PING4 == *'-t1'* ]] && P4="ping -c1"
  P6="ping6 -c1"
  for SZ in "${MTU_SIZES[@]}"; do
    CMD="$([[ $ipv == 6 ]] && echo $P6 || echo $P4) -s $SZ $TARGET"
    if ! eval "$CMD" >/dev/null 2>&1; then BH=1; BH_FAIL+=("$SZ"); say "[WARN] MTU $SZ failed"
    else say "[ OK ] MTU $SZ ok"; fi
  done
fi
BH_FAIL_STR=$(IFS=,; echo "${BH_FAIL[*]:-none}")

###############################################################################
# Output files                                                                 #
###############################################################################
TS=$(date -u +%FT%TZ); FN=$(date +%Y%m%d_%H%M%S)
SUMMARY="$OUTDIR/summary_$FN.log"; CSV="$OUTDIR/results_$FN.csv"; JSON="$OUTDIR/results_$FN.json"
TMP_FILES+=("$SUMMARY" "$CSV" "$JSON")
echo "[$TS] target=$TARGET port=$PORT BH=$BH ($BH_FAIL_STR)" >"$SUMMARY"
echo "No,Proto,Dir,DSCP,S,W,BW,Thpt,Up,Down,Jit,Loss,Retr,Stat" >"$CSV"
echo "{ \"timestamp\":\"$TS\",\"target\":\"$TARGET\",\"mtu_blackhole\":$BH,\"mtu_failed_sizes\":\"$BH_FAIL_STR\",\"results\":[" >"$JSON"; FIRST=1

###############################################################################
# iperf executor                                                               #
###############################################################################
iperf_run() {
  local tmp; tmp=$(mktemp); TMP_FILES+=("$tmp")
  local cmd=(iperf3 "$@" -J); ((IPERF_TIMEOUT)) && cmd=(timeout "$IPERF_TIMEOUT" "${cmd[@]}")
  "${cmd[@]}" >"$tmp" 2>&1 & spin $!; echo "$tmp"
}

###############################################################################
# Single test (robust gegen iperf‑Fehler)                                     #
###############################################################################
N=0
run() {
  local proto=$1 dir=$2 dscp=$3 streams=$4 win=$5 bw=$6 sat=$7 tos=$8
  local label=$dir; [[ $sat ]] && label+=" (sat)"

  # ---------- iperf Aufruf ----------
  local args=(-c "$TARGET" -p "$PORT" -t "$DURATION" -O "$OMIT" -S "$tos")
  [[ $ipv == 6 ]] && args+=( -6 )
  [[ $dir == RX ]] && args+=( -R )
  [[ $dir == BD ]] && args+=( --bidir )
  [[ $proto == UDP ]] && args+=( -u -b "$bw" ) || args+=( -P "$streams" -w "$win" )

  (( ++N ));  say "[#${N}] $proto $label $dscp"
  local f; f=$(iperf_run "${args[@]}")

  # ---------- Initialwerte ----------
  local stat="OK" thr="" up="" dn="" jit="" loss="" retr="" bw_mbps=""
  [[ $bw ]] && bw_mbps=$(h2m "$bw")

  # ---------- JSON prüfen ----------
  if ! jq -e . "$f" >/dev/null 2>&1; then
    stat="FAIL"
  else
    # ---------- Parsing nur wenn OK ----------
    if [[ $proto == TCP ]]; then
      if [[ $dir == BD ]]; then
        local up_bps=$(jq -r '.end.sum_sent.bits_per_second' "$f")
        local dn_bps=$(jq -r '.end.sum_received.bits_per_second' "$f")
        up=$(awk "BEGIN{printf %.2f,$up_bps/1e6}")
        dn=$(awk "BEGIN{printf %.2f,$dn_bps/1e6}")
        thr="$up/$dn"
        retr="$(jq -r '.end.sum_sent.retransmits //0' "$f")/$(jq -r '.end.sum_received.retransmits //0' "$f")"
      else
        local bps=$(jq -r '.end.'$( [[ $dir == RX ]] && echo sum_received || echo sum_sent )'.bits_per_second' "$f")
        thr=$(awk "BEGIN{printf %.2f,$bps/1e6}")
        retr=$(jq -r '.end.sum_sent.retransmits //0' "$f")
      fi
    else  # UDP
      local bps=$(jq -r '.end.sum_received.bits_per_second' "$f")
      local jitter_ms=$(jq -r '.end.sum_received.jitter_ms' "$f")
      local lp=$(jq -r '.end.sum_received.lost_packets //0' "$f")
      local tp=$(jq -r '.end.sum_received.packets //0' "$f")
      thr=$(awk "BEGIN{printf %.2f,$bps/1e6}")
      jit=$(awk "BEGIN{printf %.2f,$jitter_ms}")
      (( tp > 0 )) && loss=$(awk "BEGIN{printf %.2f,($lp/$tp)*100}") || loss=0
    fi
  fi

  # ---------- CSV schreiben ----------
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$N" "$proto" "$label" "$dscp" "$(csv "$streams")" "$(csv "$win")" \
    "$bw_mbps" "$thr" "$up" "$dn" "$jit" "$loss" "$retr" "$stat" >>"$CSV"

  # ---------- JSON‑Objekt bauen (jq 1.5‑kompatibel) ----------
  local obj
  obj=$(jq -n \
      --argjson n "$N" \
      --arg p "$proto" \
      --arg d "$label" \
      --arg c "$dscp" \
      --argjson s "${streams:-null}" \
      --arg w "$win" \
      --argjson bw "${bw_mbps:-null}" \
      --arg thr "$thr" \
      --arg up "$up" \
      --arg dn "$dn" \
      --arg jit "$jit" \
      --argjson loss "${loss:-null}" \
      --arg retr "$retr" \
      --arg st "$stat" \
'{
  test_no:       $n,
  protocol:      $p,
  direction:     $d,
  dscp:          $c,
  streams:       $s,
  window:        (if $w == "" then null else $w end),
  bandwidth_mbps:$bw,
  throughput_mbps:
                 (if $thr == "" then null else ($thr|tonumber) end),
  throughput_up_mbps:
                 (if $up == "" then null else ($up|tonumber) end),
  throughput_down_mbps:
                 (if $dn == "" then null else ($dn|tonumber) end),
  jitter_ms:     (if $jit == "" then null else ($jit|tonumber) end),
  loss_percent:  $loss,
  retransmits:   (if $retr == "" then null else $retr end),
  status:        $st
}')


  [[ $FIRST == 1 ]] && { echo "  $obj" >>"$JSON"; FIRST=0; } || echo " , $obj" >>"$JSON"
  [[ $stat == FAIL ]] && EXIT_STATUS=1
  echo "${loss:-0}"          # Rückgabe für Saturation‑Loop
}


###############################################################################
# Matrix                                                                       #
###############################################################################
for d in "${DSCP_CLASSES[@]}"; do tos=${TOS[$d]:-0}
  for dir in TX RX BD; do [[ $dir == BD && BIDIR == 0 ]] && continue
    for s in "${TCP_PARALLEL_STREAMS[@]}"; do
      for w in "${TCP_WINDOW_SIZES[@]}"; do slot; run TCP "$dir" "$d" "$s" "$w" "" "" "$tos" >/dev/null & done
    done
  done
  for dir in TX RX; do slot; run UDP "$dir" "$d" 1 "" "$UDP_START_BW" "" "$tos" >/dev/null & done
  cur=$(h2m "$UDP_START_BW"); max=$(h2m "$UDP_MAX_BW"); step=$(h2m "$UDP_BW_STEP"); ((step<=0))&&step=1
  for dir in TX RX; do
    while (( cur<=max )); do
      loss=$(run UDP "$dir" "$d" 1 "" "${cur}M" sat "$tos")
      awk "BEGIN{exit !($loss>$UDP_LOSS_THRESHOLD)}" && break
      cur=$(awk -v a="$cur" -v b="$step" 'BEGIN{printf "%.0f", a+b}')
    done
    cur=$(h2m "$UDP_START_BW")   # reset for next dir
  done
done
wait
echo " ]}" >>"$JSON"

###############################################################################
# Summary                                                                      #
###############################################################################
TOP10=$(awk -F, 'NR>1&&$8~/^[0-9.]+$/{print $8","$0}' "$CSV" | sort -t, -k1,1nr | head -n10 | cut -d, -f2-)
MAXTCP=$(awk -F, 'NR>1&&$2=="TCP"&&$8~/^[0-9.]+$ && $8>m{m=$8;L=$0} END{print L}' "$CSV")
MAXUDP=$(awk -F, 'NR>1&&$2=="UDP"&&$8~/^[0-9.]+$ && $8>m{m=$8;L=$0} END{print L}' "$CSV")

{
  echo -e "\nCSV summary:"; column -s, -t "$CSV" 2>/dev/null || cat "$CSV"
  echo -e "\nTop‑10 throughput:"; echo "$TOP10" | column -s, -t 2>/dev/null || cat
  echo -e "\nProtocol maxima:"; [[ $MAXTCP ]] && echo "TCP » $MAXTCP"; [[ $MAXUDP ]] && echo "UDP » $MAXUDP"
} | tee -a "$SUMMARY"
echo "Files: $SUMMARY  $CSV  $JSON"
exit $EXIT_STATUS
