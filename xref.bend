# xref.bend — xref table, trailer, and resolver (§7.5.4, §7.5.6, §7.5.7)
# Consumes the remaining token stream left by pfile_full's PCut at `xref`:
#   xref <start> <count> (offset gen f/n)* trailer <<dict>> startxref <offset> %%EOF

import Base
import ./lex.bend as Lx
import ./parser.bend as P

# ---- xref entry: object number, generation, in-use/free, byte offset (Table 15)

type XE is Data:
  XE{num: U32, gen: U32, in_use: Bool, offset: U32}


# ---- xref parse result

type XRes is Data:
  XOK{table: List<&2, XE>, trailer: P.Obj, startxref: U32}
  XErr{why: String}


# ---- full file result: parsed objects + xref table + trailer + startxref

type FullRes is Data:
  FullRes{objs: List<&2, P.BO>, xref: List<&2, XE>, trailer: P.Obj, startxref: U32}
  FullErr{why: String}


# ---- wrapper for (entries, remaining tokens) — avoids pair-matching computed values

type XEList is Data:
  XEList{entries: List<&2, XE>, rem: List<&2, Lx.Tok>}


# ---- xref_entry_fn: self-recursive entry parser.
# remaining = entries left to parse AFTER this one (Nat fuel, matched first).
# in_use = in_use flag for current entry (computed from f/n TWord at call site).
# whole2 = gen, whole = offset of current entry.

def xref_entry_fn(remaining: Nat, in_use: Bool, tt3: List<&2, Lx.Tok>, acc: List<&2, XE>, whole2: U32, whole: U32) -> XEList:
  match remaining:
    case 0n:
      XEList{List.reverse(&2, XE, Con{XE{0, whole2, in_use, whole}, acc}), tt3}
    case 1n+p:
      match tt3:
        case Nil{}:
          XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
        case Con{tk, tt}:
          match tk:
            case Lx.TNum{neg, whole3, fnum, fden}:
              # whole3 = next offset; expect gen TNum
              match tt:
                case Nil{}:
                  XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
                case Con{tk2, tt2}:
                  match tk2:
                    case Lx.TNum{neg2, whole4, fnum2, fden2}:
                      # whole4 = next gen; expect f/n TWord
                      match tt2:
                        case Nil{}:
                          XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
                        case Con{tk3, tt3}:
                          match tk3:
                            case Lx.TWord{val3}:
                              xref_entry_fn(p, String.eq(val3, "n"), tt3, Con{XE{0, whole2, in_use, whole}, acc}, whole4, whole3)
                            case x:
                              XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
                    case x:
                      XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
                case x:
                  XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}
            case x:
              XEList{Con{XE{0, whole2, in_use, whole}, acc}, Nil{}}


# ---- xref_entries: read `start count` header, then delegate to xref_entry_fn
# for the first triplet; xref_entry_fn is self-recursive for the rest.

def xref_entries(remaining: Nat, toks: List<&2, Lx.Tok>, acc: List<&2, XE>) -> XEList:
  match remaining:
    case 0n:
      XEList{List.reverse(&2, XE, acc), toks}
    case 1n+p:
      match toks:
        case Nil{}:
          XEList{acc, Nil{}}
        case Con{tk, tt}:
          match tk:
            case Lx.TNum{neg, whole, fnum, fden}:
              # whole is offset; expect gen TNum
              match tt:
                case Nil{}:
                  XEList{acc, Nil{}}
                case Con{tk2, tt2}:
                  match tk2:
                    case Lx.TNum{neg2, whole2, fnum2, fden2}:
                      # whole2 is gen; expect f/n TWord
                      match tt2:
                        case Nil{}:
                          XEList{acc, Nil{}}
                        case Con{tk3, tt3}:
                          match tk3:
                            case Lx.TWord{val}:
                              # remaining-1 entries after this one
                              xref_entry_fn(p, String.eq(val, "n"), tt3, acc, whole2, whole)
                            case x:
                              XEList{acc, toks}
                    case x:
                      XEList{acc, toks}
                case x:
                  XEList{acc, toks}
            case x:
              XEList{acc, toks}


# ---- xref_parse_startxref: scan remaining tokens for `startxref` keyword.
# is_sx = whether the current token is `startxref` (computed by caller).
# Self-recursive on shrinking token list.

# ---- xref_offset_at: match the TNum after startxref keyword

def xref_offset_at(entries: List<&2, XE>, head: Lx.Tok) -> XRes:
  match head:
    case Lx.TNum{neg, whole, fnum, fden}:
      XOK{entries, P.ONil{}, whole}
    case x:
      XErr{"startxref offset malformed (7.5.4)"}


# ---- xref_scan: self-recursive scanner for startxref keyword.
# is_sx first (match order), then entries, head, rest.
# Self-recursive on shrinking rest list — no mutual recursion.

def xref_scan(rest: List<&2, Lx.Tok>, is_sx: Bool, entries: List<&2, XE>, head: Lx.Tok) -> XRes:
  match rest:
    case Nil{}:
      match is_sx:
        case True{}:
          xref_offset_at(entries, head)
        case False{}:
          XErr{"startxref not found in xref section (7.5.4)"}
    case Con{next_head, next_rest}:
      match is_sx:
        case True{}:
          xref_offset_at(entries, head)
        case False{}:
          match head:
            case Lx.TWord{val}:
              xref_scan(next_rest, String.eq(val, "startxref"), entries, next_head)
            case x:
              xref_scan(next_rest, False{}, entries, next_head)


# ---- xref_parse_entries_done: match computed XEList, split rem into head/rest

