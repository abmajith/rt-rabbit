from typing import Optional


class Task:
    def __init__(
        self,
        name: str,
        period: float,
        exec_time: float,
        priority: int,
        max_chunk=None,
        core_id: int = 0,
        deadline: Optional[float] = None,
    ):
        # Task properties
        self.__name = name
        self.__period = period
        self.__exec_time = exec_time
        self.__priority = priority
        self.__max_chunk = max_chunk or 0
        self.__is_cooperative = priority < 0
        self.__core_id = core_id
        self.__deadline = deadline if deadline else period

        # State variables
        self.remaining_time = 0.0
        self.next_release = 0.0
        self.deadline = self.__deadline

    @property
    def task_max_chunk(self) -> int:
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
            # release time progress as 0, T, 2T,...
            # deadline progress as D, T+D, 2T+D,...
            release_time = self.next_release
            self.deadline = release_time + self.__deadline
            self.next_release += self.__period
            return missed
        return False

    def execute(self, amount: float):
        # perfect preemption, no overhead
        self.remaining_time -= amount
        if self.remaining_time < 0:
            self.remaining_time = 0
