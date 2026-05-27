import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

_DATA_ALIGNER_LENGTH = 16
_SOF_MARKER = 0xF53A
_PAYLOADS = [0xABCD, 0x1234, 0x5678]


async def _cdc_drive_bit(dut, bit):
    dut.rf_serial_i.value = bit
    dut.rf_bit_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.rf_bit_valid_i.value = 0


async def _ideal_cdc(
    dut,
    n_cycle: int = 5,
):
    for _ in range(n_cycle):
        await RisingEdge(dut.clk)


async def init_rf_aligner(
    dut, t_clock_ns: int = 10, n_cycles: int = 5, n_cycle_gap: int = 5
):
    cocotb.start_soon(Clock(dut.clk, t_clock_ns, unit="ns").start())
    dut.rst.value = 1
    dut.cfg_clear_lock_i.value = 0
    dut.rf_serial_i.value = 0
    dut.rf_bit_valid_i.value = 0
    await _ideal_cdc(dut, n_cycles)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    # padding noise set up
    for _ in range(n_cycles):
        await _cdc_drive_bit(dut, random.choice([0, 1]))
        await RisingEdge(dut.clk)
        await _ideal_cdc(dut, n_cycle_gap)


async def send_sof_marker_bits(dut, n_cycle_gap: int = 5):

    for i in range(_DATA_ALIGNER_LENGTH - 1, -1, -1):
        bit = (_SOF_MARKER >> i) & 0x01
        await _cdc_drive_bit(dut, bit)

        if i == 0:
            await FallingEdge(dut.clk)
            assert str(dut.lock_status_o.value) == "1", "Aligner failed to lock on SOF!"
            assert str(dut.sof_detected_o.value) == "1", "SOF pulse missed!"

        await RisingEdge(dut.clk)
        await _ideal_cdc(dut, n_cycle_gap)


async def send_stream_of_bits(dut, bit_streams, n_cycle_gap: int = 5):
    for i in range(_DATA_ALIGNER_LENGTH - 1, -1, -1):
        bit = (bit_streams >> i) & 0x01
        await _cdc_drive_bit(dut, bit)

        if i == 0:
            await FallingEdge(dut.clk)
            assert str(dut.word_valid_o.value) == "1", (
                "word_valid_o was not asserted on the 16th bit boundary!"
            )
            actual_word = dut.aligned_word_o.value.to_unsigned()
            assert actual_word == bit_streams, (
                f"Mismatch! Sent: {hex(bit_streams)}, Got: {hex(actual_word)}"
            )

        await RisingEdge(dut.clk)
        await _ideal_cdc(dut, n_cycle_gap)


@cocotb.test()
async def test_aligner_hunting_and_locking(dut):
    await init_rf_aligner(dut)
    await send_sof_marker_bits(dut)
    for expected_word in _PAYLOADS:
        send_stream_of_bits(dut, expected_word)
