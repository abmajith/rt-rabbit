import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst.value = 1
    await Timer(20, units="ns")
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_udp_payload_extraction(dut):
    """Test that UDP payload is correctly extracted and port is matched"""
    
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.target_udp_port.value = 0x1234
    await reset_dut(dut)

    # UDP Header: SrcPort(2), DstPort(2), Len(2), Checksum(2)
    # DstPort is at index 2,3
    header = [0x00, 0x00, 0x12, 0x34, 0x00, 0x0A, 0x00, 0x00]
    payload = [0xDE, 0xAD, 0xBE, 0xEF]
    packet = header + payload

    dut.s_axis_tvalid.value = 0
    dut.s_axis_tuser.value = 0
    await RisingEdge(dut.clk)

    # Drive packet
    for i, byte in enumerate(packet):
        dut.s_axis_tvalid.value = 1
        dut.s_axis_tdata.value = byte
        dut.s_axis_tlast.value = 1 if i == len(packet) - 1 else 0
        await RisingEdge(dut.clk)
    
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    await RisingEdge(dut.clk)

    # Verification logic would go here (checking captured m_axis signals)
    # In a real test, use cocotb-bus or custom monitors to verify m_axis_tdata
