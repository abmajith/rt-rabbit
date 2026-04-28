from typing import List, Tuple, Dict, Optional
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import MultipleLocator
from .task import Task
from .utils import get_utility


def _draw_deadline_misses(
    ax: plt.Axes, misses: List[Tuple[float, str, int]], duration: float
):
    """
    Highlights failure points with a vertical red span (the 'Big Chunk')
    and an 'X' marker at the specific core level.
    """
    if not misses:
        return

    # Use a set to avoid drawing multiple red background chunks at the same timestamp
    unique_miss_times = sorted(list(set(m[0] for m in misses)))

    for m_time in unique_miss_times:
        # 1. The 'Big Chunk' Background Segment
        # Highlights the entire vertical timeline at the moment of failure
        ax.axvspan(
            m_time,
            m_time + (duration * 0.01),
            color="red",
            alpha=0.15,
            label="Deadline Miss Zone",
            zorder=1,  # Keep it behind the execution bars
        )

    # 2. Specific 'X' Markers
    for m_time, m_name, m_core in misses:
        ax.scatter(
            m_time,
            m_core * 10 + 4,
            color="darkred",
            marker="X",
            s=150,
            edgecolors="white",
            linewidth=1,
            zorder=10,  # Pop it to the very front
        )


def _get_core_stats_label(core_id: int, tasks: List["Task"]) -> str:
    """Detailed Y-axis label with Task Statistics (C, T, D, P)."""
    core_tasks = [t for t in tasks if t.task_core_affinity_id == core_id]
    u_core = sum(t.task_exec_time / t.task_period for t in core_tasks)

    lines = [f"CORE {core_id} (U: {u_core:.1%})", "=" * 25]
    for t in core_tasks:
        # Convert to ms for human readability
        c, t_p, d = (
            t.task_exec_time * 1000,
            t.task_period * 1000,
            t.task_deadline * 1000,
        )
        lines.append(
            f"{t.task_name:.<10} \n [P:{t.task_priority:>2}] (C:{c:>4.1f}, T:{t_p:>4.1f}, D:{d:>4.1f})ms"
        )

    return "\n".join(lines)


def _apply_plot_formatting(
    ax: plt.Axes, tasks: List["Task"], num_cores: int, color_map: dict, duration: float
):
    """Final visual polish: Grids, Labels, and Legend."""
    _apply_grid_styling(ax, duration)

    ax.set_xlabel("Time (seconds)", fontweight="bold", fontsize=10)

    # Setup Y-Axis with the statistics we built
    y_ticks = [i * 10 + 4 for i in range(num_cores)]
    y_labels = [_get_core_stats_label(i, tasks) for i in range(num_cores)]

    ax.set_yticks(y_ticks)
    ax.set_yticklabels(y_labels, fontsize=8, family="monospace", va="center")

    # Legend Logic
    legend_elements = [Patch(facecolor=color_map["IDLE"], label="IDLE CPU")]
    for name, color in color_map.items():
        if name != "IDLE":
            legend_elements.append(Patch(facecolor=color, label=name))

    if num_cores > 1:
        legend_elements.append(
            Patch(facecolor="gray", alpha=0.5, hatch="///", label="MSRP SPIN (Wait)")
        )

    ax.legend(
        handles=legend_elements,
        loc="upper left",
        bbox_to_anchor=(1, 1),
        title="Task & Protocol Legend",
        frameon=True,
        shadow=True,
    )


def _setup_plot_colors(
    tasks: List[Task],
) -> Dict[str, Tuple[float, float, float, float]]:
    """Assigns unique colors to tasks and sets the IDLE color."""
    all_task_names = list(set(t.task_name for t in tasks))
    cmap = plt.get_cmap("tab20")
    color_map = {name: cmap(i % 20) for i, name in enumerate(all_task_names)}
    color_map["IDLE"] = (0.1, 0.1, 0.12, 1.0)
    return color_map


