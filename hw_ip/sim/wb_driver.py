from cocotb.triggers import RisingEdge, Timer


class WishboneDriver:
    """Drives transactions over a standard Wishbone bus interface."""

    def __init__(self, dut, clk_signal, rst_signal):
        self.dut = dut
        self.clk = clk_signal
        self.rst = rst_signal

        self.is_unit = hasattr(dut, "wb_cyc_i")
        self.cyc = dut.wb_cyc_i if self.is_unit else dut.wb_cyc
        self.stb = dut.wb_stb_i if self.is_unit else dut.wb_stb
        self.we = dut.wb_we_i if self.is_unit else dut.wb_we
        self.adr = dut.wb_adr_i if self.is_unit else dut.wb_adr
        self.dat_w = dut.wb_dat_i if self.is_unit else dut.wb_dat_w
        self.dat_r = dut.wb_dat_o if self.is_unit else dut.wb_dat_r
        self.ack = dut.wb_ack_o if self.is_unit else dut.wb_ack

    async def reset_system(self, duration_ns: int = 100) -> None:
        """Applies reset over the specified duration."""
        self.cyc.value = 0
        self.stb.value = 0
        self.we.value = 0
        self.adr.value = 0
        self.dat_w.value = 0
        self.rst.value = 1
        await Timer(duration_ns, unit="ns")
        self.rst.value = 0
        await RisingEdge(self.clk)

    async def write_reg(self, address: int, data: int) -> None:
        """Executes a standardized Master Write Cycle."""
        await RisingEdge(self.clk)
        self.adr.value = address
        self.dat_w.value = data
        self.we.value = 1
        self.cyc.value = 1
        self.stb.value = 1

        # Wait for the Slave to assert ACK
        while True:
            await RisingEdge(self.clk)
            if self.ack.value.is_resolvable and int(self.ack.value) == 1:
                break

        self.cyc.value = 0
        self.stb.value = 0
        self.we.value = 0

    async def read_reg(self, address: int) -> int:
        """Executes a standardized Master Read Cycle."""
        await RisingEdge(self.clk)
        self.adr.value = address
        self.we.value = 0
        self.cyc.value = 1
        self.stb.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.ack.value.is_resolvable and int(self.ack.value) == 1:
                # Handles multi-bit data vectors safely via .to_unsigned()
                read_data = self.dat_r.value.to_unsigned()
                break

        self.cyc.value = 0
        self.stb.value = 0
        return read_data
