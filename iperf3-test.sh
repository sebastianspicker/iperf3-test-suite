#!/bin/bash
# Bash-Skript zur Automatisierung von iperf3-Netzwerktests mit umfassender Funktionalität und Logging.
#
# Features:
# - Unterstützt TCP-Tests in drei Richtungen (TX, RX, BD) mit konfigurierbaren Fenstergrößen und parallelen Streams.
# - Unterstützt UDP-Tests (TX und RX) mit konfigurierbarer Startbandbreite.
# - Definierbare DSCP-Klassen (z.B. CS0, AF11, CS5, EF, AF41) – werden in allen Richtungen getestet.
# - UDP-Saturation-Tests (TX und RX) mit steigender Bandbreite bis zur konfigurierten Verlustschwelle.
# - Adaptive Zielverfügbarkeits-Prüfung via ping und nc; Tests werden übersprungen, wenn Ziel nicht erreichbar.
# - Automatische IPv6-Erkennung und Verwendung für Tests, falls verfügbar.
# - Fortschrittsanzeige (Punkte) während jedes Tests.
# - Logging der Ergebnisse in Text-, CSV- und JSON-Dateien mit Zeitstempel.
# - Tabellarische Zusammenfassung nach Testende (auf Konsole und im Text-Log).
# - Verwendung von jq und awk zum Parsen der iperf3-Ausgaben und Formatieren der Ergebnisse.
# - Robuste Fehlerbehandlung für leere/ungültige JSON-Ausgaben (markiert als FAIL).
#
# Voraussetzungen: iperf3 (Version >= 3.7 für BD-Tests), jq, awk, ping, nc.
# Aufruf: ./iperf_tests.sh <Zielhost> [Port]
# Beispiel: ./iperf_tests.sh iperf.example.com 5201

# Prüfe Eingabeparameter (mindestens Zielhost)
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 <target_host_or_ip> [port]" >&2
    echo "Beispiel: $0 iperf.example.com 5201" >&2
    exit 1
fi

TARGET="$1"
PORT="${2:-5201}"

# Prüfe erforderliche Tools
for cmd in iperf3 jq awk ping nc; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "Error: Required tool '$cmd' is not installed." >&2
        exit 1
    fi
done

# Prüfe iperf3-Version für BD-Unterstützung (benötigt >= 3.7)
IPERF_VERSION=$(iperf3 --version 2>&1 | awk 'NR==1{print $2}')
IPERF_MAJOR=$(echo "$IPERF_VERSION" | cut -d. -f1)
IPERF_MINOR=$(echo "$IPERF_VERSION" | cut -d. -f2)
BIDIR_SUPPORTED=0
if [ -n "$IPERF_MAJOR" ] && [ -n "$IPERF_MINOR" ]; then
    if [ "$IPERF_MAJOR" -ge 3 ] && [ "$IPERF_MINOR" -ge 7 ]; then
        BIDIR_SUPPORTED=1
    fi
fi

# Ermittele IP-Version und Erreichbarkeit des Ziels
IP_VERSION="4"
PING_CMD="ping -c1 -W1"
NC_CMD="nc -z -w2"
if [[ "$TARGET" == *:* ]]; then
    # IPv6-Adresse erkannt
    IP_VERSION="6"
    PING_CMD="ping6 -c1 -W1"
    NC_CMD="nc -6 -z -w2"
fi

PING_SUCCESS=0
if [ "$IP_VERSION" = "4" ]; then
    if $PING_CMD "$TARGET" >/dev/null 2>&1; then
        PING_SUCCESS=1
    else
        # Wenn IPv4 fehlschlägt, versuche IPv6
        if ping6 -c1 -W1 "$TARGET" >/dev/null 2>&1; then
            IP_VERSION="6"
            PING_SUCCESS=1
            NC_CMD="nc -6 -z -w2"
        fi
    fi
else
    # IPv6 vorgesehen
    if $PING_CMD "$TARGET" >/dev/null 2>&1; then
        PING_SUCCESS=1
    fi
fi

if [ $PING_SUCCESS -ne 1 ]; then
    echo "Target $TARGET is unreachable (ping failed). Skipping tests." >&2
    exit 0
fi

