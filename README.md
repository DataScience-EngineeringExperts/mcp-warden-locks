# mcp-warden-locks

**A public, append-only corpus of Sigstore-signed MCP server surface locks**, consumed by
[`mcp-warden check --against-community`](https://github.com/DataScience-EngineeringExperts/mcp-warden/blob/main/docs/COMMUNITY_CORPUS.md).

Every entry is an independent observation: an attester spawned a *pinned* package
version in a sandbox, recorded the surface it declared over the MCP handshake
(`tools/list` / `resources/list` / `prompts/list`), and signed the lock's digest **bound to
that package coordinate** with a Sigstore keyless identity. A consumer compares what *they*
observe against what *the attesters they trust* observed.

> ## Consensus attests observation, not safety.
>
> A matching digest means the surface you see is the surface the attesters saw for this
> exact version — no more. It does **not** mean the server is benign, correct, or free of
> prompt injection. A server poisoned identically for everyone matches consensus. What the
> corpus does is turn a *targeted* rug-pull (a surface served only to you) into a loud
> `MISMATCH`, and make "was it already poisoned when I first pinned it?" answerable.

## Layout

```
attesters.json                      discovery list of attester ids → identities (NOT the trust root)
targets.yaml                        what dse-nightly attests: pinned coordinates + sandbox spawn argv
locks/<ecosystem>/<segment>/<version>/<attester-id>.lock            the captured surface
locks/<ecosystem>/<segment>/<version>/<attester-id>.lock.sigstore   Sigstore bundle over the v2 statement
```

`ecosystem` is `npm` or `pypi`; `segment` is the package name with `/` → `__`
(`@modelcontextprotocol/server-filesystem` → `@modelcontextprotocol__server-filesystem`).
**Nothing under `locks/` is ever modified or deleted** — the `append-only` check is a
required status on `main` and fails any PR that tries. A new version is a new path.

## Using it

Only **one** attester exists at launch (`dse-nightly`, run by DSE from this repo's
`attest.yml`). One attester is an observation, not consensus — so pass `--min-attesters 1`
until a second independent attester joins, and read every verdict with that in mind.

```bash
pip install "mcp-warden-cli[sigstore]"

# pin the corpus commit you audited, pin the attester YOU trust, compare:
mcp-warden check npx -y @modelcontextprotocol/server-filesystem@2026.8.31 /tmp \
  --lock warden.lock --against-community \
  --corpus https://github.com/DataScience-EngineeringExperts/mcp-warden-locks \
  --corpus-ref <40-hex commit sha of this repo> \
  --attester dse-nightly=https://github.com/DataScience-EngineeringExperts/mcp-warden-locks/.github/workflows/attest.yml@refs/heads/main@https://token.actions.githubusercontent.com \
  --min-attesters 1
```

| Verdict | Exit | Meaning |
|---|---|---|
| clean match | 0 | ≥ `--min-attesters` trusted attesters saw your surface for this coordinate |
| `WRD-CONSENSUS-NOVEL` | 0 | nobody you trust has attested this coordinate |
| `WRD-CONSENSUS-INSUFFICIENT` | 0 | fewer agreeing attesters than you required |
| `WRD-CONSENSUS-MISMATCH` | **1** | your surface differs from every trusted attestation — stop and look |
| `WRD-CONSENSUS-SPLIT` | **1** | trusted attesters disagree with each other — the corpus or upstream is compromised |
| `…-UNVERIFIABLE` / `…-UNREACHABLE` / `…-UNPINNED-TRUST` | **2** | fail closed; nothing was compared |

The trust root is **yours**: `attesters.json` here is discovery only. A corpus (or a fork of
one) that could name its own trusted identities would verify anything its operator signed.
Signature verification needs network to Sigstore's trust root on first use.

## How entries are produced

`.github/workflows/attest.yml` runs nightly: for each target in `targets.yaml` with no lock
yet — pre-fetch with install scripts disabled → capture inside a **network-less, non-root,
read-only, capability-dropped** container → sign on the runner with ambient OIDC → one PR
with only new paths, merged automatically once the `append-only` gate passes. The full
contract, and what it does *not* defend against, is in [`docs/SANDBOX.md`](docs/SANDBOX.md).

Targets are pinned exact versions from the official MCP servers and widely used third-party
ones. Servers that refuse to start without a credential are given an obviously fake one in
`targets.yaml`; servers that need a live backend to even list their tools are skipped with a
comment rather than attested wrongly.

## Becoming an attester

Run your own sandboxed pipeline under an identity you control, open a PR adding your
`{id, certificate_identity, oidc_issuer}` to `attesters.json` with the `attester-onboarding`
label, then submit locks as new paths. See [`docs/SANDBOX.md`](docs/SANDBOX.md) §"Becoming
an attester". Your entries verify only for consumers who choose to pin your id.

## Status

Phase 2 of [DSE-1515](https://linear.app/dseofficial/issue/DSE-1515) (mcp-warden). Consumer
side shipped in mcp-warden `c0fd858` (`check --against-community`). Requests, second
attesters, and target additions: open an issue or PR here.

License: MIT (tooling and docs). Lock files are factual records of published package
metadata.
