import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_TIMEOUT_CYCLE = (
    400  # 400 system cycles max window at 100MHz (sys clock) vs 500kHz (rf clock)
)
_INJECT_EDGES = 20
_DELTA_NS = 1


async def drive_async_rf_clock(
    dut, bit_rate_hz: int = 500000, jitter_percent_cap: float = 0.05
):
    # RF simulated Clock with jitter drifting
    base_half_period_ps = int((1.0 / bit_rate_hz) * 1e12) // 2
    dut.rf_clock_i.value = 0
    while True:
        jitter_percent = random.uniform(-jitter_percent_cap, jitter_percent_cap)
        half_period_ps = int(base_half_period_ps * (1.0 + jitter_percent))
        await Timer(half_period_ps, unit="ps")
        dut.rf_clock_i.value = ~dut.rf_clock_i.value


async def init_rf_cdc(
    dut,
    t_clock_ns: int = 10,
    bit_rate_hz: int = 500000,
    jitter_percent_cap: float = 0.05,
    n_cycles: int = 5,
):
    cocotb.start_soon(Clock(dut.clk, t_clock_ns, unit="ns").start())
    dut.rst.value = 1
    dut.rf_clock_i.value = 0
    dut.rf_data_i.value = 0
    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(drive_async_rf_clock(dut, bit_rate_hz, jitter_percent_cap))


@cocotb.test()
async def test_cdc_edge_capture_and_metastability(dut):
    # 3-stage shift-register edge detection validation
    await init_rf_cdc(dut)
    for _ in range(_INJECT_EDGES):
        await RisingEdge(dut.rf_clock_i)
        dut.rf_data_i.value = random.choice([0, 1])
        pulse_found = False

        for _ in range(_TIMEOUT_CYCLE):
            await RisingEdge(dut.clk)
            if str(dut.rf_bit_valid_o.value) == "1":
                pulse_found = True
                # small stabilize time to check the result
                await Timer(_DELTA_NS, unit="ns")
                assert dut.rf_serial_o.value == dut.rf_data_i.value, (
                    "CDC data corruption detected!"
                )
                break

        assert pulse_found, (
            "The synchronizer dropped an asynchronous RF clock edge event!"
        )
