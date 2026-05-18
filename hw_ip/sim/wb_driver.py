# hw_ip/sim/wb_driver.py
from cocotb.triggers import RisingEdge, Timer


class WishboneDriver:
    """
    A reusable Hardware Driver that isolates the raw Wishbone bus protocol
    mechanisms from your high-level test scenario logic.
    """

    def __init__(self, dut, clk_signal, rst_signal):
        self.dut = dut
        self.clk = clk_signal
        self.rst = rst_signal

    async def reset_system(self, duration_ns=100):
        """Standardized system initialization routine"""
        self.dut.wb_cyc.value = 0
        self.dut.wb_stb.value = 0
        self.dut.wb_we.value = 0
        self.dut.wb_adr.value = 0
        self.dut.wb_dat_w.value = 0

        self.rst.value = 1
        await Timer(duration_ns, unit="ns")
        self.rst.value = 0
        await RisingEdge(self.clk)

    async def write_reg(self, address, data):
        """Abstract memory-mapped register write operation"""
        await RisingEdge(self.clk)
        self.dut.wb_adr.value = address
        self.dut.wb_dat_w.value = data
        self.dut.wb_we.value = 1
        self.dut.wb_cyc.value = 1
        self.dut.wb_stb.value = 1

        # Wait for hardware handshake acknowledgment
        while not self.dut.wb_ack.value:
            await RisingEdge(self.clk)

        await RisingEdge(self.clk)
        self.dut.wb_cyc.value = 0
        self.dut.wb_stb.value = 0
        self.dut.wb_we.value = 0