def xref_parse_entries_done(xl: XEList) -> XRes:
  match xl:
    case XEList{entries, rem}:
      match rem:
        case Nil{}:
          XErr{"startxref not found in xref section (7.5.4)"}
        case Con{head, rest}:
          xref_scan(rest, False{}, entries, head)


# ---- xref_parse: parse full xref section from tokens (after `xref` consumed)
# Token sequence: TNum(start) TNum(count) entries... [trailer dict] startxref TNum(offset)

def xref_parse(toks: List<&2, Lx.Tok>) -> XRes:
  match toks:
    case Nil{}:
      XErr{"unexpected end of tokens in xref section (7.5.4)"}
    case Con{tk, tt}:
      match tk:
        case Lx.TNum{neg, whole, fnum, fden}:
          # whole is start; expect count TNum
          match tt:
            case Nil{}:
              XErr{"unexpected end of tokens in xref subsection header (7.5.4)"}
            case Con{tk2, tt2}:
              match tk2:
                case Lx.TNum{neg, whole, fnum, fden}:
                  # whole is count; parse entries
                  xref_parse_entries_done(xref_entries(U32.to_nat(whole), tt2, Nil{}))
                case x:
                  XErr{"xref subsection count malformed (7.5.4)"}
        case x:
          XErr{"xref subsection start malformed (7.5.4)"}


# ---- xfile: full file parse — lex → parse objects → parse xref regime.
# Wraps pfile_full (lex + object parse, stops at xref/stream/EOF) with
# xref_parse (xref table + startxref). Returns FullRes carrying all parsed
# objects for later resolution (7.3.10, 7.5.4).

# ---- llen_tok: token-list length, for the trailer-parser fuel budget

def llen_tok(rest: List<&2, Lx.Tok>) -> Nat:
  match rest:
    case Nil{}:
      0n
    case Con{head, rest2}:
      (1n + llen_tok(rest2) : Nat)


# ---- xtr_find: self-recursive scan for the `trailer` keyword.
# eq = whether head is the trailer TWord; on True the dict tokens ride in
# as `rest`. Match order: rest, eq, head — mirrors xref_scan (rest, is_sx,
# entries, head) with the flag before the examined token.

def xtr_find(rest: List<&2, Lx.Tok>, eq: Bool, head: Lx.Tok) -> List<&2, Lx.Tok>:
  match rest:
    case Nil{}:
      Nil{}
    case Con{next_head, next_rest}:
      match eq:
        case True{}:
          # head is the `trailer` keyword; the dict tokens start AT head
          Con{head, rest}
        case False{}:
          match head:
            case Lx.TWord{val}:
              xtr_find(next_rest, String.eq(val, "trailer"), next_head)
            case x:
              xtr_find(next_rest, False{}, next_head)


# xtr_first: seed the walk with the first token of `rem`

def xtr_first(rest: List<&2, Lx.Tok>) -> List<&2, Lx.Tok>:
  match rest:
    case Nil{}:
      Nil{}
    case Con{head, rest2}:
      match head:
        case Lx.TWord{+val}:
          xtr_find(rest2, String.eq(val, "trailer"), head)
        case x:
          xtr_find(rest2, False{}, head)


# ---- xtr_until_sx: self-recursive prefix cut — collect tokens until the
# first `startxref` word; eq = whether head is that word. Returns the
# prefix in order. Match order: rest, eq, head.

def xtr_until_sx(rest: List<&2, Lx.Tok>, eq: Bool, head: Lx.Tok, acc: List<&2, Lx.Tok>) -> List<&2, Lx.Tok>:
  match rest:
    case Nil{}:
      match eq:
        case True{}:
          # last prepended token is the `startxref` keyword itself: drop it
          match acc:
            case Nil{}:
              Nil{}
            case Con{_sxk, acc2}:
              List.reverse(&2, Lx.Tok, acc2)
        case False{}:
          List.reverse(&2, Lx.Tok, Con{head, acc})
    case Con{next_head, next_rest}:
      match eq:
        case True{}:
          match acc:
            case Nil{}:
              Nil{}
            case Con{_sxk, acc2}:
              List.reverse(&2, Lx.Tok, acc2)
        case False{}:
          match head:
            case Lx.TWord{+val}:
              xtr_until_sx(next_rest, String.eq(val, "startxref"), next_head, Con{head, acc})
            case x:
              xtr_until_sx(next_rest, False{}, next_head, Con{head, acc})


# xtr_cut: seed the prefix cut with the first token of the trailer slice

def xtr_cut(rest: List<&2, Lx.Tok>) -> List<&2, Lx.Tok>:
  match rest:
    case Nil{}:
      Nil{}
    case Con{+head, rest2}:
      match head:
        case Lx.TWord{+val}:
          xtr_until_sx(rest2, String.eq(val, "startxref"), head, Nil{})
        case x:
          xtr_until_sx(rest2, False{}, head, Nil{})


# =============== §7.5.8 cross-reference streams =================
# The stream regime replaces the classic table when the parse regime stops
# on `startxref` (7.5.8.1). Three passes over the object table:
#   1. audit — every stream object's Length is checked against its data
#      length, with at most two extra end-of-line bytes (7.3.8.2)
#   2. find  — exactly one XRef-typed stream object carries the section
#      (Table 17, Type)
#   3. decode — the stream dictionary entries are checked (Table 17) and
#      the body's rows are read big-endian by the W widths (7.5.8.3)
# Each pass is one self-recursive walker with a Nat fuel and one state
# type; computed comparisons ride into the next state as fields. No
# mutual recursion anywhere in this block (the checker rejects cycles).

