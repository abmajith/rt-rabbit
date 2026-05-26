import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadWrite, Edge, Combine
from cocotb.types import Logic

# --- Wishbone Master Helper Routines ---

async def wb_write(dut, address: int, data: int):
    """Executes a standard single-cycle Wishbone write transaction."""
    dut.wb_adr_i.value = address
    dut.wb_dat_i.value = data
    dut.wb_we_i.value = 1
    dut.wb_stb_i.value = 1
    dut.wb_cyc_i.value = 1
    
    # Wait for the cycle where ACK is active
    while True:
        await RisingEdge(dut.wb_clk_i)
        if dut.wb_ack_o.value == 1:
            break
            
    # Drop the bus lines immediately on the ACK clock edge 
    # to prevent an accidental double-write evaluation phase
    dut.wb_we_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    
    # Let the signals settle across the delta cycle boundary
    await RisingEdge(dut.wb_clk_i)

async def wb_read(dut, address: int) -> int:
    """Executes a standard single-cycle Wishbone read transaction."""
    dut.wb_adr_i.value = address
    dut.wb_we_i.value = 0
    dut.wb_stb_i.value = 1
    dut.wb_cyc_i.value = 1
    
    while True:
        await RisingEdge(dut.wb_clk_i)
        if dut.wb_ack_o.value == 1:
            await ReadWrite()  # Settle simulator delta cycles before sampling
            read_val = dut.wb_dat_o.value.to_unsigned()
            break
            
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    return read_val

async def system_reset(dut):
    """Pulses the synchronous active-high reset line."""
    dut.wb_rst_i.value = 1
    dut.wb_adr_i.value = 0
    dut.wb_dat_i.value = 0
    dut.wb_we_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    dut.lock_status_i.value = 0
    dut.frame_complete_i.value = 0
    dut.tracked_packet_idx_i.value = 0
    dut.tracked_data_type_i.value = 0
    dut.err_overflow_i.value = 0
    dut.err_length_mismatch_i.value = 0
    
    for _ in range(5):
        await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)


# --- Unit Tests ---

@cocotb.test()
async def test_wishbone_reads_and_telemetry_packing(dut):
    """Verifies that compile-time parameters and dynamic inputs register correctly on the bus."""
    cocotb.start_soon(Clock(dut.wb_clk_i, 10, unit="ns").start())
    await system_reset(dut)
    
    dut._log.info("Reading compilation markers at offset 0...")
    markers = await wb_read(dut, address=0x0)
    assert markers == 0x0AC5F53A, f"Marker mismatch! Got {hex(markers)}"
    
    dut.tracked_data_type_i.value = 0xDEAF
    dut.tracked_packet_idx_i.value = 0x1234
    await RisingEdge(dut.wb_clk_i) 
    
    dut._log.info("Reading packed dynamic metadata at offset 1...")
    metadata = await wb_read(dut, address=0x1)
    assert metadata == 0xDEAF1234, f"Dynamic metadata packing mismatch! Got {hex(metadata)}"

    dut.lock_status_i.value = 1
    await RisingEdge(dut.wb_clk_i)
    
    dashboard = await wb_read(dut, address=0x2)
    assert (dashboard & 0x1) == 1, "Live lock status bit did not pass through to Dashboard."


@cocotb.test()
async def test_sticky_flags_and_control_pulsing(dut):
    """Validates latching of pipeline error events, manual register clearing, and stroke flags."""
    cocotb.start_soon(Clock(dut.wb_clk_i, 10, unit="ns").start())
    await system_reset(dut)
    
    dut._log.info("Injecting hardware pipeline tracking pulses...")
    dut.err_overflow_i.value = 1
    dut.err_length_mismatch_i.value = 1
    dut.frame_complete_i.value = 1
    await RisingEdge(dut.wb_clk_i)
    
    dut.err_overflow_i.value = 0
    dut.err_length_mismatch_i.value = 0
    dut.frame_complete_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    
    dashboard = await wb_read(dut, address=0x2)
    expected_bits = (1 << 3) | (1 << 2) | (1 << 1)
    assert (dashboard & 0xF) == expected_bits, f"Sticky flags missing! Dashboard: {hex(dashboard)}"
    
    dut._log.info("Writing control word to clear dashboard and assert manual unlock strobe...")
    
    strobe_captured = False

    async def monitor_strobe():
        nonlocal strobe_captured
        # Run a simple sampling loop observing transitions on every single clock edge
        while True:
            await RisingEdge(dut.wb_clk_i)
            await ReadWrite()
            if dut.cfg_clear_lock_o.value == 1:
                strobe_captured = True

    # Fork the background monitor task loop
    strobe_worker = cocotb.start_soon(monitor_strobe())
    
    # Execute the Wishbone write transaction 
    await wb_write(dut, address=0x3, data=0x00000003)
    
    # Add a brief padding window to settle out any registered output pipelines
    for _ in range(2):
        await RisingEdge(dut.wb_clk_i)
        await ReadWrite()
        if dut.cfg_clear_lock_o.value == 1:
            strobe_captured = True

    # Kill the background strobe monitor task cleanly before asserting
    strobe_worker.cancel()

    # Assert that the strobe was cleanly recorded at least once during the window
    assert strobe_captured, "cfg_clear_lock_o strobe wasn't captured high during or immediately after the control write!"
    
    # Read back dashboard to confirm sticky bits flushed cleanly
    dashboard_cleared = await wb_read(dut, address=0x2)
    assert (dashboard_cleared & 0xE) == 0, f"Sticky dashboard registers failed to flush! Got: {hex(dashboard_cleared)}"