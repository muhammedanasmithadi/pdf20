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