# ---- result types

type AudRes is Data:
  AudOk{}
  AudErr{why: String}


type NRid is Data:
  NRid{val: U32, rest: String}
  NREnd{}


type WRes is Data:
  WOK{a: U32, b: U32, c: U32}
  WErr{why: String}


type SIRes is Data:
  SZOK{sz: U32}
  SZErr{why: String}


type IRRes is Data:
  IROK{pairs: List<&2, U32>}
  IRErr{why: String}


type XSD is Data:
  XSDok{filt: Bool, wf: Bool, wo: P.Obj, ix: Bool, iox: P.Obj, szi: Bool, soz: P.Obj}


type XRRes is Data:
  XROk{rows: List<&2, XE>}
  XRErr{why: String}


type XSF is Data:
  XSFound{n: Nat, sn: Nat, d: P.Obj, dat: String}


type XSX is Data:
  XSX{sx: U32}
  XSNo{}


# ---- object-table length, for the walker fuel budgets

def llen_bo(bos: List<&2, P.BO>) -> Nat:
  match bos:
    case Nil{}:
      0n
    case Con{head, rest}:
      Nat.add(1n, llen_bo(rest))


# ---- audit states:
#   AUl  take the lead object of robj
#   AUe  walk a stream dictionary hunting the Length entry
#   AUv  decide the carried candidate (eq = key was "Length")
#   AUn  Length accepted as a direct non-negative integer; decide more
#   AUf  no-overflow held; decide fit

type AudSt is Data:
  AUl{robj: List<&2, P.BO>}
  AUe{robj: List<&2, P.BO>, els: List<&2, P.PEntry>, dat: String}
  AUv{robj: List<&2, P.BO>, els: List<&2, P.PEntry>, dat: String, eq: Bool, v: P.Obj}
  AUn{robj: List<&2, P.BO>, dat: String, more: Bool, whole: U32}
  AUf{robj: List<&2, P.BO>, fit: Bool}


def aud(fuel: Nat, st: AudSt) -> AudRes:
  match fuel:
    case 0n:
      AudErr{"out of fuel auditing stream lengths (internal)"}
    case 1n+f:
      match st:
        case AUl{robj}:
          match robj:
            case Nil{}:
              AudOk{}
            case Con{P.BO{num, gen, o}, rest}:
              match o:
                case P.OStream{d, dat}:
                  match d:
                    case P.ODict{els}:
                      aud(f, AUe{rest, els, dat})
                    case x:
                      AudErr{"the stream dictionary shall be a direct dictionary object (7.3.8.1)"}
                case x:
                  aud(f, AUl{rest})
        case AUe{robj, els, dat}:
          match els:
            case Nil{}:
              AudErr{"stream dictionary without a Length entry (Table 5, 7.3.8.2)"}
            case Con{P.PE{k, v}, rest}:
              aud(f, AUv{robj, rest, dat, String.eq(k, "Length"), v})
        case AUv{robj, els, +dat, eq, v}:
          match eq:
            case True{}:
              match v:
                # an indirect Length stays unresolved in v0; the check is skipped
                case P.OInd{num, gen}:
                  aud(f, AUl{robj})
                case P.ONum{neg, +whole, fnum, fden}:
                  match neg:
                    case True{}:
                      AudErr{"Length shall be a non-negative integer (Table 5, 7.3.8.2)"}
                    case False{}:
                      match fnum:
                        case 0n:
                          # Length is exactly the data byte count (7.3.8.2):
                          # declared under the actual length is "more"
                          aud(f, AUn{robj, dat, Nat.is_lt(Nat.add(U32.to_nat(whole), 2n), String.length(dat)), whole})
                        case 1n+p:
                          AudErr{"Length shall be an integer (Table 5, 7.3.8.2)"}
                case x:
                  AudErr{"Length shall be an integer (Table 5, 7.3.8.2)"}
            case False{}:
              aud(f, AUe{robj, els, dat})
        case AUn{robj, dat, more, whole}:
          match more:
            case True{}:
              AudErr{"stream data has more bytes than Length (7.3.8.2)"}
            case False{}:
              # within the tolerance window (7.3.8.2, note): data longer
              # than Length by at most two end-of-line bytes is accepted —
              # v0 counts the extra bytes and does not verify their shape
              aud(f, AUf{robj, Nat.is_lt(String.length(dat), U32.to_nat(whole))})
        case AUf{robj, fewer}:
          match fewer:
            case True{}:
              AudErr{"stream data has fewer bytes than Length (7.3.8.2)"}
            case False{}:
              aud(f, AUl{robj})


# audit (7.3.8.2): Length shall name the exact data length, allowing at
# most two extra end-of-line bytes; an indirect Length stays unresolved
# in v0, so its check is skipped.

def audit(+bos: List<&2, P.BO>) -> AudRes:
  aud(Nat.add(Nat.mul(64n, llen_bo(bos)), 256n), AUl{bos})


# ---- find states: count XRef-typed streams (n) and all streams (sn),
# keeping the last XRef stream's dictionary and body.
#   FLe  take the lead object
#   FSt  destruct a stream's dictionary (sn already counted)
#   FEn  walk its entries hunting Type
#   FCa  decide the carried candidate (isT = key was "Type")
#   FNa  v was a name; xeq = the name was "XRef" — the adopt branch

type FdSt is Data:
  FLe{bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String}
  FSt{bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String, d2: P.Obj, dat2: String}
  FEn{bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String, d2: P.Obj, dat2: String, els: List<&2, P.PEntry>}
  FCa{bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String, d2: P.Obj, dat2: String, els: List<&2, P.PEntry>, isT: Bool, v: P.Obj}
  FNa{bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String, d2: P.Obj, dat2: String, els: List<&2, P.PEntry>, xeq: Bool}


