#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# iperf3-test.sh — All‑in‑one iperf3 automation (Live‑Output + CSV‑Summary)
#-------------------------------------------------------------------------------
set -euo pipefail
shopt -s lastpipe

##### Defaults ##############################################################
DURATION=10
OMIT=1
PORT=5201
MAX_JOBS=1
OUTDIR="$(pwd)/logs"
QUIET=0
MTU_CHECK=1
MTU_SIZES=(1400 1472 1600)
IPERF_TIMEOUT=60
UDP_START_BW="1M"
UDP_MAX_BW="1G"
UDP_BW_STEP="10M"
UDP_LOSS_THRESHOLD=5.0
TCP_PARALLEL_STREAMS=(1 4 8)
TCP_WINDOW_SIZES=("default" "128K" "256K")
DSCP_CLASSES=(CS0 AF11 CS5 EF AF41)

##### Cleanup trap ###########################################################
TMP_FILES=()
EXIT_STATUS=0
cleanup(){
  ec=$?
  for f in "${TMP_FILES[@]:-}"; do [[ -e $f ]] && rm -f "$f"; done
  jobs -pr | xargs -r kill 2>/dev/null || true
  exit "${EXIT_STATUS:-$ec}"
}
trap cleanup EXIT INT TERM

##### CLI #####################################################################
usage(){ cat <<EOF >&2
Usage: $0 [opts] <target>
  -p PORT       (default: $PORT)
  -j MAX_JOBS   (default: $MAX_JOBS)
  -t DURATION   (default: $DURATION)
  -s OMIT       (default: $OMIT)
  -d DSCPs      (default: ${DSCP_CLASSES[*]})
  -u START,MAX,STEP,LOSS   (default: $UDP_START_BW,$UDP_MAX_BW,$UDP_BW_STEP,$UDP_LOSS_THRESHOLD)
  -o OUTDIR     (default: $OUTDIR)
  -T TIMEOUT    (default: $IPERF_TIMEOUT)
  -N            disable MTU probe
  -q            quiet
  -h            help
EOF
  exit 1
}
valid(){
  [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk "BEGIN{exit !($2 $3)}" &>/dev/null \
    || { echo "Bad $1=$2" >&2; exit 2; }
}
while getopts "p:j:t:s:d:u:o:T:Nqh" opt; do
  case $opt in
    p) valid PORT "$OPTARG" '>=1&&OPTARG<=65535'; PORT=$OPTARG ;;
    j) valid MAX_JOBS "$OPTARG" '>=1'; MAX_JOBS=$OPTARG ;;
    t) valid DURATION "$OPTARG" '>=1'; DURATION=$OPTARG ;;
    s) valid OMIT "$OPTARG" '>=0'; OMIT=$OPTARG ;;
    d) IFS=',' read -ra DSCP_CLASSES <<<"$OPTARG" ;;
    u) IFS=',' read -r UDP_START_BW UDP_MAX_BW UDP_BW_STEP UDP_LOSS_THRESHOLD <<<"$OPTARG" ;;
    o) OUTDIR=$OPTARG ;;
    T) valid IPERF_TIMEOUT "$OPTARG" '>=0'; IPERF_TIMEOUT=$OPTARG ;;
    N) MTU_CHECK=0 ;;
    q) QUIET=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
