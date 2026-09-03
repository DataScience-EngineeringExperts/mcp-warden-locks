#!/usr/bin/env bash
# Attest ONE target: stage 1 pre-fetch (network on, package managers only, no
# third-party code executes), stage 2 sandboxed capture (network none, non-root,
# read-only, no caps), stage 3 signing on the host (see tools/sign_lock.py).
# Reads the target as JSON on $TARGET_JSON (never via ${{ }} interpolation).
# Env: IMAGE (attester image), OUT (output root, default ./out), SIGN=1 to sign.
set -euo pipefail
: "${TARGET_JSON:?TARGET_JSON (one plan.py entry) is required}"
: "${IMAGE:?IMAGE is required}"
OUT="${OUT:-$PWD/out}"; CACHE="${CACHE:-$PWD/cache}"
mkdir -p "$OUT" "$CACHE"
coord=$(printf '%s' "$TARGET_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["coordinate"])')
lock_rel=$(printf '%s' "$TARGET_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["lock_rel"])')
mapfile -t spawn < <(printf '%s' "$TARGET_JSON" | python3 -c 'import json,sys;[print(a) for a in json.load(sys.stdin)["spawn"]]')
mapfile -t envkv < <(printf '%s' "$TARGET_JSON" | python3 -c 'import json,sys;[print(f"{k}={v}") for k,v in json.load(sys.stdin).get("env",{}).items()]')
eco=${coord%%:*}; rest=${coord#*:}; version=${rest##*@}; name=${rest%@*}; segment=${name//\//__}
lock_path="$OUT/$lock_rel"; mkdir -p "$(dirname "$lock_path")"
uid=$(id -u); gid=$(id -g)
if [ "$uid" = "0" ]; then echo "refusing to run as root" >&2; exit 2; fi
echo "== [$coord] stage 1: pre-fetch (network on, --ignore-scripts / --only-binary)"
case "$eco" in
  npm)
    docker run --rm --network bridge --user "$uid:$gid" -e HOME=/tmp -e npm_config_cache=/tmp/npm-cache \
      --tmpfs /tmp:rw,nosuid,size=256m -v "$CACHE:/cache" "$IMAGE" \
      npm install --prefix "/cache/npm/$segment" --ignore-scripts --no-audit --no-fund --no-package-lock --loglevel=error "$name@$version" ;;
  pypi)
    docker run --rm --network bridge --user "$uid:$gid" -e HOME=/tmp \
      --tmpfs /tmp:rw,nosuid,size=256m -v "$CACHE:/cache" "$IMAGE" \
      pip install --quiet --no-cache-dir --only-binary :all: --target "/cache/pypi/$segment" "$name==$version" ;;
  *) echo "unknown ecosystem $eco" >&2; exit 2 ;;
esac
echo "== [$coord] stage 2: sandboxed capture (network none, non-root, read-only, cap-drop ALL)"
envflags=(); for kv in "${envkv[@]:-}"; do [ -n "$kv" ] && envflags+=(-e "$kv"); done
docker run --rm --network none --user "$uid:$gid" --read-only --cap-drop ALL \
  --security-opt no-new-privileges --pids-limit 256 --memory 512m \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 \
  -e "PYTHONPATH=/cache/pypi/$segment" -e "NODE_PATH=/cache/npm/$segment/node_modules" "${envflags[@]}" \
  -v "$CACHE:/cache:ro" -v "$OUT:/out" "$IMAGE" \
  timeout 120 mcp-warden pin --lock "/out/$lock_rel" -- "${spawn[@]}"
test -s "$lock_path"
if [ "${SIGN:-0}" = "1" ]; then
  echo "== [$coord] stage 3: sign on host (v2 statement, ambient OIDC)"
  python3 "$(dirname "$0")/sign_lock.py" "$lock_path" "$coord"
  test -s "$lock_path.sigstore"
fi
echo "== [$coord] OK -> $lock_rel"
