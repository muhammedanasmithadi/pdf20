# parser.bend — the 7.5 object-regime automaton over the lexer's tokens.
# Same shape as the lexer: one self-recursive pval(fuel, pst); transitions
# are non-recursive defs answering the next PST, so helpers never call back
# into pval and there is no mutual recursion. The walker keeps:
#   stk  — frame stack, top frame awaits the next event (FStart always bottom)
#   pend — numbers pending that may close as `num gen R` (7.3.10)
#   acc  — finished indirect objects, accumulated reversed
#   stop — a terminal answer (PCut/PErr) already computed; pval returns it
# Value events are filed through pdisp, which answers FBAD{why} on the stack
# for bad contexts; the next event diagnoses an FBAD top. EOF, stream, and
# xregime-boundary words turn into stop answers directly.
#
# v0.1 deferral (decided): header-number integrality/negativity validation
# is kept out — u32of keeps a header number's whole part, so a negative or
# fractional header number parses with loss; the validation pass (7.3.10:
# positive object numbers, non-negative generations) closes that gap later.

import Base
import ./lex.bend as Lx

# ---- object model (7.3.1: nine basic types + indirect references)

type Obj is Data:
  ONil{}
  OBool{b: Bool}
  ONum{neg: Bool, whole: U32, fnum: Nat, fden: Nat}
  OName{val: String}
  OStr{val: String}
  OArr{els: List<&2, Obj>}
  ODict{els: List<&2, PEntry>}
  OInd{num: U32, gen: U32}
  OStream{d: Obj, dat: String}

# dictionary entry (7.3.7): key shall be a name; null-valued entries are
# kept here and dropped by the validation pass.
type PEntry is Data:
  PE{k: String, v: Obj}

# one parsed indirect object (7.3.10)
type BO is Data:
  BO{num: U32, gen: U32, o: Obj}

# pending numbers that may close as an indirect reference (7.3.10)
type Pend is Data:
  PNil{}
  PN1{a: Obj}
  PN2{a: Obj, b: Obj}

# stack frames. FStart = top level between objects; FNum1/FNum2 = header
# phases `num gen obj`; FHead = an object value is expected; FPost = value
# done, endobj/stream expected; FArr/FD = collectors (FD.k = pending key);
# FBAD carries a quoted diagnostic to the next event.
type Fr is Data:
  FStart{}
  FNum1{a: Obj}
  FNum2{a: Obj, b: Obj}
  FHead{num: Obj, gen: Obj}
  FPost{num: Obj, gen: Obj, v: Obj}
  FArr{rev: List<&2, Obj>}
  FD{rev: List<&2, PEntry>, k: Maybe<&2, String>}
  FStream{num: Obj, gen: Obj, d: Obj}
  FStreamX{num: Obj, gen: Obj, d: Obj, dat: String}
  FBAD{why: String}

# walker state
type PST is Data:
  PST{stop: Maybe<&2, PRes>, toks: List<&2, Lx.Tok>, stk: List<&2, Fr>, pend: Pend, acc: List<&2, BO>}

# walker answer: POks = walker returned cleanly to top level; PCut = stopped
# at a regime boundary word (stream stays opaque; xref/trailer/startxref are
# the next milestone's regime); PErr = nonconformity, why cites the clause.
type PRes is Data:
  POks{objs: List<&2, BO>}
  PCut{objs: List<&2, BO>, kw: String}
  PErr{why: String}

# ---- first aid: header numbers become U32. v0.1 deferral keeps the whole
# part only (see file header note); the defensive O-case answer is 0.

def u32of(o: Obj) -> U32:
  match o:
    case ONil{}:
      0
    case OBool{x}:
      0
    case ONum{neg, whole, fnum, fden}:
      whole
    case OName{x}:
      0
    case OStr{x}:
      0
    case OArr{x}:
      0
    case ODict{x}:
      0
    case OInd{num, gen}:
      num
    case OStream{d, dat}:
      0

# ---- per-frame diagnostics: what the frame was still expecting

def pdefltfd(k: Maybe<&2, String>) -> String:
  match k:
    case None{}:
      "dictionary key shall be a name (7.3.7)"
    case Some{k}:
      "object value expected (7.3.1)"

def pdeflt(f: Fr) -> String:
  match f:
    case FStart{}:
      "indirect object definition expected (7.3.10)"
    case FNum1{x}:
      "generation number expected (7.3.10)"
    case FNum2{x, y}:
      "obj keyword expected after the header numbers (7.3.10)"
    case FHead{x, y}:
      "object value expected (7.3.1)"
    case FArr{els}:
      "array element expected (7.3.6)"
    case FD{els, k}:
      pdefltfd(k)
    case FPost{x, y, z}:
      "endobj (or stream) expected after the value (7.3.10)"
    case FStream{num, gen, d}:
      "stream body expected (7.3.8.1)"
    case FStreamX{num, gen, d, dat}:
      "endstream expected after the stream body (7.3.8.1)"
    case FBAD{why}:
      why

