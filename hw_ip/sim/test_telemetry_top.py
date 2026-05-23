import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random


def calculate_crc16_ccitt(data: list) -> int:
    """Calculates standard CCITT-16 CRC matching our RTL engine."""
    crc = 0xFFFF
    for byte in data:
        for i in range(8):
            bit = (byte >> (7 - i)) & 1
            if bit ^ (crc >> 15):
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def generate_rf_stream(opcode: int, payload: list, inject_bad_crc=False) -> list:
    """Generates an array of bits matching the physical layer layout."""
    sync_word = [1, 1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0]  # 16'hF53A

    # Packet Construction: Length is Opcode (1) + Payload length (3) = 4
    packet_body = [len(payload) + 1, opcode] + payload
    crc = calculate_crc16_ccitt(packet_body)

    if inject_bad_crc:
        crc = crc ^ 0x5555  # Corrupt the CRC signature bit-mask deliberately

    packet_body.append((crc >> 8) & 0xFF)
    packet_body.append(crc & 0xFF)

    # Flatten packet body bytes to raw bits
    bitstream = list(sync_word)
    for byte in packet_body:
        for i in range(8):
            bit = (byte >> (7 - i)) & 1
            bitstream.append(bit)
    return bitstream


async def drive_rf_bits(dut, bitstream: list, bit_period_ns=100):
    """Simulates physical over-the-air baseband transceiver transitions."""
    for bit in bitstream:
        dut.rf_data.value = bit
        dut.rf_clk.value = 1
        await Timer(bit_period_ns // 2, unit="ns")
        dut.rf_clk.value = 0
        await Timer(bit_period_ns // 2, unit="ns")


async def init_system_clear(dut):
    cocotb.start_soon(Clock(dut.sys_clk, 10, unit="ns").start())
    dut.sys_rst.value = 1
    dut.wb_ack_i.value = 0
    dut.wb_err_i.value = 0
    dut.rf_clk.value = 0
    dut.rf_data.value = 0
    for _ in range(5):
        await RisingEdge(dut.sys_clk)
    dut.sys_rst.value = 0
    await RisingEdge(dut.sys_clk)


# ==================== TEST CASES ====================


@cocotb.test()
async def test_single_perfect_patch_reconstruction(dut):
    """Scenario 1: Verifies a single pristine packet safely arrives on the Wishbone bus."""
    await init_system_clear(dut)

    # Opcode 0x02, 3-byte payload: 0x00, 0x00, 0x8C (Motor Speed 140 counts/sec)
    bits = generate_rf_stream(opcode=0x02, payload=[0x00, 0x00, 0x8C])

    # Send stream over simulated air interface
    await drive_rf_bits(dut, bits)

    # Monitor system clock domain to catch the Master transaction initiation
    bus_captured = False
    for _ in range(100):
        await RisingEdge(dut.sys_clk)
        if dut.wb_cyc_o.value == 1 and dut.wb_stb_o.value == 1:
            bus_captured = True
            assert dut.wb_dat_o.value.to_unsigned() == 0x0200008C, (
                f"Data Corrupted! Got: {hex(dut.wb_dat_o.value.to_unsigned())}"
            )
            assert dut.wb_adr_o.value.to_unsigned() == 0x00002000, (
                "Wrong Wishbone base destination address"
            )

            # Answer back as the system crossbar memory controller
            dut.wb_ack_i.value = 1
            await RisingEdge(dut.sys_clk)
            dut.wb_ack_i.value = 0

            await RisingEdge(dut.sys_clk)
            break

    assert bus_captured, (
        "Hanging Fault: Telemetry system completely failed to request the Wishbone Bus!"
    )

    # Verify the CPU notification interrupt fired precisely on completion
    await RisingEdge(dut.sys_clk)
    assert dut.irq_packet_ready.value == 1, "Interrupt signaling failed to execute!"


@cocotb.test()
async def test_multiple_sequential_patches(dut):
    """Scenario 2: Validates back-to-back packets to prove clear_lock cycles correctly."""
    await init_system_clear(dut)

    # Packet A: Emergency Stop Command (Opcode 0x01, payload 0x000000)
    packet_a = generate_rf_stream(opcode=0x01, payload=[0x00, 0x00, 0x00])
    # Packet B: Heading Correction Command (Opcode 0x04, payload 0x000045)
    packet_b = generate_rf_stream(opcode=0x04, payload=[0x00, 0x00, 0x45])

    # --- Dispatch Packet A ---
    dut._log.info("--- Dispatched Packet A (E-Stop) ---")
    await drive_rf_bits(dut, packet_a)

    for _ in range(50):
        await RisingEdge(dut.sys_clk)
        if dut.wb_cyc_o.value == 1:
            assert dut.wb_dat_o.value.to_unsigned() == 0x01000000
            dut.wb_ack_i.value = 1
            await RisingEdge(dut.sys_clk)
            dut.wb_ack_i.value = 0
            break

    # Allow dead-time between packages to simulate inter-packet delay variables
    await Timer(500, unit="ns")

    # --- Dispatch Packet B ---
    dut._log.info("--- Dispatched Packet B (Heading Update) ---")
    await drive_rf_bits(dut, packet_b)

    bus_b_captured = False
    for _ in range(100):
        await RisingEdge(dut.sys_clk)
        if dut.wb_cyc_o.value == 1:
            bus_b_captured = True
            assert dut.wb_dat_o.value.to_unsigned() == 0x04000045
            dut.wb_ack_i.value = 1
            await RisingEdge(dut.sys_clk)
            dut.wb_ack_i.value = 0
            break

    assert bus_b_captured, (
        "Fail: Aligner did not reset its window to frame the second sequential transmission!"
    )


@cocotb.test()
async def test_failed_hardware_corrupted_crc(dut):
    """Scenario 3: Verifies that corrupted packets are filtered out entirely by the CRC layer."""
    await init_system_clear(dut)

    # Generate packet with corrupted CRC bits
    corrupted_bits = generate_rf_stream(
        opcode=0x02, payload=[0xAA, 0xBB, 0xCC], inject_bad_crc=True
    )
    await drive_rf_bits(dut, corrupted_bits)

    # Monitor system clock cycles. The Wishbone master must remain completely quiet.
    for _ in range(100):
        await RisingEdge(dut.sys_clk)
        assert dut.wb_cyc_o.value == 0, (
            "Security Violation: Corrupted packet bypass filter and reached Master bus layer!"
        )

    assert dut.irq_packet_ready.value == 0, (
        "Error: Interrupt triggered for an invalid data batch."
    )


@cocotb.test()
async def test_failed_hardware_bus_hang_timeout(dut):
    """Scenario 4: Validates the watchdog boundary under a dead lock memory controller condition."""
    await init_system_clear(dut)

    bits = generate_rf_stream(opcode=0x02, payload=[0x11, 0x22, 0x33])
    await drive_rf_bits(dut, bits)

    # Wait for the master to take the bus
    for _ in range(50):
        await RisingEdge(dut.sys_clk)
        if dut.wb_cyc_o.value == 1:
            break

    # Deliberately leave wb_ack_i at 0 to mimic a unresponsive slave device
    dut._log.info(
        "Simulating non-responsive slave interface. Verifying watchdog escalation bounds..."
    )

    # Clock the simulator past the 15-cycle limit threshold
    for _ in range(25):
        await RisingEdge(dut.sys_clk)

    assert dut.wb_cyc_o.value == 0, (
        "Protocol Violation: Watchdog failed to force a master bus drop sequence!"
    )
    assert dut.bus_timeout_err.value == 1, (
        "Fault Reporting Failure: Internal error flag did not assert."
    )
