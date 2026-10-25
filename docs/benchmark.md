# Lexer spike — week 1 benchmark

Date: 2026-10-24. Toolchain: Bend 2.0.39, native build (`-o`), single-core.

## Method

`runner.bend` reads argv[1] whole, lexes it with `lex.bend` (clause 7.2/7.3
automaton), and reports `OK <tokens> <bytes>` or `ERR <why> <bytes>`. Wall
time around the process invocation; file size from the reported byte count.

```sh
bend runner.bend -o runner_bin
./runner_bin file.pdf
```

## Results

| Input | Bytes | Tokens | Wall | Throughput |
|---|---|---|---|---|
| synth: `1 22 333 0 47 -4 0.5 12.34 ` ×160k | 4,320,000 | 1,280,000 | 0.177 s | **24 MB/s** |
| synth: dict/name/string/hex/comment mix ×70k | 9,240,000 | 1,120,000 | 0.354 s | **26 MB/s** |
| corpus 328 KB | 328,400 | — | 0.013 s | (early LexErr) |

The mix stress-cases every automaton state: `<<` dicts, names, strings with
`\(`, `\\`, `\110` octal, `\<41424344>` escapes, balanced parens, hex strings,
keywords, comments with CRLF, reals, arrays. All exercised in one pass at 26
MB/s.

## Verdict on the week-1 kill criterion

The criterion was: kill Bend and port the engine to Rust if throughput is
unusable or the checker fights the design. Verdict:

- Throughput 24–26 MB/s stands well above every PDF parsing bottleneck
  downstream of the lexer; usable.
- The checker never forced a redesign. Empirical rules that shaped the file
  (all confirmed by checker probes, recorded in `AGENTS.md` style notes):
  defs bind in order (no forward refs, no mutual recursion → one
  self-recursive `toks` fed by non-recursive `tr_*` transitions);
  computed Bool scrutinees are illegal → every predicate passes through a
  helper's parameter (`hexval`, the `z*` flag convention); match binders
  must ascend in parameter order; reuse needs quantity marks — `+b` on
  parameters and `+b`/`+depth` inside patterns; `List<&2, Tok>` for
  copyable accumulating fields; `Nat` fuel on `toks` for termination
  (`2n+8` per byte budget, exhaustion = diagnostic).

## Interpreter vs native

The bend interpreter rejects deep lists: a 328 KB file overflows its fixed
machine stack (`bend: memory fault (machine stack stack overflow?)`) even at
`ulimit -s` 256 MB, while 2.4 KB files run fine. Native builds handle the
same file in 7 ms. All benchmarks use native builds; the corpus sweep script
does too.

## Known limitation (accepted for week 1)

The runner lexes the whole file, so compressed/binary stream bodies (content
streams, font/image streams) produce verdicts like `bad file byte`, `stray
gt`, `bad lt sequence`, `bad brace in file syntax` — deterministic, and
never a crash. The parser milestone (§7.5 object regime) drives the lexer
per sourced object and keeps stream bytes opaque (§7.3.8.2), at which point
the corpus sweep becomes a verdict-agreement comparison against
`qpdf --check`.

# Parser milestone — week 2 benchmark

Date: 2026-10-25. Toolchain: Bend 2.0.39, native build (`-o`), single-core.

## Method

`runner.bend` reads argv[1] whole, lexes it (`lex.bend`, clause 7.2/7.3),
then parses the object regime (`parser.bend`, clause 7.5), reporting
`LEX: OK <tokens> <bytes> | PARSE: OK/CUT/ERR <objects> <bytes>`. Wall time
around the process invocation.

```sh
bend runner.bend -o runner_bin
./runner_bin file.pdf
```

## Results

| Corpus | Files | Lexable | Parse OK | Parse CUT | Parse ERR | Parser crashes |
|---|---|---|---|---|---|---|
| pdf.js | 1,007 | 187 | 1 | 160 | 26 | 0 |
| pdfbox | 137 | 16 | 0 | 11 | 5 | 0 |

Every parse `ERR` cites an ISO 32000-2:2020 clause (7.3.1, 7.3.6, 7.3.7,
7.3.10). Zero crashes on every lexable file in both corpora. The 3 files
that crash (`filled-background.pdf`, `issue7847_radial.pdf`,
`tiling-pattern-box.pdf`) overflow the lexer's `Nat` fuel (`2*ntok + 8`
exceeds `2^48-1`) — a pre-existing lexer limit, not a parser defect.

## Parser design (7.5 object regime)

