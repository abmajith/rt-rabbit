import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadWrite, RisingEdge


async def wb_write(dut, address: int, data: int):
    dut.wb_adr_i.value = address
    dut.wb_dat_i.value = data
    dut.wb_we_i.value = 1
    dut.wb_stb_i.value = 1
    dut.wb_cyc_i.value = 1

    while True:
        await RisingEdge(dut.wb_clk_i)
        if dut.wb_ack_o.value == 1:
            break

    dut.wb_we_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    await RisingEdge(dut.wb_clk_i)


async def wb_read(dut, address: int) -> int:
    dut.wb_adr_i.value = address
    dut.wb_we_i.value = 0
    dut.wb_stb_i.value = 1
    dut.wb_cyc_i.value = 1

    while True:
        await RisingEdge(dut.wb_clk_i)
        if dut.wb_ack_o.value == 1:
            await ReadWrite()
            read_val = dut.wb_dat_o.value.to_unsigned()
            break

    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    return read_val


async def system_reset(dut, t_clock_ns: int = 10, n_cycle: int = 5):
    cocotb.start_soon(Clock(dut.wb_clk_i, t_clock_ns, unit="ns").start())
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

    for _ in range(n_cycle):
        await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)


@cocotb.test()
async def test_wishbone_reads_and_telemetry_packing(dut):
    await system_reset(dut)
    markers = await wb_read(dut, address=0x0)
    assert markers == 0x0AC5F53A, f"Marker mismatch! Got {hex(markers)}"

    dut.tracked_data_type_i.value = 0xDEAF
    dut.tracked_packet_idx_i.value = 0x1234
    await RisingEdge(dut.wb_clk_i)

    metadata = await wb_read(dut, address=0x1)
    assert metadata == 0xDEAF1234, (
        f"Dynamic metadata packing mismatch! Got {hex(metadata)}"
    )

    dut.lock_status_i.value = 1
    await RisingEdge(dut.wb_clk_i)

    dashboard = await wb_read(dut, address=0x2)
    assert (dashboard & 0x1) == 1, (
        "Live lock status bit did not pass through to Dashboard."
    )


@cocotb.test()
async def test_sticky_flags_and_control_pulsing(dut):
    await system_reset(dut)
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
    assert (dashboard & 0xF) == expected_bits, (
        f"Sticky flags missing! Dashboard: {hex(dashboard)}"
    )
    strobe_captured = False

    async def monitor_strobe():
        nonlocal strobe_captured
        while True:
            await RisingEdge(dut.wb_clk_i)
            await ReadWrite()
            if dut.cfg_clear_lock_o.value == 1:
                strobe_captured = True

    strobe_worker = cocotb.start_soon(monitor_strobe())
    await wb_write(dut, address=0x3, data=0x00000003)
    for _ in range(2):
        await RisingEdge(dut.wb_clk_i)
        await ReadWrite()
        if dut.cfg_clear_lock_o.value == 1:
            strobe_captured = True

    # Kill the background strobe monitor task cleanly before asserting
    strobe_worker.cancel()
    assert strobe_captured, (
        "cfg_clear_lock_o strobe wasn't captured high during or immediately after the control write!"
    )
    dashboard_cleared = await wb_read(dut, address=0x2)
    assert (dashboard_cleared & 0xE) == 0, (
        f"Sticky dashboard registers failed to flush! Got: {hex(dashboard_cleared)}"
    )
