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
import ./xref.bend as X
import ./resolve.bend as R
import ./writer.bend as W

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

# Golden laws for resolution and validation (7.10, Tables 15/29/30).
# R = resolve.bend: dict_get (7.3.7), resolve_obj (7.3.10), validate.

# /Root lookup in a trailer with /Size and /Root present
law res_dict_root:
  {R.dict_get("Root", P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}) == R.Res{P.OInd{1, 0}} : R.Resolved}

# resolution of a reference with no defining object: treated as null (7.3.9)
law res_obj_miss:
  {R.resolve_obj(Con{P.BO{1, 0, P.ONil{}}, Nil{}}, 9, 0, R.U32_eq(1, 9), False{}, P.ONil{}) == R.Res{P.ONil{}} : R.Resolved}

# a reference to an existing object resolves to that object
law res_obj_found:
  {R.resolve_obj(Con{P.BO{1, 0, P.OName{"/Root"}}, Nil{}}, 1, 0, False{}, False{}, P.ONil{}) == R.Res{P.OName{"/Root"}} : R.Resolved}

# one-level tree: /Catalog -> /Pages(Kids [3 0 R]) -> /Page counts 1
law val_one_page:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 1, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Nil{}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VOk{1} : R.ValRes}

# a trailer without Root cites Table 15/7.5.5
law val_trailer_no_root:
  {R.validate(X.FullRes{Nil{}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 2, 0n, 1n}}, Nil{}}}, 0}) == R.VErr{"trailer missing Root (Table 15, 7.5.5)"} : R.ValRes}

# page without Parent cites Table 30/7.7.3
law val_page_no_parent:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 1, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Nil{}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"page missing Parent (Table 30, 7.7.3)"} : R.ValRes}

# Golden laws for encryption (7.6). X = resolve.bend, Pdf = lex.bend.

# dict_get finds an Encrypt entry present in the trailer (7.3.7)
law dict_get_encrypt_found:
  {R.dict_get("Encrypt", P.ODict{Con{P.PE{"Encrypt", P.OInd{4, 0}}, Nil{}}}) == R.Res{P.OInd{4, 0}} : R.Resolved}

# dict_get misses an absent Encrypt key (7.3.7)
law dict_get_encrypt_missing:
  {R.dict_get("Encrypt", P.ODict{Con{P.PE{"Size", P.ONum{False{}, 2, 0n, 1n}}, Nil{}}}) == R.RErr{"key not found in dictionary (7.3.7)"} : R.Resolved}

# a trailer with an Encrypt entry is rejected (7.6: v0 does not implement decryption)
law val_encrypt_rejected:
  {R.validate(X.FullRes{Nil{}, Nil{}, P.ODict{Con{P.PE{"Encrypt", P.OInd{4, 0}}, Nil{}}}, 0}) == R.VErr{"document is encrypted (7.6); encryption not supported in v0"} : R.ValRes}

# check_header_ver helper law (7.5.2)
# Golden laws for the cross-reference stream milestone (7.5.8). X = xref.bend.

# The lexer hands the parser a TStreamBody token carrying opaque stream data
# (7.3.8.1); W [1 4 2] is the v0 acceptance case (Table 17, 7.5.8.3); one
# type-1 row decodes to an in-use XE at the field-2 offset (Table 18);
# the audit accepts data equal to Length (7.3.8.2).

law xs_lex_body:
  {Pdf.lex(Con{115, Con{116, Con{114, Con{101, Con{97, Con{109, Con{10, Con{0, Con{255, Con{101, Con{0, Con{110, Con{66, Con{10, Con{101, Con{110, Con{100, Con{115, Con{116, Con{114, Con{101, Con{97, Con{109, Con{10, Nil{}}}}}}}}}}}}}}}}}}}}}}}}}) == Pdf.Lexed{Con{Pdf.TWord{"stream"}, Con{Pdf.TStreamBody{SCon{Char.from_u32(0), SCon{Char.from_u32(255), SCon{Char.from_u32(101), SCon{Char.from_u32(0), SCon{Char.from_u32(110), SCon{Char.from_u32(66), SCon{Char.from_u32(10), SNil{}}}}}}}}}, Con{Pdf.TWord{"endstream"}, Nil{}}}}} : Pdf.Lex}

