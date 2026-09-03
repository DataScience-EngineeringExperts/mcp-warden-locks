# Attester sandbox contract

An attester runs third-party MCP servers to record their declared surface. A malicious
server must not be able to poison the attester, its signing identity, or the corpus.
This is the contract `dse-nightly` (`.github/workflows/attest.yml`) meets, and the bar a
second attester is asked to meet before its id is added to `attesters.json`.

## Three stages, two trust levels

| Stage | Where | Network | Third-party code runs? | Secrets present? |
|---|---|---|---|---|
| 1 — pre-fetch | container, same image | on | **no** — `npm install --ignore-scripts`, `pip install --only-binary :all:` | none |
| 2 — capture | container | **`--network none`** | **yes** — the MCP server is spawned | none (no OIDC token inside) |
| 3 — sign | runner, no container | on | **no** — `tools/sign_lock.py` over a lock already on disk | ambient OIDC only |

The lock is written **unsigned** inside stage 2 from the SDK handshake alone
(`initialize` → `tools/list` / `resources/list` / `prompts/list`); no tool is ever called,
no result is ever read. Stage 3 signs the file's `overall_digest` bound to the package
coordinate (the v2 statement) with the workflow's ambient GitHub OIDC identity.

## Stage 2 sandbox (verbatim from `tools/attest_one.sh`)

```
docker run --rm --network none --user <runner-uid>:<gid> --read-only --cap-drop ALL \
  --security-opt no-new-privileges --pids-limit 256 --memory 512m \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 \
  -v cache:/cache:ro -v out:/out <image> timeout 120 mcp-warden pin --lock /out/… -- <spawn argv>
```

- **Ephemeral runner** — a fresh GitHub-hosted VM per job, one package per job
  (`strategy.matrix`, `max-parallel: 6`), destroyed afterwards.
- **Non-root** — the runner's own uid (never 0; the script refuses to run as root).
- **No network** — no egress, no DNS. A server that phones home at startup cannot.
- **Read-only root, read-only package cache** — the only writable paths are `/out`
  (the lock) and a 64 MiB `noexec,nosuid` tmpfs.
- **No capabilities, no privilege escalation, 256 pids, 512 MiB, 120 s** — a fork bomb,
  memory bomb, or hang is contained and the target is simply skipped.
- **Digest-pinned image** (`Dockerfile`: `node:22-bookworm-slim@sha256:…`) with mcp-warden
  installed from a pinned commit (`WARDEN_REF`). Nothing from any target is baked in.
- **Pre-fetch with scripts disabled** — `npm install --ignore-scripts`, `pip install
  --only-binary :all:` — so `postinstall` hooks and `setup.py` never execute anywhere, on
  either side of the sandbox. Packages that ship no wheel are dropped, not built.

## What this does **not** protect against

- **A server that is poisoned identically for everyone.** The corpus records what was
  observed; it does not review content. Consensus turns a *targeted* attack into a loud one.
  Pair it with a static tool-poisoning scanner.
- **A server whose declared surface depends on its arguments or environment.** Targets are
  captured with the fixed `spawn`/`env` in `targets.yaml` (dummy credentials where a server
  refuses to start without one). A consumer launching it differently may legitimately see a
  different surface — that is `MISMATCH` doing its job, not a false positive to suppress.
- **Compromise of the attester's GitHub identity or the package registry itself.** Stage 1
  trusts npm/PyPI to serve the named version. Registry provenance is a separate control.
- **Bugs in `mcp-warden pin` or the MCP SDK** while parsing a hostile handshake — mitigated
  by the resource limits above and by the fact that the capture process holds no secrets.
- **Timing/side channels** and anything outside the container boundary (kernel bugs).

## Becoming an attester

1. Run your own copy of this workflow (or any pipeline meeting the table above) under an
   identity you control; sign with `pin --sign --coordinate` or `tools/sign_lock.py`.
2. Open a PR adding one object to `attesters.json` (`id`, exact `certificate_identity`,
   `oidc_issuer`) with the `attester-onboarding` label. The append-only gate refuses
   `attesters.json` changes without it.
3. Submit locks as PRs containing **only new paths**
   `locks/<ecosystem>/<segment>/<version>/<your-id>.lock` + `.lock.sigstore`.

Consumers decide whom to trust: your id does nothing until someone pins it with
`--attester`. **Consensus attests observation, not safety.**
