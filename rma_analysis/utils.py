from typing import Optional
import math
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.lines import Line2D
from .task import Task


def calculate_rta(
    task: Task,
    hp_tasks: Optional[list[Task]],
    blocking_time: float = 0.0,
    interference_time: float = 0.0,
):
    """
    Computes the Worst-Case Response Time (Ri) using iterative fixed-point analysis.

    Formula: Ri = Ci + Bi (Blocking) + I_same (Interference) + Sum(ceil(Ri/Tj) * Cj)

    Args:
        task: The task under analysis.
        hp_tasks: Tasks with higher priority that can preempt the subject task.
        blocking_time: Local blocking (Bi) from lower-priority tasks (PCP/MSRP).
        interference_time: Delay from tasks with equal priority (I_same).
    """
    # Too pessimistic, in RMS this can happen
    ri = task.task_exec_time + blocking_time + interference_time

    while True:
        # Higher-priority preemption
        interference = (
            sum(math.ceil(ri / hp.task_period) * hp.task_exec_time for hp in hp_tasks)
            if hp_tasks
            else 0
        )

        new_ri = task.task_exec_time + blocking_time + interference_time + interference
        if abs(new_ri - ri) < 1e-9:
            return ri
        if new_ri > task.task_period:
            return float("inf")  # System is mathematically unsafe
        ri = new_ri


def calculate_pcp_delay_factors(
    task: Task,
    all_tasks: list[Task],
    priority_policy: str = "FIFO",
    quantum: float = 0.001,
) -> tuple[float, float]:
    """
    Calculates blocking and interference terms based on Priority Ceiling Protocol theory.

    Returns:
        tuple: (b_local, i_same) where b_local is the maximum non-preemptive
        chunk of any lower-priority task, and i_same is the same-priority delay
        based on FIFO or Round Robin policies.
    """
    # B_local (PCB Theory):
    # In PCP/Zephyr, blocked by MAX max_chunk of any lower priority tasks
    # for co-operative tasks have ceiling priority higher than all preemptive task

    lp_tasks = [t for t in all_tasks if t.task_priority > task.task_priority]
    b_local: float = max([0.0] + [t.task_max_chunk for t in lp_tasks])

    # I_same same priority interference
    sp_tasks = [
        t for t in all_tasks if t.task_priority == task.task_priority and t != task
    ]
    i_same = 0.0
    if not sp_tasks:
        return b_local, i_same
    if priority_policy == "FIFO":
        # pessimistic worst case
        i_same = sum(t.task_exec_time for t in sp_tasks)
    if priority_policy == "FIFO_TIGHT":
        i_same = max(t.task_exec_time for t in sp_tasks)
    elif priority_policy == "RR":
        i_same = len(sp_tasks) * quantum
    else:
        raise NotImplementedError(f"{priority_policy} policy was not implemented")
    return b_local, i_same


def calculate_msrp_delays(task: Task, all_tasks: list[Task]) -> tuple[float, float]:
    """
    Calculates MSRP blocking factors: Local Priority Inversion and Remote Spin.

    MSRP Theory:
    - B_local: The maximum non-preemptive chunk (L) of any lower-priority task
      on the same core.
    - B_remote: The sum of the longest critical sections (L) for the SAME resource
      across all OTHER cores.

    Args:
        task: The task being analyzed.
        all_tasks: The global task set.

    Returns:
        tuple: (b_local, b_remote)
    """
    my_core = task.task_core_affinity_id
    res_id = task.task_resource_id

    # 1. B_LOCAL: Priority inversion on the local core
    lp_local = [
        t
        for t in all_tasks
        if t.task_core_affinity_id == my_core and t.task_priority > task.task_priority
    ]
    b_local = max([0.0] + [t.task_max_chunk for t in lp_local])

    # 2. B_REMOTE (Spin): Only applies if the task actually uses a global resource
    b_remote = 0.0
    if res_id != -1:
        other_cores = set(
            t.task_core_affinity_id
            for t in all_tasks
            if t.task_core_affinity_id != my_core
        )
        for core_id in other_cores:
            # Find the longest chunk on this specific other core for the SAME resource
            remote_contention = [
                t.task_max_chunk
                for t in all_tasks
                if t.task_core_affinity_id == core_id and t.task_resource_id == res_id
            ]
            b_remote += max([0.0] + remote_contention)

    return b_local, b_remote


def get_utility(tasks: Optional[list[Task]]) -> float:
    """Simple U = sum(Ci/Ti) check."""
    if not tasks:
        return 0.0
    return sum(t.task_exec_time / t.task_period for t in tasks)


def is_harmonic(periods: list[float]) -> bool:
    """Checks if all periods are multiples of each other."""
    if not periods:
        return True
    periods = sorted(periods)
    for i in range(len(periods) - 1):
        # If the larger period isn't a multiple of the smaller one
        if not math.isclose((periods[i + 1] / periods[i]) % 1.0, 0.0, abs_tol=1e-9):
            return False
    return True


def get_thu_bound(periods: list[float]) -> float:
    """Returns the utilization bound. 1.0 if harmonic, else the RMS bound."""
    if is_harmonic(periods):
        return 1.0
    n = len(periods)
    if n == 0:
        return 1.0
    return n * (2 ** (1 / n) - 1)
