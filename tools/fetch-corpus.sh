#!/usr/bin/env bash
# Fetches corpus A (pdf.js test files) and C (pdfbox test resources).
# Corpus binaries never enter git; manifests land in corpus/*.manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/corpus"

echo "== corpus A: mozilla/pdf.js test/pdfs =="
if [ ! -d "$ROOT/corpus/pdfjs/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse https://github.com/mozilla/pdf.js "$ROOT/corpus/pdfjs"
  (cd "$ROOT/corpus/pdfjs" && git sparse-checkout set test/pdfs)
fi
(cd "$ROOT/corpus/pdfjs/test/pdfs" && git ls-tree -r --name-only HEAD | sort) > "$ROOT/corpus/pdfjs.manifest"
echo "$(wc -l < "$ROOT/corpus/pdfjs.manifest") files listed"

echo "== corpus C: apache/pdfbox test resources =="
if [ ! -d "$ROOT/corpus/pdfbox/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse https://github.com/apache/pdfbox "$ROOT/corpus/pdfbox"
  (cd "$ROOT/corpus/pdfbox" && git sparse-checkout set pdfbox/src/test/resources)
fi
(cd "$ROOT/corpus/pdfbox/pdfbox/src/test/resources" && find . -type f -iname '*.pdf' | sed 's|^\./||' | sort) > "$ROOT/corpus/pdfbox.manifest"
echo "$(wc -l < "$ROOT/corpus/pdfbox.manifest") files listed"

echo "== corpus B: pdfium — manual step =="
echo "Clone https://github.com/chromium/chromium (or via depot_tools gclient sync pdfium) and set corpus/pdfium/"
