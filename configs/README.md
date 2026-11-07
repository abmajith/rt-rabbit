# SoC configurations

One file per SoC variant. A file names the core and lists the options that
differ from the defaults (the defaults are the full current specification,
see `mk/config.mk`).

```make
# configs/rabbit5_rv32i.mk
CONFIG_CORE := rabbit5
RV32M := 0
```

Every command takes `CONFIG=<file name>`; `CORE=<core>` is the short form for
the core's default configuration (`configs/<core>.mk`):

```sh
make soc-sim CONFIG=rabbit5_rv32i PROG=muldiv
make formal  CONFIG=rabbit5_rv32i
tools/synth_sky130.sh rabbit5 rabbit5_rv32i
asic/orfs/run.sh rabbit5_rv32i
```

Build folders are named after the configuration (`build/gls/<CONFIG>`,
`sw/baremetal/build/<CONFIG>`, ...), so variants never mix.

| Configuration | Core | Options | ISA |
|---|---|---|---|
| `rabbit3` | rabbit3 | defaults | RV32IM + Zicsr |
| `rabbit3_rv32i` | rabbit3 | `RV32M := 0` | RV32I + Zicsr |
| `rabbit5` | rabbit5 | defaults | RV32IM + Zicsr |
| `rabbit5_rv32i` | rabbit5 | `RV32M := 0` | RV32I + Zicsr |
| `cv32e40p`, `cve2`, `ibex` | reference cores | fixed | RV32IMC + Zicsr |

## Options

| Option | Default | Meaning | Where it acts |
|---|---|---|---|
| `RV32M` | 1 | M extension: MUL, MULH*, DIV*, REM* | `rabbit_decoder` (illegal if 0), `rabbit_execute` (no `rabbit_muldiv` if 0), `misa`, `-march`, riscv-formal ISA |

Rules:
- options are set only in these files, never on the command line, so a
  build folder always matches its name;
- a reference core accepts only the defaults (its `core.mk` stops the build
  otherwise);
- every option has a test that the hardware really is absent when it is off
  (for `RV32M := 0`: riscv-formal's `ill` check with ISA `rv32i`, and
  `PROG=muldiv`, which then checks that every M instruction traps).
