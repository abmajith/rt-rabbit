# Multi-Core Real-Time Analyzer (MSRP)
## Purpose:
- Cross-Core Orchestration: Manages multiple single-core engines and a global Resource Arbiter to handle shared hardware/memory.
- MSRP Logic: Implements the Multiprocessor Stack Resource Policy, where tasks "spin" (busy-wait) for global resources to ensure predictable blocking.
- Global RTA: Extends single-core math to include Remote Blocking factors that occur when Core A waits for Core B.
- Contention Analysis: Identifies bottlenecks where multiple cores are fighting for the same Resource ID simultaneously.

## MSRP Delay Factor Logic:
Quantifies delays caused by cross-core synchronization and resource locking.
- **Bremote** (Spin): Calculates the total wait time while spinning. It is the sum of the longest critical sections (L) on all other cores that use the same resource.
- **FIFO Serialization:** MSRP treats global resource requests as a queue. Even a high-priority task must wait its turn if a task from another core requested the resource first.
- **Non-Preemptibility:** During a "Spin" or "Lock," the task becomes non-preemptive on its local core to prevent deadlocks and nested waiting.

## Simulation Behavior:
- **Spin State:** Unlike single-core blocking, "Spinning" consumes CPU cycles. The task is "Running" but its remaining_time does not decrease.
- **Arbiter Check:** At every tick, the task asks the Arbiter: "Is my resource free?" If no, is_spinning remains True, and the task stays at the head of the core's schedule.