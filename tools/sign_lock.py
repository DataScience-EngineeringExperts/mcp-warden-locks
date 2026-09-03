#!/usr/bin/env python3
"""Sign an already-captured lock with the v2 (coordinate-bound) statement.

Stage 3 of the attester: the lock was written UNSIGNED inside the network-less
sandbox (Sigstore keyless signing needs the OIDC token, which the sandbox does not
have). This runs on the runner with no third-party code executing and signs the
lock's ``overall_digest`` bound to the package coordinate, exactly as
``mcp-warden pin --sign --coordinate`` would have. Ambient GitHub OIDC is used
(``id-token: write``); no explicit token is read from the environment.

Usage: sign_lock.py <lock-path> <ecosystem:name@version>
"""
from __future__ import annotations

import sys
from pathlib import Path

from rich.console import Console

from mcp_warden.cli_sign import sign_after_pin
from mcp_warden.corpus_coordinate import parse_explicit
from mcp_warden.lockfile import read_lock


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    lock_path = Path(argv[1])
    coord = parse_explicit(argv[2])
    if coord is None:
        print(f"error: not a pinned coordinate: {argv[2]!r}", file=sys.stderr)
        return 2
    lock = read_lock(lock_path)
    # sign_after_pin raises typer.Exit on any failure (fail closed, no partial sidecar).
    sign_after_pin(lock, lock_path, None, Console(stderr=True), coordinate=str(coord))
    print(f"signed {lock_path} for {coord}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