# Prüfe TCP-Port mit nc (iperf3-Server erreichbar?)
if ! $NC_CMD "$TARGET" $PORT >/dev/null 2>&1; then
    echo "Target $TARGET port $PORT is not reachable (iperf3 server not responding). Skipping tests." >&2
    exit 0
fi

# Konfiguration (anpassbare Variablen)
DURATION=10                # Testdauer pro iperf3-Lauf (Sekunden)
OMIT=1                     # Warmup-Zeit in Sek. (ersten 1s ignorieren für stabilere Messung)
# TCP_PARALLEL_STREAMS=(1 4 8)        # parallele TCP-Streams
TCP_PARALLEL_STREAMS=(1)
# TCP_WINDOW_SIZES=("default" "128K" "256K")      # TCP-Fenstergrößen
TCP_WINDOW_SIZES=("default")
# DSCP_CLASSES=("CS0" "AF11" "CS5" "EF" "AF41")  # zu testende DSCP-Klassen
DSCP_CLASSES=("EF" "AF41")
UDP_START_BW="10M"        # Startbandbreite für UDP-Tests
UDP_MAX_BW="100M"            # maximale Bandbreite für UDP-Saturation
UDP_BW_STEP="10M"         # Schrittweite der Bandbreitenerhöhung (UDP-Saturation)
UDP_LOSS_THRESHOLD=5.0     # Verlustschwelle (%) für UDP-Saturation

# DSCP-Klassen auf TOS-Wert (DSCP<<2) mappen
declare -A DSCP_TOS
DSCP_TOS["CS0"]=0
DSCP_TOS["CS1"]=$((1*8<<2))   # CS1 = DSCP 8 -> TOS 32
DSCP_TOS["CS2"]=$((2*8<<2))
DSCP_TOS["CS3"]=$((3*8<<2))
DSCP_TOS["CS4"]=$((4*8<<2))
DSCP_TOS["CS5"]=$((5*8<<2))
DSCP_TOS["CS6"]=$((6*8<<2))
DSCP_TOS["CS7"]=$((7*8<<2))
# AF-Klassen (Assured Forwarding)
DSCP_TOS["AF11"]=$((10<<2))  # DSCP 10 -> TOS 40
DSCP_TOS["AF12"]=$((12<<2))
DSCP_TOS["AF13"]=$((14<<2))
DSCP_TOS["AF21"]=$((18<<2))
DSCP_TOS["AF22"]=$((20<<2))
DSCP_TOS["AF23"]=$((22<<2))
DSCP_TOS["AF31"]=$((26<<2))
DSCP_TOS["AF32"]=$((28<<2))
DSCP_TOS["AF33"]=$((30<<2))
DSCP_TOS["AF41"]=$((34<<2))
DSCP_TOS["AF42"]=$((36<<2))
DSCP_TOS["AF43"]=$((38<<2))
# Expedited Forwarding (EF)
DSCP_TOS["EF"]=$((46<<2))    # EF = DSCP 46 -> TOS 184

# Log-Dateien mit Zeitstempel vorbereiten
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FN=$(date '+%Y%m%d_%H%M%S')
SUMMARY_FILE="iperf_summary_${TIMESTAMP_FN}.log"
CSV_FILE="iperf_results_${TIMESTAMP_FN}.csv"
JSON_FILE="iperf_results_${TIMESTAMP_FN}.json"

# Schreibe Header in Log-Dateien
echo "[${TIMESTAMP}] Starting iperf3 tests (Target: ${TARGET}, Port: ${PORT}, Duration: ${DURATION}s, Streams: ${TCP_PARALLEL_STREAMS[*]}, Windows: ${TCP_WINDOW_SIZES[*]}, DSCP: ${DSCP_CLASSES[*]}, UDP start BW: ${UDP_START_BW}, Loss threshold: ${UDP_LOSS_THRESHOLD}%)" > "$SUMMARY_FILE"
echo "TestNo,Protocol,Direction,DSCP,Streams,Window,Bandwidth,Throughput_Mbps,Jitter_ms,Loss_pct,Retransmits,Status" > "$CSV_FILE"
# JSON-Datei initialisieren
echo "{" > "$JSON_FILE"
echo "  \"timestamp\": \"${TIMESTAMP}\"," >> "$JSON_FILE"
echo "  \"target\": \"${TARGET}\"," >> "$JSON_FILE"
echo "  \"results\": [" >> "$JSON_FILE"

