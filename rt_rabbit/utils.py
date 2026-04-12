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
    elif priority_policy == "RR":
        i_same = len(sp_tasks) * quantum
    else:
        raise NotImplementedError(f"{priority_policy} policy was not implemented")
    return b_local, i_same


def calculate_msrp_delays(task: Task, all_tasks: list[Task]) -> tuple[float, float]:
    """
    MSRP theory:
    B_local: Priority inversion on the same core.
    B_remote (spin): waiting for tasks on other cores to release global resources
    """
    my_core = task.task_core_affinity_id

    # B_LOCAL: Lower priority tasks on my core that are non-preemptive (max_chunk)
    lp_local = [
        t
        for t in all_tasks
        if t.task_core_affinity_id == my_core and t.task_priority > task.task_priority
    ]
    b_local: float = max([0.0] + [t.task_max_chunk for t in lp_local])

    # B_REMOVE: (MSRP Spin)
    # IN MSRP, the 'spin' is the sum of the max critical sections of
    # tasks on OTHER cores that could be accessed while we are waiting.
    # Logic: For every other core, find the longest chunk that could be block us.
    b_remote = 0.0
    other_cores = set(
        t.task_core_affinity_id for t in all_tasks if t.task_core_affinity_id != my_core
    )
    for core_id in other_cores:
        remote_tasks = [t for t in all_tasks if t.task_core_affinity_id == core_id]
        b_remote += max([0.0] + [t.task_max_chunk for t in remote_tasks])

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


def generate_system_plot(history, tasks, duration=0.1, misses=None):
    if not history:
        return

    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    from matplotlib.lines import Line2D

    times = [h[0] for h in history]
    num_cores = len(history[0][1])
    tick_ms = times[1] - times[0] if len(times) > 1 else 0.0001

    fig, ax = plt.subplots(figsize=(14, num_cores * 2))

    # 1. Setup Colors
    all_task_names = list(set(t.task_name for t in tasks))
    colors = plt.get_cmap("tab20")
    color_map = {name: colors(i % 20) for i, name in enumerate(all_task_names)}
    idle_color = (0.1, 0.1, 0.12, 1.0)
    color_map["IDLE"] = idle_color

    # 2. Draw Period Ticks (Background)
    for t in tasks:
        num_releases = int(duration / t.task_period)
        for r in range(num_releases + 1):
            release_time = r * t.task_period
            ax.axvline(
                x=release_time,
                color=color_map[t.task_name],
                linestyle="--",
                alpha=0.15,
                linewidth=0.7,
                zorder=1,
            )

    # 3. Plot Execution Bars with Duration Labels
    for core_id in range(num_cores):
        y_base = core_id * 10
        task_history = [h[1][core_id] for h in history]

        i = 0
        while i < len(times) - 1:
            raw_name = task_history[i]
            start_idx = i

            # Group continuous blocks of the same state
            while i < len(times) - 1 and task_history[i] == raw_name:
                i += 1

            end_idx = i
            run_duration = times[end_idx - 1] - times[start_idx] + tick_ms

            # --- SANITIZATION LOGIC ---
            # Turn "Task_A (SPIN)" -> "Task_A" for color lookup
            base_name = raw_name.split(" (")[0]
            is_spinning = "(SPIN)" in raw_name

            current_color = color_map.get(base_name, idle_color)

            # If spinning, make it slightly more transparent or use a hatch
            alpha_val = 0.5 if is_spinning else 1.0
            hatch_pattern = "///" if is_spinning else None

            ax.broken_barh(
                [(times[start_idx], run_duration)],
                (y_base, 8),
                facecolors=current_color,
                alpha=alpha_val,
                hatch=hatch_pattern,
                edgecolor="white" if not is_spinning else current_color,
                linewidth=0.5,
                zorder=2,
            )

            # Add Duration Label
            if base_name != "IDLE" and run_duration > (
                duration * 0.01
            ):  # Only label if big enough
                mid_x = times[start_idx] + (run_duration / 2)
                label_text = f"{run_duration * 1000:.1f}ms"

                ax.text(
                    mid_x,
                    y_base + 4,
                    label_text,
                    ha="center",
                    va="center",
                    color="white",
                    fontsize=7,
                    fontweight="bold",
                    rotation=90 if run_duration < (duration * 0.05) else 0,
                )

    # 4. Handle Deadline Misses
    if misses:
        for miss_time, task_name, core_id in misses:
            ax.scatter(
                miss_time, core_id * 10 + 4, color="red", marker="X", s=100, zorder=5
            )
            ax.axvspan(
                miss_time, miss_time + (duration * 0.005), color="red", alpha=0.2
            )

    # 5. Formatting
    ax.set_xlabel("Time (s)")
    y_ticks = [i * 10 + 4 for i in range(num_cores)]
    y_labels = []
    for i in range(num_cores):
        c_tasks = [t for t in tasks if t.task_core_affinity_id == i]
        task_info = ", ".join([f"{t.task_name}" for t in c_tasks])
        y_labels.append(f"CORE {i}\n[{task_info}]")

    ax.set_yticks(y_ticks)
    ax.set_yticklabels(y_labels, fontsize=9)

    # 6. Legend
    legend_elements = [Patch(facecolor=idle_color, label="IDLE")]
    for name in all_task_names:
        legend_elements.append(Patch(facecolor=color_map[name], label=name))
    legend_elements.append(
        Patch(facecolor="gray", alpha=0.5, hatch="///", label="MSRP SPIN (Wait)")
    )

    ax.legend(handles=legend_elements, loc="upper left", bbox_to_anchor=(1, 1))
    plt.tight_layout()
    plt.show()
