# Agents working in pdf20

When using Bend in this repo:
- run `bend PROOF.bend` before proposing any commit; `--verdict` is the CI gate
- `LAWS.bend` states the invariants. Never edit, weaken, or re-scoped it without
  the human's explicit instruction
- every nonconformity diagnostic must cite the clause (and table, when the rule
  is a dictionary table) of ISO 32000-2:2020 — the sponsored text in `docs/`
- clause numbering follows ISO 32000-2:2020, with PDF Association errata
  already folded into that text; check `docs/spec-index.md` before grepping the PDF
- put parallelism (`f a = f(x) g(y)`) on independent structure only: separate
  objects, separate subtrees. Do not parallelize cross-referencing work
- recursion on file data must shrink a matched input argument; use `Nat` fuel
  for anything bounded by the outside world; `@unsafe` only for foreign I/O
  shims, never for parser or resolver logic
- corpus binaries never enter git; keep manifests and fetch scripts in `tools/`

Style: match the guide (`bend guide`). Annotate aggressively; Bend infers
nothing. Prefer `Data`-kinded types for PDF objects; streams keep their bytes
opaque in v0.

Toolchain: Bend 2.0.39 at `~/.bend/bin`; `export PATH="$HOME/.bend/bin:$PATH"`.
`BEND_NO_TELEMETRY=1` in CI. `--verdict` additionally needs Lean v4.34.0 via
elan: `export PATH="$HOME/.elan/bin:$PATH"`.
