from typing import Dict, Optional
from .rt_analysis import RTAnalysis
from resource_arbiter import ResourceArbiter
from .task import Task
from .utils import calculate_rta
from .utils import get_utility
from .utils import calculate_msrp_delays
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
        system_resources: int = 0,
    ):
        self.tasks = tasks
        self.num_cores = num_cores
        self.scheduler = scheduler
        self.tick_ms = tick_ms
        self.time = 0.0
        self.duration = 0.1
        self.system_resources = system_resources

        # Create virtual "Single Core Analyzers" for each physical core
        self.core_analyzers = {}
        for i in range(num_cores):
            core_tasks = [t for t in tasks if t.task_core_affinity_id == i]
            self.core_analyzers[i] = RTAnalysis(core_tasks, scheduler, tick_ms)

    def run_multi_rta(self) -> Dict[int, Dict[str, dict]]:
        """Analyze simple RTA safety per core."""
        multi_results = {}

        for core_id, analyzer in self.core_analyzers.items():
            core_results = {}
            for task in analyzer.tasks:
                # 1. HP Interference (CPU Preemption on local core)
                hp_tasks = [
                    t for t in analyzer.tasks if t.task_priority < task.task_priority
                ]

                # MSRP specific delays
                b_local, b_remote = calculate_msrp_delays(task, self.tasks)
                # Same-priority interference (FIFO logic)
                # 2. Same-Priority Interference (FIFO Queue on local core)
                sp_tasks = [
                    t
                    for t in analyzer.tasks
                    if t.task_priority == task.task_priority and t != task
                ]
                i_same = sum(t.task_exec_time for t in sp_tasks)
                # covers all tasks on the core, which is safer for FIFO.
                # For RR, for the worst case, following calculation is okay
                total_blocking = b_local + b_remote

                ri = calculate_rta(
                    task,
                    hp_tasks,
                    total_blocking,
                    i_same,
                )
                core_results[task.task_name] = {
                    "rt": ri,
                    "safe": ri <= task.task_period,
                    "metrics": {
                        "b_local": b_local,
                        "b_remote": b_remote,
                        "spin": b_remote,
                    },
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

    def _execute_step_single_core(self, analyzer: RTAnalysis, core_id: int, current: Optional[Task]):
        """Internal: Executes the task provided by the multi-core orchestrator."""
        analyzer.time = self.time  
    
        # Context switch logging
        if current != analyzer.last_task:
            if current:
                _log.info(f"T={self.time:.4f}s | [Core {core_id}] -> {current.task_name}")
            analyzer.last_task = current

        if current:
            # Use the spinning state already determined by arbitration
            current.execute(self.tick_ms, is_blocked_by_remote=current.is_spinning)

            if not current.is_ready(self.time):
                _log.info(
                    f"T={self.time:.4f}s | [Core {core_id}] -> {current.task_name} finished"
                )
                # Cleanup for next release
                current.is_spinning = False
                current.current_chunk_remaining = 0.0
                analyzer.last_task = None

    def _handle_resource_arbitration(self, active_map, arbiter):
        for core_id, task in active_map.items():
            if not task:
                continue

            # Only tasks with a remaining chunk and a valid resource seek a lock
            res_id = task.task_resource_id
            if res_id != -1 and task.current_chunk_remaining > 0:
                granted = arbiter.request_lock(res_id, core_id)
                task.is_spinning = not granted

                # IMPORTANT: Only release if we actually finished the chunk work
                if task.current_chunk_remaining <= 1e-12:
                    arbiter.release_lock(res_id, core_id)
            else:
                # No resource needed or chunk finished
                task.is_spinning = False

    def run_simulation(self, duration: Optional[float], plot_requested: bool = False):
        if duration:
            self.duration = duration
        self.time = 0.0
        arbiter = ResourceArbiter(num_locks=self.system_resources)

        global_lock_owner: Optional[int] = None
        # Data structure for plotting: {time: [core0_task, core1_task, ...]}
        history = []
        history_misses = []

        # Reset task states for simulation
        for t in self.tasks:
            t.remaining_time = 0.0
            t.next_release = 0.0
            t.is_spinning = False
            t.current_chunk_remaining = 0.0

        _log.info(
            f"--- Multi-Core ({self.num_cores}) {self.scheduler} Simulation ({self.duration}s) ---"
        )
        while self.time <= duration:
            # Release logic for all tasks
            self._release_check_at_step(history_misses)

            # Get candidate tasks for each core
            active_map = {
                cid: a._get_current_task() for cid, a in self.core_analyzers.items()
            }
            self._handle_resource_arbitration(active_map, arbiter)

            # --- Capture State for Plotting ---
            if plot_requested:
                # Store what each core is doing at this exact micro-tick
                current_states = []
                for core_id in range(self.num_cores):
                    task = active_map[core_id]
                    if task:
                        label = (
                            f"{task.task_name} (SPIN)"
                            if task.is_spinning
                            else task.task_name
                        )
                        current_states.append(label)
                    else:
                        current_states.append("IDLE")
                history.append((self.time, current_states))
            # --- Capture State for Plotting ---

            # Each core picks and executes its own task
            for core_id, analyzer in self.core_analyzers.items():
                task_to_run = active_map[core_id]
                self._execute_step_single_core(analyzer, core_id, task_to_run)

            self.time += self.tick_ms

        # --- Plotting Block ---
        if plot_requested and history:
            generate_system_plot(history, self.tasks, self.duration, history_misses)
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