law xs_w_w142:
  {X.xs_w(P.OArr{Con{P.ONum{False{}, 1, 0n, 1n}, Con{P.ONum{False{}, 4, 0n, 1n}, Con{P.ONum{False{}, 2, 0n, 1n}, Nil{}}}}}) == X.WOK{1, 4, 2} : X.WRes}

law xs_decode_w1410:
  {X.xr(Con{0, Con{1, Nil{}}}, 0, 0, SCon{Char.from_u32(1), SCon{Char.from_u32(0), SCon{Char.from_u32(0), SCon{Char.from_u32(0), SCon{Char.from_u32(10), SCon{Char.from_u32(0), SCon{Char.from_u32(0), SNil{}}}}}}}}, 1n, 4n, 2n) == X.XROk{Con{X.XE{0, 0, True{}, 10}, Nil{}}} : X.XRRes}

law xs_audit_exact:
  {X.audit(Con{P.BO{4, 0, P.OStream{P.ODict{Con{P.PE{"Length", P.ONum{False{}, 3, 0n, 1n}}, Nil{}}}, SCon{Char.from_u32(49), SCon{Char.from_u32(50), SCon{Char.from_u32(51), SNil{}}}}}}, Nil{}}) == X.AudOk{} : X.AudRes}
# Golden laws for the object-stream milestone (7.5.7). X = xref.bend.
# String literals norm here; lex-level byte escapes are not needed for
# these laws (the acceptance data carries no escapes).

# os_take keeps the first n characters of a slice region (7.5.7: an object
# spans from its header offset to the next offset); sdrop seeks past the
# N-pairs header counted by the First entry (Table 16, 7.5.7); the fuel
# gate errs; pair offsets are byte offsets in the raw stream data and
# shall be in increasing order (7.5.7); the object stream's generation
# shall be zero (7.5.7); the v0 acceptance case header "3 8 4 23" with
# First 8 decodes the stored page dict and the number 42 (Table 16).

law os_take_two:
  {X.os_take(2n, "42!") == "42" : String}

law os_drop_header8:
  {Pdf.sdrop(8n, "3 8 4 23<</Type /Page>>42") == "<</Type /Page>>42" : String}

law osh_fuel_gate:
  {X.osh(0n, X.SBad{"x"}) == X.DErr{"out of object stream header fuel (internal)"} : X.OSDc}

law os_gen_gen_zero:
  {X.os_decode(P.BO{1, 1, P.OStream{P.ODict{Nil{}}, SNil{}}}) == X.DErr{"the generation number of an object stream shall be zero (7.5.7)"} : X.OSDc}

law osh_ord_bad:
  {X.osh(8n, X.SOrd{Nil{}, Con{9, Con{5, Nil{}}}, 9, False{}, SNil{}, Nil{}}) == X.DErr{"the offsets in an object stream shall be in increasing order (7.5.7)"} : X.OSDc}

law osh_start_two_pairs:
  {X.osh_start("3 8 4 23<</Type /Page>>42", 8, 2n) == X.DOK{Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Nil{}}}}, Con{P.BO{4, 0, P.ONum{False{}, 42, 0n, 1n}}, Nil{}}}} : X.OSDc}
# Golden laws for the keyword values (7.3.2, 7.3.9). X = xref.bend,
# R = resolve.bend. The bare words true/false/null are the only object
# values among words (7.3.2 booleans, 7.3.9 null; the syntax is
# case-sensitive, 7.2.3, so True is not a keyword); a dictionary entry
# valued null answers the required-key lookups as if omitted (7.3.9,
# Table 15). String literals norm (see the 7.5.7 section).

