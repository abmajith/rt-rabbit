# hw_ip/sim/test_qei_ip.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from wb_driver import WishboneDriver


async def step_quadrature_clockwise(dut, steps=1):
    """Simulates a physical motor rotating forward by stepping channel pins"""
    for _ in range(steps):
        dut.enc_a_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_b_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_a_pin.value = 0
        await Timer(100, unit="ns")
        dut.enc_b_pin.value = 0
        await Timer(100, unit="ns")


@cocotb.test()
async def test_encoder_tracking_verification(dut):
    """Verify that our hardware safely tracks real-world motor spin directions"""
    cocotb.start_soon(Clock(dut.sys_clk, 20, unit="ns").start())

    driver = WishboneDriver(dut, clk_signal=dut.sys_clk, rst_signal=dut.sys_rst)
    await driver.reset_system()

    # Ensure raw initial position lines are cleared
    dut.enc_a_pin.value = 0
    dut.enc_b_pin.value = 0
    await Timer(100, unit="ns")

    target_ticks = 8
    dut._log.info(
        f"Physical Action: Rotating motor clockwise by {target_ticks} steps..."
    )
    await step_quadrature_clockwise(dut, steps=target_ticks)

    # Give the hardware debouncer a few clock cycles to process the final edge
    await Timer(100, unit="ns")

    # 4. Read back the position count register over the memory-mapped Wishbone bus
    dut._log.info("Bus Action: Reading QEI counter register...")
    # Base address for QEI is 4 because bit 2 is set high (100 in binary = 4)
    await RisingEdge(dut.sys_clk)
    dut.wb_adr.value = 4
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value = 0

    # Wait for the hardware interface to acknowledge the read
    while not dut.wb_ack.value:
        await RisingEdge(dut.sys_clk)

    captured_position = dut.wb_dat_r.value.integer
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0

    # 5. Core Verification Assertion
    dut._log.info(
        f"Verification Check: Hardware reports position = {captured_position}"
    )
    assert captured_position == target_ticks, (
        f"VERIFICATION FAILURE: Hardware position mismatch! "
        f"Expected {target_ticks}, got {captured_position}"
    )

    dut._log.info(
        "SUCCESS: Quadrature Encoder Interface tracking matches physics perfectly!"
    )
