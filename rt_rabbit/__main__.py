import sys
import yaml
import argparse
from rt_rabbit.task import Task
from rt_rabbit.rt_analysis import RTAnalysis
from rt_rabbit.rt_multi_analysis import RTMultiAnalysis


def parse_time(s):
    if isinstance(s, (int, float)):
        return float(s)
    if "ms" in s:
        return float(s.replace("ms", "")) / 1000
    if "us" in s:
        return float(s.replace("us", "")) / 1_000_000
    return float(s)


def load_config(path):
    with open(path) as f:
        data = yaml.safe_load(f)

    system = data.get("system", {})
    tasks = []

    for t in data.get("tasks", []):
        tasks.append(
            Task(
                name=t["name"],
                period=parse_time(t["period"]),
                exec_time=parse_time(t["execution"]),
                priority=t["priority"],
                max_chunk=parse_time(t.get("max_chunk", 0)),
                core_id=t.get("core_affinity", 0),
                resource_id=t.get("resource_id", None),
            )
        )
    return tasks, system


def main():
    parser = argparse.ArgumentParser(
        description="RT-Rabbit: Robotics Real-Time Assistant"
    )
    parser.add_argument("config", help="Path to the YAML task configuration")
    parser.add_argument(
        "--stress", action="store_true", help="Run with hardware jitter/overhead"
    )
    parser.add_argument("--plot", action="store_true", help="Show the timing plot")
    args = parser.parse_args()

    tasks, system = load_config(args.config)
    num_cores = system.get("cores", 1)
    scheduler = system.get("scheduler", "RMS")
    duration = system.get("duration", 0.1)
    target = system.get("target", "zephyr").lower()
    priority_policy = system.get("priority_policy", "FIFO")
    resources = system.get("resources", 0)

    print(f"[*] Target RTOS: {target.upper()}")

    if num_cores > 1:
        engine = RTMultiAnalysis(
            tasks, num_cores=num_cores, scheduler=scheduler, system_resources=resources
        )
        # RTA
        engine.print_multi_rta_report()
        engine.run_simulation(duration, plot_requested=True if args.plot else False)
    else:
        engine = RTAnalysis(tasks, scheduler=scheduler, priority_policy=priority_policy)
        # RTA
        engine.print_rt_report()
        # Simulation
        if args.stress:
            # Pass hardware constants likely derived from your board design
            engine.run_stress_test(
                duration,
                context_switch_ms=0.00005,
                jitter_ms=0.0001,
                plot_requested=True if args.plot else False,
            )
            engine.print_stress_report(
                context_switch_ms=0.00005,
                jitter_ms=0.0001,
            )
        else:
            engine.run_simulation(duration, plot_requested=True if args.plot else False)


if __name__ == "__main__":
    main()
