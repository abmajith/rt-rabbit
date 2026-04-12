from typing import Optional


class Task:
    """
    Unified Task model for Real-Time Systems supporting MSRP and PCP.

    This class serves as the core entity for both Single-Core and Multi-Core
    simulations. It encapsulates Zephyr-specific task behaviors and the
    resource synchronization logic required for different RTOS protocols.

    Assumptions & Constraints:
        - MSRP (Multi-Core): Uses busy-waiting (spinning) for global resources.
        - PCP (Single-Core): Uses priority ceilings to prevent local inversion.
        - Zephyr Logic: Negative priorities denote 'Cooperative' tasks, which
        are modeled as having a critical section equal to their full execution time.
    """

    def __init__(
        self,
        name: str,
        period: float,
        exec_time: float,
        priority: int,
        max_chunk=None,
        core_id: int = 0,
        deadline: Optional[float] = None,
        resource_id: Optional[
            int
        ] = None,  # maximum one global resource id a task can use
    ):
        """
        Initializes a Task with dual-protocol support.

        Args:
            name: Task identifier.
            period: Repetition interval (T).
            exec_time: Computational requirement (C).
            priority: positive means pre-emptive, negative means co-operative task in Zephyr.
            max_chunk: Duration of the critical section (L). In MSRP, this is the
                locked duration; in PCP, this defines the blocking term (B).
            core_id: CPU affinity (0-N-1).
            deadline: Relative deadline (D). Defaults to T if None.
            resource_id: Global/Local resource identifier.
        """

        # Task properties
        self.__name = name
        self.__period = period
        self.__exec_time = exec_time
        self.__priority = priority
        self.__is_cooperative = priority < 0
        # in zephyr max_chunk should be exec_time if its cooperative task
        # important for PIP (Priority Inheritance protocol)or PCP Priority Ceiling Protocol
        self.__is_cooperative = priority < 0
        self.__max_chunk = self.__exec_time if self.__is_cooperative else max_chunk or 0
        self.__core_id = core_id
        self.__deadline = deadline if deadline else period
        self.__resource_id = resource_id

        # State variables
        self.remaining_time = 0.0
        self.next_release = 0.0
        self.deadline = self.__deadline
        self.is_spinning = False
        self.current_chunk_remaining = 0.0

    @property
    def task_max_chunk(self) -> float:
        return self.__max_chunk

    @property
    def is_cooperative(self) -> bool:
        return self.__is_cooperative

    @property
    def task_deadline(self) -> float:
        return self.__deadline

    @property
    def task_name(self) -> str:
        return self.__name

    @property
    def task_period(self) -> float:
        return self.__period

    @property
    def task_exec_time(self) -> float:
        return self.__exec_time

    @property
    def task_priority(self) -> int:
        return self.__priority

    @property
    def task_core_affinity_id(self) -> int:
        return self.__core_id

    @property
    def task_resource_id(self) -> int:
        # Explicitly check for None so that 0 is treated as a valid ID
        return self.__resource_id if self.__resource_id is not None else -1

    def is_ready(self, current_time: float) -> bool:
        return self.remaining_time > 1e-9

    def release_if_needed(self, current_time: float) -> bool:
        """Releases task at T=0 and subsequent periods. Returns True on deadline miss."""
        if (
            current_time + 1e-12 >= self.next_release
            # or abs(current_time - self.next_release) < 1e-9
        ):
            missed = self.remaining_time > 1e-9
            self.remaining_time = self.__exec_time
            self.current_chunk_remaining = self.__max_chunk
            # release time progress as 0, T, 2T,...
            # deadline progress as D, T+D, 2T+D,...
            release_time = self.next_release
            self.deadline = release_time + self.__deadline
            self.next_release += self.__period
            return missed
        return False

    def execute(self, amount: float, is_blocked_by_remote: bool = False):
        """
        Advances the task's progress by one simulation tick.

        Logic:
            - If MSRP Blocked: task is_spinning=True. No progress on C.
            - If Running: decrements both remaining_time and current_chunk_remaining.

        Args:
            amount: Time elapsed in the current tick.
            is_blocked_by_remote: Flag from Arbiter indicating cross-core resource wait.
        """

        # perfect preemption, no overhead assumed
        # MSRP spin execution logic was added
        if is_blocked_by_remote:
            self.is_spinning = True
            return
        self.is_spinning = False
        self.remaining_time -= amount
        self.current_chunk_remaining -= amount
        if self.remaining_time < 0:
            self.remaining_time = 0.0
        if self.current_chunk_remaining < 0:
            self.current_chunk_remaining = 0.0
