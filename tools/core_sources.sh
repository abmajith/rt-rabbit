#!/usr/bin/env bash
# Print the read_slang arguments (include dirs, files, configuration defines)
# for one SoC configuration, from rtl/cores/<core>/files.f, with the few vendor
# workarounds Yosys' slang frontend needs. Used by tools/synth_sky130.sh and
# asic/orfs/run.sh.
#
#   tools/core_sources.sh <config> <scratch dir for patched copies>
#   (<config>: a file in configs/, e.g. rabbit5 or rabbit5_rv32i)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
config=$1 tmp=$2
mkdir -p "$tmp"
eval "$(make -s -C "$REPO" config-vars CONFIG="$config")"   # sets CORE, CONFIG_DEFINES

# files.f: drop comments, expand ${REPO}, turn +incdir+ into -I
SRC=$(grep -v '^//' "$REPO/rtl/cores/$CORE/files.f" | sed "s|\${REPO}|$REPO|" | sed 's|^+incdir+|-I |' | tr '\n' ' ')

if [ "$CORE" = ibex ]; then
  # slang cannot elaborate a module-level variable whose initializer reads
  # nets (ibex_top.sv, a lint-only "unused" signal). Use a copy where it is a
  # plain assign; the vendor file itself is not touched.
  sed 's/logic unused_scramble_inputs = /logic unused_scramble_inputs; assign unused_scramble_inputs = /' \
      "$REPO/third_party/ibex/rtl/ibex_top.sv" > "$tmp/ibex_top.sv"
  SRC=${SRC//$REPO\/third_party\/ibex\/rtl\/ibex_top.sv/$tmp/ibex_top.sv}
fi
echo "$SRC $CONFIG_DEFINES"
