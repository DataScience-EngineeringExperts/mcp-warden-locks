#!/usr/bin/env bash
# The corpus's one invariant: nothing under locks/ and nothing in attesters.json is
# ever modified or deleted — only added. attesters.json additions are allowed only
# on a PR carrying the `attester-onboarding` label (a human reviewed the identity).
# Usage: append_only_check.sh <base-ref> <head-ref> [label ...]
set -euo pipefail
base="$1"; head="$2"; shift 2
labels=("$@")
mb=$(git merge-base "$base" "$head")
bad=$(git diff --diff-filter=MD --name-only "$mb" "$head" -- locks attesters.json || true)
if [ -n "$bad" ]; then
  echo "::error::append-only violation — these paths were modified or deleted:"; echo "$bad"
  exit 1
fi
if git diff --name-only "$mb" "$head" -- attesters.json | grep -q .; then
  ok=0; for l in "${labels[@]:-}"; do [ "$l" = "attester-onboarding" ] && ok=1; done
  if [ "$ok" != 1 ]; then
    echo "::error::attesters.json changed without the attester-onboarding label"; exit 1
  fi
fi
added=$(git diff --diff-filter=A --name-only "$mb" "$head" -- locks | wc -l | tr -d ' ')
echo "append-only OK ($added new path(s) under locks/)"
