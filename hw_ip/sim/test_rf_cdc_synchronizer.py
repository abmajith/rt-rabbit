import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import random

async def drive_async_rf_clock(dut, bit_rate_hz=500000):
    """
    Independent coroutine simulating a drifting, jittery external RF clock.
    Runs completely decoupled from the system clock time wheel.
    """
    base_half_period_ps = int((1.0 / bit_rate_hz) * 1e12) // 2
    dut.rf_clock_i.value = 0
    
    while True:
        # Introduce up to +/- 5% random phase jitter on every single half-cycle
        jitter_percent = random.uniform(-0.05, 0.05)
        half_period_ps = int(base_half_period_ps * (1.0 + jitter_percent))
        
        await Timer(half_period_ps, unit="ps")
        dut.rf_clock_i.value = ~dut.rf_clock_i.value

@cocotb.test()
async def test_cdc_edge_capture_and_metastability(dut):
    """Isolates and validates the 3-stage shift-register edge detection performance."""
    
    # 100MHz internal FPGA system clock (10ns period)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    
    dut.rst.value = 1
    dut.rf_clock_i.value = 0
    dut.rf_data_i.value = 0
    
    # Hold reset for 5 system clock cycles
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    
    # asynchronous RF clock generator
    cocotb.start_soon(drive_async_rf_clock(dut, bit_rate_hz=500000))
    
    
    detected_edges = 0
    expected_edges = 20
    
    dut._log.info(f"Injecting {expected_edges} asynchronous clock edges with phase jitter...")
    
    for _ in range(expected_edges):
        await RisingEdge(dut.rf_clock_i)
        
        dut.rf_data_i.value = random.choice([0, 1])
        
        # Look downstream in the system clock domain. 
        # The edge detection pulse should arrive exactly 2 to 3 system clock cycles later.
        timeout_cycles = 400 # 400 system cycles max window at 100MHz vs 500kHz
        pulse_found = False
        
        for _ in range(timeout_cycles):
            await RisingEdge(dut.clk)
            if str(dut.rf_bit_valid_o.value) == "1":
                pulse_found = True
                detected_edges += 1
                
                # Check that the data bit registered matches what we sent
                # Allowing for the stage-2 sampling delay
                await Timer(1, unit="ns") # Small delta to let the output stabilize
                assert dut.rf_serial_o.value == dut.rf_data_i.value, \
                    f"CDC data corruption detected! Sent: {dut.rf_data_i.value}, Captured: {dut.rf_serial_o.value}"
                break
                
        assert pulse_found, "The synchronizer dropped an asynchronous RF clock edge event!"

    dut._log.info(f"[SUCCESS] Captured all {detected_edges}/{expected_edges} jittery edges with zero sample drops.")