import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
import random

from wb_driver import WishboneDriver
from wb_assertions import WishboneProtocolAsserter


async def drive_clockwise_ticks(dut, steps=1):
    """Simulates a motor spinning forward (A leads B)"""
    for _ in range(steps):
        dut.enc_a.value = 1
        await Timer(100, unit="ns")
        dut.enc_b.value = 1
        await Timer(100, unit="ns")
        dut.enc_a.value = 0
        await Timer(100, unit="ns")
        dut.enc_b.value = 0
        await Timer(100, unit="ns")


async def drive_counter_clockwise_ticks(dut, steps=1):
    """Simulates a motor spinning backward (B leads A)"""
    for _ in range(steps):
        dut.enc_b.value = 1
        await Timer(100, unit="ns")
        dut.enc_a.value = 1
        await Timer(100, unit="ns")
        dut.enc_b.value = 0
        await Timer(100, unit="ns")
        dut.enc_a.value = 0
        await Timer(100, unit="ns")


@cocotb.test()
async def test_encoder_bidirectional_random_fuzzing(dut):
    # Initialize 50MHz test clock line (20ns period)
    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())

    # 2. fire up the protocol checker
    protocol_checker = WishboneProtocolAsserter(dut, dut.wb_clk_i)
    cocotb.start_soon(protocol_checker.start_monitoring())
    # Connect standard verified Driver class
    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    # Force physical pins to clean default ground lines
    dut.enc_a.value = 0
    dut.enc_b.value = 0
    await Timer(100, unit="ns")

    # Ground Truth Tracking Variable
    expected_software_position = 0

    dut._log.info("--- Initiating Bidirectional Chaos Fuzzing Loop ---")

    # Run 30 random directional adjustments sequentially
    for cycle in range(30):
        direction = random.choice(["CW", "CCW"])
        random_steps = random.randint(1, 15)

        if direction == "CW":
            dut._log.info(f"Fuzz [{cycle}]: Spinning CLOCKWISE by {random_steps} steps")
            await drive_clockwise_ticks(dut, steps=random_steps)
            # Hardware updates counter twice per step cycle (A rising and A falling)
            expected_software_position += random_steps * 2
        else:
            dut._log.info(
                f"Fuzz [{cycle}]: Spinning COUNTER-CLOCKWISE by {random_steps} steps"
            )
            await drive_counter_clockwise_ticks(dut, steps=random_steps)
            expected_software_position -= random_steps * 2

        # Give the hardware internal synchronizers time to stabilize
        await Timer(100, unit="ns")

        # Read back position over the bus using your centralized driver framework
        # Target address 0x00 (QEI Position Tracker Register)
        raw_hw_val = await driver.read_reg(address=0)

        # Explicit sign extension block for 32-bit two's complement handling
        if raw_hw_val & (1 << 31):
            hw_position = raw_hw_val - (1 << 32)
        else:
            hw_position = raw_hw_val

        dut._log.info(
            f"        -> Verification Check: HW={hw_position} | Expected={expected_software_position}"
        )

        # Core Functional Assertions
        assert hw_position == expected_software_position, (
            f"CRITICAL TRACKING FAILURE on cycle {cycle}! "
            f"Hardware position skewed! Got {hw_position}, expected {expected_software_position}"
        )

    dut._log.info("--- Testing CPU Position Reset/Preset Override ---")
    # Test writing a preset value back into the tracker using our driver framework
    preset_test_val = 500
    await driver.write_reg(address=0, data=preset_test_val)
    await Timer(100, unit="ns")

    verify_preset = await driver.read_reg(address=0)
    assert verify_preset == preset_test_val, (
        f"Register Write Failed! Expected {preset_test_val}, got {verify_preset}"
    )

    dut._log.info(
        "SUCCESS: QEI block-level verification passed cleanly with WishboneDriver!"
    )
