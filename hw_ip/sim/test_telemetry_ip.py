# hw_ip/sim/test_telemetry_ip.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from wb_driver import WishboneDriver


@cocotb.test()
async def test_complete_wishbone_telemetry_subsystem(dut):
    """Functional Test: Complete bus-to-peripheral register verification."""

    # Start System Clock mapped to wrapper
    cocotb.start_soon(Clock(dut.wb_clk_i, 20, unit="ns").start())

    driver = WishboneDriver(dut, clk_signal=dut.wb_clk_i, rst_signal=dut.wb_rst_i)
    await driver.reset_system()

    # Clean initial input states
    dut.rx_channel_1.value = 0x0
    dut.rx_channel_2.value = 0x0
    dut.rx_data_ready.value = 0
    await RisingEdge(dut.wb_clk_i)

    dut._log.info("--- Phase 1: Local CPU Bus Configuration Write Verification ---")
    test_tx_payload = 0x55AAFFAA
    # Write to local Tx storage register (Address offset 2'b10 matching 0x6 path)
    await driver.write_reg(address=0x2, data=test_tx_payload)

    # Assert that the wrapper internal logic passes the value straight into tx_inst
    assert dut.reg_tx_data.value == test_tx_payload, (
        "Wishbone bus interface failed to write reg_tx_data!"
    )

    dut._log.info("--- Phase 2: Downlink Latch & Bus Readback Verification ---")
    # Simulate an incoming packet hitting the spatial voter pins
    dut.rx_channel_1.value = 0x12345678
    dut.rx_channel_2.value = 0x12345678
    dut.rx_data_ready.value = 1
    await RisingEdge(dut.wb_clk_i)
    dut.rx_data_ready.value = 0
    await RisingEdge(dut.wb_clk_i)

    # Perform a Wishbone master read sequence from the Rx command register (Address offset 2'b01)
    await RisingEdge(dut.wb_clk_i)
    dut.wb_adr_i.value = 0x1  # Address 2'b01
    dut.wb_cyc_i.value = 1
    dut.wb_stb_i.value = 1
    dut.wb_we_i.value = 0  # Read Mode

    while not dut.wb_ack_o.value:
        await RisingEdge(dut.wb_clk_i)

    readback_data = dut.wb_dat_o.value.to_unsigned()
    dut.wb_cyc_i.value = 0
    dut.wb_stb_i.value = 0

    dut._log.info(
        f"Wishbone Master captured downlink payload data: {hex(readback_data)}"
    )
    assert readback_data == 0x12345678, f"Read-back mismatch! Got {hex(readback_data)}"
    dut._log.info(
        "SUCCESS: Integrated telemetry peripheral block functional verification passed!"
    )
