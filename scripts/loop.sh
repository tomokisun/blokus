#!/bin/bash
set -euo pipefail

CYCLES=${1:-5}
THRESHOLD=${2:-0.55}

echo "=== m4-loop: cycles=$CYCLES, promote_threshold=$THRESHOLD ==="

# Collect per-cycle results for final report
declare -a CYCLE_TS=()
declare -a CYCLE_WIN_A=()
declare -a CYCLE_WIN_B=()
declare -a CYCLE_SCORE_A=()
declare -a CYCLE_SCORE_B=()
declare -a CYCLE_RANK_A=()
declare -a CYCLE_RANK_B=()
declare -a CYCLE_ELO_B=()
declare -a CYCLE_PROMOTED=()

PROMOTED_COUNT=0

for i in $(seq 1 "$CYCLES"); do
  TS=$(date +%Y%m%d-%H%M%S)
  echo ""
  echo "========== cycle $i/$CYCLES (RUN_TS=$TS) =========="

  make m4-all RUN_TS="$TS"

  REPORT="Reports/eval-$TS.json"
  if [ ! -f "$REPORT" ]; then
    echo "ERROR: eval report not found: $REPORT"
    exit 1
  fi

  WIN_RATE_A=$(python3 -c "import json; print(json.load(open('$REPORT'))['winRateA'])")
  WIN_RATE_B=$(python3 -c "import json; print(json.load(open('$REPORT'))['winRateB'])")
  SCORE_A=$(python3 -c "import json; print(json.load(open('$REPORT'))['avgScoreA'])")
  SCORE_B=$(python3 -c "import json; print(json.load(open('$REPORT'))['avgScoreB'])")
  RANK_A=$(python3 -c "import json; print(json.load(open('$REPORT'))['avgRankA'])")
  RANK_B=$(python3 -c "import json; print(json.load(open('$REPORT'))['avgRankB'])")
  ELO_B=$(python3 -c "import json; print(json.load(open('$REPORT')).get('estimatedEloB', 'N/A'))")

  echo ""
  echo "--- eval result ---"
  echo "  win_rate: A=$WIN_RATE_A, B=$WIN_RATE_B"
  echo "  elo_b: $ELO_B"
  echo "  threshold: $THRESHOLD"

  PROMOTED="no"
  SHOULD_PROMOTE=$(python3 -c "print('yes' if $WIN_RATE_B >= $THRESHOLD else 'no')")
  if [ "$SHOULD_PROMOTE" = "yes" ]; then
    make m4-promote RUN_TS="$TS"
    echo "  -> PROMOTED (cycle $i)"
    PROMOTED="yes"
    PROMOTED_COUNT=$((PROMOTED_COUNT + 1))
  else
    echo "  -> SKIPPED promote (cycle $i)"
  fi

  CYCLE_TS+=("$TS")
  CYCLE_WIN_A+=("$WIN_RATE_A")
  CYCLE_WIN_B+=("$WIN_RATE_B")
  CYCLE_SCORE_A+=("$SCORE_A")
  CYCLE_SCORE_B+=("$SCORE_B")
  CYCLE_RANK_A+=("$RANK_A")
  CYCLE_RANK_B+=("$RANK_B")
  CYCLE_ELO_B+=("$ELO_B")
  CYCLE_PROMOTED+=("$PROMOTED")
done

echo ""
echo "================================================================"
echo "  FINAL REPORT: $CYCLES cycles completed, $PROMOTED_COUNT promoted"
echo "================================================================"
echo ""
printf "%-4s  %-16s  %7s  %7s  %8s  %8s  %6s  %6s  %8s  %s\n" \
  "#" "RUN_TS" "WIN_A" "WIN_B" "SCORE_A" "SCORE_B" "RNK_A" "RNK_B" "ELO_B" "PROMOTED"
printf "%-4s  %-16s  %7s  %7s  %8s  %8s  %6s  %6s  %8s  %s\n" \
  "---" "----------------" "-------" "-------" "--------" "--------" "------" "------" "--------" "--------"

for i in $(seq 0 $((CYCLES - 1))); do
  c=$((i + 1))
  promoted_mark=""
  if [ "${CYCLE_PROMOTED[$i]}" = "yes" ]; then
    promoted_mark="*** YES"
  else
    promoted_mark="no"
  fi
  printf "%-4s  %-16s  %7s  %7s  %8s  %8s  %6s  %6s  %8s  %s\n" \
    "$c" "${CYCLE_TS[$i]}" "${CYCLE_WIN_A[$i]}" "${CYCLE_WIN_B[$i]}" \
    "${CYCLE_SCORE_A[$i]}" "${CYCLE_SCORE_B[$i]}" \
    "${CYCLE_RANK_A[$i]}" "${CYCLE_RANK_B[$i]}" \
    "${CYCLE_ELO_B[$i]}" "$promoted_mark"
done

echo ""
echo "=== m4-loop completed ==="
