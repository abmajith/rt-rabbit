#!/usr/bin/env bash
# Reproduce every check of the rabbit cores on your own machine.
#
#   tools/check_all.sh                 quick + gls            (~10 min)
#   tools/check_all.sh quick           lint, firmware on all cores, muldiv exhaustive sim  (~1 min)
#   tools/check_all.sh gls             firmware on the gate-level netlists                  (~10 min)
#   tools/check_all.sh formal          riscv-formal + timing + muldiv proof, both cores     (~60 min)
#   tools/check_all.sh synth           sky130 area / delay table (needs the sky130 PDK)     (~1 min)
#   tools/check_all.sh mutants         plant known bugs, check they are caught              (~30-60 min)
#   tools/check_all.sh all             everything above                                     (~2-3 h)
#
# Several stages can be given: tools/check_all.sh quick formal
# Logs: build/check_all/<stage>/...   Summary at the end; exit code 1 if anything failed.
#
# Needs (as in CI): verilator >= 5.03x, yosys with the slang frontend, sby +
# boolector + yosys-abc (OSS CAD Suite has all of them), riscv64-unknown-elf-gcc,
# uv. "synth" also needs the sky130 PDK (see tools/synth_sky130.sh).
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

STAGES=${*:-quick gls}
[ "$STAGES" = all ] && STAGES="quick gls formal synth mutants"
LOGS=build/check_all
mkdir -p "$LOGS"
SUMMARY=()
FAILED=0

need() { command -v "$1" >/dev/null || { echo "missing tool: $1"; exit 1; }; }
need make; need verilator; need yosys; need uv; need riscv64-unknown-elf-gcc
case " $STAGES " in *" formal "*|*" mutants "*) need sby; need yosys-abc ;; esac

# step <log name> <expected text in output or ""> <command...>
step() {
  local name=$1 expect=$2; shift 2
  local log="$LOGS/$name.log" t0=$SECONDS
  mkdir -p "$(dirname "$log")"
  printf '%-36s ' "$name"
  if "$@" > "$log" 2>&1 && { [ -z "$expect" ] || grep -q "$expect" "$log"; }; then
    local extra; extra=$(grep -oE 'finished after [0-9]+ cycles|[0-9]+/[0-9]+ checks PASS' "$log" | tail -1)
    printf 'PASS  %5ds  %s\n' $((SECONDS - t0)) "$extra"
    SUMMARY+=("PASS  $name  $extra")
  else
    printf 'FAIL  %5ds  see %s\n' $((SECONDS - t0)) "$log"
    SUMMARY+=("FAIL  $name  ($log)")
    FAILED=1
  fi
}

for stage in $STAGES; do
  echo "=== $stage"
  case $stage in
    quick)
      for c in rabbit3 rabbit5 cv32e40p; do
        step "quick/lint-$c" "" make lint CORE=$c
        for p in hello irq muldiv; do
          step "quick/sim-$c-$p" "RESULT: PASS" make soc-sim CORE=$c PROG=$p
        done
      done
      step "quick/muldiv-exhaustive-8bit" "RESULT: PASS" make -C dv/formal/rabbit muldiv-sim
      ;;
    gls)
      for c in rabbit3 rabbit5; do
        for p in hello irq muldiv; do
          step "gls/$c-$p" "RESULT: PASS" make gls-smoke CORE=$c PROG=$p
        done
      done
      ;;
    formal)
      step "formal/muldiv-unit" "" make -C dv/formal/rabbit muldiv
      for c in rabbit5 rabbit3; do
        step "formal/$c-riscv-formal" "53/53 checks PASS" make -C dv/formal/rabbit CORE=$c riscv-formal
        step "formal/$c-timing" "" make -C dv/formal/rabbit CORE=$c timing
      done
      ;;
    synth)
      step "synth/sky130" "" tools/synth_sky130.sh
      cat "$LOGS/synth/sky130.log"
      ;;
    mutants)
      step "mutants/all" "" python3 tools/mutants.py --baseline
      tail -12 "$LOGS/mutants/all.log"
      ;;
    *) echo "unknown stage: $stage"; exit 2 ;;
  esac
done

echo
echo "=== summary ($STAGES)"
printf '%s\n' "${SUMMARY[@]}"
[ $FAILED = 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit $FAILED
