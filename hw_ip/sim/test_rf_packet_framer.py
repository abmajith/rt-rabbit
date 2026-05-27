import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadWrite, RisingEdge

_SOF_MARKER = 0xF53A
_BAD_EOF = 0xEEEE


async def drive_word(dut, word: int, is_sof: bool = False):
    dut.aligned_word_i.value = word
    dut.word_valid_i.value = 1
    dut.sof_detected_i.value = 1 if is_sof else 0
    await RisingEdge(dut.clk)
    dut.word_valid_i.value = 0
    dut.sof_detected_i.value = 0
    await RisingEdge(dut.clk)


async def system_reset(dut, t_clock_ns: int = 10, n_cycles: int = 5):
    cocotb.start_soon(Clock(dut.clk, t_clock_ns, unit="ns").start())
    dut.rst.value = 1
    dut.word_valid_i.value = 0
    dut.sof_detected_i.value = 0
    dut.aligned_word_i.value = 0
    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_nominal_packet_framing_flow(dut):
    await system_reset(dut)
    # Constant Frame Configuration Data Mapping
    PACKET_IDX = 0x1234
    DATA_TYPE = 0xABCD
    LENGTH = 2
    PAYLOAD_1 = 0x1111
    PAYLOAD_2 = 0x2222
    CRC_VAL = 0x5555
    EOF_VAL = 0x0AC5

    await drive_word(dut, _SOF_MARKER, is_sof=True)  # IDLE -> INDEX
    await drive_word(dut, PACKET_IDX)  # INDEX -> TYPE
    await drive_word(dut, DATA_TYPE)  # TYPE -> LENGTH
    await drive_word(dut, LENGTH)  # LENGTH -> PAYLOAD
    await drive_word(dut, PAYLOAD_1)  # PAYLOAD (count=2)
    await drive_word(dut, PAYLOAD_2)  # PAYLOAD (count=1 -> CRC)
    await drive_word(dut, CRC_VAL)  # CRC -> EOF

    dut.aligned_word_i.value = EOF_VAL
    dut.word_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.word_valid_i.value = 0
    await ReadWrite()

    assert dut.frame_complete_o.value == 1, (
        "frame_complete_o failed to pulse on valid EOF marker match!"
    )
    assert dut.out_packet_idx.value.to_unsigned() == PACKET_IDX, (
        "Packet tracking sequence index mismatched!"
    )
    assert dut.out_data_type.value.to_unsigned() == DATA_TYPE, (
        "Telemetry payload parsing type field corrupted!"
    )
    assert dut.err_length_mismatch_o.value == 0, (
        "Spurious length mismatch error flagged!"
    )


@cocotb.test()
async def test_framing_error_handling_and_anomalies(dut):
    await system_reset(dut)

    await drive_word(dut, word=_SOF_MARKER, is_sof=True)
    await drive_word(dut, 0x0001)
    await drive_word(dut, 0x9999)
    await drive_word(dut, 1)
    await drive_word(dut, 0xDEAF)
    await drive_word(dut, 0x7777)

    dut.aligned_word_i.value = _BAD_EOF
    dut.word_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.word_valid_i.value = 0
    await ReadWrite()

    assert dut.err_length_mismatch_o.value == 1, (
        "Failed to raise err_length_mismatch_o on corrupted EOF payload!"
    )
    assert dut.frame_complete_o.value == 0, (
        "Framer erroneously flagged completion for a damaged packet!"
    )
