import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from wb_driver import WishboneDriver
from wb_assertions import WishboneProtocolAsserter


@cocotb.test()
async def test_pwm_unit_and_wb_assertions(dut):
    """Validates Bus Interconnect, Register Mapping, and Protocol Compliance"""

    # 1. Initialize clock structure (50 MHz = 20ns period)
    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())

    # 2. fire up the protocol checker
    protocol_checker = WishboneProtocolAsserter(dut, dut.wb_clk_i)
    cocotb.start_soon(protocol_checker.start_monitoring())

    # 3. Setup driver
    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    dut._log.info(
        "[Verification Stage]: Testing Memory Mapped Read/Write Back Veracity..."
    )

    # Test Register Write and Read-back matching
    await driver.write_reg(address=0x01, data=1200)  # Write to REG_PER
    read_back_period = await driver.read_reg(address=0x01)
    assert read_back_period == 1200, (
        f"Register Corruption: Expected 1200, read {read_back_period}"
    )

    await driver.write_reg(address=0x02, data=300)  # Write to REG_DUTY
    read_back_duty = await driver.read_reg(address=0x02)
    assert read_back_duty == 300, (
        f"Register Corruption: Expected 300, read {read_back_duty}"
    )

    dut._log.info("[Verification Stage]: Checking Waveform Timing Accuracy...")
    await driver.write_reg(address=0x00, data=1)  # Enable Controller Core

    # Wait for stable cycle
    await RisingEdge(dut.pwm_pad_o)
    t_start = cocotb.utils.get_sim_time(unit="ns")
    await FallingEdge(dut.pwm_pad_o)
    t_mid = cocotb.utils.get_sim_time(unit="ns")
    await RisingEdge(dut.pwm_pad_o)
    t_end = cocotb.utils.get_sim_time(unit="ns")

    high_time = t_mid - t_start
    total_time = t_end - t_start
    calculated_duty = (high_time / total_time) * 100

    assert total_time == (1200 * 20), (
        f"Timing Error: Expected {1200 * 20}ns period, got {total_time}ns"
    )
    assert calculated_duty == 25.0, (
        f"Duty Cycle Error: Expected 25.0%, got {calculated_duty}%"
    )
    dut._log.info(f"[PASSED]: Duty cycle cleanly verified at {calculated_duty}%")


@cocotb.test()
async def test_pwm_unit_fuzzing_and_saturation(dut):
    """Simulates heavy stress profiles and safety-critical saturation limits"""
    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())
    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    # Define operating environment metrics
    base_period = 500
    await driver.write_reg(address=0x01, data=base_period)
    await driver.write_reg(address=0x00, data=1)

    dut._log.info(
        "[Verification Stage]: Injecting Constrained Random Robotic Inputs..."
    )

    # Fuzzing array containing safe values, 0% dropouts, and over-throttle extremes
    stress_profiles = [100, 0, 250, 500, 650, 0, 125, 900]

    for index, target_duty in enumerate(stress_profiles):
        dut._log.info(
            f"Fuzz Transaction Run #{index}: Programming Duty Target = {target_duty} ticks"
        )
        await driver.write_reg(address=0x02, data=target_duty)

        for _ in range(base_period + 10):
            await RisingEdge(dut.wb_clk_i)

            current_pad_state = int(dut.pwm_pad_o.value)
            if target_duty == 0:
                assert current_pad_state == 0, (
                    "Safety Breach: Motor activated during requested 0% safe shutdown state!"
                )
            elif target_duty >= base_period:
                assert current_pad_state == 1, (
                    "Safety Breach: Signal glitched out or dropped low during saturation throttle!"
                )