def _apply_grid_styling(ax: plt.Axes, duration: float):
    """
    Creates a high-precision grid layout.
    Major lines every 10ms, Minor lines every 1ms.
    """
    # Major ticks every 0.01s (10ms)
    ax.xaxis.set_major_locator(MultipleLocator(0.01))
    # Minor ticks every 0.001s (1ms) - The 'Fine Progression' lines
    ax.xaxis.set_minor_locator(MultipleLocator(0.001))

    # Style the Major grid (darker, solid)
    ax.grid(which="major", color="#CCCCCC", linestyle="-", alpha=0.6, linewidth=0.8)

    # Style the Minor grid (lighter, dotted)
    ax.grid(which="minor", color="#DDDDDD", linestyle=":", alpha=0.4, linewidth=0.5)

    # Ensure the grid is behind the execution bars
    ax.set_axisbelow(True)


def generate_system_plot(
    history: List[Tuple[float, List[str]]],
    tasks: List[Task],
    duration: float = 0.1,
    misses: Optional[List[Tuple[float, str, int]]] = None,
):
    """
    Renders a Gantt-style chart with fine-grained grids and core-specific statistics.
    """
    if not history:
        return

    times = [h[0] for h in history]
    num_cores = len(history[0][1])
    tick_ms = times[1] - times[0] if len(times) > 1 else 0.0001
    color_map = _setup_plot_colors(tasks)

    fig, ax = plt.subplots(figsize=(14, max(5, num_cores * 2.5)))

    # Apply visual aids
    _apply_grid_styling(ax, duration)

    # Background Period Guides
    for t in tasks:
        num_releases = int(duration / t.task_period)
        for r in range(num_releases + 1):
            ax.axvline(
                x=r * t.task_period,
                color=color_map[t.task_name],
                linestyle="--",
                alpha=0.1,
                linewidth=0.8,
            )

    # Core Execution
    for core_id in range(num_cores):
        y_base = core_id * 10
        task_history = [h[1][core_id] for h in history]

        i = 0
        while i < len(times) - 1:
            raw_name = task_history[i]
            start_idx = i
            while i < len(times) - 1 and task_history[i] == raw_name:
                i += 1

            run_duration = times[i - 1] - times[start_idx] + tick_ms
            base_name = raw_name.split(" (")[0]

            # Styling: MSRP hatch only if multi-core
            is_spinning = "(SPIN)" in raw_name and num_cores > 1
            hatch = "///" if is_spinning else None
            alpha = 0.6 if is_spinning else 1.0

            ax.broken_barh(
                [(times[start_idx], run_duration)],
                (y_base, 8),
                facecolors=color_map.get(base_name, color_map["IDLE"]),
                alpha=alpha,
                hatch=hatch,
                edgecolor="white",
                linewidth=0.5,
            )

            # Labels for human debugging
            if base_name != "IDLE" and run_duration > (duration * 0.005):
                ax.text(
                    times[start_idx] + (run_duration / 2),
                    y_base + 4,
                    f"{run_duration * 1000:.1f}ms",
                    ha="center",
                    va="center",
                    color="white",
                    fontsize=6,
                    fontweight="bold",
                    rotation=90 if run_duration < (duration * 0.04) else 0,
                )

    # Deadline Miss markers
    if misses:
        for m_time, _, m_core in misses:
            ax.scatter(
                m_time, m_core * 10 + 4, color="red", marker="X", s=120, zorder=10
            )
    if misses:
        _draw_deadline_misses(ax, misses, duration)

    # 5. Final Formatting
    _apply_plot_formatting(ax, tasks, num_cores, color_map, duration)

    # Y-Axis and Legend
    ax.set_yticks([i * 10 + 4 for i in range(num_cores)])
    ax.set_yticklabels(
        [_get_core_stats_label(i, tasks) for i in range(num_cores)], fontsize=9
    )
    ax.set_xlabel("Time (seconds)")

    _create_legend(ax, color_map, num_cores)

    plt.tight_layout()
    plt.show()


def _create_legend(ax, color_map, num_cores):
    legend_elements = [Patch(facecolor=color_map["IDLE"], label="IDLE")]
    for name, color in color_map.items():
        if name != "IDLE":
            legend_elements.append(Patch(facecolor=color, label=name))
    if num_cores > 1:
        legend_elements.append(
            Patch(facecolor="gray", alpha=0.5, hatch="///", label="MSRP SPIN (Wait)")
        )
    ax.legend(
        handles=legend_elements, loc="upper left", bbox_to_anchor=(1, 1), fontsize=8
    )
