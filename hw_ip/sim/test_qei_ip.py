# hw_ip/sim/test_qei_ip.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

from wb_driver import WishboneDriver


# ==============================================================================
# INDUSTRIAL TESTING APPX: CONCURRENT MOTOR SIMULATORS
# ==============================================================================
async def drive_clockwise_ticks(dut, steps=1):
    """Simulates a motor spinning forward (A leads B)"""
    for _ in range(steps):
        dut.enc_a_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_b_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_a_pin.value = 0
        await Timer(100, unit="ns")
        dut.enc_b_pin.value = 0
        await Timer(100, unit="ns")


async def drive_counter_clockwise_ticks(dut, steps=1):
    """Simulates a motor spinning backward (B leads A)"""
    for _ in range(steps):
        dut.enc_b_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_a_pin.value = 1
        await Timer(100, unit="ns")
        dut.enc_b_pin.value = 0
        await Timer(100, unit="ns")
        dut.enc_a_pin.value = 0
        await Timer(100, unit="ns")


async def read_hardware_position(dut, driver):
    """Abstract helper to execute a synchronous Wishbone register read"""
    await RisingEdge(dut.sys_clk)
    dut.wb_adr.value = 4  # Base QEI Register Address Mapping Space
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value = 0  # Read mode operation

    while not dut.wb_ack.value:
        await RisingEdge(dut.sys_clk)

    # Uses signed conversion since position can go negative when spinning backward!
    captured_val = dut.wb_dat_r.value.to_signed()

    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    return captured_val


# ==============================================================================
# FULL-FLEDGED ADVANCED STRESS VERIFICATION
# ==============================================================================
@cocotb.test()
async def test_encoder_bidirectional_random_fuzzing(dut):
    """
    Advanced Verification Suite: Stress-testing the QEI core
    tracking accuracy across unpredictable, chaotic flight profiles.
    """
    cocotb.start_soon(Clock(dut.sys_clk, 20, unit="ns").start())
    driver = WishboneDriver(dut, clk_signal=dut.sys_clk, rst_signal=dut.sys_rst)
    await driver.reset_system()

    # Force physical pins to clean default ground lines
    dut.enc_a_pin.value = 0
    dut.enc_b_pin.value = 0
    await Timer(100, unit="ns")

    # Ground Truth Tracking Variable
    expected_software_position = 0

    dut._log.info("--- Initiating Bidirectional Chaos Fuzzing Loop ---")

    # Run 30 random directional adjustments sequentially
    for cycle in range(30):
        # Constrained Random Choice: Spin CW or CCW? How many steps?
        direction = random.choice(["CW", "CCW"])
        random_steps = random.randint(1, 15)

        if direction == "CW":
            dut._log.info(f"Fuzz [{cycle}]: Spinning CLOCKWISE by {random_steps} steps")
            await drive_clockwise_ticks(dut, steps=random_steps)
            # 2x multiplier because the hardware updates counter twice per step cycle
            expected_software_position += random_steps * 2
        else:
            dut._log.info(
                f"Fuzz [{cycle}]: Spinning COUNTER-CLOCKWISE by {random_steps} steps"
            )
            await drive_counter_clockwise_ticks(dut, steps=random_steps)
            expected_software_position -= random_steps * 2

        # Give the hardware internal synchronizers time to stabilize
        await Timer(100, unit="ns")

        # Read back position over the bus to check tracking validity
        hw_position = await read_hardware_position(dut, driver)
        dut._log.info(
            f"        -> Verification Check: HW={hw_position} | Expected={expected_software_position}"
        )

        # Core Functional Assertions
        assert hw_position == expected_software_position, (
            f"CRITICAL TRACKING FAILURE on cycle {cycle}! "
            f"Hardware position skewed! Got {hw_position}, expected {expected_software_position}"
        )

    dut._log.info("SUCCESS: QEI core passed comprehensive verification fuzzing!")