def fnd(fuel: Nat, st: FdSt) -> XSF:
  match fuel:
    case 0n:
      XSFound{0n, 0n, P.ONil{}, SNil{}}
    case 1n+f:
      match st:
        case FLe{bos, +n, +sn, +d, +dat}:
          match bos:
            case Nil{}:
              XSFound{n, sn, d, dat}
            case Con{P.BO{num, gen, o}, rest}:
              match o:
                # stream object: count it, destruct its dictionary
                case P.OStream{d2, dat2}:
                  fnd(f, FSt{rest, n, Nat.add(sn, 1n), d, dat, d2, dat2})
                case x:
                  fnd(f, FLe{rest, n, sn, d, dat})
        case FSt{bos, n, sn, d, dat, +d2, dat2}:
          match d2:
            case P.ODict{els}:
              fnd(f, FEn{bos, n, sn, d, dat, d2, dat2, els})
            case x:
              fnd(f, FLe{bos, n, sn, d, dat})
        case FEn{bos, n, sn, d, dat, d2, dat2, els}:
          match els:
            case Nil{}:
              fnd(f, FLe{bos, n, sn, d, dat})
            case Con{P.PE{k, v}, rest}:
              fnd(f, FCa{bos, n, sn, d, dat, d2, dat2, rest, String.eq(k, "Type"), v})
        case FCa{bos, n, sn, d, dat, d2, dat2, +els, isT, v}:
          match isT:
            case True{}:
              match v:
                case P.OName{val}:
                  # Type shall be the name XRef (Table 17, 7.5.8.2)
                  fnd(f, FNa{bos, n, sn, d, dat, d2, dat2, els, String.eq(val, "XRef")})
                case x:
                  fnd(f, FEn{bos, n, sn, d, dat, d2, dat2, els})
            case False{}:
              fnd(f, FEn{bos, n, sn, d, dat, d2, dat2, els})
        case FNa{bos, +n, +sn, +d, +dat, +d2, +dat2, els, xeq}:
          match xeq:
            case True{}:
              # adopt this stream's dictionary and body; a later stream
              # overwrites (the last one carries the live section)
              fnd(f, FLe{bos, Nat.add(n, 1n), sn, d2, dat2})
            case False{}:
              fnd(f, FEn{bos, n, sn, d, dat, d2, dat2, els})


def xfind(+bos: List<&2, P.BO>, n: Nat, sn: Nat, d: P.Obj, dat: String) -> XSF:
  fnd(Nat.add(Nat.mul(64n, llen_bo(bos)), 256n), FLe{bos, n, sn, d, dat})


# ---- startxref offset extraction (7.5.5: the keyword startxref is followed
# by a byte offset; in the stream regime the offset names the stream object)

def xsneg(neg: Bool, whole: U32) -> XSX:
  match neg:
    case True{}:
      XSNo{}
    case False{}:
      XSX{whole}


def xsx(rest: List<&2, Lx.Tok>) -> XSX:
  match rest:
    case Nil{}:
      XSNo{}
    case Con{head, rest2}:
      match head:
        case Lx.TNum{neg, whole, fnum, fden}:
          xsneg(neg, whole)
        case x:
          XSNo{}


# ---- dictionary entry collector: Filter / W / Index / Size flags+values.
# One self-recursive walk; fk/wk/ik/sk carry the key comparisons of the
# carried pair, computed for the tail's head by each call site.

def xdw(els: List<&2, P.PEntry>, filt: Bool, wf: Bool, wo: P.Obj, ix: Bool, iox: P.Obj, szi: Bool, soz: P.Obj, fk: Bool, wk: Bool, ik: Bool, sk: Bool, v: P.Obj) -> XSD:
  match els:
    case Nil{}:
      # the carried pair closes at the end too
      match fk:
        case True{}:
          XSDok{True{}, wf, wo, ix, iox, szi, soz}
        case False{}:
          match wk:
            case True{}:
              XSDok{filt, True{}, v, ix, iox, szi, soz}
            case False{}:
              match ik:
                case True{}:
                  XSDok{filt, wf, wo, True{}, v, szi, soz}
                case False{}:
                  match sk:
                    case True{}:
                      XSDok{filt, wf, wo, ix, iox, True{}, v}
                    case False{}:
                      XSDok{filt, wf, wo, ix, iox, szi, soz}
    case Con{P.PE{+k, +v2}, rest}:
      match fk:
        case True{}:
          xdw(rest, True{}, wf, wo, ix, iox, szi, soz, String.eq(k, "Filter"), String.eq(k, "W"), String.eq(k, "Index"), String.eq(k, "Size"), v2)
        case False{}:
          match wk:
            case True{}:
              xdw(rest, filt, True{}, v, ix, iox, szi, soz, String.eq(k, "Filter"), String.eq(k, "W"), String.eq(k, "Index"), String.eq(k, "Size"), v2)
            case False{}:
              match ik:
                case True{}:
                  xdw(rest, filt, wf, wo, True{}, v, szi, soz, String.eq(k, "Filter"), String.eq(k, "W"), String.eq(k, "Index"), String.eq(k, "Size"), v2)
                case False{}:
                  match sk:
                    case True{}:
                      xdw(rest, filt, wf, wo, ix, iox, True{}, v, String.eq(k, "Filter"), String.eq(k, "W"), String.eq(k, "Index"), String.eq(k, "Size"), v2)
                    case False{}:
                      xdw(rest, filt, wf, wo, ix, iox, szi, soz, String.eq(k, "Filter"), String.eq(k, "W"), String.eq(k, "Index"), String.eq(k, "Size"), v2)


