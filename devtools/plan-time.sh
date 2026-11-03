#!/usr/bin/env bash
# Checks that resolution stays fast: times ./build plan --new and, when
# there is a current build, ./build plan, against their time budgets, and
# fails when one goes over. The best of the runs counts, so a busy machine
# does not fail it; the first run may also restore references.
#
#   plan-time.sh [-n <runs>] [-s <dir>]
#
#   -n <runs>   runs of each (default 3)
#   -s <dir>    save each plan's output (plan-new.txt, plan.txt) there, to
#               compare before and after a change: it must stay the same
#
# The budgets, in seconds: POS_PLAN_NEW_BUDGET (default 10) and
# POS_PLAN_BUDGET (default 5), for the pos project (~190 packages).

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
runs=3 save=
while getopts n:s: o; do
  case $o in
    n) runs=$OPTARG ;;
    s) save=$OPTARG ;;
    *) sed -n '2,/^$/s/^# \{0,1\}//p' "$0" >&2; exit 2 ;;
  esac
done
[[ $runs =~ ^[1-9][0-9]*$ ]] || { echo "runs is a number, not '$runs'" >&2; exit 2; }
[[ -z $save ]] || mkdir -p "$save"

# Time a plan: sets BEST to the shortest of the runs, in seconds (%.1f),
# and saves the last run's output as $save/$1.txt. A plan that cannot
# build everything exits 1 and is timed all the same; STATUS says so.
# Inputs:
#   $1      name (plan-new, plan)
#   ${@:2}  ./build plan arguments
# Outputs:
#   BEST, BEST_MS, STATUS (" (exit <n>)", or nothing)
time_plan() {
  local name=$1 i start ms best= out rc
  shift
  out=$(mktemp)
  for ((i = 0; i < runs; i++)); do
    start=${EPOCHREALTIME/[.,]/}
    rc=0
    "$base/build" plan "$@" >"$out" 2>&1 || rc=$?
    ms=$(( (${EPOCHREALTIME/[.,]/} - start) / 1000 ))
    [[ -n $best ]] && ((best <= ms)) || best=$ms
  done
  [[ -z $save ]] || mv "$out" "$save/$name.txt"
  rm -f "$out"
  BEST_MS=$best
  STATUS=
  ((rc == 0)) || STATUS=" (exit $rc)"
  BEST=$((best / 1000)).$((best % 1000 / 100))
}

# Check a plan's best time against its budget.
# Inputs:
#   $1      label, $2 budget in seconds; BEST, BEST_MS, STATUS
# Outputs:
#   over (set when over)
check() {
  if ((BEST_MS > $2 * 1000)); then
    echo "$1: ${BEST}s, over the budget of $2s$STATUS"
    over=1
  else
    echo "$1: ${BEST}s (budget $2s)$STATUS"
  fi
}

over=
time_plan plan-new --new
check "plan --new" "${POS_PLAN_NEW_BUDGET:-10}"
if [[ -e $base/work/builds/current ]]; then
  time_plan plan
  check "plan" "${POS_PLAN_BUDGET:-5}"
else
  echo "plan: no current build, not timed"
fi
[[ -z $over ]] || {
  echo "profile it: PS4='+\${EPOCHREALTIME} \${FUNCNAME[0]:-main}:\${LINENO} ' bash -x buildsys/build.sh plan --new" >&2
  exit 1
}
