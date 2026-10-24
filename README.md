# pdf20

A strict PDF 2.0 file reader/validator/writer. Reads ISO 32000-2:2020 files,
resolves the object graph, validates against the spec, and rejects
non-conformant files with a diagnostic that cites the spec clause.

Written in Bend 2. Correctness invariants live in `LAWS.bend`; every change to
the engine must keep `bend PROOF.bend` green before it can be committed.

## Which spec

- Base: **ISO 32000-2:2020** (PDF 2.0), Edition 2, published 2020-12. This is
  the current official edition; no newer edition exists.
- Corrections: the PDF Association maintains the official industry-approved
  errata at <https://pdf-issues.pdfa.org/32000-2-2020/>. The sponsored copy
  bundled with errata is in `docs/`. Clause citations in diagnostics point at
  this text.
- Out of scope for v0: the five standardized extensions bundled next to it
  (TS 32001/32002/32005/32007, ECMAScript).

## v0 scope

In: clause 7 syntax — scalar objects, arrays, dictionaries, streams
(contents stay opaque bytes), classic xref tables, xref streams,
object streams, incremental update merging, trailer/catalog/page tree
structure checks. Writer with bit-precise roundtrip.

Out: rendering, fonts, images, annotations, JavaScript, attachments,
encryption decode (rejects with 7.6 citation instead), all image codecs.

## Laws

Rooted in `LAWS.bend`:

1. Parser totality — every input bytes yields a verdict, never a hang (no
   unmarked recursion, decoder depth bounded).
2. Byte-precise roundtrip — `serialize(parse(b)) == b` for every conformant
   file.
3. Acyclic page tree, resolution consistency — every indirect reference
   resolves to a defined object; page tree children navigate without cycles.
4. Resource cap — any single decompressed/allocated structure above the cap
   is rejected, never OOM.

## Layout

```
src/          Bend source (lexer, parser, resolver, validator, writer)
LAWS.bend     the invariants
PROOF.bend    proofs demanded by the laws
docs/         the spec text, spec notes, corpus notes
corpus/       cached test corpora (git-ignored except manifests)
tools/        harness scripts (corpus fetch, differential runs)
```

## Roadmap

1. Week 1 — spike: lexer + scalar objects, roundtrip law green, measure
   MB/s. Kill criterion: unusable throughput or checker fights → keep laws,
   port engine to Rust, reuse spec work.
2. Weeks 2–3 — clause 7.5: xref tables, xref streams, object streams,
   incremental updates, resolution.
3. Week 4+ — validator diagnostics for 7.10 structure, page tree walk.
4. Continuous — corpus drives new laws.
