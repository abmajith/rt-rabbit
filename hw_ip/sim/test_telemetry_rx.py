import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

# Hardware Constants (Match these with your Verilog parameters)
MAX_SKEW_DELAY = 32


async def init_system(dut):
    """Resets the module and driving pins to a known clean state."""
    dut.rst.value = 1
    dut.mimo_mode_i.value = 0
    dut.rx_channel_1.value = 0
    dut.rx_ch1_ready.value = 0
    dut.rx_channel_2.value = 0
    dut.rx_channel_2.value = 0
    dut.rx_ch2_ready.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_symmetric_skew_ch2_leads_ch1(dut):
    """Symmetry Check: Channel 2 arrives early, Channel 1 arrives late within window"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    test_data = 0xABCDE123
    dut.mimo_mode_i.value = 0  # Strict Majority Mode

    # Channel 2 leads
    dut.rx_channel_2.value = test_data
    dut.rx_ch2_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch2_ready.value = 0

    # Skew delay of 12 cycles
    for _ in range(12):
        await RisingEdge(dut.clk)
        assert dut.voted_cmd_valid.value == 0, "Error: Triggered before Ch1 arrived."

    # Channel 1 catches up
    dut.rx_channel_1.value = test_data
    dut.rx_ch1_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0

    await RisingEdge(dut.clk)
    assert dut.voted_cmd_valid.value == 1, "Failed symmetric arrival tracking."
    assert dut.voted_cmd.value == test_data, "Data mismatched on symmetric catch-up."


@cocotb.test()
async def test_corner_watchdog_timeout_ch1_isolated(dut):
    """Corner Case: Ch1 hits ready, Ch2 drops completely -> Watchdog Timeout"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    dut.mimo_mode_i.value = 0  # Strict mode: drop on single-channel failure
    dut.rx_channel_1.value = 0x5555AAAA
    dut.rx_ch1_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0

    # Wait out the maximum window length plus safety overhead
    for _ in range(MAX_SKEW_DELAY + 2):
        await RisingEdge(dut.clk)
        assert dut.voted_cmd_valid.value == 0, (
            "Strict mode must not validate isolated channels!"
        )

    # Check that status flags exposed the timeout error condition
    # (Checking if error tracking bit within the 4-bit status vector set)
    assert dut.status_flags.value != 0, (
        "Status register failed to record skew window timeout."
    )


@cocotb.test()
async def test_corner_mimo_fallback_ch1_only(dut):
    """Corner Case: Watchdog expires but software mode permits Ch1-only fallback"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    fallback_data = 0x7777BBBB
    dut.mimo_mode_i.value = 1  # Mode 1: Fallback to Ch1 on timeout

    dut.rx_channel_1.value = fallback_data
    dut.rx_ch1_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0

    # Tick past window limit
    for _ in range(MAX_SKEW_DELAY + 1):
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    # After watchdog expires, fallback logic should extract Ch1 data explicitly
    assert dut.voted_cmd_valid.value == 1, (
        "Fallback processing failed to flag valid strobe."
    )
    assert dut.voted_cmd.value == fallback_data, (
        "Fallback mode failed to retrieve intact Ch1 data."
    )


@cocotb.test()
async def test_corner_data_contradiction(dut):
    """Corner Case: Channels arrive synchronized but payloads contradict"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    dut.mimo_mode_i.value = 0  # Strict mode
    dut.rx_channel_1.value = 0x0000FFFF
    dut.rx_channel_2.value = 0xFFFF0000  # Direct conflict
    dut.rx_ch1_ready.value = 1
    dut.rx_ch2_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0
    dut.rx_ch2_ready.value = 0

    await RisingEdge(dut.clk)
    assert dut.voted_cmd_valid.value == 0, (
        "Security Failure: Conflicting payloads allowed through!"
    )


@cocotb.test()
async def test_corner_chatter_retrigger(dut):
    """Corner Case: Double pulsed ready line during active window (Chatter Resilience)"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await init_system(dut)

    dut.mimo_mode_i.value = 0

    # Ch1 alerts
    dut.rx_channel_1.value = 0xEEEEEEEE
    dut.rx_ch1_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0

    await RisingEdge(dut.clk)

    # Fault injection: Ch1 erroneously fires a second ready strobe while window is already open
    dut.rx_ch1_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch1_ready.value = 0

    # Ch2 clears normally
    dut.rx_channel_2.value = 0xEEEEEEEE
    dut.rx_ch2_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rx_ch2_ready.value = 0

    await RisingEdge(dut.clk)
    # State machine must ignore the internal chatter pulse and resolve cleanly
    assert dut.voted_cmd_valid.value == 1, (
        "Module locked up or threw out data due to pulse chatter."
    )
