# LAWS.bend — the invariants pdf20 will not break.
# Human-owned file: state the law, never weaken it. Proofs live in PROOF.bend.
#
# Roadmap laws (added per milestone, each must come with its proof):
#   lexer_total      — every input byte sequence yields a verdict
#   roundtrip_bytes  — serialize(parse(b)) == b for every conformant file
#   page_tree_acyclic — page tree children navigate without cycles
#   resolution_defined — every used indirect reference resolves
#   stream_cap       — allocations above the cap are rejected, never OOM

import Base

# Offset arithmetic in clause 7.5 runs on natural numbers (xref positions,
# lengths, gaps). `x + 0 == x` is the first lemma every offset-normalization
# proof rewrites through.
law nat_add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}
