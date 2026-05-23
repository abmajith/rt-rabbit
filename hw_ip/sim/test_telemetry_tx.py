# hw_ip/sim/test_telemetry_tx.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def init_system(dut):
    """Initializes and resets the transmitter module."""
    dut.rst.value = 1
    dut.tx_payload_data.value = 0x0

    # Toggle clock while holding reset
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_tx_periodic_strobe(dut):
    """Verify that the TX pulse occurs at exactly the configured period interval."""
    # Start clock (100MHz)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    test_pattern = 0xABCDE123
    dut.tx_payload_data.value = test_pattern
    max_count = int(dut.MAX_COUNT.value)
    cocotb.log.info(f"Running test with MAX_COUNT = {max_count}")
    while dut.tx_start_pulse.value == 0:
        await RisingEdge(dut.clk)

    # when the tx_start_pulse one is 1, it should send the payload data
    assert dut.tx_raw_stream.value == test_pattern, "Initial data stream mismatch!"
    # Advance one more clock cycle to clear the active strobe
    await RisingEdge(dut.clk)
    cycle_count = 1
    while dut.tx_start_pulse.value == 0:
        await RisingEdge(dut.clk)
        cycle_count += 1
        assert cycle_count <= (max_count + 5), (
            "Error: Timer exceeded MAX_COUNT without pulsing!"
        )

    expected_period = max_count + 1
    assert cycle_count == expected_period, (
        f"Timing violation! Expected {expected_period} cycles, got {cycle_count}."
    )
    cocotb.log.info(
        "Periodic interval matches cycle-accurate hardware target successfully."
    )


@cocotb.test()
async def test_tx_payload_latching(dut):
    """Verify that payload data is only latched into the stream on the strobe pulse."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    dut.tx_payload_data.value = 0x11111111

    # Wait until mid-way through a counting phase
    for _ in range(10):
        await RisingEdge(dut.clk)

    # Change payload data while the timer is actively counting
    dut.tx_payload_data.value = 0x22222222
    await RisingEdge(dut.clk)

    # Ensure stream didn't update prematurely
    assert dut.tx_raw_stream.value != 0x22222222, (
        "Security bug: Data leaked into stream before pulse window!"
    )

    # Fast forward until the pulse fires
    while dut.tx_start_pulse.value == 0:
        await RisingEdge(dut.clk)

    # Check that the new value was captured at the strobe boundary
    assert dut.tx_raw_stream.value == 0x22222222, (
        "Data failed to latch cleanly at strobe boundary."
    )


@cocotb.test()
async def test_tx_reset_behavior(dut):
    """Verify asynchronous/synchronous reset resets the counter mid-flight."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    dut.tx_payload_data.value = 0xABCDEF00

    # Let it count part way
    for _ in range(20):
        await RisingEdge(dut.clk)

    # Assert reset mid-flight
    dut.rst.value = 1
    await RisingEdge(dut.clk)

    # Verify values are wiped instantly
    assert dut.tx_raw_stream.value == 0, "Reset failed to clear raw data stream."
    assert dut.tx_start_pulse.value == 0, "Reset allowed an illegal pulse output."
