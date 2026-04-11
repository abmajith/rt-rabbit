from typing import Optional
import math
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.lines import Line2D
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
    # Too pessimistic, in RMS this can happen
    # FIFO, not every task can state ready at once
    # in RR, its time slice, some rough bound should introduced later
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
    Calculates the blocking from shared resources,
    Blocking model assumes non-nested critical sections and bounded max_chunk
    Assumes only one remote blocking at worst case
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


def generate_system_plot(history, tasks, resource_map=None, duration=0.1, misses=None):
    """
    Restores the high-precision vertical period ticks for both
    Single and Multi-core analysis.
    """
    if not history:
        return

    times = [h[0] for h in history]
    num_cores = len(history[0][1])
    num_res = len(resource_map) if resource_map else 0
    # Use the actual tick from history if possible
    tick_ms = times[1] - times[0] if len(times) > 1 else 0.0001

    fig, ax = plt.subplots(figsize=(14, (num_cores + num_res) * 1.5))

    # 1. Setup Colors
    all_task_names = list(set(t.task_name for t in tasks))
    colors = plt.get_cmap("tab20")
    color_map = {name: colors(i % 20) for i, name in enumerate(all_task_names)}
    idle_color = (0.1, 0.1, 0.12, 1.0)  # Deep charcoal for IDLE
    color_map["IDLE"] = idle_color

    # 2. We draw these first so they are behind the execution bars
    for t in tasks:
        num_releases = int(duration / t.task_period)
        for r in range(num_releases + 1):
            release_time = r * t.task_period
            ax.axvline(
                x=release_time,
                color=color_map[t.task_name],
                linestyle="--",
                alpha=0.25,  # Faint but visible
                linewidth=0.7,
                zorder=1,  # Keep behind bars
            )

    # 3. Plot Execution Bars
    for core_id in range(num_cores):
        y_base = core_id * 10
        task_history = [h[1][core_id] for h in history]
        for i in range(len(times) - 1):
            task_name = task_history[i]
            ax.broken_barh(
                [(times[i], tick_ms)],
                (y_base, 8),
                facecolors=color_map[task_name],
                linewidth=0,
                zorder=2,
            )
    if misses:
        for miss_time, task_name, core_id in misses:
            # Draw a vertical red marker where the deadline was missed
            ax.scatter(
                miss_time,
                core_id * 10 + 4,
                color="red",
                marker="X",
                s=100,
                label="DEADLINE MISS" if miss_time == misses[0][0] else "",
            )
            # Optional: Draw a subtle red span across the whole core lane for that period
            ax.axvspan(miss_time, miss_time + 0.001, color="red", alpha=0.3)

    # 4. Resource / Bus Lanes
    if resource_map:
        for res_idx, res_name in enumerate(resource_map.keys()):
            y_pos = (num_cores + res_idx) * 10
            for i in range(len(times) - 1):
                owner = history[i][2].get(res_name, "None")
                if owner != "None":
                    ax.broken_barh(
                        [(times[i], tick_ms)],
                        (y_pos, 8),
                        facecolors="red",
                        alpha=0.5,
                        zorder=2,
                    )

    # 5. Labels & Formatting
    ax.set_xlabel("Time (s)")
    ax.set_title("System Timing Analysis: Period Ticks vs Execution")

    # Custom Labels with C/T info
    y_ticks = []
    y_labels = []
    for i in range(num_cores):
        y_ticks.append(i * 10 + 4)
        # Filter tasks for this core for the label
        c_tasks = [t for t in tasks if t.task_core_affinity_id == i]
        task_info = "\n".join(
            [
                f"{t.task_name[:6]}({t.task_exec_time * 1000:.1f}/{t.task_period * 1000:.1f})"
                for t in c_tasks
            ]
        )
        y_labels.append(f"CORE {i}\n{task_info}")

    # 3. Plot Execution Bars with Duration Labels
    for core_id in range(num_cores):
        y_base = core_id * 10
        task_history = [h[1][core_id] for h in history]

        # Detection logic for task duration
        i = 0
        while i < len(times) - 1:
            task_name = task_history[i]
            start_idx = i

            # Find how long this specific task instance runs
            while i < len(times) - 1 and task_history[i] == task_name:
                i += 1

            end_idx = i
            run_duration = times[end_idx - 1] - times[start_idx] + tick_ms

            # Plot the block
            ax.broken_barh(
                [(times[start_idx], run_duration)],
                (y_base, 8),
                facecolors=color_map[task_name],
                linewidth=0,
                zorder=2,
            )

            # Add Duration Label (only if it's a real task and not IDLE, or label IDLE too)
            if task_name != "IDLE" and run_duration > 0:
                # Place text in the middle of the block
                mid_x = times[start_idx] + (run_duration / 2)
                # Convert to ms or us for readability
                label_text = (
                    f"{run_duration * 1000:.2f}ms"
                    if run_duration >= 0.001
                    else f"{run_duration * 1_000_000:.0f}us"
                )

                ax.text(
                    mid_x,
                    y_base + 4,
                    label_text,
                    ha="center",
                    va="center",
                    color="white",
                    fontsize=7,
                    fontweight="bold",
                    rotation=90 if run_duration < 0.005 else 0,
                )

    if resource_map:
        for r in resource_map.keys():
            y_ticks.append((num_cores + len(y_ticks) - num_cores) * 10 + 4)
            y_labels.append(f"BUS: {r}")

    ax.set_yticks(y_ticks)
    ax.set_yticklabels(y_labels, fontsize=8)

    # 6. Legend
    legend_elements = [Patch(facecolor=idle_color, label="IDLE")]
    for name in all_task_names:
        legend_elements.append(Patch(facecolor=color_map[name], label=name))
    if resource_map:
        legend_elements.append(
            Patch(facecolor="red", alpha=0.5, label="Bus Contention")
        )
    if misses:
        legend_elements.append(
            Line2D(
                [0],
                [0],
                marker="X",
                color="w",
                label="DEADLINE MISS",
                markerfacecolor="red",
                markersize=10,
            )
        )

    ax.legend(handles=legend_elements, loc="upper left", bbox_to_anchor=(1, 1))

    plt.grid(axis="x", linestyle=":", alpha=0.2)
    plt.tight_layout()
    plt.show()
