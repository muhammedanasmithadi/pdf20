# PROOF.bend — the gate. AI writes proofs here; LAWS.bend is not editable.
# Run: bend PROOF.bend            (fast check)
# Run: bend PROOF.bend --verdict  (proven BendTT kernel, include in CI)

import Base
import ./LAWS.bend as Laws

def Laws.nat_add_zero(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Laws.nat_add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}
