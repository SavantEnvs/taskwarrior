#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Pre-built by mayhem/build.sh (normal flags, separate build-tests/ tree). Never compiled here.
BT="$SRC/build-tests"
TASK="$BT/src/task"; CALC="$BT/src/calc"; LEX="$BT/src/lex"; RUNNER="$BT/test/test_runner"
for b in "$TASK" "$CALC" "$LEX" "$RUNNER"; do
  [ -x "$b" ] || { echo "missing $b — mayhem/build.sh did not produce it" >&2; emit_ctrf "taskwarrior" 0 1; exit 1; }
done

# The default config does `include default.theme`, resolved from the CWD: run everything from doc/rc.
cd "$SRC/doc/rc"

passed=0; failed=0; skipped=0

# 1) Upstream's C++ unit tests (TAP): each test source is a separate `test_runner <name>`.
for n in $(grep -o '[a-z_0-9]*_test(' "$BT/test/cpp_tests.cpp" | tr -d '(' | sort -u); do
  line=$(timeout 600 "$RUNNER" "$n" 2>&1 | grep -E '^# [0-9]+ passed, [0-9]+ failed' | tail -1)
  if [ -z "$line" ]; then echo "FAIL unit:$n (no TAP summary)"; failed=$((failed+1)); continue; fi
  p=$(sed -E 's/^# ([0-9]+) passed.*/\1/' <<<"$line")
  f=$(sed -E 's/^# [0-9]+ passed, ([0-9]+) failed.*/\1/' <<<"$line")
  s=$(sed -E 's/.*failed, ([0-9]+) skipped.*/\1/' <<<"$line")
  echo "unit:$n $line"
  passed=$((passed+p)); failed=$((failed+f)); skipped=$((skipped+s))
done

# 2) Known-answer tests on the built CLI binaries: fixed input -> asserted output value.
kat() {  # kat <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); else echo "FAIL kat:$1 expected [$2] got [$3]"; failed=$((failed+1)); fi
}
strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }

kat calc-prec        "7"                    "$("$CALC" '1+2*3' 2>&1)"
kat calc-paren       "18"                   "$("$CALC" '(2+3)*4 - 6/3' 2>&1)"
kat calc-exp         "1024"                 "$("$CALC" '2 ^ 10' 2>&1)"
kat calc-mod         "1"                    "$("$CALC" '7%3' 2>&1)"
kat calc-neg         "10"                   "$("$CALC" '-5 * -2' 2>&1)"
kat calc-cmp-true    "true"                 "$("$CALC" '3 > 2' 2>&1)"
kat calc-cmp-false   "false"                "$("$CALC" '1 == 2' 2>&1)"
kat calc-date-add    "2019-01-02T00:00:00"  "$("$CALC" '2019-01-01 + 1d' 2>&1)"
kat calc-duration    "PT1H30M"              "$("$CALC" '1h + 30min' 2>&1)"
kat lex-tokens       "argument 'pro:x +tag'
  token 'pro:x' pair
  token '+tag' tag" "$("$LEX" 'pro:x +tag' 2>&1 | strip)"

# 3) End-to-end through the real taskchampion-backed datastore, in a throwaway TASKDATA.
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export TASKRC="$W/taskrc" TASKDATA="$W/data"; mkdir -p "$TASKDATA"
printf 'data.location=%s\nconfirmation=off\ncolor=off\nverbose=nothing\n' "$TASKDATA" > "$TASKRC"
"$TASK" add hello world +foo priority:H >/dev/null 2>&1
"$TASK" add second one project:work >/dev/null 2>&1
kat task-count       "2"            "$("$TASK" count 2>&1)"
kat task-count-tag   "1"            "$("$TASK" +foo count 2>&1)"
kat task-count-proj  "1"            "$("$TASK" project:work count 2>&1)"
kat task-get-desc    "hello world"  "$("$TASK" _get 1.description 2>&1)"
kat task-get-prio    "H"            "$("$TASK" _get 1.priority 2>&1)"
kat task-get-tags    "foo"          "$("$TASK" _get 1.tags 2>&1)"
kat task-export      "hello world|H|pending|foo|6.8;second one||pending||1;" \
  "$("$TASK" export 2>/dev/null | python3 -c '
import json,sys
print("".join("%s|%s|%s|%s|%s;" % (t["description"], t.get("priority",""), t["status"], ",".join(t.get("tags",[])), t["urgency"]) for t in json.load(sys.stdin)))')"
"$TASK" 1 done >/dev/null 2>&1
kat task-done-count  "1"            "$("$TASK" status:completed count 2>&1)"
kat task-pending     "1"            "$("$TASK" status:pending count 2>&1)"

[ "$passed" -gt 0 ] || { echo "no tests passed" >&2; failed=$((failed+1)); }
emit_ctrf "taskwarrior (test_runner + calc/lex/task KATs)" "$passed" "$failed" "$skipped"