# ---- W checks (Table 17, 7.5.8.3): W shall be an array of exactly three
# integers; the second element shall not be zero (field 2 carries the
# object offset); a zero first element means the type field is absent and
# the type defaults to 1; v0 caps each width at 4 bytes.

type WSt is Data:
  SWa{els: List<&2, P.Obj>, n: Nat, a: U32, b: U32, c: U32}
  SWz{bok: Bool, wok: Bool, a: U32, b: U32, c: U32}


def xsw(fuel: Nat, st: WSt) -> WRes:
  match fuel:
    case 0n:
      WErr{"out of fuel decoding W (internal)"}
    case 1n+f:
      match st:
        case SWa{els, +n, +a, +b, +c}:
          match els:
            case Nil{}:
              # read ends: W shall have exactly three integers
              match n:
                case 3n:
                  # bok: field-2 width shall not be zero; wok: every width
                  # within the 4-byte v0 cap
                  xsw(f, SWz{U32.is_ne(b, 0), Bool.and(Bool.and(Bool.not(Nat.is_lt(4n, U32.to_nat(a))), Bool.not(Nat.is_lt(4n, U32.to_nat(b)))), Bool.not(Nat.is_lt(4n, U32.to_nat(c)))), a, b, c})
                case 0n:
                  WErr{"W shall have exactly three integers (Table 17, 7.5.8.3)"}
                case 1n:
                  WErr{"W shall have exactly three integers (Table 17, 7.5.8.3)"}
                case 2n:
                  WErr{"W shall have exactly three integers (Table 17, 7.5.8.3)"}
                case 4n+p:
                  WErr{"W shall have exactly three integers (Table 17, 7.5.8.3)"}
            case Con{head, rest}:
              match head:
                case P.ONum{neg, whole, fnum, fden}:
                  match neg:
                    case True{}:
                      WErr{"W shall be an array of integers (Table 17, 7.5.8.3)"}
                    case False{}:
                      match fnum:
                        case 0n:
                          match n:
                            case 0n:
                              xsw(f, SWa{rest, 1n, whole, b, c})
                            case 1n:
                              xsw(f, SWa{rest, 2n, a, whole, c})
                            case 2n:
                              xsw(f, SWa{rest, 3n, a, b, whole})
                            case 3n+q:
                              WErr{"W shall have exactly three integers (Table 17, 7.5.8.3)"}
                        case 1n+p:
                          WErr{"W shall be an array of integers (Table 17, 7.5.8.3)"}
                case x:
                  WErr{"W shall be an array of integers (Table 17, 7.5.8.3)"}
        case SWz{bok, wok, a, b, c}:
          match bok:
            case True{}:
              match wok:
                case True{}:
                  WOK{a, b, c}
                case False{}:
                  WErr{"cross-reference fields wider than 4 bytes are not supported in v0 (7.5.8.3)"}
            case False{}:
              WErr{"the second element of W shall not be zero (Table 17, 7.5.8.3)"}


def xs_w(o: P.Obj) -> WRes:
  match o:
    case P.OInd{num, gen}:
      WErr{"cross-reference stream entries shall be direct objects (7.5.8.2)"}
    case P.OArr{+els}:
      xsw(Nat.add(Nat.mul(2n, List.length(&2, P.Obj, els)), 2n), SWa{els, 0n, 0, 0, 0})
    case x:
      WErr{"W shall be an array of integers (Table 17, 7.5.8.3)"}


def xs_sz_neg(neg: Bool, whole: U32) -> SIRes:
  match neg:
    case True{}:
      SZErr{"Size shall be a non-negative integer (Table 17, 7.5.8.2)"}
    case False{}:
      SZOK{whole}


def xs_sz_int(fnum: Nat, neg: Bool, whole: U32) -> SIRes:
  match fnum:
    case 0n:
      xs_sz_neg(neg, whole)
    case 1n+p:
      SZErr{"Size shall be an integer (Table 17, 7.5.8.2)"}


# ---- Size checks (Table 17): Size (Required) shall be an integer; the
# entries shown in Table 17 shall be direct objects (7.5.8.2)

def xs_sz(o: P.Obj) -> SIRes:
  match o:
    case P.OInd{num, gen}:
      SZErr{"cross-reference stream entries shall be direct objects (7.5.8.2)"}
    case P.ONum{neg, whole, fnum, fden}:
      xs_sz_int(fnum, neg, whole)
    case x:
      SZErr{"Size shall be an integer (Table 17, 7.5.8.2)"}


# ---- Index checks (Table 17): optional, an array of integer pairs sorted
# in ascending order by object number; subsections cannot overlap. Default
# value [0 Size].

type ISt is Data:
  IWa{els: List<&2, P.Obj>, odd: Bool, acc: List<&2, U32>}


def xiw(fuel: Nat, st: ISt) -> IRRes:
  match fuel:
    case 0n:
      IRErr{"out of fuel decoding Index (internal)"}
    case 1n+f:
      match st:
        case IWa{els, odd, acc}:
          match els:
            case Nil{}:
              match odd:
                case True{}:
                  IRErr{"Index shall contain an even number of integers (Table 17, 7.5.8.2)"}
                case False{}:
                  IROK{List.reverse(&2, U32, acc)}
            case Con{head, rest}:
              match head:
                case P.ONum{neg, whole, fnum, fden}:
                  match neg:
                    case True{}:
                      IRErr{"Index integers shall be non-negative (Table 17, 7.5.8.2)"}
                    case False{}:
                      match fnum:
                        case 0n:
                          # pair bookkeeping: odd/even alternates per integer
                          xiw(f, IWa{rest, Bool.not(odd), Con{whole, acc}})
                        case 1n+p:
                          IRErr{"Index shall be an array of integers (Table 17, 7.5.8.2)"}
                case x:
                  IRErr{"Index shall be an array of integers (Table 17, 7.5.8.2)"}


