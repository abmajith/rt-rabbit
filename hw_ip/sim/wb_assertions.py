from cocotb.triggers import RisingEdge


class WishboneProtocolAsserter:
    """
    Formal Property Verification Layer for Wishbone B4 Compliance.
    Monitors signals at the rising clock edge to catch specification violations safely.
    """

    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

        # Detect wrapper layer vs unit layer dynamically
        self.is_unit = hasattr(dut, "wb_cyc_i")
        self.cyc = dut.wb_cyc_i if self.is_unit else dut.wb_cyc
        self.stb = dut.wb_stb_i if self.is_unit else dut.wb_stb
        self.ack = dut.wb_ack_o if self.is_unit else dut.wb_ack

    def _safe_get_bit(self, signal) -> int:
        """Safely extracts a bit value even during reset or floating states."""
        if not signal.value.is_resolvable:
            return 0  # Treat uninitialized/floating bus lines as logic 0 (inactive)
        return int(signal.value)

    async def start_monitoring(self):
        while True:
            await RisingEdge(self.clk)
            cyc_val = self._safe_get_bit(self.cyc)
            stb_val = self._safe_get_bit(self.stb)
            ack_val = self._safe_get_bit(self.ack)

            # --- Rule 1: Strobe Rule (Spec Clause 3.1) ---
            # WISHBONE SPEC: STB can only be active high if CYC is actively asserted.
            if stb_val == 1:
                assert cyc_val == 1, (
                    f"[WISHBONE PROTOCOL ERROR]: STB asserted while CYC was un-asserted! "
                    f"(CYC={cyc_val}, STB={stb_val})"
                )

            # --- Rule 2: Acknowledge Rule (Spec Clause 3.2) ---
            # WISHBONE SPEC: ACK must never be asserted unless a valid transaction cycle is ongoing.
            if ack_val == 1:
                assert cyc_val == 1 and stb_val == 1, (
                    f"[WISHBONE PROTOCOL ERROR]: Slave returned ACK outside a valid active cycle! "
                    f"(CYC={cyc_val}, STB={stb_val}, ACK={ack_val})"
                )
