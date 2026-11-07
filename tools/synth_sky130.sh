#!/usr/bin/env bash
# Area and longest combinational path of SoC configurations on sky130 (Yosys + ABC).
#
#   tools/synth_sky130.sh                 every configuration in configs/
#   tools/synth_sky130.sh rabbit3 rabbit3_rv32i     selected ones
#
# Finds the sky130_fd_sc_hd typical-corner liberty file in $SKY130_LIB, or
# under $PDK_ROOT, or under ~/.ciel / ~/.volare (ciel / volare installs).
# Numbers are a quick comparison, not sign-off: no wires, no placement, and
# ABC's delay varies by about +-0.6 ns between runs of nearly the same RTL.
# Logs: build/synth_sky130/<config>.log
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

LIB=${SKY130_LIB:-}
if [ -z "$LIB" ]; then
  LIB=$(ls ${PDK_ROOT:-/nonexistent}/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
           ~/.ciel/ciel/sky130/versions/*/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
           ~/.volare/volare/sky130/versions/*/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
           2>/dev/null | head -1 || true)
fi
if [ -z "$LIB" ] || [ ! -f "$LIB" ]; then
  echo "sky130 liberty not found: set SKY130_LIB=/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib"
  echo "(install the PDK with: pip install ciel && ciel enable --pdk sky130 <version>)"
  exit 1
fi

OUT=build/synth_sky130
mkdir -p "$OUT"
CONFIGS=${*:-$(ls configs/*.mk | xargs -n1 basename | sed 's/\.mk$//')}

printf '%-16s %14s %12s %12s\n' config "area um2" "of it flops" "delay ns"
for c in $CONFIGS; do
  SRC=$(tools/core_sources.sh "$c" "$OUT/src_$c")
  yosys -p "read_slang $SRC --top rabbit_cpu -DSYNTHESIS; \
            synth -top rabbit_cpu -booth -flatten; \
            dfflibmap -liberty $LIB; \
            abc -liberty $LIB -dont_use *lpflow* -script $REPO/tools/abc_sky130.scr; \
            stat -liberty $LIB" > "$OUT/$c.log" 2>&1 || { echo "$c: synthesis failed, see $OUT/$c.log"; continue; }
  area=$(grep 'Chip area for module' "$OUT/$c.log" | tail -1 | awk '{print $NF}')
  seq=$(grep 'used for sequential elements' "$OUT/$c.log" | tail -1 | awk '{print $(NF-1)}')
  dly=$(grep -oE 'Delay *= *[0-9.]+ ps' "$OUT/$c.log" | tail -1 | grep -oE '[0-9.]+')
  printf '%-16s %14.0f %12.0f %12.2f\n' "$c" "$area" "$seq" "$(echo "$dly / 1000" | bc -l)"
done
