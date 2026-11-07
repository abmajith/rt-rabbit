#!/usr/bin/env bash
# Energy of one program on one routed core, from real switching activity.
#
#   asic/orfs/energy.sh <core> [program] [period of the ORFS run, ns] [platform]
#   asic/orfs/energy.sh rabbit3 hello            # uses build/orfs/sky130hd/rabbit3_8.0ns
#
# Needs a finished asic/orfs/run.sh of that core. Steps:
#  1. Yosys rebuilds every sky130 cell of the routed netlist (6_final.v) from
#     the logic function in the cell library, so Verilator can simulate it.
#     The cells stay separate modules: flattening would rename the routed
#     wires, and OpenSTA matches the activity to the layout by wire name;
#  2. the SoC testbench runs the program on that netlist and records every
#     wire (VCD); the program must still PASS (a post-layout check);
#  3. OpenSTA computes power from that activity, with the wire capacitances
#     of the layout (SPEF), at the simulation clock (10 ns = 100 MHz);
#  4. energy = power x cycles x 10 ns.
# Output: build/orfs/<platform>/<core>_<period>ns/energy/<program>.*
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
CORE=${1:?usage: asic/orfs/energy.sh <core> [program] [period ns] [platform]}
PROG=${2:-hello}
PERIOD=${3:-8.0}
PLATFORM=${4:-sky130hd}
SIM_PERIOD_NS=10      # the cocotb testbench clock
IMAGE=${ORFS_IMAGE:-openroad/orfs@sha256:8b4f3942318d740ea1f73f4f895bbac150b32e41eb3b7baf7722adec6538bbcf}

WORK=$REPO/build/orfs/$PLATFORM/${CORE}_${PERIOD}ns
RES=$WORK/results/$PLATFORM/$CORE/base
OUT=$WORK/energy
[ -f "$RES/6_final.v" ] || { echo "no routed netlist: run asic/orfs/run.sh $CORE $PLATFORM $PERIOD first"; exit 1; }
mkdir -p "$OUT"

case $PLATFORM in
  sky130hd) LIB_IN_IMAGE=/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib ;;
  ihp-sg13g2) LIB_IN_IMAGE=/OpenROAD-flow-scripts/flow/platforms/ihp-sg13g2/lib/sg13g2_stdcell_typ_1p20V_25C.lib ;;
  *) echo "unknown platform $PLATFORM"; exit 1 ;;
esac

# 1. functional netlist (the liberty file is read from the image, so both
#    steps use exactly the same cell library)
if [ ! -f "$OUT/rabbit_cpu_pnr.v" ] || [ "$RES/6_final.v" -nt "$OUT/rabbit_cpu_pnr.v" ]; then
  docker run --rm -u "$(id -u):$(id -g)" -v "$REPO:$REPO" "$IMAGE" bash -c "
    cd /OpenROAD-flow-scripts && source env.sh > /dev/null 2>&1
    yosys -q -l $OUT/import.log -p 'read_liberty -ignore_miss_func -ignore_miss_dir $LIB_IN_IMAGE; \
      read_verilog $RES/6_final.v; hierarchy -top rabbit_cpu; \
      write_verilog -noattr $OUT/rabbit_cpu_pnr.v'"
fi

# 2. run the program on it, recording every wire (also the _123_ ones).
#    One run at a time: the testbench always writes dump.fst in its folder.
cd "$REPO/dv/cocotb/soc"
rm -f dump.fst
uv run make -j8 CORE="$CORE" PROG="$PROG" GLS=1 NETLIST="$OUT/rabbit_cpu_pnr.v" WAVES=1 \
     VERILATOR_EXTRA=--trace-underscore SIM_BUILD="sim_build_${CORE}_pnr_${PLATFORM}" > "$OUT/$PROG.sim.log" 2>&1 || true
CYCLES=$(grep -oE 'finished after [0-9]+ cycles' "$OUT/$PROG.sim.log" | grep -oE '[0-9]+' || true)
grep -q "RESULT: PASS" "$OUT/$PROG.sim.log" || { echo "$CORE/$PROG: program failed on the routed netlist, see $OUT/$PROG.sim.log"; exit 1; }
# OpenSTA's VCD reader knows 'wire' but not 'logic' (only a type label in VCD)
fst2vcd dump.fst 2>/dev/null | sed 's/^\$var logic /$var wire /' > "$OUT/$PROG.vcd"
rm -f dump.fst

# 3. power from the activity
cat > "$OUT/$PROG.power.tcl" <<EOF
read_db $RES/6_final.odb
read_liberty $LIB_IN_IMAGE
read_sdc $RES/6_final.sdc
read_spef $RES/6_final.spef
create_clock -name clk -period $SIM_PERIOD_NS [get_ports clk_i]
read_vcd -scope rabbit_soc_sim/u_cpu $OUT/$PROG.vcd
report_activity_annotation
report_power
EOF
docker run --rm -u "$(id -u):$(id -g)" -v "$REPO:$REPO" "$IMAGE" bash -c "
  cd /OpenROAD-flow-scripts && source env.sh > /dev/null 2>&1
  openroad -no_init -exit $OUT/$PROG.power.tcl" > "$OUT/$PROG.power.log" 2>&1

# 4. summary
python3 - "$OUT/$PROG.power.log" "$CORE" "$PROG" "$CYCLES" "$SIM_PERIOD_NS" <<'EOF'
import re, sys
log, core, prog, cycles, t = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5])
ann = re.search(r"^vcd\s+(\d+)", log, re.M); un = re.search(r"^unannotated\s+(\d+)", log, re.M)
rows = {m[0]: float(m[4]) for m in re.findall(r"^(Sequential|Combinational|Clock|Total)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", log, re.M)}
p = rows["Total"]
e_nj = p * cycles * t * 1e-9 * 1e9
print(f"{core:9} {prog:7} {cycles:7d} cycles  {p*1e3:6.2f} mW at {1000/t:.0f} MHz  energy {e_nj:8.1f} nJ  "
      f"({e_nj*1e3/cycles:5.1f} pJ/cycle)  seq {rows['Sequential']*1e3:.2f} comb {rows['Combinational']*1e3:.2f} "
      f"clock {rows['Clock']*1e3:.2f} mW  pins from VCD {ann[1] if ann else '?'} / unannotated {un[1] if un else '?'}")
EOF
