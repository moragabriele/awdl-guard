#!/bin/bash
# Measures Wi-Fi latency so you can compare AWDL allowed vs held down with real numbers.
#
#   ./scripts/latency-bench.sh [seconds] [target]
#
# Run it once with AWDL allowed and once held down (e.g. `awdl-guardctl allow 10`
# then `awdl-guardctl cancel` with Mode=off), ideally doing the same thing on the
# Mac each time. Each run appends a CSV row to ./latency-results.csv.
set -euo pipefail

DURATION="${1:-120}"
TARGET="${2:-$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')}"
INTERVAL=0.1
SPIKE_MS=30
RESULTS="${RESULTS:-latency-results.csv}"

if [ -z "$TARGET" ]; then
    echo "No default gateway found; pass a target host as 2nd argument." >&2
    exit 1
fi

AWDL_STATE=$(ifconfig awdl0 2>/dev/null | head -n1 | grep -q "<UP" && echo up || echo down)
COUNT=$(awk -v d="$DURATION" -v i="$INTERVAL" 'BEGIN { printf "%d", d / i }')

echo "Pinging $TARGET for ${DURATION}s ($COUNT packets), awdl0 is $AWDL_STATE..."
RAW=$(ping -i "$INTERVAL" -c "$COUNT" -W 1000 "$TARGET" 2>/dev/null || true)

STATS=$(printf '%s\n' "$RAW" | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p' | sort -n | awk -v sent="$COUNT" -v spike="$SPIKE_MS" '
    { v[NR] = $1; sum += $1; if ($1 > spike) spikes++ }
    function pct(p,   i) { i = int(p * NR + 0.5); if (i < 1) i = 1; if (i > NR) i = NR; return v[i] }
    END {
        if (NR == 0) { print "0,100,,,,,,,0"; exit }
        printf "%d,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d\n",
            NR, 100 * (sent - NR) / sent, v[1], sum / NR, pct(0.50), pct(0.95), pct(0.99), v[NR], spikes
    }')

# Jitter: mean absolute difference between consecutive replies, in send order.
JITTER=$(printf '%s\n' "$RAW" | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p' | awk '
    NR > 1 { d = $1 - prev; if (d < 0) d = -d; sum += d; n++ } { prev = $1 }
    END { if (n) printf "%.2f", sum / n; else print "" }')

IFS=, read -r RECV LOSS MIN AVG P50 P95 P99 MAX SPIKES <<< "$STATS"

printf '\n%-14s %s\n' "awdl0:" "$AWDL_STATE"
printf '%-14s %s / %s (loss %s%%)\n' "replies:" "$RECV" "$COUNT" "$LOSS"
printf '%-14s min %s  avg %s  p50 %s ms\n' "latency:" "$MIN" "$AVG" "$P50"
printf '%-14s p95 %s  p99 %s  max %s ms\n' "tail:" "$P95" "$P99" "$MAX"
printf '%-14s %s ms\n' "jitter:" "$JITTER"
printf '%-14s %s packets > %s ms\n' "spikes:" "$SPIKES" "$SPIKE_MS"

if [ ! -f "$RESULTS" ]; then
    echo "timestamp,awdl0,target,seconds,sent,received,loss_pct,min_ms,avg_ms,p50_ms,p95_ms,p99_ms,max_ms,jitter_ms,spikes_over_${SPIKE_MS}ms" > "$RESULTS"
fi
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$AWDL_STATE,$TARGET,$DURATION,$COUNT,$RECV,$LOSS,$MIN,$AVG,$P50,$P95,$P99,$MAX,$JITTER,$SPIKES" >> "$RESULTS"
echo "Saved to $RESULTS"