A second automaton mirrors the lexer: one self-recursive `pval(fuel, pst)`
with an explicit frame stack (`FStart`/`FNum1`/`FNum2`/`FHead`/`FPost`/
`FArr`/`FD`/`FBAD`), a `pend` field (`PNil`/`PN1`/`PN2`) that disambiguates
`num gen R` references from bare numbers, and a `stop` slot carrying terminal
answers (`POks`/`PCut`/`PErr`). Helpers return `PST` and never call back into
`pval`, so there is no mutual recursion. Every token is consumed at most twice
(flush + re-feed), so fuel `2*ntok + 8` covers the walk and the EOF check.
Dictionary keys must be names (7.3.7); stream bodies stay opaque and end the
walk at `PCut` (7.3.8.1). All rejections cite ISO 32000-2:2020 clauses.

## Laws proved

Nine golden parser laws in `LAWS.bend` (`par_empty`, `par_num_obj`,
`par_ref_err` and six more), each with a `{==}` proof in `PROOF.bend`, passing
both `bend PROOF.bend` and `bend PROOF.bend --verdict`.

# Xref milestone — week 3 benchmark

Date: 2026-10-25. Toolchain: Bend 2.0.39, native build (`-o`), single-core.

## Method

`runner.bend` reads argv[1] whole, lexes it (`lex.bend`, clause 7.2/7.3),
parses the object regime (`parser.bend`, clause 7.5), then parses the xref
regime (`xref.bend`, clause 7.5.4), reporting
`LEX: ... | PARSE: ... | XREF: OK/CUT/ERR <entries> <startxref> <bytes>`.
Wall time around the process invocation.

```sh
bend runner.bend -o runner_bin
./runner_bin file.pdf
```

## Results

| Corpus | Files | Lexable | Parse OK | Parse CUT | Parse ERR | XRef OK | XRef ERR | Parser crashes |
|---|---|---|---|---|---|---|---|---|
| pdf.js | 1,007 | 187 | 1 | 160 | 26 | 21 | 0 | 0 |
| pdfbox | 137 | 16 | 0 | 11 | 5 | 6 | 0 | 0 |

XRef `ERR` on lexable files occurs when the parser stopped at `stream` (PCut)
before reaching the xref regime — streams are opaque in v0, so xref parsing
only succeeds on files where all objects precede any stream. All xref `ERR`
verdicts cite ISO 32000-2:2020 clause 7.5.4. Zero crashes on every lexable
file in both corpora; the 3 pre-existing lexer fuel crashes are unchanged.

## Xref design (7.5.4 file structure)

A second automaton (`xref_scan`) walks the token stream left by `pfile_full`'s
PCut at `xref`, reading `<start> <count>` then `count`×`(offset gen f/n)`
triplets, scanning for `startxref`, and reading its offset. Dictionary keys
must be names (7.3.7). The xref table maps object numbers to byte offsets for
later resolution. All rejections cite ISO 32000-2:2020 clause 7.5.4.

## Laws proved

Nine golden parser laws plus xref laws in `LAWS.bend`, each with a `{==}`
proof in `PROOF.bend`, passing both `bend PROOF.bend` and
`bend PROOF.bend --verdict`.

# Validation milestone — week 4 benchmark

Date: 2026-10-25. Toolchain: Bend 2.0.39, single-core. Two additions
land together: real trailer-dictionary parsing (§7.5.4) in `xref.bend`
and the §7.10 validator (`resolve.bend`) on top of it.

## Method

`resolve.bend` reads argv[1] and runs the whole clause-7 chain: lex
(§7.2/7.3), parse (§7.5), xref + trailer (§7.5.4), then validates the
trailer and the document page tree (§7.10, Tables 15/29/30), reporting
`VALID <n> pages` or `INVALID <cited clause>`. Golden fixtures replace a
corpus sweep here: the §7.10 chain only engages on files whose classic
xref precedes any stream, and streams stay opaque in v0, so few corpus
files reach validation. Fixture verdicts:

| Fixture | Bytes | Verdict |
|---|---|---|
| full1.pdf — catalog → /Pages → 1 kid | 291 | VALID 1 pages |
| full2.pdf — catalog → /Pages → 2 kids | 350 | VALID 2 pages |
| ref1.pdf — trailer /Root points to a missing object | 160 | INVALID object 2 0 R not found (7.3.10) |
| xref1.pdf — catalog without /Pages | 147 | INVALID catalog missing Pages (Table 29, 7.7.2) |
| mini.pdf — malformed xref subsection header | 403 | INVALID xref subsection start malformed (7.5.4) |
| tiny3.pdf — 18-byte header stub | 18 | INVALID no xref section found (7.5.4) |

Zero crashes across the fixtures and the earlier corpus sweeps;
`bend runner.bend` stays clean (`40 lines: OK … | CUT … | XOK …`).

## Design (§7.5.4 trailer + §7.10 validation)

