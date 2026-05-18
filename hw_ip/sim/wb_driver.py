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

        # Automatically detect if we are testing a Unit Module or Top-Level
        self.is_unit = hasattr(dut, "wb_cyc_i")

        # Dynamic signal alias binding handles both styles seamlessly
        self.cyc = dut.wb_cyc_i if self.is_unit else dut.wb_cyc
        self.stb = dut.wb_stb_i if self.is_unit else dut.wb_stb
        self.we = dut.wb_we_i if self.is_unit else dut.wb_we
        self.adr = dut.wb_adr_i if self.is_unit else dut.wb_adr
        self.dat = dut.wb_dat_i if self.is_unit else dut.wb_dat_w

    async def reset_system(self, duration_ns=100):
        self.cyc.value = 0
        self.stb.value = 0
        self.we.value = 0
        self.adr.value = 0
        self.dat.value = 0

        self.rst.value = 1
        await Timer(duration_ns, unit="ns")
        self.rst.value = 0
        await RisingEdge(self.clk)

    async def write_reg(self, address, data):
        await RisingEdge(self.clk)
        self.adr.value = address
        self.dat.value = data
        self.we.value = 1
        self.cyc.value = 1
        self.stb.value = 1

        ack_signal = self.dut.wb_ack_o if self.is_unit else self.dut.wb_ack
        while not ack_signal.value:
            await RisingEdge(self.clk)

        await RisingEdge(self.clk)
        self.cyc.value = 0
        self.stb.value = 0
        self.we.value = 0
