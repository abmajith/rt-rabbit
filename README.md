# rt-rabbit 🐇

Real-time robotics analysis & verification toolkit.

## 🚀 What is this?

rt-rabbit is a tool to analyze real-time behavior in robotics systems.

It helps answer:
- Will my control loop miss deadlines?
- What happens under CPU load?
- Is my scheduling safe?
## 🧠 Features

- [x] Task modeling (period, execution time, priority)
- [x] RMS scheduler simulation
- [x] CPU Utilization analysis
- [x] CLI interface via `uv`
- [x] Timeline visualization
- [x] Deadline miss detection
- [ ] Zephyr / RTOS integration
- [ ] Trace-based analysis

## 📦 Example

```yaml
system:
  scheduler: RMS
  duration: 0.1

tasks:
  - name: motor_control
    period: 1ms
    execution: 200us
    priority: 1

  - name: sensor_read
    period: 5ms
    execution: 500us
    priority: 2
```

```bash
 uv run python  rt_rabbit examples/standard_rms.yaml 
```
Graphical plot
```bash
 uv run python  rt_rabbit examples/standard_rms.yaml --plot 
```

Rt Stress test
```bash
 uv run python  rt_rabbit examples/standard_rms.yaml --stress 
```