# Testzähler vorbereiten
test_no=0
total_tcp_tests=$(( ${#DSCP_CLASSES[@]} * 3 * ${#TCP_PARALLEL_STREAMS[@]} * ${#TCP_WINDOW_SIZES[@]} ))
total_udp_fixed_tests=$(( ${#DSCP_CLASSES[@]} * 2 ))
# Obere Schranke für UDP-Saturation-Schleifen berechnen (für Fortschrittsanzeige)
to_mbps() {
    local bw_str="$1"
    local num=$(echo "$bw_str" | sed 's/[^0-9.]//g')
    local unit=$(echo "$bw_str" | sed 's/[0-9.]//g')
    case "$unit" in
        "G"|"g") echo $(awk "BEGIN {printf \"%d\", $num * 1000}") ;;
        "K"|"k") echo $(awk "BEGIN {printf \"%d\", $num / 1000}") ;;
        "M"|"m"|"") echo $(awk "BEGIN {printf \"%d\", $num}") ;;
        *) echo $(awk "BEGIN {printf \"%d\", $num}") ;;
    esac
}
START_Mbps=$(to_mbps "$UDP_START_BW")
MAX_Mbps=$(to_mbps "$UDP_MAX_BW")
STEP_Mbps=$(to_mbps "$UDP_BW_STEP")
if [ $STEP_Mbps -lt 1 ]; then STEP_Mbps=1; fi
udp_steps=0
if [ $MAX_Mbps -gt $START_Mbps ]; then
    udp_steps=$(( ($MAX_Mbps - $START_Mbps) / $STEP_Mbps ))
fi
udp_steps=$((udp_steps + 1))
total_udp_saturation_tests=$(( ${#DSCP_CLASSES[@]} * 2 * udp_steps ))
total_estimated_tests=$(( total_tcp_tests + total_udp_fixed_tests + total_udp_saturation_tests ))

# Temporäre Datei für iperf3-Ausgabe
TMP_JSON=$(mktemp)

# Fortschrittsanzeige (Punkte während ein Hintergrundprozess läuft)
progress_dots() {
    local pid=$1
    while kill -0 $pid 2>/dev/null; do
        printf "."
        sleep 1
    done
}

# Tests ausführen
first_json=1
for DSCP in "${DSCP_CLASSES[@]}"; do
    tos_value=${DSCP_TOS[$DSCP]:-0}
    echo "" | tee -a "$SUMMARY_FILE"
    echo "DSCP $DSCP (TOS $tos_value):" | tee -a "$SUMMARY_FILE"

    # TCP-Tests (TX, RX, BD)
    for direction in "TX" "RX" "BD"; do
        if [ "$direction" = "BD" ] && [ $BIDIR_SUPPORTED -ne 1 ]; then
            echo "Skipping TCP bidirectional test for DSCP $DSCP (iperf3 version ${IPERF_VERSION} does not support --bidir)" | tee -a "$SUMMARY_FILE"
            continue
        fi
        for streams in "${TCP_PARALLEL_STREAMS[@]}"; do
            for win in "${TCP_WINDOW_SIZES[@]}"; do
                protocol="TCP"
                iperf_cmd="iperf3 -c \"$TARGET\" -p $PORT -t $DURATION -J -O $OMIT"
                if [ "$IP_VERSION" = "6" ]; then
                    iperf_cmd="$iperf_cmd -6"
                fi
                if [ "$direction" = "RX" ]; then
                    iperf_cmd="$iperf_cmd -R"
                elif [ "$direction" = "BD" ]; then
                    iperf_cmd="$iperf_cmd --bidir"
                fi
                iperf_cmd="$iperf_cmd -P $streams -w $win"
                iperf_cmd="$iperf_cmd -S $tos_value"
                test_no=$((test_no+1))
                desc="$protocol $direction DSCP $DSCP - ${streams} stream(s), window $win"
                echo -n "Running test $test_no/$total_estimated_tests: $desc "
                eval "$iperf_cmd" > "$TMP_JSON" 2>&1 &
                pid=$!
                progress_dots $pid
                wait $pid
                exit_code=$?
                if [ $exit_code -ne 0 ]; then
                    echo " done (error)"
                else
                    echo " done."
                fi
                status="OK"
                throughput_mbps="" jitter_ms="" loss_pct="" retrans=""
                if ! jq -e . "$TMP_JSON" >/dev/null 2>&1; then
                    status="FAIL"
                    error_msg=$(grep -m1 -o "iperf3: .*" "$TMP_JSON")
                    echo "Test $test_no FAILED: $error_msg" | tee -a "$SUMMARY_FILE"
                else
                    if [ "$direction" = "BD" ]; then
                        # Bidirektional: Durchsatz und Retransmits für Up/Down
                        bps_up=$(jq -r '.end.sum_sent.bits_per_second' "$TMP_JSON")
                        bps_down=$(jq -r '.end.sum_received.bits_per_second' "$TMP_JSON")
                        retr_up=$(jq -r '.end.sum_sent.retransmits // 0' "$TMP_JSON")
                        retr_down=$(jq -r '.end.sum_received.retransmits // 0' "$TMP_JSON")
                        throughput_up=$(awk "BEGIN {printf \"%.2f\", $bps_up/1000000}")
                        throughput_down=$(awk "BEGIN {printf \"%.2f\", $bps_down/1000000}")
                        throughput_mbps="${throughput_up}/${throughput_down}"
                        retrans="${retr_up}/${retr_down}"
                        jitter_ms=""
                        loss_pct=""
                        echo "TCP BD ${streams}x$win: Up ${throughput_up} Mb/s, Down ${throughput_down} Mb/s, Retrans ${retr_up}/${retr_down}" | tee -a "$SUMMARY_FILE"
                    else
                        if [ "$direction" = "RX" ]; then
                            bps=$(jq -r '.end.sum_received.bits_per_second' "$TMP_JSON")
                            retr=$(jq -r '.end.sum_sent.retransmits // 0' "$TMP_JSON")
                        else
                            bps=$(jq -r '.end.sum_sent.bits_per_second' "$TMP_JSON")
                            retr=$(jq -r '.end.sum_sent.retransmits // 0' "$TMP_JSON")
                        fi
                        throughput_val=$(awk "BEGIN {printf \"%.2f\", $bps/1000000}")
                        throughput_mbps="$throughput_val"
                        retrans="$retr"
                        jitter_ms=""
                        loss_pct=""
                        echo "TCP $direction ${streams}x$win: ${throughput_val} Mb/s, Retrans $retr" | tee -a "$SUMMARY_FILE"
                    fi
                fi
                streams_field="$streams"
                window_field="$win"
                bandwidth_field=""
                echo "$test_no,$protocol,$direction,$DSCP,$streams_field,$window_field,$bandwidth_field,$throughput_mbps,$jitter_ms,$loss_pct,$retrans,$status" >> "$CSV_FILE"
                if [ $first_json -eq 1 ]; then
                    first_json=0
                    echo "    {" >> "$JSON_FILE"
                else
                    echo "    ," >> "$JSON_FILE"
                    echo "    {" >> "$JSON_FILE"
                fi
                echo "      \"test_no\": $test_no," >> "$JSON_FILE"
                echo "      \"protocol\": \"$protocol\"," >> "$JSON_FILE"
                echo "      \"direction\": \"$direction\"," >> "$JSON_FILE"
                echo "      \"dscp\": \"$DSCP\"," >> "$JSON_FILE"
                echo "      \"streams\": $streams," >> "$JSON_FILE"
                echo "      \"window\": \"$win\"," >> "$JSON_FILE"
                if [ -n "$bandwidth_field" ]; then
                    echo "      \"bandwidth_mbps\": $bandwidth_field," >> "$JSON_FILE"
                else
                    echo "      \"bandwidth_mbps\": null," >> "$JSON_FILE"
                fi
                # JSON throughput: wenn BD, Ausgabe als Objekt (up/down); sonst Zahl
                if [ "$direction" = "BD" ]; then
                    if [ "$status" = "OK" ]; then
                        echo "      \"throughput_mbps\": { \"up\": $(awk "BEGIN {print $bps_up/1000000}"), \"down\": $(awk "BEGIN {print $bps_down/1000000}") }," >> "$JSON_FILE"
                    else
                        echo "      \"throughput_mbps\": { \"up\": null, \"down\": null }," >> "$JSON_FILE"
                    fi
                else
                    if [ -n "$throughput_mbps" ]; then
                        numeric_thpt=$(echo "$throughput_mbps" | sed 's/[^0-9.\-]//g')
                        if [ -z "$numeric_thpt" ]; then numeric_thpt="0"; fi
                        echo "      \"throughput_mbps\": $numeric_thpt," >> "$JSON_FILE"
                    else
                        echo "      \"throughput_mbps\": null," >> "$JSON_FILE"
                    fi
                fi
                if [ -n "$jitter_ms" ]; then
                    echo "      \"jitter_ms\": $jitter_ms," >> "$JSON_FILE"
                else
                    echo "      \"jitter_ms\": null," >> "$JSON_FILE"
                fi
                if [ -n "$loss_pct" ]; then
                    echo "      \"loss_percent\": $loss_pct," >> "$JSON_FILE"
                else
                    echo "      \"loss_percent\": null," >> "$JSON_FILE"
                fi
                if [ -n "$retrans" ]; then
                    if [[ "$retrans" == *"/"* ]]; then
                        echo "      \"retransmits\": \"$retrans\"," >> "$JSON_FILE"
                    else
                        echo "      \"retransmits\": $retrans," >> "$JSON_FILE"
                    fi
                else
                    echo "      \"retransmits\": null," >> "$JSON_FILE"
                fi
                echo "      \"status\": \"$status\"" >> "$JSON_FILE"
                echo "    }" >> "$JSON_FILE"
            done
        done
    done

    # UDP-Tests (feste Startbandbreite)
    for direction in "TX" "RX"; do
        protocol="UDP"
        streams=1
        win=""
        bandwidth=$UDP_START_BW
        test_no=$((test_no+1))
        desc="$protocol $direction DSCP $DSCP - ${bandwidth} start"
        iperf_cmd="iperf3 -c \"$TARGET\" -p $PORT -u -t $DURATION -J -b $bandwidth"
        if [ "$IP_VERSION" = "6" ]; then
            iperf_cmd="$iperf_cmd -6"
        fi
        if [ "$direction" = "RX" ]; then
            iperf_cmd="$iperf_cmd -R"
        fi
        iperf_cmd="$iperf_cmd -S $tos_value"
        echo -n "Running test $test_no/$total_estimated_tests: $desc "
        eval "$iperf_cmd" > "$TMP_JSON" 2>&1 &
        pid=$!
        progress_dots $pid
        wait $pid
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo " done (error)"
        else
            echo " done."
        fi
        status="OK"
        throughput_mbps="" jitter_ms="" loss_pct="" retrans=""
        if ! jq -e . "$TMP_JSON" >/dev/null 2>&1; then
            status="FAIL"
            error_msg=$(grep -m1 -o "iperf3: .*" "$TMP_JSON")
            echo "Test $test_no FAILED: $error_msg" | tee -a "$SUMMARY_FILE"
        else
            delivered_bps=$(jq -r '.end.sum.bits_per_second // 0' "$TMP_JSON")
            jitter=$(jq -r '.end.sum.jitter_ms // 0' "$TMP_JSON")
            lost_packets=$(jq -r '.end.sum.lost_percent // 0' "$TMP_JSON")
            total_packets=$(jq -r '.end.sum_received.packets // 0' "$TMP_JSON")
            if [ -z "$lost_packets" ] || [ -z "$total_packets" ] || [ "$total_packets" -eq 0 ]; then
                loss_percent=0
            else
                loss_percent=$(awk "BEGIN {printf \"%.2f\", ($lost_packets/$total_packets)*100}")
            fi
            throughput_val=$(awk "BEGIN {printf \"%.2f\", $delivered_bps/1000000}")
            throughput_mbps="$throughput_val"
            jitter_ms=$(awk "BEGIN {printf \"%.2f\", $jitter}")
            loss_pct="$loss_percent"
            retrans=""
            echo "UDP $direction $bandwidth: ${throughput_val} Mb/s, Jitter ${jitter_ms} ms, Loss ${loss_percent}%" | tee -a "$SUMMARY_FILE"
        fi
        streams_field="$streams"
        window_field=""
        bw_mbps=$(to_mbps "$bandwidth")
        bandwidth_field="$bw_mbps"
        echo "$test_no,$protocol,$direction,$DSCP,$streams_field,$window_field,$bandwidth_field,$throughput_mbps,$jitter_ms,$loss_pct,$retrans,$status" >> "$CSV_FILE"
        if [ $first_json -eq 1 ]; then
            first_json=0
            echo "    {" >> "$JSON_FILE"
        else
            echo "    ," >> "$JSON_FILE"
            echo "    {" >> "$JSON_FILE"
        fi
        echo "      \"test_no\": $test_no," >> "$JSON_FILE"
        echo "      \"protocol\": \"$protocol\"," >> "$JSON_FILE"
        echo "      \"direction\": \"$direction\"," >> "$JSON_FILE"
        echo "      \"dscp\": \"$DSCP\"," >> "$JSON_FILE"
        echo "      \"streams\": 1," >> "$JSON_FILE"
        echo "      \"window\": null," >> "$JSON_FILE"
        echo "      \"bandwidth_mbps\": $bw_mbps," >> "$JSON_FILE"
        if [ -n "$throughput_mbps" ]; then
            numeric_thpt=$(echo "$throughput_mbps" | sed 's/[^0-9.\-]//g')
            if [ -z "$numeric_thpt" ]; then numeric_thpt="0"; fi
            echo "      \"throughput_mbps\": $numeric_thpt," >> "$JSON_FILE"
        else
            echo "      \"throughput_mbps\": null," >> "$JSON_FILE"
        fi
        if [ -n "$jitter_ms" ]; then
            echo "      \"jitter_ms\": $jitter_ms," >> "$JSON_FILE"
        else
            echo "      \"jitter_ms\": null," >> "$JSON_FILE"
        fi
        if [ -n "$loss_pct" ]; then
            echo "      \"loss_percent\": $loss_pct," >> "$JSON_FILE"
        else
            echo "      \"loss_percent\": null," >> "$JSON_FILE"
        fi
        echo "      \"retransmits\": null," >> "$JSON_FILE"
        echo "      \"status\": \"$status\"" >> "$JSON_FILE"
        echo "    }" >> "$JSON_FILE"
    done

    # UDP-Saturation-Tests
    for direction in "TX" "RX"; do
        protocol="UDP"
        streams=1
        win=""
        current_mbps=$START_Mbps
        saturation_done=0
        while [ $saturation_done -eq 0 ]; do
            if [ $current_mbps -gt $MAX_Mbps ]; then
                current_mbps=$MAX_Mbps
            fi
            if [ $current_mbps -ge 1000 ]; then
                bandwidth="${current_mbps}M"
            else
                bandwidth="${current_mbps}M"
            fi
            test_no=$((test_no+1))
            desc="$protocol $direction DSCP $DSCP - saturation ${bandwidth}"
            iperf_cmd="iperf3 -c \"$TARGET\" -p $PORT -u -t $DURATION -J -b $bandwidth"
            if [ "$IP_VERSION" = "6" ]; then
                iperf_cmd="$iperf_cmd -6"
            fi
            if [ "$direction" = "RX" ]; then
                iperf_cmd="$iperf_cmd -R"
            fi
            iperf_cmd="$iperf_cmd -S $tos_value"
            echo -n "Running test $test_no/$total_estimated_tests: $desc "
            eval "$iperf_cmd" > "$TMP_JSON" 2>&1 &
            pid=$!
            progress_dots $pid
            wait $pid
            exit_code=$?
            if [ $exit_code -ne 0 ]; then
                echo " done (error)"
            else
                echo " done."
            fi
            status="OK"
            throughput_mbps="" jitter_ms="" loss_pct="" retrans=""
            loss_percent=0
            if ! jq -e . "$TMP_JSON" >/dev/null 2>&1; then
                status="FAIL"
                error_msg=$(grep -m1 -o "iperf3: .*" "$TMP_JSON")
                echo "Test $test_no FAILED: $error_msg" | tee -a "$SUMMARY_FILE"
                saturation_done=1
            else
                delivered_bps=$(jq -r '.end.sum.bits_per_second // 0' "$TMP_JSON")
                jitter=$(jq -r '.end.sum.jitter_ms // 0' "$TMP_JSON")
                lost_packets=$(jq -r '.end.sum.lost_percent // 0' "$TMP_JSON")
                total_packets=$(jq -r '.end.sum_received.packets // 0' "$TMP_JSON")
                if [ -n "$total_packets" ] && [ "$total_packets" -gt 0 ] && [ -n "$lost_packets" ]; then
                    loss_percent=$(awk "BEGIN {printf \"%.2f\", ($lost_packets/$total_packets)*100}")
                else
                    loss_percent=0
                fi
                throughput_val=$(awk "BEGIN {printf \"%.2f\", $delivered_bps/1000000}")
                throughput_mbps="$throughput_val"
                jitter_ms=$(awk "BEGIN {printf \"%.2f\", $jitter}")
                loss_pct="$loss_percent"
                retrans=""
                echo "UDP $direction $bandwidth: ${throughput_val} Mb/s, Jitter ${jitter_ms} ms, Loss ${loss_percent}%" | tee -a "$SUMMARY_FILE"
                if (( $(awk "BEGIN {print ($loss_percent > $UDP_LOSS_THRESHOLD)}") )); then
                    saturation_done=1
                elif [ $current_mbps -eq $MAX_Mbps ]; then
                    saturation_done=1
                else
                    current_mbps=$(( current_mbps + STEP_Mbps ))
                fi
            fi
            streams_field="1"
            window_field=""
            bw_mbps=$(to_mbps "$bandwidth")
            bandwidth_field="$bw_mbps"
            echo "$test_no,$protocol,$direction,$DSCP,$streams_field,$window_field,$bandwidth_field,$throughput_mbps,$jitter_ms,$loss_pct,$retrans,$status" >> "$CSV_FILE"
            if [ $first_json -eq 1 ]; then
                first_json=0
                echo "    {" >> "$JSON_FILE"
            else
                echo "    ," >> "$JSON_FILE"
                echo "    {" >> "$JSON_FILE"
            fi
            echo "      \"test_no\": $test_no," >> "$JSON_FILE"
            echo "      \"protocol\": \"$protocol\"," >> "$JSON_FILE"
            echo "      \"direction\": \"$direction (saturation)\"," >> "$JSON_FILE"
            echo "      \"dscp\": \"$DSCP\"," >> "$JSON_FILE"
            echo "      \"streams\": 1," >> "$JSON_FILE"
            echo "      \"window\": null," >> "$JSON_FILE"
            echo "      \"bandwidth_mbps\": $bw_mbps," >> "$JSON_FILE"
            if [ -n "$throughput_mbps" ]; then
                numeric_thpt=$(echo "$throughput_mbps" | sed 's/[^0-9.\-]//g')
                if [ -z "$numeric_thpt" ]; then numeric_thpt="0"; fi
                echo "      \"throughput_mbps\": $numeric_thpt," >> "$JSON_FILE"
            else
                echo "      \"throughput_mbps\": null," >> "$JSON_FILE"
            fi
            if [ -n "$jitter_ms" ]; then
                echo "      \"jitter_ms\": $jitter_ms," >> "$JSON_FILE"
            else
                echo "      \"jitter_ms\": null," >> "$JSON_FILE"
            fi
            if [ -n "$loss_pct" ]; then
                echo "      \"loss_percent\": $loss_pct," >> "$JSON_FILE"
            else
                echo "      \"loss_percent\": null," >> "$JSON_FILE"
            fi
            echo "      \"retransmits\": null," >> "$JSON_FILE"
            echo "      \"status\": \"$status\"" >> "$JSON_FILE"
            echo "    }" >> "$JSON_FILE"
            if [ $saturation_done -eq 1 ]; then
                break
            fi
        done
    done
done

# JSON-Array und Objekt abschließen
echo "  ]" >> "$JSON_FILE"
echo "}" >> "$JSON_FILE"

# Temporäre Datei entfernen
rm -f "$TMP_JSON"

# Tabellarische Übersicht ausgeben (und ins Log schreiben)
echo -e "\nTest Summary:" | tee -a "$SUMMARY_FILE"
column -s, -t "$CSV_FILE" | tee -a "$SUMMARY_FILE"
echo "All tests completed. Results saved to $SUMMARY_FILE, $CSV_FILE, and $JSON_FILE." | tee -a "$SUMMARY_FILE"
