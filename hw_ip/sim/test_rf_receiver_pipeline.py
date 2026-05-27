import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadWrite, RisingEdge, Timer

from wb_assertions import WishboneProtocolAsserter
from wb_driver import WishboneDriver


async def generate_async_rf_bit_stream(dut, bits: list, period_ns: int = 40):
    for bit in bits:
        dut.rf_data.value = bit
        dut.rf_clock.value = 0
        await Timer(period_ns // 2, unit="ns")
        dut.rf_clock.value = 1
        await Timer(period_ns // 2, unit="ns")
    dut.rf_clock.value = 0


def convert_word_to_bit_array(word: int, length: int = 16) -> list:
    return [(word >> i) & 0x01 for i in range(length - 1, -1, -1)]


@cocotb.test()
async def test_end_to_end_telemetry_packet_integration(dut):

    cocotb.start_soon(Clock(dut.wb_clk, 10, unit="ns").start())
    wb_driver = WishboneDriver(dut, dut.wb_clk, dut.wb_rst)
    asserter = WishboneProtocolAsserter(dut, dut.wb_clk)
    cocotb.start_soon(asserter.start_monitoring())

    dut.rf_clock.value = 0
    dut.rf_data.value = 0
    await wb_driver.reset_system(duration_ns=100)

    SOF = 0xF53A
    IDX = 0x7777
    TYP = 0xBBBB
    LEN = 0x0001
    DAT = 0x1111
    CRC = 0x9999
    EOF = 0x0AC5

    raw_packet_stream = []
    for word_vector in [SOF, IDX, TYP, LEN, DAT, CRC, EOF]:
        raw_packet_stream.extend(convert_word_to_bit_array(word_vector))

    # pre/post-append stream
    full_serial_stream = [0, 1, 1, 0] + raw_packet_stream + [0, 0, 0, 0]

    dut._log.info("Injecting raw asynchronous serial bit-stream into RF Receiver...")
    await generate_async_rf_bit_stream(dut, full_serial_stream, period_ns=40)

    for _ in range(20):
        await RisingEdge(dut.wb_clk)

    compile_markers = await wb_driver.read_reg(address=0x0)
    assert compile_markers == 0x0AC5F53A, (
        f"Invalid compile markers: {hex(compile_markers)}"
    )
    parsed_metadata = await wb_driver.read_reg(address=0x1)
    assert parsed_metadata == 0xBBBB7777, (
        f"Telemetry fields mismatched: {hex(parsed_metadata)}"
    )

    dashboard_status = await wb_driver.read_reg(address=0x2)
    assert (dashboard_status & 0x01) == 1, (
        "RF Bit Aligner failed to achieve grid lock state."
    )
    assert (dashboard_status & 0x02) == 0, (
        "Telemetry framework reported unexpected buffer overflow!"
    )
    assert (dashboard_status & 0x04) == 0, (
        "Pipeline flagged frame structure corruption error!"
    )
    assert (dashboard_status & 0x08) == 8, (
        f"Packet Framer failed to pulse final completion bit! Status was: {hex(dashboard_status)}"
    )

    dut._log.info("Flushing hardware telemetry log states...")
    await wb_driver.write_reg(
        address=0x3, data=0x00000002
    )  # Clear bit 1 active high command

    for _ in range(5):
        await RisingEdge(dut.wb_clk)
    await ReadWrite()

    post_clear_dashboard = await wb_driver.read_reg(address=0x2)
    assert (post_clear_dashboard & 0x0E) == 0, (
        f"Dashboard metrics failed to clear! Got: {hex(post_clear_dashboard)}"
    )
    assert (post_clear_dashboard & 0x0E) == 0, "Dashboard metrics failed to clear."
