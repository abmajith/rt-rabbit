import random
from typing import Optional, Dict
from .task import Task
from .utils import calculate_pcp_delay_factors
from .utils import calculate_rta, get_utility
from .utils import generate_system_plot
from .logger import get_logger

_log = get_logger("RTAnalysis")


class RTAnalysis:
    """
    Single-core Real-Time Analyzer supporting RMS, EDF, FP, and LST scheduling.

    This class provides both mathematical Response Time Analysis (RTA) and
    cycle-accurate simulation to validate task set schedulability under
    Priority Ceiling Protocol (PCP) and Zephyr cooperative constraints.
    """

    def __init__(
        self,
        tasks: list[Task],
        scheduler: str = "RMS",
        tick_ms: float = 0.0001,
        priority_policy: str = "FIFO",  # or RR,
        quantum_tick: float = 0.001,
    ):
        self.tasks = tasks
        self.scheduler = scheduler
        self.tick_ms = tick_ms
        self.time = 0.0
        self.duration = 0.1
        self.last_task = None
        self.priority_policy = priority_policy
        self.quantum_tick = quantum_tick

    def run_rta(self) -> Dict[str, dict]:
        """Performs fixed-point RTA calculation including PCP blocking and same-priority interference."""
        results = {}
        for _, task in enumerate(self.tasks):
            hp_tasks = [t for t in self.tasks if t.task_priority < task.task_priority]
            b_local, i_same = calculate_pcp_delay_factors(
                task=task,
                all_tasks=self.tasks,
                priority_policy=self.priority_policy,
                quantum=self.quantum_tick,
            )

            ri = calculate_rta(task, hp_tasks, b_local, i_same)
            results[task.task_name] = {
                "rt": ri,
                "safe": ri <= task.task_period,
                "blocking": b_local,
                "sp_interference": i_same,
            }

        return results

    def _release_check_at_step(self, history_misses):
        for t in self.tasks:
            if t.release_if_needed(self.time):
                _log.error(
                    f"T={self.time:.4f}s | {t.task_name} DEADLINE MISS (Overrun)"
                )
                # --- Plot related code ---
                # Track this for the plot
                history_misses.append((self.time, t.task_name, t.task_core_affinity_id))
                # --- Plot related code ---
            """
            elif abs(self.time - (t.next_release - t.task_period)) < 1e-9:
                _log.debug(f"T={self.time:.4f}s | {t.task_name} released")
            """

    def _get_current_task(self) -> Optional[Task]:
        """Internal: Logic to pick the next task based on scheduler rules."""
        ready = [t for t in self.tasks if t.is_ready(self.time)]
        if not ready:
            return None

        # Cooperative Lock Logic (Highest Priority: Zephyr rule)
        if self.last_task and self.last_task.task_priority < 0:
            if self.last_task.is_ready(self.time):
                return self.last_task

        # Standard Scheduler Logic
        if self.scheduler == "RMS":
            return min(ready, key=lambda x: (x.task_period, x.task_priority))
        elif self.scheduler == "EDF":
            return min(
                ready, key=lambda x: (x.deadline, x.remaining_time, x.task_priority)
            )
        elif self.scheduler == "FP":
            return min(ready, key=lambda x: x.task_priority)
        elif self.scheduler == "LST":
            return min(ready, key=lambda x: x.deadline - self.time - x.remaining_time)
        return None

    def _execute_step(self, current: Optional[Task]):
        """Internal: Logs switching and executes task work."""
        if current != self.last_task:
            if current:
                _log.info(f"T={self.time:.4f}s | Running {current.task_name}")
            """
            else:
                _log.debug(f"T={self.time:.4f}s | CPU Idle")
            """
            self.last_task = current

        if current:
            current.execute(self.tick_ms)
            if not current.is_ready(self.time):
                _log.info(f"T={self.time:.4f}s | {current.task_name} finished")
                self.last_task = None

    def run_simulation(self, duration: Optional[float], plot_requested: bool = False):
        if duration:
            self.duration = duration
        self.time = 0.0
        self.last_task = None

        # for plotting the task execution on the cpu
        history = []
        history_misses = []
        _log.info(
            f"--- Starting {self.scheduler} Simulation (Duration: {self.duration}s) ---"
        )

        while self.time <= self.duration:
            # release logic
            self._release_check_at_step(history_misses)
            # Selection Logic
            current = self._get_current_task()

            # --- Capture State for Plotting ---
            if plot_requested:
                # Store what each core is doing at this exact micro-tick
                history.append((self.time, [current.task_name if current else "IDLE"]))
            # --- Capture State for Plotting ---

            # task execution
            self._execute_step(current)
            # update time step
            self.time += self.tick_ms

        # --- Plotting Block ---
        if plot_requested:
            generate_system_plot(
                history,
                self.tasks,
                self.duration,
                history_misses,
            )
        # --- Plotting Block ---

    def run_stress_test(
        self,
        duration: Optional[float],
        context_switch_ms: float = 0.00005,
        jitter_ms: float = 0.0001,
        plot_requested: bool = False,
    ):
        """
        Stress Test Simulation:
        - Introduces Context Switch Overhead (Csw) to the regular run_simulation
            R_i += 2×C_{sw} for context switch for saving,loading registers and other stateful machine registers.
        - Introduces Release Jitter (Ji) to the task execution time because of interrupts or hardware latency.
            T_release = (n x Period) + random(0, Jitter)
        """
        if duration:
            self.duration = duration
        self.time = 0.0
        self.last_task = None

        # for plotting the task execution on the cpu
        history = []
        history_misses = []

        _log.info(
            f"--- STRESS TEST START (Csw: {context_switch_ms}s, Jitter: {jitter_ms}s) ---"
        )

        while self.time <= self.duration:
            # Release Logic with JITTER
            for t in self.tasks:
                # Task might be released slightly late due to interrupt latency
                actual_jitter = random.uniform(0, jitter_ms)
                if self.time >= (t.next_release + actual_jitter):
                    if t.release_if_needed(self.time):
                        _log.error(f"T={self.time:.4f}s | {t.task_name} STRESS MISS")

            # Selection Logic
            current = self._get_current_task()

            # --- Capture State for Plotting ---
            if plot_requested:
                # Store what each core is doing at this exact micro-tick
                history.append((self.time, [current.task_name if current else "IDLE"]))
            # --- Capture State for Plotting ---

            #  CONTEXT SWITCH OVERHEAD
            if current != self.last_task and current is not None:
                _log.debug(
                    f"T={self.time:.4f}s | Context Switch Overhead to {current.task_name}"
                )
                self.time += context_switch_ms

            self._execute_step(current)
            self.time += self.tick_ms

        # --- Plotting Block ---
        if plot_requested:
            generate_system_plot(
                history,
                self.tasks,
                self.duration,
                history_misses,
            )
        # --- Plotting Block ---

    def setDuration(self, duration: Optional[float]):
        if duration:
            self.duration = duration

    def get_rt_report(self) -> list[str]:
        advice = []
        u = get_utility(self.tasks)
        rta_results = self.run_rta()

        # 1. Physical Capacity Check (Applies to all)
        if u > 1.0:
            advice.append(
                f"CRITICAL: Utilization is {u:.2%}. The CPU is physically overloaded."
            )
            advice.append(
                "No schedule is possible. You must reduce execution times or increase periods."
            )
            return advice

        # 2. Scheduler-Specific Heuristics
        if self.scheduler == "RMS":
            # Check for Rate Monotonic priority assignment
            sorted_by_period = sorted(self.tasks, key=lambda x: x.task_period)
            for i in range(len(sorted_by_period) - 1):
                if (
                    sorted_by_period[i].task_priority
                    > sorted_by_period[i + 1].task_priority
                ):
                    advice.append(
                        f"RMS PRIORITY MISMATCH: '{sorted_by_period[i].task_name}' has a shorter period but lower priority "
                        f"than '{sorted_by_period[i + 1].task_name}'."
                    )

        elif self.scheduler == "EDF":
            # EDF is optimal; if it fails and U < 1, it's almost always due to blocking (Bi)
            if any(not res["safe"] for res in rta_results.values()):
                advice.append(
                    "EDF NOTE: EDF is optimal. Failures here are usually caused by Cooperative Blocking (max_chunk)."
                )

        elif self.scheduler == "FP":
            # FP doesn't have a rule like RMS, so we just check if it's "Safe"
            advice.append(
                "FP NOTE: Using custom Fixed Priorities. Ensure critical tasks have the lowest priority numbers."
            )

        # 3. Blocking and Interference Analysis (The "Why" of the failure)
        for name, res in rta_results.items():
            if not res["safe"]:
                task = next(t for t in self.tasks if t.task_name == name)

                # Identify if Blocking (Bi) or Interference (Ii) is the main culprit
                lp_tasks = [
                    t for t in self.tasks if t.task_priority > task.task_priority
                ]
                sp_tasks = [
                    t
                    for t in self.tasks
                    if t.task_priority == task.task_priority and t != task
                ]
                bi = max([t.task_max_chunk for t in (lp_tasks + sp_tasks)] + [0])

                if bi > 0 and (task.task_exec_time + bi > task.task_period):
                    max_allowed_bi = max(0, task.task_period - task.task_exec_time)
                    advice.append(
                        f"BLOCKING ALERT: '{name}' fails due to cooperative blocking. "
                        f"Lower priority tasks must yield (max_chunk) within {max_allowed_bi:.4f}s."
                    )
                else:
                    # If not blocking, it's preemption (interference)
                    advice.append(
                        f"PREEMPTION ALERT: '{name}' is interrupted too often by higher-priority tasks. "
                        f"Current Response Time: {res['rt']:.4f}s vs Period: {task.task_period:.4f}s."
                    )

        return advice

    def print_rt_report(self):
        """Prints a clean summary of the system health."""
        _log.info("=" * 40)
        _log.info(f"RT-RABBIT DESIGN REPORT")
        _log.info("=" * 40)
        _log.info(f"Overall CPU Utilization: {get_utility(self.tasks) * 100:.2f}%")

        advice_list = self.get_rt_report()
        if not advice_list:
            _log.info("RESULT: System is mathematically SAFE.")
        else:
            _log.warning(f"RESULT: System is UNSAFE. Found {len(advice_list)} issues.")
            for msg in advice_list:
                _log.warning(f"  [!] {msg}")
        _log.info("=" * 40)

    def get_stress_advice(
        self, context_switch_ms: float, jitter_ms: float
    ) -> list[str]:
        advice = []
        rta_results = self.run_rta()

        for name, res in rta_results.items():
            task = next(t for t in self.tasks if t.task_name == name)

            if res["safe"]:
                # Calculate "Slack Time"
                slack = task.task_period - res["rt"]

                # If Slack is less than the overhead of a few context switches + jitter
                # the system is 'Fragile'
                overhead_estimate = (2 * context_switch_ms) + jitter_ms

                if slack < overhead_estimate:
                    advice.append(
                        f"FRAGILITY WARNING: '{name}' is mathematically safe but has only {slack:.6f}s slack. "
                        f"Hardware glitches (Csw/Jitter) totaling {overhead_estimate:.6f}s will likely break it."
                    )
            else:
                advice.append(
                    f"STRESS FAILURE: '{name}' is already unsafe in perfect conditions. Overhead only makes it worse."
                )

        return advice

    def print_stress_report(self, context_switch_ms: float, jitter_ms: float):
        """Prints a report focused on hardware overhead and jitter."""
        _log.info("=" * 50)
        _log.info(f"RT-RABBIT STRESS & FRAGILITY REPORT")
        _log.info("=" * 50)

        stress_advice = self.get_stress_advice(context_switch_ms, jitter_ms)

        if not stress_advice:
            _log.info(
                "STABILITY: System has healthy slack to absorb hardware glitches."
            )
        else:
            _log.warning("STABILITY ISSUE: System is sensitive to OS overhead.")
            for msg in stress_advice:
                _log.warning(f"  [!] {msg}")
        _log.info("=" * 50)