The trailer dictionary is parsed by re-entering the existing object
regime: the token remnant past `trailer` is cut at `startxref` and fed to
`P.pval` seeded with a synthetic `0 0 obj` head frame plus a synthetic
`endobj` token, so the dict closes through the normal value path and no
new parser code is written. The validator is one fuel-driven state
machine (`trav`, 25 frame variants): the scrutinee field rides first in
each state, computed lookups (`dict_get`, `resolve_obj`, `String.eq`)
ride into the next state, and fuel is `32 * len(objs) + 24`. The walk
checks trailer Size (Table 15), resolve Root (7.3.10), catalog Type
(Table 29), Pages ref and page-tree root Type/Kids (Table 30), then
counts `/Page` kids. Every rejection cites its clause and table.

One mechanism discovery shaped the golden laws: the lexer treats `/` as
the name-start marker and stores names without it (§7.3.5), so parser
keys are `Size`, not `/Size` — dictionary lookups in the validator and
the laws both match bare text.

## Laws proved

Four golden §7.10 laws in `LAWS.bend` — `res_dict_root` (7.3.7 lookup),
`res_obj_miss` (7.3.10 citation), `val_one_page` (full Table 29/30 walk
counts 1 page), `val_trailer_no_root` (Table 15, 7.5.5 citation) — 15
laws total, each with a `{==}` proof in `PROOF.bend`, passing both
`bend PROOF.bend` and `bend PROOF.bend --verdict`.

## Week 5 — cross-reference streams (§7.5.8)

The parse regime now stops on `startxref` and hands the token remnant to a
new dispatch: keyword `xref` opens the classic table (7.5.4), keyword
`startxref` opens the cross-reference-stream regime (7.5.8.1). The lexer
contributes a body-skip state: after `stream` plus its end-of-line marker
(7.3.8.1) the DFA consumes data opaquely until the `endstream` sequence,
emitting a `TStreamBody` token — a mis-skipped byte is recovered inside the
body scan, and `endstream` needs no interpreter stack.

The stream regime is three passes over the parsed object table, each one
self-recursive walker with a Nat fuel (64 * objects + 256):

1. audit — every stream object's data is checked against its `Length`
   entry: equal, or longer by at most two end-of-line bytes (7.3.8.2 and
   its note; v0 counts the extras without verifying their shape). An
   indirect `Length` stays unresolved in v0, so its check is skipped.
2. find — exactly one stream object may carry `/Type /XRef` (Table 17);
   zero streams reports 7.5.4, streams with a wrong Type report
   Table 17/7.5.8.2, two or more XRef streams report the incremental
   chain as unsupported v0 (Table 17 Prev, 7.5.6).
3. decode — the dictionary entries collect in table order: `Filter`
   present means the v0 limitation diagnostic (Table 5 Filter, 7.4);
   `W` must be three non-negative integers with a non-zero second
   element (Table 17, 7.5.8.3) capped at 4 bytes per field; `Size`
   must be a direct non-negative integer (Table 17, 7.5.8.2); `Index`
   defaults to `[0 Size]` and its pairs must be sorted ascending
   without overlap. Rows are decoded big-endian per the `W` widths:
   type 0 rows are free, type 1 rows carry an offset and generation,
   type 2 rows report the compressed-entry v0 limit (7.5.7), any other
   type references the null object and keeps its position as a free
   placeholder (Table 18, 7.5.8.3). The stream dictionary doubles as
   the trailer (7.5.8.1).

## Results

Classic fixtures unchanged: mini XOK 5 entries objs=4, full1 XOK 4/3,
full2 XOK 5/4, ref1 XOK 2/1, xref1 XOK 2/1, tiny3 the same 7.5.4 error.
New cross-reference-stream fixtures, all raw (unfiltered) with `W [1 4 2]`:
full1x (Index [0 4] and X [0 5], explicit or defaulted) decode XOK with
the same entry counts as their classic twins. One battery of negatives
cites exactly one clause each: Filter (Table 5 Filter, 7.4), data longer
than Length by more than two bytes (7.3.8.2), `W[1] = 0` (Table 17,
7.5.8.3), unsorted overlapping subsections (Table 17, 7.5.8.2), a type-2
row (7.5.7), two XRef streams (Table 17 Prev, 7.5.6).

## Bend 2 mechanics that shaped the code

The checker's definition order is bottom-up: no definition may reference
a later one, so every wrapper (audit, xfind, xs_w, xs_ix, xr) is written
after its recursion walker and the file's tail segments are ordered
callee-first. Inline `match` on a computed value is illegal — every
comparison result rides as a parameter into the next state (the
`RXo`/`RXt` pattern). Match scrutinees must follow ascending binder
order, so the row state carries the row-count field before the pair
list. A binder used more than once is marked with `+` at its binding
site, and match scrutinees that are re-read in an arm need the mark too.
One affine subtlety worth recording: a def parameter consumed by two
sibling arms must be marked at the definition site, while the same reuse
across separate top-level arms stays plain.
