"""Run a bare-metal program on rabbit_soc_sim and check its result.

The firmware talks to the testbench through rabbit_sim_ctrl:
  PUTC -> characters collected here into `console`
  EXIT -> ends the test; exit code 0 means PASS
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

MAX_CYCLES = int(os.environ.get("RABBIT_MAX_CYCLES", "200000"))


async def run_firmware(dut, max_cycles: int = MAX_CYCLES):
    """Reset the SoC, run until EXIT is written, return (exit_code, console, cycles)."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.irq_i.value = 0
    dut.rst_ni.value = 0
    await ClockCycles(dut.clk_i, 5)
    dut.rst_ni.value = 1

    console = []
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk_i)
        if dut.putc_valid_o.value:
            ch = chr(int(dut.putc_char_o.value))
            console.append(ch)
        if dut.exit_valid_o.value:
            text = "".join(console)
            for line in text.splitlines():
                dut._log.info("fw| %s", line)
            return int(dut.exit_code_o.value), text, cycle

    text = "".join(console)
    dut._log.error("console so far:\n%s", text)
    raise TimeoutError(f"firmware did not exit within {max_cycles} cycles")


@cocotb.test()
async def test_firmware_passes(dut):
    """Firmware must exit with code 0 and print RESULT: PASS."""
    prog = os.environ.get("RABBIT_PROG", "?")
    dut._log.info("firmware: %s", os.environ.get("RABBIT_FIRMWARE"))
    code, console, cycles = await run_firmware(dut)
    dut._log.info("%s finished after %d cycles, exit code 0x%08x", prog, cycles, code)
    if code & 0xFFFF0000 == 0xDEAD0000:
        raise AssertionError(f"unexpected trap, mcause={code & 0x3ff}")
    assert code == 0, f"firmware reported {code} failed checks"
    assert "RESULT: PASS" in console