(( $# < 1 )) && usage
TARGET=$1
mkdir -p "$OUTDIR"

##### Prerequisites ###########################################################
for cmd in iperf3 jq awk ping nc column tee stdbuf; do
  command -v "$cmd" &>/dev/null || { echo "$cmd missing"; exit 1; }
done

##### iperf version & bidir ##############################################
IPERF_VERSION=$(iperf3 --version 2>&1 | awk 'NR==1{print $2}')
IPERF_MAJOR=${IPERF_VERSION%%.*}
IPERF_MINOR=${IPERF_VERSION#*.}; IPERF_MINOR=${IPERF_MINOR%%.*}
BIDIR=$(( IPERF_MAJOR>3 || (IPERF_MAJOR==3 && IPERF_MINOR>=7) ))

##### DSCP → TOS map #########################################################
declare -A TOS
for i in {0..7}; do dscp=$((i*8)); TOS[CS$i]=$((dscp<<2)); done
TOS[EF]=$((46<<2))
for x in 1 2 3 4; do
  for y in 1 2 3; do
    dscp=$((8*x + 2*y))         # AFx1=10, AFx2=12, AFx3=14, ...
    TOS[AF${x}${y}]=$((dscp<<2)) # ToS/TClass byte = DSCP << 2
  done
done

##### Helpers #################################################################
h2m(){
  if [[ -z $1 ]]; then
    echo 0; return
  fi
  local num unit
  num=${1//[^0-9.]/}
  unit=${1//[0-9.]/}; unit=${unit,,}
  case $unit in
    g) awk -v n="$num" 'BEGIN{printf "%.0f",n*1000}' ;;
    k) awk -v n="$num" 'BEGIN{printf "%.0f",n/1000}' ;;
    *) awk -v n="$num" 'BEGIN{printf "%.0f",n}'      ;;
  esac
}
slot(){
  while (( $(jobs -pr | wc -l) >= MAX_JOBS )); do sleep .1; done
}
say(){
  (( QUIET )) || echo -e "$*" >&2
}

##### Reachability ############################################################
SKIP=0; ipv=4
if ping -c1 -W1 "$TARGET" &>/dev/null; then
  ipv=4
elif ping -6 -c1 -W1 "$TARGET" &>/dev/null; then
  ipv=6
else
  say "[WARN] ping to $TARGET failed — skipping tests."
  SKIP=1
fi
if (( SKIP==0 )); then
  if ! bash -c ">/dev/tcp/$TARGET/$PORT" &>/dev/null; then
    say "[WARN] port $PORT on $TARGET not reachable — skipping tests."
    SKIP=1
  fi
fi

##### Output files ############################################################
TS=$(date -u +%FT%TZ)
FN=$(date +%Y%m%d_%H%M%S)
SUMMARY="$OUTDIR/summary_$FN.log"
OUTFILE="$OUTDIR/iperf3_results_$FN.txt"
CSV="$OUTDIR/results_$FN.csv"
TMP_FILES+=("$SUMMARY")

##### MTU multi‑probe ##########################################################
BH=0
BH_FAIL=()

if (( MTU_CHECK )); then
  ts=$(date +'%F %T')
  echo "[$ts] [CHECK] MTU probe" \
    | tee -a "$SUMMARY" "$OUTFILE"

  P4="ping -c1 -M do"
  P6="ping -6 -c1"
  for SZ in "${MTU_SIZES[@]}"; do
    if ! eval "$([[ $ipv == 6 ]] && echo \$P6 || echo \$P4) -s $SZ $TARGET" &>/dev/null; then
      BH=1
      BH_FAIL+=("$SZ")
      echo "[$(date +'%F %T')] [WARN] MTU $SZ failed" \
        | tee -a "$SUMMARY" "$OUTFILE"
    else
      echo "[$(date +'%F %T')] [ OK ] MTU $SZ ok" \
        | tee -a "$SUMMARY" "$OUTFILE"
    fi
  done
fi
BH_FAIL_STR=$(IFS=,; echo "${BH_FAIL[*]:-none}")

##### Headers in die Dateien schreiben ########################################
echo "[$TS] target=$TARGET port=$PORT BH=$BH ($BH_FAIL_STR)" >"$SUMMARY"
echo "[$TS] target=$TARGET port=$PORT BH=$BH ($BH_FAIL_STR)" >"$OUTFILE"
printf 'No,Proto,Dir,DSCP,Streams,Win,Thr_s(Mb/s),Retr_s,Thr_r(Mb/s),Role\n' >"$CSV"

##### Single test #############################################################
run_test(){
  local no=$1 proto=$2 dir=$3 dscp=$4 streams=$5 win=$6 bw=$7 mode=$8 tos=$9
  ts=$(date +'%F %T')
  local label="$dir"; [[ $mode == sat ]] && label+="(sat)"

  echo "[$ts] [#${no}] $proto $label DSCP=$dscp streams=$streams win=$win bw=$bw" \
    | tee -a "$SUMMARY" "$OUTFILE"

  local args=(-c "$TARGET" -p "$PORT" -t "$DURATION" -O "$OMIT" -S "$tos")
  (( ipv==6 )) && args+=( -6 )
  if [[ $proto == TCP ]]; then
    [[ $dir == RX ]] && args+=( -R )
    [[ $dir == BD && $BIDIR == 1 ]] && args+=( --bidir )
    args+=( -P "$streams" )
    [[ $win != default ]] && args+=( -w "$win" )
  else
    args+=( -u -b "$bw" )
    [[ $dir == RX ]] && args+=( -R )
    [[ $dir == BD && $BIDIR == 1 ]] && args+=( --bidir )
  fi
  
  local tmp_out
  tmp_out=$(mktemp); TMP_FILES+=("$tmp_out")
  stdbuf -oL iperf3 "${args[@]}" 2>&1 \
    | tee -a "$SUMMARY" \
    | tee "$tmp_out" \
    | tee -a "$OUTFILE"

  local thr_s retr_s stat_s="OK"
  if grep -q " sender\$" "$tmp_out"; then
    thr_s=$(grep " sender\$" "$tmp_out" | tail -n1 | awk '{printf"%.2f",$7}')
    retr_s=$(grep " sender\$" "$tmp_out" | tail -n1 | awk '{print $9}')
  else
    stat_s="FAIL"
  fi

  local thr_r stat_r="OK"
  if grep -q " receiver\$" "$tmp_out"; then
    thr_r=$(grep " receiver\$" "$tmp_out" | tail -n1 | awk '{printf"%.2f",$7}')
  else
    stat_r="FAIL"
  fi

  echo "[$ts] [#${no}] STATUS sender=$stat_s receiver=$stat_r" \
    | tee -a "$SUMMARY" "$OUTFILE"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,,sender\n' \
    "$no" "$proto" "$dir" "$dscp" "$streams" "$win" "$thr_s" "$retr_s" \
    >>"$CSV"
  printf '%s,%s,%s,%s,%s,%s,,,%s,receiver\n' \
    "$no" "$proto" "$dir" "$dscp" "$streams" "$win" "$thr_r" \
    >>"$CSV"

  [[ $stat_s == FAIL || $stat_r == FAIL ]] && EXIT_STATUS=1

  if [[ $proto == UDP && $mode == sat ]]; then
    awk '{print $9}' <<<"$(grep ' sender$' "$tmp_out")"
  else
    echo 0
  fi
}

##### Test‑matrix ##############################################################
TEST_NO=0
(( SKIP==1 )) && { say "Skipping all tests."; exit $EXIT_STATUS; }

for d in "${DSCP_CLASSES[@]}"; do
  tos=${TOS[$d]:-0}

  # --- TCP-Tests ---
  for dir in TX RX BD; do
    [[ $dir == BD && $BIDIR == 0 ]] && continue
    for s in "${TCP_PARALLEL_STREAMS[@]}"; do
      for w in "${TCP_WINDOW_SIZES[@]}"; do
        TEST_NO=$((TEST_NO+1))
        run_test "$TEST_NO" TCP "$dir" "$d" "$s" "$w" "" normal "$tos"
      done
    done
  done

  # --- UDP normal ---
  for dir in TX RX; do
    slot
    TEST_NO=$((TEST_NO+1))
    run_test "$TEST_NO" UDP "$dir" "$d" 1 "" "$UDP_START_BW" normal "$tos" &
  done

  # --- UDP sat (early‑break) ---
  cur=$(h2m "$UDP_START_BW")
  max=$(h2m "$UDP_MAX_BW")
  step=$(h2m "$UDP_BW_STEP")
  (( step <= 0 )) && step=1
  (( max < cur )) && max=$cur
  for dir in TX RX; do
    while (( cur <= max )); do
      slot
      TEST_NO=$((TEST_NO+1))
      res=$(run_test "$TEST_NO" UDP "$dir" "$d" 1 "" "${cur}M" sat "$tos")
      awk -v x="$res" -v thr="$UDP_LOSS_THRESHOLD" 'BEGIN{exit !(x>thr)}' && break
      cur=$((cur+step))
    done
    cur=$(h2m "$UDP_START_BW")
  done
done
wait

##### Final summary ############################################################
echo -e "\n*** CSV summary: $CSV ***"
column -s, -t "$CSV"

exit $EXIT_STATUS
