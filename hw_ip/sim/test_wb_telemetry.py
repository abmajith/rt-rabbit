import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

from wb_driver import WishboneDriver
from wb_assertions import WishboneProtocolAsserter


async def init_system(dut, driver):
    """Leverages the driver's reset sequence and zero-initializes IO wires."""
    dut.rx_channel_1.value = 0
    dut.rx_ch1_ready.value = 0
    dut.rx_channel_2.value = 0
    dut.rx_ch2_ready.value = 0

    # Run your exact 100ns driver reset method
    await driver.reset_system(duration_ns=100)


@cocotb.test()
async def test_wb_telemetry_integration(dut):
    """Verify registers and data streams via production VIP."""
    # 1. Start the System Clock (100 MHz)
    cocotb.start_soon(Clock(dut.wb_clk_i, 10, unit="ns").start())
    wb_driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    wb_asserter = WishboneProtocolAsserter(dut, clk=dut.wb_clk_i)
    cocotb.start_soon(wb_asserter.start_monitoring())
    await init_system(dut, wb_driver)

    # -------------------------------------------------------------------------
    # TEST TRANSITION 1: Configuration & Transmission Pipelines
    # -------------------------------------------------------------------------
    cocotb.log.info("Writing MIMO Mode Configuration via Driver...")
    await wb_driver.write_reg(address=0, data=1)

    mode_read = await wb_driver.read_reg(address=0)
    assert mode_read == 1, f"MIMO mode config read back mismatch! Got: {mode_read}"

    cocotb.log.info("Writing Periodic TX Stream Payload...")
    tx_payload = 0x55AA3344
    await wb_driver.write_reg(address=2, data=tx_payload)

    # Fast-forward until the module's tx counter expires and fires
    while dut.tx_start_pulse.value == 0:
        await RisingEdge(dut.wb_clk_i)

    assert dut.tx_raw_stream.value == tx_payload, (
        "TX streaming payload corruption detected!"
    )
    cocotb.log.info("Wishbone-to-TX periodic streaming path validated.")

    # -------------------------------------------------------------------------
    # TEST TRANSITION 2: Hardware RX Injection to Memory Readout
    # -------------------------------------------------------------------------
    cocotb.log.info("Simulating dual-channel matched packet injection...")
    rx_packet = 0xDEADE123
    dut.rx_channel_1.value = rx_packet
    dut.rx_channel_2.value = rx_packet
    dut.rx_ch1_ready.value = 1
    dut.rx_ch2_ready.value = 1

    await RisingEdge(dut.wb_clk_i)
    dut.rx_ch1_ready.value = 0
    dut.rx_ch2_ready.value = 0

    # Allow 3 clock cycles for the internal telemetry_rx state machine to vote
    for _ in range(3):
        await RisingEdge(dut.wb_clk_i)

    # A. First Read: Verify that the sticky valid flag latched high
    status_matrix = await wb_driver.read_reg(address=3)
    cocotb.log.info(f"Status Matrix Read: 0x{status_matrix:X}")
    assert (status_matrix & 0x10) != 0, (
        "Valid flag bit [4] not set in status matrix register."
    )
    assert (status_matrix & 0x0F) == 0x3, (
        "Status bits [3:0] failed to report match status 0x3."
    )

    # B. Second Read: Collect data cache while the flag is known valid
    cached_cmd = await wb_driver.read_reg(address=1)
    assert cached_cmd == rx_packet, (
        f"Payload mismatch! Expected 0x{rx_packet:X}, got 0x{cached_cmd:X}"
    )

    # C. Third Read: Re-read status register to confirm it auto-cleared after the first read
    post_clear_status = await wb_driver.read_reg(address=3)
    assert (post_clear_status & 0x10) == 0, (
        "Clear-on-read mechanism failed! Sticky bit stayed high."
    )
    cocotb.log.info("Clear-on-read status functionality verified successfully.")

    cocotb.log.info("RX voting and caching registers validated successfully.")
    cocotb.log.info("All Wishbone protocol checks passed with zero errors.")