# ---- value filing: a completed value goes to the frame that was
# expecting it. FBAD{why} on the stack is the diagnostic vehicle; the next
# event diagnoses it (no transition ever returns PRes directly).

def pdispfd(v: Obj, f: Fr, t: List<&2, Fr>) -> List<&2, Fr>:
  match f:
    case FD{els, k}:
      match k:
        case Some{k}:
          Con{FD{Con{PE{k, v}, els}, None{}}, t}
        case None{}:
          Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}
    case x:
      Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}

def pdisp2(v: Obj, f: Fr, t: List<&2, Fr>) -> List<&2, Fr>:
  match f:
    case FArr{els}:
      Con{FArr{Con{v, els}}, t}
    case FHead{num, gen}:
      Con{FPost{num, gen, v}, t}
    case FD{els, k}:
      pdispfd(v, f, t)
    case FStart{}:
      Con{FBAD{"indirect object definition expected (7.3.10)"}, t}
    case FNum1{x}:
      Con{FBAD{"generation number expected (7.3.10)"}, t}
    case FNum2{x, y}:
      Con{FBAD{"obj keyword expected after the header numbers (7.3.10)"}, t}
    case FPost{x, y, z}:
      Con{FBAD{"stream body expected (7.3.8.1)"}, t}
    case FStream{num, gen, d}:
      Con{FBAD{"stream body expected (7.3.8.1)"}, t}
    case FStreamX{num, gen, d, dat}:
      Con{FBAD{"endstream expected after the stream body (7.3.8.1)"}, t}
    case FBAD{why}:
      Con{FBAD{why}, t}

def pdisp(v: Obj, stk: List<&2, Fr>) -> List<&2, Fr>:
  match stk:
    case Nil{}:
      Con{FBAD{"object value expected (7.3.10)"}, Nil{}}
    case Con{f, t}:
      pdisp2(v, f, t)

# ---- end-of-file diagnosis: the per-frame message answers why the walk
# did not return to top level. Match pend, then stk, then f (signature order).

def pfrmsfd(k: Maybe<&2, String>) -> String:
  match k:
    case None{}:
      "dictionary not closed at end of file (7.3.7)"
    case Some{k}:
      "dictionary entry without a value at end of file (7.3.7)"

def pfrmsg(f: Fr) -> String:
  match f:
    case FStart{}:
      "object content left after the last object at end of file (7.3.10)"
    case FNum1{x}:
      "indirect object header without the generation number (7.3.10)"
    case FNum2{x, y}:
      "indirect object header without the obj keyword (7.3.10)"
    case FHead{x, y}:
      "no object value at end of file (7.3.10)"
    case FArr{els}:
      "array not closed at end of file (7.3.6)"
    case FD{els, k}:
      pfrmsfd(k)
    case FPost{x, y, z}:
      "endobj missing at end of file (7.3.10)"
    case FStream{num, gen, d}:
      "stream body missing at end of file (7.3.8.1)"
    case FStreamX{num, gen, d, dat}:
      "endstream missing at end of file (7.3.8.1)"
    case FBAD{why}:
      why

def peof(pend: Pend, stk: List<&2, Fr>, acc: List<&2, BO>) -> PRes:
  match pend:
    case PN1{a}:
      PErr{"incomplete indirect reference at end of file (7.3.10)"}
    case PN2{a, b}:
      PErr{"incomplete indirect reference at end of file (7.3.10)"}
    case PNil{}:
      match stk:
        case Nil{}:
          POks{List.reverse(&2, BO, acc)}
        case Con{f, t}:
          match f:
            case FStart{}:
              match t:
                case Nil{}:
                  POks{List.reverse(&2, BO, acc)}
                case Con{f2, t2}:
                  PErr{pfrmsg(f2)}
            case FBAD{why}:
              PErr{why}
            case x:
              PErr{pfrmsg(f)}

# ---- numbers. A number never re-feeds: its event consumes the token.
# PNil: the number opens a chain (or starts an object header frame).
# PN1: chain grows to the pair.
# PN2 plus a third number: the pair cannot form a reference, so the first
# number files as a value and the chain re-composes with the second (7.3.10:
# a reference is `num gen R`, so only the two numbers nearest R can be it).

