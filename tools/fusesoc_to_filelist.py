#!/usr/bin/env python3
"""Turn a FuseSoC/Verilator .vc file list into a rabbit files.f.

FuseSoC copies every file into its build directory (src/<core>/...). This maps
each entry back to the original file inside the given source tree, so the
files.f works without FuseSoC. Used for rtl/cores/ibex/files.f:

  uv run --with fusesoc fusesoc --cores-root third_party/ibex \\
      run --target=lint --setup --build-root /tmp/fsoc lowrisc:ibex:ibex_top
  tools/fusesoc_to_filelist.py /tmp/fsoc/.../lowrisc_ibex_ibex_top_0.1.vc \\
      third_party/ibex > rtl/cores/ibex/files.part.f
"""
import sys
from pathlib import Path

vc, tree = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
repo = Path(__file__).resolve().parent.parent

# FuseSoC names each build sub-directory after the core: "lowrisc:prim:util:0.1"
# becomes src/lowrisc_prim_util_0.1. Map those names to the .core file's folder.
core_dir = {}
for core in tree.rglob("*.core"):
    for line in core.read_text(errors="ignore").splitlines():
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip().strip('"').strip("'")
            vlnv = name.split(":")
            if len(vlnv) == 3:
                vlnv.append("0")                   # FuseSoC's default version
            core_dir["_".join(vlnv)] = core.parent
            break


def original(rel):
    parts = Path(rel).parts
    if parts[0] not in core_dir:
        sys.exit(f"unknown core directory {parts[0]} (in {rel})")
    return core_dir[parts[0]].joinpath(*parts[1:])


out = []
for line in vc.read_text().split("\n"):
    line = line.strip()
    if line.startswith("+incdir+src/"):
        d = original(line[len("+incdir+src/"):])
        out.append("+incdir+${REPO}/" + d.relative_to(repo).as_posix())
    elif line.startswith("src/") and line.endswith((".sv", ".svh", ".v")):
        f = original(line[len("src/"):])
        if not f.is_file():
            sys.exit(f"missing {f}")
        out.append("${REPO}/" + f.relative_to(repo).as_posix())
print("\n".join(out))
