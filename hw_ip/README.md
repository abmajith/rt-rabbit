# Hardware IP Coprocessor Framework

This subsystem contains the hardware coprocessor cores and verification frameworks for the `rt-rabbit` autonomous robotic actuator ecosystem.

## Interconnect Fabric Architecture
The system utilizes an address-sliced Wishbone bus matrix to communicate with multiple peripherals concurrently. 

* 📊 **[View System Hardware Interconnect Block Diagram](./docs/block_diagram.txt)**

## System Address Allocation Map
| System Address | Target Block | Register Name | Bit Width | Access | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`3'b000` (0x0)** | `wb_pwm` | `reg_ctrl` | 32-bit | R/W | Bit 0: Module Enable |
...

## Architecture Layout
* `open_source_ip/`: Houses external audited peripheral modules.
  * `wb_pwm.v`: Custom defensively patched Wishbone Pulse Width Modulator engine featuring overflow saturation protection.
  * `wb_qei.v`: Quadrature Encoder Interface position tracker.
* `rtl/`: Top-level System-on-Chip (SoC) wrapper fabric interconnect (`rt_top.v`).
* `sim/`: Universal verification testbenches powered by `cocotb` and compiled via `Verilator`.

## Executing Co-Simulation Test Suites
Ensure your project virtual environment context is loaded via `uv`:

```bash
cd hw_ip/sim

# Target PWM Fuzzing/Directed Simulation
uv run make clean && uv run make WAVES=1 MODULE=pwm

# Target Quadrature Encoder Tracking
uv run make clean && uv run make WAVES=1 MODULE=qei

# Target the telemetry
uv run make clean && uv run make WAVES=1 TARGET=telemetry

# Target top 
uv run make clean && uv run make WAVES=1 TARGET=top
```