def pnumfd(num: Obj, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match f:
    case FD{els, k}:
      match k:
        case Some{k}:
          # after a key the number opens its value; the chain may close as a ref
          PST{None{}, tt, Con{FD{els, Some{k}}, t}, PN1{num}, acc}
        case None{}:
          PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
    case x:
      PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}

def pnum1(num: Obj, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match f:
    case FStart{}:
      # first header number opens the pending chain (7.3.10); stk unchanged
      PST{None{}, tt, Con{f, t}, PN1{num}, acc}
    case FNum1{+a}:
      # second header number completes the pending chain (7.3.10)
      PST{None{}, tt, Con{f, t}, PN2{a, num}, acc}
    case FNum2{x, y}:
      PST{None{}, tt, Con{FBAD{"obj keyword expected after the header numbers (7.3.10)"}, t}, PNil{}, acc}
    case FArr{els}:
      PST{None{}, tt, Con{f, t}, PN1{num}, acc}
    case FHead{x, y}:
      PST{None{}, tt, Con{f, t}, PN1{num}, acc}
    case FD{els, k}:
      pnumfd(num, f, t, tt, acc)
    case FPost{x, y, z}:
      PST{None{}, tt, Con{FBAD{"stream body expected (7.3.8.1)"}, t}, PNil{}, acc}
    case FStream{num, gen, d}:
      PST{None{}, tt, Con{FBAD{"stream body expected (7.3.8.1)"}, t}, PNil{}, acc}
    case FStreamX{num, gen, d, dat}:
      PST{None{}, tt, Con{FBAD{"endstream expected after the stream body (7.3.8.1)"}, t}, PNil{}, acc}
    case FBAD{why}:
      PST{None{}, tt, Con{FBAD{why}, t}, PNil{}, acc}

def pnum0(num: Obj, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match stk:
    case Nil{}:
      PST{None{}, tt, Con{FBAD{"object value expected (7.3.10)"}, Nil{}}, PNil{}, acc}
    case Con{f, t}:
      pnum1(num, f, t, tt, acc)

def pnum(neg: Bool, whole: U32, fnum: Nat, fden: Nat, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match pend:
    case PN1{a}:
      PST{None{}, tt, stk, PN2{a, ONum{neg, whole, fnum, fden}}, acc}
    case PN2{a, b}:
      PST{None{}, tt, pdisp(a, stk), PN2{b, ONum{neg, whole, fnum, fden}}, acc}
    case PNil{}:
      pnum0(ONum{neg, whole, fnum, fden}, stk, tt, acc)

# ---- names, strings. Both are values; a name additionally opens a
# dictionary key (7.3.7). Pend release: non-number tokens flush the chain by
# filing the pending value(s) and re-feeding the token (consumed ≤ twice).

def pname1(val: String, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match f:
    case FD{els, None{}}:
      # the name opens the key slot (7.3.7: the key shall be a name)
      PST{None{}, tt, Con{FD{els, Some{val}}, t}, PNil{}, acc}
    case x:
      PST{None{}, tt, pdisp2(OName{val}, f, t), PNil{}, acc}

def pname0(val: String, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match stk:
    case Nil{}:
      PST{None{}, tt, Con{FBAD{"object value expected (7.3.10)"}, Nil{}}, PNil{}, acc}
    case Con{f, t}:
      pname1(val, f, t, tt, acc)

def pname(val: String, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match pend:
    case PN1{a}:
      PST{None{}, tt, pdisp(a, stk), PNil{}, acc}
    case PN2{a, b}:
      PST{None{}, tt, pdisp(a, stk), PN1{b}, acc}
    case PNil{}:
      pname0(val, stk, tt, acc)

# literal and hexadecimal strings share one container: OStr keeps the byte
# sequence, the encoding distinction returns with the writer milestone.
def pstr(val: String, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match pend:
    case PN1{a}:
      PST{None{}, tt, pdisp(a, stk), PNil{}, acc}
    case PN2{a, b}:
      PST{None{}, tt, pdisp(a, stk), PN1{b}, acc}
    case PNil{}:
      PST{None{}, tt, pdisp(OStr{val}, stk), PNil{}, acc}

# ---- arrays (7.3.6). Elements are any of the nine types, zero allowed.

def pargfd(open: Bool, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match open:
    case True{}:
      match f:
        case FD{els, k}:
          match k:
            case Some{k}:
              PST{None{}, tt, Con{FArr{Nil{}}, Con{f, t}}, PNil{}, acc}
            case None{}:
              PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
    case False{}:
      match f:
        case FD{els, k}:
          match k:
            case Some{k}:
              PST{None{}, tt, Con{FBAD{"right bracket without an open array (7.3.6)"}, t}, PNil{}, acc}
            case None{}:
              PST{None{}, tt, pdisp(ODict{List.reverse(&2, PEntry, els)}, t), PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}

def pargf(open: Bool, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match open:
    case True{}:
      match f:
        case FArr{els}:
          PST{None{}, tt, Con{FArr{Nil{}}, Con{f, t}}, PNil{}, acc}
        case FD{els, k}:
          pargfd(True{}, f, t, tt, acc)
        case FHead{x, y}:
          PST{None{}, tt, Con{FArr{Nil{}}, Con{f, t}}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{pdeflt(f)}, t}, PNil{}, acc}
    case False{}:
      match f:
        case FArr{els}:
          PST{None{}, tt, pdisp(OArr{List.reverse(&2, Obj, els)}, t), PNil{}, acc}
        case FD{els, k}:
          pargfd(False{}, f, t, tt, acc)
        case FHead{x, y}:
          PST{None{}, tt, Con{FBAD{"right bracket without an open array (7.3.6)"}, t}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"right bracket without an open array (7.3.6)"}, t}, PNil{}, acc}

def parg(open: Bool, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match pend:
    case PN1{a}:
      PST{None{}, tt, pdisp(a, stk), PNil{}, acc}
    case PN2{a, b}:
      PST{None{}, tt, pdisp(a, stk), PN1{b}, acc}
    case PNil{}:
      match stk:
        case Nil{}:
          PST{None{}, tt, Con{FBAD{"object value expected (7.3.10)"}, Nil{}}, PNil{}, acc}
        case Con{f, t}:
          pargf(open, f, t, tt, acc)

# ---- dictionaries (7.3.7). `<<` opens, `>>` closes; keys are names; an
# entry keeps key and value as one pair; closing with a key and no value
# is the mismatched-entry answer.

def pdictfd(open: Bool, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match open:
    case True{}:
      match f:
        case FD{els, k}:
          match k:
            case Some{k}:
              PST{None{}, tt, Con{FD{Nil{}, None{}}, Con{f, t}}, PNil{}, acc}
            case None{}:
              PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
    case False{}:
      match f:
        case FD{els, k}:
          match k:
            case Some{k}:
              PST{None{}, tt, Con{FBAD{"dictionary key without a value (7.3.7)"}, t}, PNil{}, acc}
            case None{}:
              PST{None{}, tt, pdisp(ODict{List.reverse(&2, PEntry, els)}, t), PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}

def pdictf(open: Bool, f: Fr, t: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match open:
    case True{}:
      match f:
        case FD{els, k}:
          pdictfd(True{}, f, t, tt, acc)
        case FHead{x, y}:
          PST{None{}, tt, Con{FD{Nil{}, None{}}, Con{f, t}}, PNil{}, acc}
        case FArr{els}:
          PST{None{}, tt, Con{FD{Nil{}, None{}}, Con{f, t}}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{pdeflt(f)}, t}, PNil{}, acc}
    case False{}:
      match f:
        case FD{els, k}:
          pdictfd(False{}, f, t, tt, acc)
        case FHead{x, y}:
          PST{None{}, tt, Con{FBAD{"close without an open dictionary (7.3.7)"}, t}, PNil{}, acc}
        case FArr{els}:
          PST{None{}, tt, Con{FBAD{"close without an open dictionary (7.3.7)"}, t}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"close without an open dictionary (7.3.7)"}, t}, PNil{}, acc}

def pdict(open: Bool, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match pend:
    case PN1{a}:
      PST{None{}, tt, pdisp(a, stk), PNil{}, acc}
    case PN2{a, b}:
      PST{None{}, tt, pdisp(a, stk), PN1{b}, acc}
    case PNil{}:
      match stk:
        case Nil{}:
          PST{None{}, tt, Con{FBAD{"object value expected (7.3.10)"}, Nil{}}, PNil{}, acc}
        case Con{f, t}:
          pdictf(open, f, t, tt, acc)

# ---- value keywords (7.3.2, 7.3.9): a bare word at a value position is
# an object only as the keyword true, false, or null (booleans, then the
# null object); the syntax is case-sensitive (7.2.3), so True is not a
# keyword. Meaningful word content elsewhere (obj, endobj, stream, ...)
# is handled by the keyword flags; the residue has no object reading.

type PWO is Data:
  PWo{v: Obj}
  PWe{why: String}

# the two step helpers keep every match on a passed Bool (no computed
# match scrutinees); the residue diagnostic cites the keyword clauses.

def pkv_null(is_n: Bool) -> PWO:
  match is_n:
    case True{}:
      PWo{ONil{}}
    case False{}:
      PWe{"a bare word shall be one of the keywords true, false, and null (7.3.2, 7.3.9)"}

def pkv_false(w: String, is_f: Bool) -> PWO:
  match is_f:
    case True{}:
      PWo{OBool{False{}}}
    case False{}:
      pkv_null(String.eq(w, "null"))

def pword_kv(+w: String, is_t: Bool) -> PWO:
  match is_t:
    case True{}:
      PWo{OBool{True{}}}
    case False{}:
      pkv_false(w, String.eq(w, "false"))

# the word value files like any other value: pdisp covers the value
# expecting frames (FHead, array, dictionary value), PWe diagnoses

def pwo_fil(wv: PWO, f: Fr, t: List<&2, Fr>, toks: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match wv:
    case PWo{v}:
      PST{None{}, toks, pdisp(v, Con{f, t}), PNil{}, acc}
    case PWe{why}:
      PST{None{}, toks, Con{FBAD{why}, t}, PNil{}, acc}

# ---- words and regime boundaries (7.3.10, 7.3.8.1). Keyword flags are
# computed here and passed to pword1 as Bools alongside the word's PWO
# classification (no zero-param defs).

def pword1(+w: String, wv: PWO, f: Fr, t: List<&2, Fr>, wsendobj: Bool, wstream: Bool, wendstream: Bool, wxref: Bool, wtrailer: Bool, wstartxref: Bool, wxreg: Bool, toks: List<&2, Lx.Tok>, pend: Pend, acc: List<&2, BO>) -> PST:
  match f:
    case FStream{num, gen, d}:
      # only the body event may follow `stream` (7.3.8.1); words are errors
      PST{None{}, toks, Con{FBAD{"stream body expected (7.3.8.1)"}, t}, PNil{}, acc}
    case FStreamX{num, gen, d, dat}:
      match wendstream:
        case True{}:
          # body done: the stream value files, endobj closes the object
          PST{None{}, toks, Con{FPost{num, gen, OStream{d, dat}}, t}, PNil{}, acc}
        case False{}:
          PST{None{}, toks, Con{FBAD{"endstream expected after the stream body (7.3.8.1)"}, t}, PNil{}, acc}
    case FNum2{x, y}:
      # a word after the header numbers closes the header only as `obj`
      # (handled by pword_r); any other word diagnoses here (7.3.10)
      PST{None{}, toks, Con{FBAD{"obj keyword expected after the header numbers (7.3.10)"}, t}, PNil{}, acc}
    case FPost{num, gen, v}:
      match wsendobj:
        case True{}:
          # object definition complete; file BO, close the header frame (7.3.10)
          PST{None{}, toks, t, PNil{}, Con{BO{u32of(num), u32of(gen), v}, acc}}
        case False{}:
          match wstream:
            case True{}:
              # `stream` after the value: the value is the stream dictionary;
              # the body follows, endstream completes it (7.3.8.1)
              PST{None{}, toks, Con{FStream{num, gen, v}, t}, PNil{}, acc}
            case False{}:
              match wendstream:
                case True{}:
                  PST{None{}, toks, Con{FBAD{"endstream keyword without an open stream (7.3.8.1)"}, t}, PNil{}, acc}
                case False{}:
                  PST{None{}, toks, Con{FBAD{"endobj (or stream) expected after the value (7.3.10)"}, t}, PNil{}, acc}
            case False{}:
              PST{None{}, toks, Con{FBAD{"endobj (or stream) expected after the value (7.3.10)"}, t}, PNil{}, acc}
    case FHead{x, y}:
      # true/false/null file the object value; other words diagnose
      pwo_fil(wv, f, t, toks, acc)
    case FD{els, k}:
      match k:
        case Some{k}:
          # the entry value takes the same word rule (7.3.2, 7.3.9)
          pwo_fil(wv, f, t, toks, acc)
        case None{}:
          # the key slot expects a name; a bare word is not a name (7.3.7)
          PST{None{}, toks, Con{FBAD{"dictionary key shall be a name (7.3.7)"}, t}, PNil{}, acc}
    case FArr{els}:
      # array elements take the same word rule (7.3.2, 7.3.9)
      pwo_fil(wv, f, t, toks, acc)
    case FStart{}:
      match wxreg:
        case True{}:
          # `xref`/`trailer`/`startxref` between objects: PCut — xref
          # regime takes over, carrying the trigger keyword (7.5.8.1)
          PST{Some{PCut{List.reverse(&2, BO, acc), w}}, toks, Con{f, t}, PNil{}, Nil{}}
        case False{}:
          PST{None{}, toks, Con{FBAD{"indirect object definition expected (7.3.10)"}, t}, PNil{}, acc}
    case FNum1{x}:
      PST{None{}, toks, Con{FBAD{"generation number expected (7.3.10)"}, t}, PNil{}, acc}
    case FBAD{why}:
      PST{None{}, toks, Con{FBAD{why}, t}, PNil{}, acc}

# pword_r: `is_obj` says whether w is `obj` (closes `num gen obj` header),
# `is_r` says whether w is `R` (closes `num gen R` reference). Match flags
# first (signature order), then pend — R closes `num gen R` as one indirect
# reference (7.3.10); `obj` closes `num gen obj` as a header; anything else
# flushes the pending number chain.
def pword_r(is_obj: Bool, is_r: Bool, +w: String, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match is_obj:
    case True{}:
      # w is `obj`: closes `num gen obj` header (7.3.10)
      match pend:
        case PNil{}:
          PST{Some{PErr{"obj without header numbers (7.3.10)"}}, tt, stk, PNil{}, acc}
        case PN1{a}:
          PST{Some{PErr{"generation number expected (7.3.10)"}}, tt, stk, PNil{}, acc}
        case PN2{a, b}:
          PST{None{}, tt, Con{FHead{a, b}, stk}, PNil{}, acc}
    case False{}:
      match is_r:
        case True{}:
          # w is `R`: closes `num gen R` reference (7.3.10)
          match pend:
            case PNil{}:
              PST{Some{PErr{"R without object number and generation (7.3.10)"}}, tt, stk, PNil{}, acc}
            case PN1{a}:
              PST{Some{PErr{"incomplete reference: R without generation number (7.3.10)"}}, tt, stk, PNil{}, acc}
            case PN2{a, b}:
              match stk:
                case Nil{}:
                  PST{Some{PErr{"R without object number and generation (7.3.10)"}}, tt, stk, PNil{}, acc}
                case Con{f, t}:
                  match f:
                    case FStart{}:
                      # bare reference at top level: accepted, not a definition
                      PST{None{}, tt, stk, PNil{}, acc}
                    case x:
                      PST{None{}, tt, pdisp(OInd{u32of(a), u32of(b)}, stk), PNil{}, acc}
        case False{}:
          match pend:
            case PNil{}:
              match stk:
                case Nil{}:
                  PST{None{}, tt, Con{FBAD{"object value expected (7.3.10)"}, Nil{}}, PNil{}, acc}
                case Con{f, t}:
                  pword1(w, pword_kv(w, String.eq(w, "true")), f, t, String.eq(w, "endobj"), String.eq(w, "stream"), String.eq(w, "endstream"), String.eq(w, "xref"), String.eq(w, "trailer"), String.eq(w, "startxref"), (String.eq(w, "xref") || String.eq(w, "trailer") || String.eq(w, "startxref")), tt, PNil{}, acc)
            case PN1{a}:
              # flush `a`, then re-feed `w` with a cleared chain
              PST{None{}, Con{Lx.TWord{w}, tt}, pdisp(a, stk), PNil{}, acc}
            case PN2{a, b}:
              # flush `a`, chain continues with `b`
              PST{None{}, Con{Lx.TWord{w}, tt}, pdisp(a, stk), PN1{b}, acc}

def pword(+w: String, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match w:
    case x:
      pword_r(String.eq(x, "obj"), String.eq(x, "R"), x, pend, stk, tt, acc)

# ---- stream body arrival (7.3.8.1): the only frame that may accept a body
# is FStream (pushed by the `stream` keyword); it becomes FStreamX. Any
# other context diagnoses the stray body at the next event.

def pstream_body(dat: String, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match stk:
    case Nil{}:
      PST{None{}, tt, Con{FBAD{"stream body outside a stream object (7.3.8.1)"}, Nil{}}, PNil{}, acc}
    case Con{f, t}:
      match f:
        case FStream{num, gen, d}:
          PST{None{}, tt, Con{FStreamX{num, gen, d, dat}, t}, PNil{}, acc}
        case FBAD{why}:
          PST{None{}, tt, Con{f, t}, PNil{}, acc}
        case x:
          PST{None{}, tt, Con{FBAD{"stream body outside a stream object (7.3.8.1)"}, t}, PNil{}, acc}

# ---- token-kind dispatch for one event (tk matched first)

def pstep(tk: Lx.Tok, pend: Pend, stk: List<&2, Fr>, tt: List<&2, Lx.Tok>, acc: List<&2, BO>) -> PST:
  match tk:
    case Lx.TNum{neg, whole, fnum, fden}:
      pnum(neg, whole, fnum, fden, pend, stk, tt, acc)
    case Lx.TName{val}:
      pname(val, pend, stk, tt, acc)
    case Lx.TStr{val}:
      pstr(val, pend, stk, tt, acc)
    case Lx.THex{val}:
      pstr(val, pend, stk, tt, acc)
    case Lx.TArg{open}:
      parg(open, pend, stk, tt, acc)
    case Lx.TDict{open}:
      pdict(open, pend, stk, tt, acc)
    case Lx.TWord{val}:
      pword(val, pend, stk, tt, acc)
    case Lx.TStreamBody{dat}:
      pstream_body(dat, stk, tt, acc)

# ---- the self-recursive walker. fuel = 2*ntok + 8: every token consumed
# at most twice (flush + re-feed); the last recursion is the EOF stop-check.

# peof's result is a computed value, so matching it lives in its own def
def peof_done(pe: PRes) -> PST:
  match pe:
    case POks{o}:
      PST{Some{POks{o}}, Nil{}, Nil{}, PNil{}, Nil{}}
    case PCut{o, kw}:
      PST{Some{PCut{o, kw}}, Nil{}, Nil{}, PNil{}, Nil{}}
    case PErr{why}:
      PST{Some{PErr{why}}, Nil{}, Nil{}, PNil{}, Nil{}}

# pval: fuel first (termination: p shrinks), then the walker state pst.
# pst is a parameter so its fields (stop, toks, stk, pend, acc) can be
# matched in ascending field order; the recursive call pval(p, nxt) passes
# the local binder nxt directly (a variable reference, not a computed value).
def pval(fuel: Nat, pst: PST) -> PST:
  match fuel:
    case 0n:
      PST{Some{PErr{"out of parser fuel"}}, Nil{}, Nil{}, PNil{}, Nil{}}
    case 1n+p:
      match pst:
        case PST{stop, toks, stk, pend, acc}:
          match stop:
            case Some{s}:
              pst
            case None{}:
              match toks:
                case Nil{}:
                  peof_done(peof(pend, stk, acc))
                case Con{tk, tt}:
                  match tk:
                    case Lx.TNum{neg, whole, fnum, fden}:
                      # a number: pnum's PN1/PN2 arms handle any pending chain
                      nxt : PST = pstep(tk, pend, stk, tt, acc)
                      pval(p, nxt)
                    case Lx.TName{val}:
                      match pend:
                        case PNil{}:
                          pval(p, pname(val, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, PST{None{}, Con{Lx.TName{val}, tt}, pdisp(a, stk), PNil{}, acc})
                        case PN2{a, b}:
                          pval(p, PST{None{}, Con{Lx.TName{val}, tt}, pdisp(a, stk), PN1{b}, acc})
                    case Lx.TStr{val}:
                      match pend:
                        case PNil{}:
                          pval(p, pstr(val, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, PST{None{}, Con{Lx.TStr{val}, tt}, pdisp(a, stk), PNil{}, acc})
                        case PN2{a, b}:
                          pval(p, PST{None{}, Con{Lx.TStr{val}, tt}, pdisp(a, stk), PN1{b}, acc})
                    case Lx.THex{val}:
                      match pend:
                        case PNil{}:
                          pval(p, pstr(val, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, PST{None{}, Con{Lx.THex{val}, tt}, pdisp(a, stk), PNil{}, acc})
                        case PN2{a, b}:
                          pval(p, PST{None{}, Con{Lx.THex{val}, tt}, pdisp(a, stk), PN1{b}, acc})
                    case Lx.TArg{open}:
                      match pend:
                        case PNil{}:
                          pval(p, parg(open, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, PST{None{}, Con{Lx.TArg{open}, tt}, pdisp(a, stk), PNil{}, acc})
                        case PN2{a, b}:
                          pval(p, PST{None{}, Con{Lx.TArg{open}, tt}, pdisp(a, stk), PN1{b}, acc})
                    case Lx.TDict{open}:
                      match pend:
                        case PNil{}:
                          pval(p, pdict(open, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, PST{None{}, Con{Lx.TDict{open}, tt}, pdisp(a, stk), PNil{}, acc})
                        case PN2{a, b}:
                          pval(p, PST{None{}, Con{Lx.TDict{open}, tt}, pdisp(a, stk), PN1{b}, acc})
                    case Lx.TWord{+val}:
                      match pend:
                        case PNil{}:
                          pval(p, pword_r(String.eq(val, "obj"), String.eq(val, "R"), val, PNil{}, stk, tt, acc))
                        case PN1{a}:
                          pval(p, pword_r(String.eq(val, "obj"), String.eq(val, "R"), val, PN1{a}, stk, tt, acc))
                        case PN2{a, b}:
                          pval(p, pword_r(String.eq(val, "obj"), String.eq(val, "R"), val, PN2{a, b}, stk, tt, acc))
                    case Lx.TStreamBody{+dat}:
                      # a body never rides a pending number chain (it follows
                      # `stream`, which flushes the chain); route on the stack
                      pval(p, pstream_body(dat, stk, tt, acc))

# nxt.stop is a field binder, matched in its own def (computed values can't
# be scrutinized directly)
def plx_done(nxt: PST) -> PRes:
  match nxt:
    case PST{stop, toks, stk, pend, acc}:
      match stop:
        case Some{s}:
          s
        case None{}:
          PErr{"walker ended without a stop answer (internal)"}

# plx takes the lex result as its own parameter (a computed Lex value
# cannot be matched inside pfile, so this wrapper avoids that)
def plx(lx: Lx.Lex) -> PRes:
  match lx:
    case Lx.LexErr{why}:
      PErr{why}
    case Lx.Lexed{+toks}:
      n : Nat = List.length(&2, Lx.Tok, toks)
      nxt : PST = pval((Nat.mul(n, 2n) + 8n : Nat), PST{None{}, toks, Con{FStart{}, Nil{}}, PNil{}, Nil{}})
      plx_done(nxt)

# pfile wires lex + pval (wrapper def; pval cannot take a computed Lex)
def pfile(bytes: List<&2, U32>) -> PRes:
  plx(Lx.lex(bytes))

# PlxFull: parse result + remaining tokens (for xref regime consumption)
type PlxFull is Data:
  PlxFull{pr: PRes, rem: List<&2, Lx.Tok>}

# plx_done_full: extract PRes AND remaining tokens from final PST
def plx_done_full(nxt: PST) -> PlxFull:
  match nxt:
    case PST{stop, toks, stk, pend, acc}:
      match stop:
        case Some{s}:
          PlxFull{s, toks}
        case None{}:
          PlxFull{PErr{"walker ended without a stop answer (internal)"}, toks}

# plx_full: lex + parse, returns PlxFull
def plx_full(lx: Lx.Lex) -> PlxFull:
  match lx:
    case Lx.LexErr{why}:
      PlxFull{PErr{why}, Nil{}}
    case Lx.Lexed{+toks}:
      n : Nat = List.length(&2, Lx.Tok, toks)
      nxt : PST = pval((Nat.mul(n, 2n) + 8n : Nat), PST{None{}, toks, Con{FStart{}, Nil{}}, PNil{}, Nil{}})
      plx_done_full(nxt)

# pfile_full: lex + parse, returns PlxFull (pr + rem tokens for xref regime)
def pfile_full(bytes: List<&2, U32>) -> PlxFull:
  plx_full(Lx.lex(bytes))

# ---- report + entry (runner.bend will extend this later)

def str_byts(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      Con{Char.to_u32(h), str_byts(t)}

def arg1(args: List<String>) -> String:
  match args:
    case Nil{}:
      SNil{}
    case Con{h, t}:
      match t:
        case Nil{}:
          h
        case Con{h2, t2}:
          h2

def pres_rpt(pr: PRes) -> String:
  match pr:
    case POks{o}:
      (("OK " ++ Nat.show(List.length(&2, BO, o))) ++ " objects")
    case PCut{o, kw}:
      (("CUT " ++ Nat.show(List.length(&2, BO, o))) ++ " objects")
    case PErr{why}:
      (("ERR " ++ why))

# ---- read the whole file into bytes (IO), mirroring runner.bend's stages

def read_bytes_exec(rbp: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sz: U32) -> IO(List<&2, U32>):
  (f3, rres) = rbp
  match rres:
    case Fail{(code, msg)}:
      IO.die(List<&2, U32>, code, msg)
    case Done{bytes}:
      IO.pure(List<&2, U32>, bytes)

def read_read_exec(f2: File, +sz: U32) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    rbp : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f2, sz)
    ret : List<&2, U32> <- read_bytes_exec(rbp, sz)
    return ret

def read_size_exec(sfp: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, U32>):
  (f2, sres) = sfp
  match sres:
    case Fail{(code, msg)}:
      IO.die(List<&2, U32>, code, msg)
    case Done{sz}:
      read_read_exec(f2, sz)

def read_file(path: List<&2, U32>) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f1 : File <- IO.try(File, File.open_bytes(path, "r"))
    sfp : File & Result<&1, &1, U32 & String, U32> <- File.size(f1)
    ret : List<&2, U32> <- read_size_exec(sfp)
    return ret

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    bytes : List<&2, U32> <- read_file(str_byts(arg1(args)))
    ret : PRes = pfile(bytes)
    IO.print(pres_rpt(ret))