def xs_ix(o: P.Obj) -> IRRes:
  match o:
    case P.OInd{num, gen}:
      IRErr{"cross-reference stream entries shall be direct objects (7.5.8.2)"}
    case P.OArr{+els}:
      xiw(Nat.add(Nat.mul(2n, List.length(&2, P.Obj, els)), 2n), IWa{els, False{}, Nil{}})
    case x:
      IRErr{"Index shall be an array of integers (Table 17, 7.5.8.2)"}


# ---- body byte readers: fields are big-endian (7.5.8.3). rdn accumulates
# n bytes; its recursion is on the width n itself (≤ 4), so it needs no
# walker fuel. U32 arithmetic cannot overflow inside the 4-byte cap.

def rdn(n: Nat, dat: String, +acc: U32) -> NRid:
  match n:
    case 0n:
      NRid{acc, dat}
    case 1n+m:
      match dat:
        case SNil{}:
          NREnd{}
        case SCon{h, tl}:
          rdn(m, tl, U32.add(U32.mul(acc, 256), Char.to_u32(h)))


# r0: the type field read. A zero first W element means the field is absent
# and the entry type defaults to 1 (Table 17, W description, 7.5.8.2).

def r0(w0: Nat, dat: String) -> NRid:
  match w0:
    case 0n:
      NRid{1, dat}
    case 1n+p:
      rdn(w0, dat, 0)


# ---- the row walker over (pairs, body). Pair activation (Table 17,
# 7.5.8.2: subsections sorted ascending, no overlap) opens the subsection;
# each row reads type / field 2 / field 3 at the current widths and emits
# the XE row per its type (Table 18, 7.5.8.3). fuel = 6 * body bytes +
# 2 * pairs + 16: rows cost at least one body byte each because W[1]
# shall not be zero, and at most 4 walker rounds per row.

type RSt is Data:
  RXr{cnt: Nat, p: List<&2, U32>, peer: U32, nxt: U32, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>}
  RXa{p: List<&2, U32>, peer: U32, s0: U32, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>}
  RXo{p: List<&2, U32>, peer: U32, nxt: U32, c: U32, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>, bad: Bool}
  RXt{p: List<&2, U32>, peer: U32, nxt: U32, cnt: Nat, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>, rt: NRid}
  RX2{p: List<&2, U32>, peer: U32, nxt: U32, cnt: Nat, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>, t: U32, r1: NRid}
  RX3{p: List<&2, U32>, peer: U32, nxt: U32, cnt: Nat, dat: String, w0: Nat, w1: Nat, w2: Nat, acc: List<&2, XE>, t: Nat, r2: NRid, f1: U32}


def xrw(fuel: Nat, st: RSt) -> XRRes:
  match fuel:
    case 0n:
      XRErr{"out of fuel decoding the cross-reference stream rows (internal)"}
    case 1n+f:
      match st:
        # -- row mode: pairs left? rows left on the active subsection?
        case RXr{cnt, +p, peer, nxt, +dat, +w0, w1, w2, acc}:
          match cnt:
            case 0n:
              # subsection done: another subsection's pair left?
              match p:
                case Nil{}:
                  # pairs exhausted: the whole section is read (7.5.8.3)
                  XROk{List.reverse(&2, XE, acc)}
                case Con{f0, p2}:
                  xrw(f, RXa{p2, peer, f0, dat, w0, w1, w2, acc})
            case 1n+q:
              # rows remain on the active subsection: read one
              match dat:
                case SNil{}:
                  XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
                case SCon{h, tl}:
                  # read the type field at the W[0] width
                  xrw(f, RXt{p, peer, nxt, q, dat, w0, w1, w2, acc, r0(w0, dat)})
        case RXt{p, peer, nxt, cnt, dat, w0, +w1, w2, acc, rt}:
          match rt:
            case NREnd{}:
              XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
            case NRid{+t, +dat2}:
              xrw(f, RX2{p, peer, nxt, cnt, dat2, w0, w1, w2, acc, t, rdn(w1, dat2, 0)})
        case RX2{p, peer, nxt, cnt, dat, w0, w1, +w2, acc, t, r1}:
          match r1:
            case NREnd{}:
              XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
            case NRid{+f1, +dat3}:
              xrw(f, RX3{p, peer, nxt, cnt, dat3, w0, w1, w2, acc, U32.to_nat(t), rdn(w2, dat3, 0), f1})
        case RX3{p, peer, +nxt, cnt, dat, w0, w1, w2, acc, t, r2, f1}:
          match t:
            case 0n:
              # type 0: a free object; field 3 carries the generation
              match r2:
                case NREnd{}:
                  XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
                case NRid{f2, dat4}:
                  xrw(f, RXr{cnt, p, peer, U32.add(nxt, 1), dat4, w0, w1, w2, Con{XE{nxt, f2, False{}, 0}, acc}})
            case 1n:
              # type 1: an in-use object at the field-2 offset
              match r2:
                case NREnd{}:
                  XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
                case NRid{f2, dat4}:
                  xrw(f, RXr{cnt, p, peer, U32.add(nxt, 1), dat4, w0, w1, w2, Con{XE{nxt, f2, True{}, f1}, acc}})
            case 2n:
              XRErr{"compressed cross-reference entries (type 2) are not supported in v0 (7.5.7)"}
            case 3n+s:
              # any other type references the null object (7.5.8.3): the
              # row keeps its position as a free placeholder
              match r2:
                case NREnd{}:
                  XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
                case NRid{f2, dat4}:
                  xrw(f, RXr{cnt, p, peer, U32.add(nxt, 1), dat4, w0, w1, w2, Con{XE{nxt, 0, False{}, 0}, acc}})
        case RXa{p, +peer, +s0, dat, w0, w1, w2, acc}:
          match p:
            case Nil{}:
              XRErr{"Index shall contain pairs of integers (Table 17, 7.5.8.2)"}
            case Con{c, rrr}:
              # subsections sorted ascending, no overlap (Table 17, 7.5.8.2):
              # a subsection's first object number shall not fall below the
              # frontier left by the previous one
              xrw(f, RXo{rrr, peer, s0, c, dat, w0, w1, w2, acc, Nat.is_lt(U32.to_nat(s0), U32.to_nat(peer))})
        case RXo{p, peer, +nxt, +c, dat, w0, w1, w2, acc, bad}:
          match bad:
            case True{}:
              XRErr{"Index subsections shall be sorted ascending and may not overlap (Table 17, 7.5.8.2)"}
            case False{}:
              xrw(f, RXr{U32.to_nat(c), p, U32.add(nxt, c), nxt, dat, w0, w1, w2, acc})