# Golden laws for the keyword values (7.3.2, 7.3.9). X = xref.bend,
# R = resolve.bend. The bare words true/false/null are the only object
# values among words (7.3.2 booleans, 7.3.9 null; the syntax is
# case-sensitive, 7.2.3, so True is not a keyword); a dictionary entry
# valued null answers the required-key lookups as if omitted (7.3.9,
# Table 15). String literals norm (see the 7.5.7 section).

law bool_true:
  {X.os_slice_parse("true") == X.OSV{P.BO{0, 0, P.OBool{True{}}}} : X.OSSl}

law bool_false:
  {X.os_slice_parse("false") == X.OSV{P.BO{0, 0, P.OBool{False{}}}} : X.OSSl}

law bool_case:
  {X.os_slice_parse("True") == X.OSW{"a bare word shall be one of the keywords true, false, and null (7.3.2, 7.3.9)"} : X.OSSl}

law bool_dict_true:
  {X.os_slice_parse("<</A 1 /Raw true>>") == X.OSV{P.BO{0, 0, P.ODict{Con{P.PE{"A", P.ONum{False{}, 1, 0n, 1n}}, Con{P.PE{"Raw", P.OBool{True{}}}, Nil{}}}}}} : X.OSSl}

law null_stored:
  {X.os_slice_parse("null") == X.OSV{P.BO{0, 0, P.ONil{}}} : X.OSSl}

# the null-valued /Size entry answers the required-key lookup as the
# omitted entry (7.3.9, Table 15): the walker diagnoses the missing key
law null_trailer_missing:
  {R.trav(4n, R.VSzO{P.ONil{}, Nil{}, Nil{}}) == R.VErr{"trailer missing Size (Table 15, 7.5.5)"} : R.ValRes}

# Golden laws for numeric values (7.3.3). Integers: one or more decimal digits
# optionally preceded by a sign. Reals: digits with optional sign and a leading,
# trailing, or embedded PERIOD (2Eh). fnum==0n denotes an integer (no fraction
# digits); fnum>0n denotes a real (fnum/fden). A real shall not appear where an
# integer is expected (7.3.3). Byte lists are raw UTF-8/ASCII codes.

law lex_int_neg:
  {Pdf.lex(Con{45, Con{57, Con{56, Nil{}}}}) == Pdf.Lexed{Con{Pdf.TNum{True{}, 98, 0n, 1n}, Nil{}}} : Pdf.Lex}

law lex_int_pos:
  {Pdf.lex(Con{43, Con{49, Con{55, Nil{}}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 17, 0n, 1n}, Nil{}}} : Pdf.Lex}

law lex_real_embed:
  {Pdf.lex(Con{51, Con{52, Con{46, Con{53, Nil{}}}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 34, 5n, 10n}, Nil{}}} : Pdf.Lex}

law lex_real_neg:
  {Pdf.lex(Con{45, Con{51, Con{46, Con{54, Con{50, Nil{}}}}}}) == Pdf.Lexed{Con{Pdf.TNum{True{}, 3, 62n, 100n}, Nil{}}} : Pdf.Lex}

law lex_real_lead_dot:
  {Pdf.lex(Con{45, Con{46, Con{48, Con{48, Con{50, Nil{}}}}}}) == Pdf.Lexed{Con{Pdf.TNum{True{}, 0, 2n, 1000n}, Nil{}}} : Pdf.Lex}

law lex_real_trail_dot:
  {Pdf.lex(Con{52, Con{46, Nil{}}}) == Pdf.Lexed{Con{Pdf.TNum{False{}, 4, 0n, 1n}, Nil{}}} : Pdf.Lex}

# a real-valued /Size is not an integer (7.3.3): the walker rejects it
law size_real_rejected:
  {R.trav(4n, R.VSzO{P.ONum{False{}, 5, 5n, 10n}, Nil{}, Nil{}}) == R.VErr{"trailer Size shall be an integer (7.3.3)"} : R.ValRes}

