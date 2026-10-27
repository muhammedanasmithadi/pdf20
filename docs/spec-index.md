# ISO 32000-2:2020 — working index for pdf20 v0

Text: `docs/ISO_32000-2-2020_sponsored.pdf` (PDF Association sponsored copy,
Edition 2, 2020-12, with official errata folded in). Machine-readable errata
and future corrections: <https://pdf-issues.pdfa.org/32000-2-2020/> (repo:
github.com/pdf-association/pdf-issues). Any diagnostic must cite this text.
Errata page last updated 2026-03.

## Subclauses in the v0 read/validate path

| Clause | Subject | v0 deliverable |
|---|---|---|
| 7.1–7.2 | Conventions, lexical rules, whitespace, comments | lexer (comments skipped) |
| 7.3 | Data types: booleans, numbers (real precision), strings (Table 3), names, arrays, dictionaries, streams (Table 5), null | node types + parser |
| 7.3.2 | Boolean objects — keywords true and false, case-sensitive (7.2.3) | `true`/`false`/`null` parse at value positions via `pword_kv` → `PWO` (FHead, dict value, array); bare-word rejection: "a bare word shall be one of the keywords true, false, and null (7.3.2, 7.3.9)" |
| 7.3.4 | String objects — literal (Table 3 escapes) and hexadecimal; balanced parentheses, escape sequences, line continuation | lexer: TStr/TStrHex states; pstr files OStr{val}; par_str/par_hex_str laws |
| 7.3.5 | Name objects — SOLIDUS prefix, # hex escaping, case-sensitive, empty name | lexer: StName/StHash states; pname files OName{val}; par_name_hash/par_name_empty laws |
| 7.3.6 | Array objects — heterogeneous, zero elements, nested to any depth | parg/pargf/pargfd frames; pargfd diagnoses right-bracket-without-open; peof diagnoses unclosed array |
| 7.3.3 | Numeric objects — integers (optional sign) and reals (optional sign, leading/trailing/embedded PERIOD 2Eh); `fnum==0n` = integer, `fnum>0n` = real | `pnum` files `ONum{neg, whole, fnum, fden}`; lexer laws for signs/reals; **"a real shall not appear where an integer is expected (7.3.3)"** enforced at trailer Size, startxref offset, xref subsection start/count, and xref-table entry offset/generation |
| 7.3.9 | Null object — keyword null; null-valued dictionary entry answers required-key lookups as omitted | validator consumers for Size, Root, catalog Type/Pages, page tree Type/Kids, kid Type each carry an explicit `ONil` arm with the missing-key diagnostic |
| 7.3.10 | Indirect objects — object number + generation; reference to nonexistent object treated as null (7.3.9); header numbers positive/non-negative integers (7.3.3) | `resolve_obj` returns `Res{ONil{}}` for missing objects; VPnO/VKrO carry `ONil` arms; `pnum_hdr_obj` rejects object numbers ≤ 0 or non-integers; `pnum` `PN1` rejects negative/fractional generations |
| 7.3.7 | Dictionary objects — keys shall be names | dictionary KEY slot now diagnoses "dictionary key shall be a name (7.3.7)" for bare words |
| 7.4 | Filters | streams stay opaque; only /Length checked |
| 7.3.8 | Stream syntax (Table 5, Length, endstream) | lexer body-skip state; audit pass checks data against Length, ≤2 extra EOL bytes (7.3.8.2)
| 7.5.8 | Cross-reference streams (Tables 17–18) | raw unfiltered decode: W/Size/Index checks, big-endian rows, dict doubles as trailer; Filter/multi-XRef diagnostics; type-2 rows resolve into object streams (7.5.7)
| 7.5.7 | Object streams (Table 16) | Table 16 dict walk (Type ObjStm, N and First direct non-negative; Filter rejected in v0); pair-header scan inside the First budget with pair offsets relative to the raw stream data (Table 16, 7.5.7); increasing-order check; per-object slicing by take/sdrop and stored-value parse (+endobj, NOTE 7); stored stream objects and bare references rejected (7.5.7); memo table so type-2 rows index decoded streams (Table 18, 7.5.8.3)
| 7.5 | File structure: header, indirect objects, xref tables (Table 15 trailer, Table 17–18 xref streams, Table 19 hybrid reference), object streams, incremental updates | resolver + merge |
| 7.6 | Encryption — Encrypt entry in trailer (Table 15); v0 rejects encrypted documents | validate rejects /Encrypt entry: "document is encrypted (7.6); encryption not supported in v0" |
| 7.7 | Document structure: catalog (Table 29), page tree (Tables 30–31), name dictionary (Table 32), resources (Table 34) | catalog Type/Pages/Resources, page tree Type/Kids, page Type/Parent/Resources — all validated |
| 7.8 | Content streams and resources: stream syntax (7.3.8), operands/operators, resource dictionaries (Table 34) | stream Length audit (7.3.8.2); content stream parsing not yet implemented (v1) |
| 7.9 | Common data structures: rectangles, arrays, name trees, number trees | parsed as generic objects; no dedicated validation (v1) |
| 7.7 | Document structure: catalog (Table 29), page tree (Tables 30–31), name dictionary (Table 32), resources (Table 34) | catalog Type/Pages, page tree Type/Kids, page Type/Parent, catalog/page Resources — all validated |
| 7.8 | Content streams and resources: stream syntax (7.3.8), operands/operators, resource dictionaries (Table 34) | stream Length audit (7.3.8.2); content stream parsing not yet implemented (v1) |
| 7.9 | Common data structures: rectangles, arrays, name trees, number trees | parsed as generic objects; no dedicated validation (v1) |
| 7.10 | File trailer, catalog (Table 29), page tree (Tables 30–31), resources (Table 34) | validation pass; page Parent (Table 30) validated as indirect reference; Count (Table 30) validated as non-negative integer and compared against number of Kids; page MediaBox (Table 30) validated as array if present; catalog/page Resources (Table 34) validated as dictionary if present; null → missing diagnostic |
| F (Annex) | Linearized PDF (Table F.1) | read first-page chain, v1 |

The errata site lists every corrected table; the ones touching v0 are:
3, 5, 8, 15, 17, 18, 19, 21, 29, 30, 31, 32, 34, 35, 36, 37, 43, 44, 45, 47,
48, 49. Read the corrected version, never a bare-2020 copy, in these tables.

## Corpus plan (tools/fetch-corpus.sh)

| Corpus | Source | Purpose |
|---|---|---|
| A — pdf.js | github.com/mozilla/pdf.js `test/pdfs` (sparse clone) | mainstream real-world shapes |
| B — pdfium | chromium pdfium corpus test files | Chromium's pinned edge cases |
| C — pdfbox | github.com/apache/pdfbox test resources | Java-view corner cases |
| D — own | output of the human's html2pdf generator | conformant golden files |
