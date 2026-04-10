import math
from typing import Optional, Dict
from .task import Task
from .logger import get_logger

_log = get_logger("RTAnalysis")


class RTAnalysis:
    def __init__(
        self, tasks: list[Task], scheduler: str = "RMS", tick_ms: float = 0.0001
    ):
        self.tasks = tasks
        self.scheduler = scheduler
        self.time = 0.0
        self.tick_ms = tick_ms
        self.duration = 0.1
        self.last_task = None

    def utility(self) -> float:
        """Simple U = sum(Ci/Ti) check."""
        return sum(t.task_exec_time / t.task_period for t in self.tasks)

    def run_rta(self) -> Dict[str, dict]:
        """Mathematical Response Time Analysis with Zephyr Blocking logic."""
        results = {}
        for i, task in enumerate(self.tasks):
            hp_tasks = [t for t in self.tasks if t.task_priority < task.task_priority]
            sp_tasks = [
                t
                for t in self.tasks
                if t.task_priority == task.task_priority and t != task
            ]
            lp_tasks = [t for t in self.tasks if t.task_priority > task.task_priority]

            # Blocking from lower or same priority cooperative tasks
            blocking_candidates = [t.task_max_chunk for t in (lp_tasks + sp_tasks)]
            bi = max(blocking_candidates + [0])

            # Initial response time includes same-priority interference
            ri = task.task_exec_time + bi + sum(t.task_exec_time for t in sp_tasks)

            while True:
                interference = sum(
                    math.ceil(ri / hp.task_period) * hp.task_exec_time
                    for hp in hp_tasks
                )
                new_ri = (
                    task.task_exec_time
                    + bi
                    + sum(t.task_exec_time for t in sp_tasks)
                    + interference
                )

                if abs(new_ri - ri) < 1e-9:
                    break
                if new_ri > task.task_period:
                    ri = float("inf")
                    break
                ri = new_ri

            results[task.task_name] = {"rt": ri, "safe": ri <= task.task_period}
        return results

    def run_simulation(self, duration: Optional[float]):
        if duration:
            self.duration = duration
        self.last_task = None

        _log.info(
            f"--- Starting {self.scheduler} Simulation (Duration: {self.duration}s) ---"
        )

        while self.time <= self.duration:
            # release logic
            for t in self.tasks:
                if t.release_if_needed(self.time):
                    _log.error(
                        f"T={self.time:.4f}s | {t.task_name} DEADLINE MISS (Overrun)"
                    )
                """
                elif abs(self.time - (t.next_release - t.task_period)) < 1e-9:
                    _log.debug(f"T={self.time:.4f}s | {t.task_name} released")
                """
            # Selection Logic
            ready = [t for t in self.tasks if t.is_ready(self.time)]
            current = None

            # Priority1: Cooperative Lock (Zephyr rule)
            if self.last_task and self.last_task.task_priority < 0:
                if self.last_task.is_ready(self.time):
                    current = self.last_task

            # Priority2: Scheduler Decision
            if current is None and ready:
                if self.scheduler == "RMS":
                    current = min(ready, key=lambda x: (x.task_period, x.task_priority))
                elif self.scheduler == "EDF":
                    current = min(ready, key=lambda x: (x.deadline, x.task_priority))
                elif self.scheduler == "FP":
                    current = min(ready, key=lambda x: x.task_priority)
                else:
                    raise NotImplementedError(
                        f"{self.scheduler} algorithm not implemented"
                    )

            # Context switch
            if current != self.last_task:
                if current:
                    _log.info(f"T={self.time:.4f}s | Running {current.task_name}")
                else:
                    _log.debug(f"T={self.time:.4f}s | CPU Idle")
                self.last_task = current

            # Execution
            if current:
                current.execute(self.tick_ms)
                if not current.is_ready(self.time):
                    _log.info(f"T={self.time:.4f}s | {current.task_name} finished")
                    self.last_task = None

            self.time += self.tick_ms

    def resetTime(self):
        self.time = 0.0

    def setDuration(self, duration: Optional[float]):
        if duration:
            self.duration = duration

    def get_rt_report(self) -> list[str]:
        advice = []
        u = self.utility()
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
        _log.info(f"Overall CPU Utilization: {self.utility() * 100:.2f}%")

        advice_list = self.get_rt_report()
        if not advice_list:
            _log.info("RESULT: System is mathematically SAFE.")
        else:
            _log.warning(f"RESULT: System is UNSAFE. Found {len(advice_list)} issues.")
            for msg in advice_list:
                _log.warning(f"  [!] {msg}")
        _log.info("=" * 40)