# the offset after the startxref keyword shall be an integer (7.5.4, 7.3.3)
law xref_offset_int:
  {X.xref_offset_at(Nil{}, Pdf.TNum{False{}, 5, 0n, 1n}) == X.XOK{Nil{}, P.ONil{}, 5} : X.XRes}

law xref_offset_real:
  {X.xref_offset_at(Nil{}, Pdf.TNum{False{}, 5, 5n, 10n}) == X.XErr{"startxref offset shall be an integer (7.5.4, 7.3.3)"} : X.XRes}

# xref-table entry offsets and generations are integers (7.5.4 Table 15, 7.3.3):
# a real offset or generation is rejected.
law xref_entry_offset_real:
  {X.xref_entries(1n, Con{Pdf.TNum{False{}, 5, 5n, 10n}, Nil{}}, Nil{}) == X.XEErr{"xref entry offset shall be an integer (7.5.4, 7.3.3)"} : X.XEntryRes}

law xref_entry_gen_real:
  {X.xref_entries(1n, Con{Pdf.TNum{False{}, 5, 0n, 1n}, Con{Pdf.TNum{False{}, 0, 5n, 10n}, Nil{}}}, Nil{}) == X.XEErr{"xref entry generation shall be an integer (7.5.4, 7.3.3)"} : X.XEntryRes}

law xref_entry_int_ok:
  {X.xref_entries(1n, Con{Pdf.TNum{False{}, 5, 0n, 1n}, Con{Pdf.TNum{False{}, 0, 0n, 1n}, Con{Pdf.TWord{"n"}, Nil{}}}}, Nil{}) == X.XEOk{Con{X.XE{0, 0, True{}, 5}, Nil{}}, Nil{}} : X.XEntryRes}

# Golden laws for strings (7.3.4), names (7.3.5), arrays (7.3.6).
# Byte lists are raw ASCII codes.

law par_arr:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{91, Con{49, Con{32, Con{50, Con{93, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.OArr{Con{P.ONum{False{}, 1, 0n, 1n}, Con{P.ONum{False{}, 2, 0n, 1n}, Nil{}}}}}, Nil{}}} : P.PRes}

law par_hex_str:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{60, Con{52, Con{69, Con{62, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.OStr{"N"}}, Nil{}}} : P.PRes}

law par_name_hash:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{47, Con{65, Con{35, Con{50, Con{48, Con{66, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.OName{"A B"}}, Nil{}}} : P.PRes}

law par_name_empty:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{47, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.OName{""}}, Nil{}}} : P.PRes}

law par_str:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{40, Con{97, Con{98, Con{99, Con{41, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.OStr{"abc"}}, Nil{}}} : P.PRes}


# Golden laws for indirect object header numbers (7.3.10, 7.3.3).
# Byte lists are raw ASCII codes.

law hdr_valid:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.ONum{False{}, 42, 0n, 1n}}, Nil{}}} : P.PRes}