def xr(+p: List<&2, U32>, peer: U32, nxt: U32, +dat: String, w0: Nat, w1: Nat, w2: Nat) -> XRRes:
  xrw(Nat.add(Nat.mul(6n, String.length(dat)), Nat.add(Nat.mul(2n, List.length(&2, U32, p)), 16n)), RXr{0n, p, peer, nxt, dat, w0, w1, w2, Nil{}})


def xs_runcase(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, rr: XRRes) -> FullRes:
  match rr:
    case XRErr{why}:
      FullErr{why}
    case XROk{rows}:
      # the stream dictionary doubles as the trailer (7.5.8.1)
      FullRes{robj, rows, d, sx}


def xs_pairs(robj: List<&2, P.BO>, d: P.Obj, +dat: String, sx: U32, a: U32, b: U32, c: U32, pr: IRRes) -> FullRes:
  match pr:
    case IRErr{why}:
      FullErr{why}
    case IROK{pairs}:
      xs_runcase(robj, d, dat, sx, xr(pairs, 0, 0, dat, U32.to_nat(a), U32.to_nat(b), U32.to_nat(c)))


def xs_sz_ok(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, ix: Bool, iox: P.Obj, a: U32, b: U32, c: U32, sz: U32) -> FullRes:
  match ix:
    case False{}:
      # default Index value (Table 17, 7.5.8.2): [0 Size]
      xs_pairs(robj, d, dat, sx, a, b, c, IROK{Con{0, Con{sz, Nil{}}}})
    case True{}:
      xs_pairs(robj, d, dat, sx, a, b, c, xs_ix(iox))


def xs_sz_case(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, ix: Bool, iox: P.Obj, a: U32, b: U32, c: U32, sr: SIRes) -> FullRes:
  match sr:
    case SZErr{why}:
      FullErr{why}
    case SZOK{sz}:
      xs_sz_ok(robj, d, dat, sx, ix, iox, a, b, c, sz)


def xs_w_ok(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, ix: Bool, iox: P.Obj, szi: Bool, soz: P.Obj, a: U32, b: U32, c: U32) -> FullRes:
  match szi:
    case False{}:
      FullErr{"cross-reference stream without a Size entry (Table 17, 7.5.8.2)"}
    case True{}:
      xs_sz_case(robj, d, dat, sx, ix, iox, a, b, c, xs_sz(soz))


def xs_w_case(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, ix: Bool, iox: P.Obj, szi: Bool, soz: P.Obj, wr: WRes) -> FullRes:
  match wr:
    case WErr{why}:
      FullErr{why}
    case WOK{a, b, c}:
      xs_w_ok(robj, d, dat, sx, ix, iox, szi, soz, a, b, c)


def xs_check(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, sd: XSD) -> FullRes:
  match sd:
    case XSDok{filt, wf, wo, ix, iox, szi, soz}:
      match filt:
        case True{}:
          FullErr{"cross-reference streams stored with a Filter are not supported in v0 (Table 5 Filter, 7.4)"}
        case False{}:
          match wf:
            case False{}:
              FullErr{"cross-reference stream without a W entry (Table 17, 7.5.8.2)"}
            case True{}:
              xs_w_case(robj, d, dat, sx, ix, iox, szi, soz, xs_w(wo))


# ---- decode: collect the dictionary entries, then check table order:
# Filter, W, Size, Index. The stream dictionary doubles as the trailer
# (7.5.8.1).

def xs_decode(robj: List<&2, P.BO>, +d: P.Obj, dat: String, sx: U32) -> FullRes:
  match d:
    case P.ODict{els}:
      xs_check(robj, d, dat, sx, xdw(els, False{}, False{}, P.ONil{}, False{}, P.ONil{}, False{}, P.ONil{}, False{}, False{}, False{}, False{}, P.ONil{}))
    case x:
      FullErr{"the cross-reference stream dictionary shall be a direct dictionary (7.3.8.1)"}


