# Single-Core Real-Time Analyzer

## Purpose: 
- Orchestrates mathematical analysis and cycle-accurate simulation 
    for single-core scheduling under varying policies (RMS, EDF, FP, LST).
- run_rta(): Performs fixed-point iteration to determine the Worst-Case Response Time (Ri​) including blocking and same-priority interference.
- run_simulation(): Executes a discrete-time simulation (Ttick​) to validate mathematical results against practical scheduling scenarios.
- run_stress_test(): Evaluates system Fragility by injecting hardware-realistic overheads like context-switch latency (Csw​) and release jitter (Ji​).
- get_rt_report(): Diagnoses "Unsafe" systems by identifying if the root cause is Utilization, Cooperative Blocking, or Preemption Interference.

## RTA Logic: 
- Implements the **standard RTA** recurrence relation: Ri(n+1)​=Ci​+Bi​+∑j∈hp(i)​⌈Tj​Ri(n)​​⌉Cj​.
- **Context:** Used for both Single-Core (PCP) and Multi-Core (MSRP) to find the convergence point where task execution and preemptions stabilize.

## PCP Delay Factor Logic: 
Quantifies non-preemptive delays based on Zephyr/PCP scheduling theory.
- **Blocal​:** Calculates the blocking term as max(Lj​) for all lower-priority tasks (j∈lp(i)), representing the wait time for a non-preemptive "chunk" to finish.
- **Isame​:** Calculates interference from tasks with identical priority based on the OS policy (FIFO assumes worst-case arrival; RR assumes a single quantum delay).