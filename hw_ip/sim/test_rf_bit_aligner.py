import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
import random

async def cdc_spec_drive_bit(dut, bit):
    """
    Presents a stable data bit and pulses valid for exactly 1 system clock cycle.
    """
    dut.rf_serial_i.value = bit
    dut.rf_bit_valid_i.value = 1
    await RisingEdge(dut.clk)      # Captured by RTL
    
    dut.rf_bit_valid_i.value = 0   # Immediately drop strobe
    await RisingEdge(dut.clk)      # Clear out active holds
    for _ in range(5):             # Gap between serial bits
        await RisingEdge(dut.clk)

@cocotb.test()
async def test_aligner_hunting_and_locking(dut):
    # Start 100MHz system clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    
    # Reset
    dut.rst.value = 1
    dut.cfg_clear_lock_i.value = 0
    dut.rf_serial_i.value = 0
    dut.rf_bit_valid_i.value = 0
    for _ in range(5): await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    
    # 1. Padding noise
    for _ in range(5):
        await cdc_spec_drive_bit(dut, random.choice([0, 1]))
        
    # 2. Stream SOF Marker (0xF53A)
    SOF_MARKER = 0xF53A
    dut._log.info(f"Sending SOF Marker: {hex(SOF_MARKER)}")
    for i in range(15, -1, -1):
        bit = (SOF_MARKER >> i) & 0x01
        if i == 0:
            # Drive final bit tightly
            dut.rf_serial_i.value = bit
            dut.rf_bit_valid_i.value = 1
            await RisingEdge(dut.clk)
            dut.rf_bit_valid_i.value = 0 # Drop it instantly!
            
            # Check lock status safely on the falling edge of this cycle
            await FallingEdge(dut.clk)
            assert str(dut.lock_status_o.value) == "1", "Aligner failed to lock on SOF!"
            assert str(dut.sof_detected_o.value) == "1", "SOF pulse missed!"
            await RisingEdge(dut.clk)    # Complete the bit slot
            
            for _ in range(5): 
                await RisingEdge(dut.clk)
        else:
            await cdc_spec_drive_bit(dut, bit)

    # 3. Stream payloads cleanly
    test_payload = [0xABCD, 0x1234, 0x5678]
    for expected_word in test_payload:
        dut._log.info(f"Streaming data word: {hex(expected_word)}")
        
        for i in range(15, -1, -1):
            bit = (expected_word >> i) & 0x01
            if i == 0:
                # Intercept last payload bit 
                dut.rf_serial_i.value = bit
                dut.rf_bit_valid_i.value = 1
                await RisingEdge(dut.clk)
                dut.rf_bit_valid_i.value = 0 # Clear strobe instantly
                
                # Verify outputs on this cycle's falling edge
                await FallingEdge(dut.clk)
                assert str(dut.word_valid_o.value) == "1", "word_valid_o was not asserted on the 16th bit boundary!"
                actual_word = dut.aligned_word_o.value.to_unsigned()
                assert actual_word == expected_word, f"Mismatch! Sent: {hex(expected_word)}, Got: {hex(actual_word)}"
                
                await RisingEdge(dut.clk)
                for _ in range(5): 
                    await RisingEdge(dut.clk)
            else:
                await cdc_spec_drive_bit(dut, bit)

    dut._log.info("[PASSED] Isolated Unit Test for rf_bit_aligner successful.")