#!/usr/bin/env python3
"""Convert a flat binary (loaded at address 0) into a $readmemh file of
32-bit little-endian words, one word per line."""
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <in.bin> <out.hex>", file=sys.stderr)
        return 2
    data = Path(sys.argv[1]).read_bytes()
    data += b"\0" * (-len(data) % 4)
    words = (int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4))
    Path(sys.argv[2]).write_text("".join(f"{w:08x}\n" for w in words))
    return 0


if __name__ == "__main__":
    sys.exit(main())