def xs_sxc(rem: List<&2, Lx.Tok>, robj: List<&2, P.BO>, d: P.Obj, dat: String, xs: XSX) -> FullRes:
  match xs:
    case XSNo{}:
      FullErr{"startxref shall be followed by a byte offset (7.5.5)"}
    case XSX{sx}:
      xs_decode(robj, d, dat, sx)


def xs_find(+rem: List<&2, Lx.Tok>, +robj: List<&2, P.BO>, fs: XSF) -> FullRes:
  match fs:
    case XSFound{n, sn, d, dat}:
      match n:
        case 0n:
          match sn:
            case 0n:
              FullErr{"no xref section found (7.5.4)"}
            case 1n+p:
              FullErr{"the cross-reference stream dictionary shall have a Type entry with the value XRef (Table 17, 7.5.8.2)"}
        case 1n:
          xs_sxc(rem, robj, d, dat, xsx(rem))
        case 2n+q:
          # several cross-reference streams: an incremental-update chain
          FullErr{"incremental cross-reference updates are not supported in v0 (Table 17 Prev, 7.5.6)"}


# ---- regime entry: audit first, then find, then dispatch.

def xs_aud(+rem: List<&2, Lx.Tok>, +robj: List<&2, P.BO>, ra: AudRes) -> FullRes:
  match ra:
    case AudErr{why}:
      FullErr{why}
    case AudOk{}:
      xs_find(rem, robj, xfind(robj, 0n, 0n, P.ONil{}, SNil{}))


def xs_route(rem: List<&2, Lx.Tok>, +robj: List<&2, P.BO>) -> FullRes:
  xs_aud(rem, robj, audit(robj))


# ---- xtr_pick: the first BO's object is the trailer dictionary

def xtr_pick(bos: List<&2, P.BO>, objs: List<&2, P.BO>, entries: List<&2, XE>, sx: U32) -> FullRes:
  match bos:
    case Nil{}:
      FullErr{"trailer dictionary has no value (7.5.4)"}
    case Con{P.BO{bnum, bgen, bobj}, brest}:
      FullRes{objs, entries, bobj, sx}


# ---- xtr_pval_done: match the result PST of the trailer-dict parse

def xtr_pval_done(pst: P.PST, objs: List<&2, P.BO>, entries: List<&2, XE>, sx: U32) -> FullRes:
  match pst:
    case P.PST{stop, toks, stk, pend, acc}:
      match stop:
        case Some{P.PCut{bos, kw}}:
          xtr_pick(bos, objs, entries, sx)
        case Some{P.POks{bos}}:
          xtr_pick(bos, objs, entries, sx)
        case Some{P.PErr{why}}:
          FullErr{why}
        case None{}:
          FullErr{"trailer dictionary incomplete (7.5.4)"}


# ---- xtr_parse: run the object regime over the trailer-dict tokens.
# Seeds a fake `0 0 obj` header (FHead with zero ONums) so the dict parses
# as an object value, and appends a synthetic `endobj` to close it (7.5.4).

def xtr_parse(+dtoks: List<&2, Lx.Tok>, objs: List<&2, P.BO>, entries: List<&2, XE>, sx: U32) -> FullRes:
  match dtoks:
    case Nil{}:
      FullErr{"trailer dictionary missing (7.5.4)"}
    case x:
      fuel : Nat = Nat.add(Nat.mul(Nat.add(llen_tok(dtoks), 1n), 2n), 8n)
      xtr_pval_done(
        P.pval(fuel,
          P.PST{None{}, List.append(&2, Lx.Tok, dtoks, Con{Lx.TWord{"endobj"}, Nil{}}),
                Con{P.FHead{P.ONum{False{}, 0, 0n, 1n}, P.ONum{False{}, 0, 0n, 1n}}, Nil{}},
                P.PNil{}, Nil{}}),
        objs, entries, sx)


# ---- xfile_two: after the xref table parsed, parse the trailer dict from
# the same token remnant (second pass; startxref came from the first)

def xfile_two(xres: XRes, rem: List<&2, Lx.Tok>, objs: List<&2, P.BO>) -> FullRes:
  match xres:
    case XOK{table, trailer, startxref}:
      xtr_parse(xtr_cut(xtr_first(rem)), objs, table, startxref)
    case XErr{why}:
      FullErr{why}


# xfile_bytes: full file parse from raw bytes

# xfile_kw2: the keyword comparison result selects the regime (7.5.8.1:
# startxref selects the stream regime; anything else names a classic table)

def xfile_kw2(+rem: List<&2, Lx.Tok>, +objs: List<&2, P.BO>, kweq: Bool) -> FullRes:
  match kweq:
    case True{}:
      xfile_two(xref_parse(rem), rem, objs)
    case False{}:
      xs_route(rem, objs)


# xfile_kw: the PCut trigger keyword selects the xref regime. `xref` opens a
# classic cross-reference table (7.5.4); `startxref` opens a cross-reference
# stream, whose offset tail is rem (7.5.8.1: the value following startxref
# shall be the byte offset of the cross-reference stream).

def xfile_kw(rem: List<&2, Lx.Tok>, objs: List<&2, P.BO>, kw: String) -> FullRes:
  xfile_kw2(rem, objs, String.eq(kw, "xref"))


def xfile(px: P.PlxFull) -> FullRes:
  match px:
    case P.PlxFull{pr, +rem}:
      match pr:
        case P.PCut{objs, kw}:
          xfile_kw(rem, objs, kw)
        case P.POks{objs}:
          FullErr{"no xref section found (7.5.4)"}
        case P.PErr{why}:
          FullErr{why}


def xfile_bytes(bytes: List<&2, U32>) -> FullRes:
  xfile(P.plx_full(Lx.lex(bytes)))
