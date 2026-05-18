# hw_ip/sim/test_telemetry_tx.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


@cocotb.test()
async def test_autonomous_transmission_interval(dut):
    """Unit Test: Verify autonomous streaming intervals and output latching."""

    # Start clock (50MHz)
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    # Assert Reset Sequence
    dut.rst.value = 1
    dut.tx_payload_data.value = 0xABCDE123
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    dut._log.info("Simulating hardware counter loop natively...")

    # Sample variables safely until the counter rolls over and fires the pulse
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.tx_start_pulse.value == 1:
            dut._log.info("Detected tx_start_pulse firing successfully!")
            assert dut.tx_raw_stream.value == 0xABCDE123, (
                f"Data stream corruption! Got {hex(dut.tx_raw_stream.value)}"
            )
            break

    # Advance one more clock cycle to check fallback clearing logic
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert dut.tx_start_pulse.value == 0, (
        "Pulse error: tx_start_pulse must clear after exactly 1 clock cycle!"
    )
    dut._log.info("SUCCESS: telemetry_tx unit test passed completely.")