law hdr_obj_zero:
  {P.pfile(Con{48, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law hdr_obj_neg:
  {P.pfile(Con{45, Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law hdr_obj_frac:
  {P.pfile(Con{49, Con{46, Con{53, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law hdr_gen_neg:
  {P.pfile(Con{49, Con{32, Con{45, Con{49, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}) == P.PErr{"generation number shall be a non-negative integer (7.3.10)"} : P.PRes}

law hdr_gen_frac:
  {P.pfile(Con{49, Con{32, Con{48, Con{46, Con{53, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}) == P.PErr{"generation number shall be a non-negative integer (7.3.10)"} : P.PRes}


# Golden laws for indirect object header numbers (7.3.10, 7.3.3).
# Byte lists are raw ASCII codes.

law par_hdr_valid:
  {P.pfile(Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}) == P.POks{Con{P.BO{1, 0, P.ONum{False{}, 42, 0n, 1n}}, Nil{}}} : P.PRes}

law par_hdr_obj_zero:
  {P.pfile(Con{48, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law par_hdr_obj_neg:
  {P.pfile(Con{45, Con{49, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law par_hdr_obj_frac:
  {P.pfile(Con{49, Con{46, Con{53, Con{32, Con{48, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}) == P.PErr{"object number shall be a positive integer (7.3.10)"} : P.PRes}

law par_hdr_gen_neg:
  {P.pfile(Con{49, Con{32, Con{45, Con{49, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}) == P.PErr{"generation number shall be a non-negative integer (7.3.10)"} : P.PRes}

law par_hdr_gen_frac:
  {P.pfile(Con{49, Con{32, Con{48, Con{46, Con{53, Con{32, Con{111, Con{98, Con{106, Con{32, Con{52, Con{50, Con{32, Con{101, Con{110, Con{100, Con{111, Con{98, Con{106, Nil{}}}}}}}}}}}}}}}}}}}}) == P.PErr{"generation number shall be a non-negative integer (7.3.10)"} : P.PRes}

# page tree without Count cites Table 30/7.7.3

law val_page_no_count:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Nil{}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Nil{}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"page tree root missing Count (Table 30, 7.7.3)"} : R.ValRes}

law val_page_mediabox_bad:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 1, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Con{P.PE{"MediaBox", P.ONum{False{}, 42, 0n, 1n}}, Nil{}}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"page MediaBox not an array (7.3.6, Table 30)"} : R.ValRes}

law val_page_count_mismatch:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 5, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Nil{}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"page tree Count does not match number of Kids (Table 30, 7.7.3)"} : R.ValRes}

law val_page_badres:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Nil{}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 1, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Con{P.PE{"Resources", P.ONum{False{}, 42, 0n, 1n}}, Nil{}}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"page Resources not a dictionary (Table 34, 7.7.4)"} : R.ValRes}

law val_catalog_badres:
  {R.validate(X.FullRes{Con{P.BO{1, 0, P.ODict{Con{P.PE{"Type", P.OName{"Catalog"}}, Con{P.PE{"Pages", P.OInd{2, 0}}, Con{P.PE{"Resources", P.ONum{False{}, 42, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{2, 0, P.ODict{Con{P.PE{"Type", P.OName{"Pages"}}, Con{P.PE{"Kids", P.OArr{Con{P.OInd{3, 0}, Nil{}}}}, Con{P.PE{"Count", P.ONum{False{}, 1, 0n, 1n}}, Nil{}}}}}}, Con{P.BO{3, 0, P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Con{P.PE{"Parent", P.OInd{2, 0}}, Nil{}}}}}, Nil{}}}}, Nil{}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, 4, 0n, 1n}}, Con{P.PE{"Root", P.OInd{1, 0}}, Nil{}}}}, 0}) == R.VErr{"catalog Resources not a dictionary (Table 34, 7.7.4)"} : R.ValRes}

# Writer laws (w = writer.bend). ser is fuel-bounded; these use enough fuel
# for the small inputs.

law ser_int:
  {W.ser_num(False{}, 42, 0n, 1n) == "42" : String}

law ser_neg:
  {W.ser_num(True{}, 5, 0n, 1n) == "-5" : String}

law ser_name:
  {W.ser(10n, W.SIObj{P.OName{"Page"}}) == "/Page" : String}

law ser_arr:
  {W.ser(10n, W.SIList{Con{P.ONum{False{}, 1, 0n, 1n}, Con{P.ONum{False{}, 2, 0n, 1n}, Nil{}}}}) == "1 2" : String}

law ser_dict:
  {W.ser(10n, W.SIObj{P.ODict{Con{P.PE{"Type", P.OName{"Page"}}, Nil{}}}}) == "<< /Type /Page  >>" : String}
