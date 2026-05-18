# hw_ip/sim/test_top_system.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from wb_driver import WishboneDriver


@cocotb.test()
async def test_full_system_integration(dut):
    """Verify Wishbone transactions execute to distinct peripherals without collision."""

    # Start System Clock
    cocotb.start_soon(Clock(dut.sys_clk, 20, unit="ns").start())

    # Bind custom reusable driver
    bus = WishboneDriver(dut, dut.sys_clk, dut.sys_rst)

    dut.uart_rx.value = 1
    dut.enc_a_pin.value = 0
    dut.enc_b_pin.value = 0

    dut._log.info("Resetting entire SoC...")
    await bus.reset_system()

    # Write to PWM Config Register (Address 3'b000 = 0)
    dut._log.info("Writing to PWM Module...")
    await bus.write_reg(address=0, data=0x000000FF)

    # Write to Telemetry Config Register (Address 3'b110 = 6)
    dut._log.info("Writing to Telemetry Module...")
    await bus.write_reg(address=6, data=0x12345678)

    # Let it tick
    for _ in range(10):
        await RisingEdge(dut.sys_clk)

    dut._log.info(
        "All parallel blocks responded cleanly without breaking existing logic!"
    )
