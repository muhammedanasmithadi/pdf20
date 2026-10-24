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
| 7.3 | Data types: booleans, numbers (real precision), strings (Tables 3), names, arrays, dictionaries, streams (Table 5), null | node types + parser |
| 7.4 | Filters | streams stay opaque; only /Length checked |
| 7.5 | File structure: header, indirect objects, xref tables (Table 15 trailer, Table 17–18 xref streams, Table 19 hybrid reference), object streams, incremental updates | resolver + merge |
| 7.6 | Encryption | enforced rejection, cited |
| 7.10 | File trailer, catalog (Table 29), page tree (Tables 30–31), resources (Table 34) | validation pass |
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
