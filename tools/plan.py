#!/usr/bin/env python3
"""Emit the attestation matrix: every target in targets.yaml whose lock path does
not exist yet. Output is a JSON list on stdout (consumed by the workflow's
``strategy.matrix``). No target is ever re-attested: the corpus is append-only, and
a second observation of the same coordinate by the same attester is not new
evidence.

Usage: plan.py [--attester ID] [--all] [--limit N]      -> JSON list of coordinates (the matrix)
       plan.py --one <coordinate>                     -> that target's full JSON (spawn/env/lock_rel)

The matrix carries ONLY coordinates: GitHub refuses to emit a job output that looks
like it contains a secret, and the dummy credentials in `env` trip that heuristic.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
_COORD = re.compile(r"^(npm|pypi):([^@\s]+|@[^/\s]+/[^@\s]+)@([0-9][^\s@]*)$")


def lock_dir(coordinate: str) -> Path:
    m = _COORD.match(coordinate)
    if not m:
        raise SystemExit(f"bad coordinate in targets.yaml: {coordinate!r}")
    eco, name, version = m.groups()
    segment = name.replace("/", "__")
    return ROOT / "locks" / eco / segment / version


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--attester", default="dse-nightly")
    ap.add_argument("--all", action="store_true", help="ignore existing locks (dry runs)")
    ap.add_argument("--limit", type=int, default=0, help="attest at most N targets (0 = all)")
    ap.add_argument("--one", metavar="COORDINATE", help="print the full entry for one coordinate")
    ns = ap.parse_args()
    doc = yaml.safe_load((ROOT / "targets.yaml").read_text(encoding="utf-8"))
    out = []
    for t in doc["targets"]:
        if t.get("skip"):
            continue
        d = lock_dir(t["coordinate"])
        if not ns.all and not ns.one and (d / f"{ns.attester}.lock").exists():
            continue
        out.append({
            "coordinate": t["coordinate"],
            "spawn": t["spawn"],
            "env": t.get("env", {}),
            "lock_rel": str((d / f"{ns.attester}.lock").relative_to(ROOT)),
        })
    if ns.one:
        match = [t for t in out if t["coordinate"] == ns.one]
        if not match:
            raise SystemExit(f"no pending target {ns.one!r}")
        json.dump(match[0], sys.stdout, separators=(",", ":"))
        return 0
    if ns.limit > 0:
        out = out[: ns.limit]
    json.dump([t["coordinate"] for t in out], sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
