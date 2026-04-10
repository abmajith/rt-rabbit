from typing import Dict, Optional
from matplotlib import pyplot as plt
from matplotlib.patches import Patch
from .rt_analysis import RTAnalysis
from .task import Task
from .utils import calculate_rta
from .utils import get_utility
from .utils import get_blocking_triplet
from .utils import generate_system_plot
from .logger import get_logger

_log = get_logger("RTMultiAnalysis")


class RTMultiAnalysis:
    def __init__(
        self,
        tasks: list[Task],
        num_cores: int = 2,
        scheduler: str = "RMS",
        tick_ms: float = 0.0001,
        resource_map: dict | None = None,
    ):
        self.tasks = tasks
        self.num_cores = num_cores
        self.scheduler = scheduler
        self.tick_ms = tick_ms
        self.time = 0.0
        self.duration = 0.1
        self.resource_map = resource_map

        # Create virtual "Single Core Analyzers" for each physical core
        self.core_analyzers = {}
        for i in range(num_cores):
            core_tasks = [t for t in tasks if t.task_core_affinity_id == i]
            self.core_analyzers[i] = RTAnalysis(core_tasks, scheduler, tick_ms)

    def run_multi_rta(self) -> Dict[int, Dict[str, dict]]:
        """Analyze simple RTA safety per core."""
        multi_results = {}
        resource_map = self.resource_map or {}

        for core_id, analyzer in self.core_analyzers.items():
            core_results = {}
            for task in analyzer.tasks:
                # 1. HP Interference (CPU Preemption on local core)
                hp_tasks = [
                    t for t in analyzer.tasks if t.task_priority < task.task_priority
                ]

                # 2. Same-Priority Interference (FIFO Queue on local core)
                sp_tasks = [
                    t
                    for t in analyzer.tasks
                    if t.task_priority == task.task_priority and t != task
                ]

                # 3. Resource Blocking (The "Constraint" logic from your notes)
                b_local, b_remote, _ = get_blocking_triplet(
                    task, self.tasks, resource_map
                )

                # Note: We ignore i_same from triplet here because sp_tasks
                # covers all tasks on the core, which is safer for FIFO.
                total_b = b_local + b_remote

                ri = calculate_rta(
                    task.task_exec_time,
                    task.task_period,
                    hp_tasks,
                    total_b,
                    sp_tasks,
                )
                core_results[task.task_name] = {
                    "rt": ri,
                    "safe": ri <= task.task_period,
                    "metrics": {"b_local": b_local, "b_remote": b_remote},
                }
            multi_results[core_id] = core_results
        return multi_results

    def _release_check_at_step(self, history_misses):
        for t in self.tasks:
            if t.release_if_needed(self.time):
                _log.error(
                    f"T={self.time:.4f}s | {t.task_name} MISS on Core {t.task_core_affinity_id}"
                )
                # --- Plot related code ---
                # Track this for the plot
                history_misses.append((self.time, t.task_name, t.task_core_affinity_id))
                # --- Plot related code ---
            """
            elif abs(self.time - (t.next_release - t.task_period)) < 1e-9:
                _log.debug(f"T={self.time:.4f}s | {t.task_name} released")
            """

    def _execute_step_single_core(self, analyzer: RTAnalysis, core_id: int):
        """Internal: Logs switching and executes task work."""
        analyzer.time = self.time  # Sync time to sub-analyzers
        current = analyzer._get_current_task()
        # Context switch logging needs to be core-aware
        if current != analyzer.last_task:
            if current:
                _log.info(
                    f"T={self.time:.4f}s | [Core {core_id}] -> {current.task_name}"
                )
            analyzer.last_task = current

        if current:
            current.execute(self.tick_ms)
            if not current.is_ready(self.time):
                _log.info(
                    f"T={self.time:.4f}s | [Core {core_id}] -> {current.task_name} finished"
                )
                analyzer.last_task = None

    def run_simulation(self, duration: Optional[float], plot_requested: bool = False):
        if duration:
            self.duration = duration
        self.time = 0.0

        # Data structure for plotting: {time: [core0_task, core1_task, ...]}
        history = []
        history_misses = []

        # Reset task states for simulation
        for t in self.tasks:
            t.remaining_time = 0.0
            t.next_release = 0.0

        _log.info(
            f"--- Multi-Core ({self.num_cores}) {self.scheduler} Simulation ({self.duration}s) ---"
        )
        while self.time <= duration:
            # Release logic for all tasks
            self._release_check_at_step(history_misses)

            # --- Capture State for Plotting ---
            if plot_requested:
                # Store what each core is doing at this exact micro-tick
                current_states = []
                active_resources = {res: "None" for res in self.resource_map.keys()}
                for core_id in range(self.num_cores):
                    task = self.core_analyzers[core_id]._get_current_task()
                    name = task.task_name if task else "IDLE"
                    current_states.append(name)
                    if task:
                        for res, users in self.resource_map.items():
                            if name in users:
                                active_resources[res] = f"Core {core_id}"
                history.append((self.time, current_states, active_resources))
            # --- Capture State for Plotting ---

            # Each core picks and executes its own task
            for core_id, analyzer in self.core_analyzers.items():
                self._execute_step_single_core(analyzer=analyzer, core_id=core_id)
            self.time += self.tick_ms

        # --- Plotting Block ---
        if plot_requested and history:
            generate_system_plot(
                history, self.tasks, self.resource_map, self.duration, history_misses
            )
        # --- Plotting Block ---

    def print_multi_rta_report(self):
        """
        Prints a high-level design verification report for multi-core systems.
        Focuses on cross-core interference and local blocking.
        """
        results = self.run_multi_rta()

        _log.info("=" * 65)
        _log.info(f"RT-RABBIT MULTI-CORE DESIGN REPORT ({self.num_cores} Cores)")
        _log.info("=" * 65)

        for core_id, tasks in results.items():
            u_core = get_utility(
                tasks=[t for t in self.tasks if t.task_core_affinity_id == core_id]
            )
            _log.info(f"CORE {core_id} | Total Utilization: {u_core * 100:.2f}%")
            _log.info(f"{'-' * 65}")
            _log.info(
                f"{'Task Name':<15} | {'RT':<10} | {'Status':<6} | {'B_Loc':<8} | {'B_Rem'}"
            )

            for name, data in tasks.items():
                status = "SAFE" if data["safe"] else "UNSAFE"
                rt_str = (
                    f"{data['rt']:.5f}s" if data["rt"] != float("inf") else "TIMEOUT"
                )
                b_loc = f"{data['metrics']['b_local']:.5f}"
                b_rem = f"{data['metrics']['b_remote']:.5f}"

                _log.info(
                    f"{name:<15} | {rt_str:<10} | {status:<6} | {b_loc:<8} | {b_rem}"
                )
            _log.info("")

        # Global Design Advice
        self._print_design_advice(results)
        _log.info("=" * 65)

    def _print_design_advice(self, results):
        """Internal: Analyzes the results to give board-level advice."""
        for core_id, tasks in results.items():
            for name, data in tasks.items():
                if not data["safe"]:
                    if data["metrics"]["b_remote"] > 0:
                        _log.warning(
                            f"  [!] '{name}' fails due to Cross-Core Blocking ({data['metrics']['b_remote']}s)."
                        )
                    if data["metrics"]["b_local"] > 0 and data["rt"] != float("inf"):
                        _log.warning(
                            f"  [!] '{name}' is heavily delayed by local priority inversion."
                        )
