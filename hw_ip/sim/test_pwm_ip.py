# hw_ip/sim/test_pwm_ip.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
import random
from wb_driver import WishboneDriver


@cocotb.test()
async def test_scenario_directed_simulation(dut):
    """Scenario A: Standard simulation targeting static speed metrics."""

    # 1. Fire up the shared infrastructure clock engine
    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())

    # 2. Instantiate our modular driver interface
    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    dut._log.info("Executing directed configuration sequence...")
    await driver.write_reg(address=0x01, data=500)  # Period = 500 ticks
    await driver.write_reg(address=0x02, data=125)  # Duty = 125 ticks (25%)
    await driver.write_reg(address=0x00, data=1)  # Enable core

    # ==========================================================================
    # COMPREHENSIVE SIGNAL METRIC MEASUREMENT
    # ==========================================================================
    dut._log.info("Measuring physical PWM output wave metrics...")
    # Wait for the start of Cycle 1
    await RisingEdge(dut.pwm_pad_o)
    t_rise1 = cocotb.utils.get_sim_time(unit="ns")

    # Wait for the falling edge (end of high time)
    await FallingEdge(dut.pwm_pad_o)
    t_fall = cocotb.utils.get_sim_time(unit="ns")

    # Wait for the start of Cycle 2 (completion of a full period)
    await RisingEdge(dut.pwm_pad_o)
    t_rise2 = cocotb.utils.get_sim_time(unit="ns")

    # Calculate intervals
    high_time_ns = t_fall - t_rise1
    total_period_ns = t_rise2 - t_rise1

    # Calculate real-world generated frequency (Converting ns to Hz)
    real_frequency_hz = 1_000_000_000 / total_period_ns
    measured_duty_cycle = (high_time_ns / total_period_ns) * 100

    dut._log.info("--- Measured Waveform Report ---")
    dut._log.info(f"  > Active High Pulse Duration: {high_time_ns} ns")
    dut._log.info(f"  > Measured Total Period:    {total_period_ns} ns")
    dut._log.info(f"  > Calculated Frequency:      {real_frequency_hz / 1000:.2f} kHz")
    dut._log.info(f"  > Calculated Duty Cycle:     {measured_duty_cycle:.1f} %")
    dut._log.info("--------------------------------")

    # Strict Verification Assertions
    assert total_period_ns == 10000, (
        f"Frequency Bug: Expected 10,000ns period, got {total_period_ns}ns"
    )
    assert measured_duty_cycle == 25.0, (
        f"Duty Bug: Expected 25% duty cycle, got {measured_duty_cycle}%"
    )

    dut._log.info("Directed simulation completed successfully.")


@cocotb.test()
async def test_scenario_random_verification(dut):
    """Scenario B: Stress test the hardware core against random robotic input profiles."""

    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())
    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    await driver.write_reg(address=0x01, data=200)  # Base Period Window = 200 ticks
    await driver.write_reg(address=0x00, data=1)  # Enable core

    dut._log.info("Starting constrained random validation fuzzing...")
    for _ in range(20):
        target_speed = random.choice(
            [0, 50, 100, 200, 250]
        )  # Includes safety corner cases
        await driver.write_reg(address=0x02, data=target_speed)

        # --- Wait 1 clock edge for the register assignment to hit the pin! ---
        await RisingEdge(dut.wb_clk_i)
        # Run the simulation engine for 1 complete PWM wave frame to verify response
        for _ in range(200):
            await RisingEdge(dut.wb_clk_i)

            # Real-time hardware assertion monitoring
            if target_speed == 0:
                assert dut.pwm_pad_o.value == 0, (
                    "Safety Bug: Motor active during 0 speed lock!"
                )
            if target_speed >= 200:
                assert dut.pwm_pad_o.value == 1, (
                    "Safety Bug: Wave glitched out during over-throttle saturation!"
                )
