from typing import Optional
import math
from .task import Task


def calculate_rta(
    task_exec_time: float,
    task_period: float,
    hp_tasks: Optional[list[Task]],
    blocking_time: float = 0.0,  # b_local + b_remote
    sp_tasks: Optional[list[Task]] = None,
):
    """
    Core Response Time Analysis math used by all analyzers.
    Initial: Ri = Ci + Bi + Ii (Interference) + Si (Same priority interference)
    Update: Ii = sum(ceil(Ri/Tj)Ci)
    """
    Si = sum(t.task_exec_time for t in sp_tasks) if sp_tasks else 0
    ri = task_exec_time + blocking_time + Si

    while True:
        # Higher-priority preemption
        interference = (
            sum(math.ceil(ri / hp.task_period) * hp.task_exec_time for hp in hp_tasks)
            if hp_tasks
            else 0
        )

        new_ri = task_exec_time + blocking_time + Si + interference
        if abs(new_ri - ri) < 1e-9:
            return ri
        if new_ri > task_period:
            return float("inf")  # System is mathematically unsafe
        ri = new_ri


def get_blocking_triplet(
    task: Task, all_tasks: list[Task], resource_map: dict
) -> tuple[float, float, float]:
    """
    Calculates the blocking from shared resources
    """
    if not resource_map:
        return 0.0, 0.0, 0.0
    b_local: float = 0.0  # same core id
    b_remote: float = 0.0  # from different core id
    i_same: float = 0.0  # from same core id with same priority (FIFO/Queue)
    for res_id, users in resource_map.items():
        if task.task_name in users:
            # 1. LOCAL SAME PRIORITY (Interference - The Sum)
            # These tasks are on the same core and share the resource.
            # If they are already running, you wait for their whole execution.
            same_prio = [
                t
                for t in all_tasks
                if t.task_name in users
                and t.task_core_affinity_id == task.task_core_affinity_id
                and t.task_priority == task.task_priority
                and t.task_name != task.task_name
            ]
            i_same += sum(t.task_exec_time for t in same_prio)

            # 2. LOCAL LOWER PRIORITY (Blocking - The Max)
            # These tasks are on the same core but lower priority.
            # You only wait for their current 'max_chunk' to finish.
            lower_prio = [
                t
                for t in all_tasks
                if t.task_name in users
                and t.task_core_affinity_id == task.task_core_affinity_id
                and t.task_priority > task.task_priority
            ]
            if lower_prio:
                b_local = max(b_local, max(t.task_max_chunk for t in lower_prio))

            # 3. REMOTE BLOCKING (Cross-Core - The Max)
            # Task on another core is using the hardware (e.g., I2C bus)
            remote_users = [
                t
                for t in all_tasks
                if t.task_name in users
                and t.task_core_affinity_id != task.task_core_affinity_id
            ]
            if remote_users:
                b_remote = max(b_remote, max(t.task_max_chunk for t in remote_users))
    return b_local, b_remote, i_same


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
