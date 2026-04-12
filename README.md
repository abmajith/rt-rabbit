# rt-rabbit 🐇

Real-Time Response-Time Analysis (RTA) & Verification Toolkit
rt-rabbit provides deterministic analysis and cycle-accurate simulation for real-time task sets. It is designed to bridge the gap between theoretical schedulability analysis and practical system behavior under hardware-realistic conditions.

## 🧠 Core Analysis Engine

The toolkit implements industry-standard real-time synchronization protocols:
- [Single-Core (PCP)](./single_core_rt.md): Analyzes local priority inversion and preemption using the Priority Ceiling Protocol and Response Time Analysis (RTA).
- [Multi-Core (MSRP)](./multi_core_rt.md): Evaluates cross-core resource contention and global spin-locking behavior using the Multiprocessor Stack Resource Policy.


## 🛠 Feature

- [x] Task modeling (period, execution time, priority)
- [x] Task Simulation, Stress Test (by injecting context-switch overhead (Csw​) and release jitter (Ji​)) runs. 
- [x] Verification: Mathematical RTA for RMS, EDF, and Fixed Priority (FP) schedulers.
- [x] MSRP/PCP Simulation: Native support for shared resources and non-preemptible critical sections.
- [x] Diagnostic Plotting: High-precision Gantt charts with MSRP spin-tracking and deadline-miss "Red Zones."
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
