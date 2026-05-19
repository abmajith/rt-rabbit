# hw_ip/sim/test_telemetry_rx.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ReadOnly


@cocotb.test()
async def test_spatial_voter_matching_and_mismatch(dut):
    """Unit Test: Verify dual-channel spatial voting and fault detection."""

    # Start clock (50MHz)
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    # Reset the sub-module
    dut.rst.value = 1
    dut.rx_channel_1.value = 0
    dut.rx_channel_2.value = 0
    dut.rx_data_ready.value = 0
    await Timer(60, unit="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    dut._log.info("--- Testing Scenario 1: Clean Matching Data Downlink ---")
    dut.rx_channel_1.value = 0xDEADBEEF
    dut.rx_channel_2.value = 0xDEADBEEF
    dut.rx_data_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_data_ready.value = 0

    # Let non-blocking assignments settle before reading back values
    await RisingEdge(dut.clk)
    await ReadOnly()

    status_val = dut.status_flags.value.to_unsigned()
    assert dut.voted_cmd.value == 0xDEADBEEF, (
        f"Voter failed on valid match! Got {hex(dut.voted_cmd.value)}"
    )
    assert (status_val & 0x1) == 1, (
        f"Link Alive flag (bit 0) should be set! Got {bin(status_val)}"
    )
    assert (status_val & 0x2) == 0, (
        f"Voter Error flag (bit 1) should be clear! Got {bin(status_val)}"
    )

    # --- FIX: Step out of ReadOnly phase by waiting for the next clock edge ---
    await RisingEdge(dut.clk)

    dut._log.info("--- Testing Scenario 2: Corrupted Channel Data Mismatch ---")
    dut.rx_channel_1.value = 0x00001111
    dut.rx_channel_2.value = 0x99999999
    dut.rx_data_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_data_ready.value = 0

    await RisingEdge(dut.clk)
    await ReadOnly()

    status_val_error = dut.status_flags.value.to_unsigned()
    assert (status_val_error & 0x2) == 2, (
        f"CRITICAL: Voter Error flag (bit 1) missed a mismatch! Got {bin(status_val_error)}"
    )
    dut._log.info("SUCCESS: telemetry_rx unit test passed completely.")
