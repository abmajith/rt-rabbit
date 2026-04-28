# 🐇 RT-Rabbit

Real-Time Response-time Analysis & Behavior Identification Tool

RT-Rabbit is a simulator and mathematical analyzer for real-time periodic tasks, supporting both single-core and multi-core synchronization protocols.


Select a module below to view specific analysis logic, scheduling theories, and protocol implementations:
- [Single-Core Analysis](./single_core_rt.md)
    * Covers RMS, EDF, and PCP (Priority Ceiling Protocol). Focuses on local blocking and preemption.
- [Multi-Core Analysis](./multi_core_rt.md)
    * Covers MSRP (Multiprocessor Stack Resource Policy). Focuses on cross-core spin-locking and global resource contention.


## Comparison Reminder:
Factor	Single-Core (PCP)	Multi-Core (MSRP)
Blocking	Max of one local task (Bloc​)	Sum of many remote tasks (Brem​)
Idle Time	CPU can run other tasks	CPU "Spins" (Busy-wait)
Policy	Priority Ceiling	FIFO Global Queue