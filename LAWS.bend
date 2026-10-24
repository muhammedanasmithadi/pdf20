# LAWS.bend — the invariants pdf20 will not break.
# Human-owned file: state the law, never weaken it. Proofs live in PROOF.bend.
#
# Roadmap laws (added per milestone, each must come with its proof):
#   roundtrip_bytes   — serialize(parse(b)) == b for every conformant file
#   page_tree_acyclic — page tree children navigate without cycles
#   resolution_defined — every used indirect reference resolves
#   stream_cap        — allocations above the cap are rejected, never OOM

import Base
import ./lex.bend as Pdf
import ./parser.bend as P

# Offset arithmetic in clause 7.5 runs on natural numbers (xref positions,
# lengths, gaps). `x + 0 == x` is the first lemma every offset-normalization
# proof rewrites through.
law nat_add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

# Golden laws for the lexer (checker 7.2/7.3). Each {==} computes both sides;
# inputs are raw byte codes because Bend string escapes are unproven.
# bytes: 40=( 41=) 43=+ 45=- 46=. 47=/ 49='1' 50='2' 51='3' 60=< 62=>
#        65=A 71=G 83=S 92=\ 37=% 10=LF 32=SP 110='n'

law lex_empty:
  {Pdf.lex(Nil{}) == Pdf.Lexed{Nil{}} : Pdf.Lex}

law lex_int12:
  {Pdf.lex(Con{49, Con{50, Nil{}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 12, 0n, 1n}, Nil{}}} : Pdf.Lex}

law lex_ws_gap:
  {Pdf.lex(Con{49, Con{50, Con{32, Con{51, Nil{}}}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 12, 0n, 1n}, Con{Pdf.TNum{False{}, 3, 0n, 1n}, Nil{}}}} : Pdf.Lex}

law lex_comment:
  {Pdf.lex(Con{37, Con{32, Con{65, Con{10, Con{49, Nil{}}}}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 1, 0n, 1n}, Nil{}}} : Pdf.Lex}

law lex_str_esc:
  {Pdf.lex(Con{40, Con{92, Con{110, Con{41, Nil{}}}}}) == Pdf.Lexed{Con{Pdf.TStr{SCon{Char.from_u32(10), SNil{}}}, Nil{}}} : Pdf.Lex}

law lex_name_gs:
  {Pdf.lex(Con{47, Con{71, Con{83, Nil{}}}}) == Pdf.Lexed{Con{Pdf.TName{SCon{Char.from_u32(71), SCon{Char.from_u32(83), SNil{}}}}, Nil{}}} : Pdf.Lex}

law lex_dict_open:
  {Pdf.lex(Con{60, Con{60, Nil{}}}) == Pdf.Lexed{Con{Pdf.TDict{True{}}, Nil{}}} : Pdf.Lex}

# Golden laws for the parser (7.5 object regime). Inputs are raw byte codes;
# pfile = lex + pval. A POks carries finished indirect objects (7.3.10);
# a PErr cites the violated clause.

law par_empty:
  {P.pfile(Nil{}) == P.POks{Nil{}} : P.PRes}

law par_num_obj:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{49, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.ONum{False{}, 12, 0n, 1n}}, Nil{}}} : P.PRes}

law par_ref_err:
  {P.pfile(Con{53, Con{32, Con{111, Con{98, Con{106, Nil{}}}}}}) == P.PErr{"generation number expected (7.3.10)"} : P.PRes}
