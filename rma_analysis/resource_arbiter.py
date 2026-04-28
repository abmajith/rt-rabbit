from typing import Dict, Optional


class ResourceArbiter:
    def __init__(self, num_locks: int):
        # lock_id -> core_id (who currently holds it)
        self.locks: Dict[int, Optional[int]] = {i: None for i in range(num_locks)}

    def request_lock(self, lock_id: int, core_id: int) -> bool:
        # if requested resource lock_id available assign it to the cpu core
        if self.locks[lock_id] is None or self.locks[lock_id] == core_id:
            self.locks[lock_id] = core_id
            return True
        return False

    def release_lock(self, lock_id: int, core_id: int):
        # if asked to release the lock for correct cpu id, release it
        if self.locks.get(lock_id) == core_id:
            self.locks[lock_id] = None
