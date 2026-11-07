#!/usr/bin/env bash
# Place-and-route one core with OpenROAD-flow-scripts (Docker image), then
# report the real longest path (with wires), area and power.
#
#   asic/orfs/run.sh <core> [platform] [clock period ns]
#   asic/orfs/run.sh rabbit3                      # sky130hd, 8 ns
#   asic/orfs/run.sh ibex ihp-sg13g2 8
#
# Steps:
#  1. our Yosys + slang turns the core (rtl/cores/<core>/files.f) into one
#     plain Verilog file - the same front end for every core;
#  2. ORFS (inside openroad/orfs, pinned below) runs synthesis, floorplan,
#     placement, clock tree, routing;
#  3. the summary line comes from ORFS' final reports.
# Output: build/orfs/<platform>/<core>_<period>ns/ (logs/, reports/, results/)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
CORE=${1:?usage: asic/orfs/run.sh <core> [platform] [period ns]}
PLATFORM=${2:-sky130hd}
PERIOD=${3:-8.0}
IMAGE=${ORFS_IMAGE:-openroad/orfs@sha256:8b4f3942318d740ea1f73f4f895bbac150b32e41eb3b7baf7722adec6538bbcf}

WORK=$REPO/build/orfs/$PLATFORM/${CORE}_${PERIOD}ns
mkdir -p "$WORK/src"

# 1. one plain Verilog file
SRC=$("$REPO/tools/core_sources.sh" "$CORE" "$WORK/src/patched")
yosys -q -l "$WORK/src/frontend.log" -p "read_slang $SRC --top rabbit_cpu -DSYNTHESIS; \
          hierarchy -top rabbit_cpu; proc; opt_clean; bmuxmap; bwmuxmap; demuxmap; \
          write_verilog -noattr $WORK/src/$CORE.v"

# 2. ORFS design configuration
cat > "$WORK/config.mk" <<EOF
export PLATFORM        = $PLATFORM
export DESIGN_NAME     = rabbit_cpu
export DESIGN_NICKNAME = $CORE
export VERILOG_FILES   = $WORK/src/$CORE.v
export SDC_FILE        = $REPO/asic/orfs/constraint.sdc
export CLOCK_PERIOD    = $PERIOD
# moderate density: the same for every core
export CORE_UTILIZATION       = 45
export PLACE_DENSITY_LB_ADDON = 0.2
EOF

docker run --rm -u "$(id -u):$(id -g)" -v "$REPO:$REPO" -e CLOCK_PERIOD="$PERIOD" "$IMAGE" bash -c "
  cd /OpenROAD-flow-scripts && source env.sh > /dev/null 2>&1
  make -C flow DESIGN_CONFIG=$WORK/config.mk WORK_HOME=$WORK
" > "$WORK/flow.log" 2>&1 || { echo "$CORE: flow failed, see $WORK/flow.log"; tail -20 "$WORK/flow.log"; exit 1; }

# 3. summary
"$REPO/asic/orfs/summary.py" "$WORK" "$CORE" "$PERIOD" "$PLATFORM"
