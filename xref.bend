# xref.bend — xref table, trailer, and resolver (§7.5.4, §7.5.6, §7.5.7)
# Consumes the remaining token stream left by pfile_full's PCut at `xref`:
#   xref <start> <count> (offset gen f/n)* trailer <<dict>> startxref <offset> %%EOF

import Base
import ./lex.bend as Lx
import ./parser.bend as P

# ---- xref entry: object number, generation, in-use/free, byte offset (Table 15)

type XE is Data:
  XE{num: U32, gen: U32, in_use: Bool, offset: U32}
  # type-2 entry: the object lives in the object stream `stmn` at
  # position `idxn` (Table 18, 7.5.8.3)
  XEC{num: U32, stmn: U32, idxn: U32}


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
              # type 2: the object lives in the object stream named by
              # field 2 (f1), at the field-3 position (f2) (Table 18, 7.5.8.3)
              match r2:
                case NREnd{}:
                  XRErr{"not enough bytes for the cross-reference subsection (7.5.8.3)"}
                case NRid{f2, dat4}:
                  xrw(f, RXr{cnt, p, peer, U32.add(nxt, 1), dat4, w0, w1, w2, Con{XEC{nxt, f1, f2}, acc}})
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


# ---- object streams (7.5.7). A type-2 cross-reference entry (Table 18,
# 7.5.8.3) stores the object in an object stream: field 2 names the stream,
# field 3 the position within the stream's N stored objects. The stream's
# dictionary carries the Table 16 entries; its data holds N header pairs
# (object number, byte offset relative to the First entry) and then the N
# objects, values only (7.5.7). v0 decodes raw (unfiltered) streams and
# merges the stored objects into the file's object table as generation-zero
# indirect objects; Extends collections are ignored in v0.

type OSRes is Data:
  OSOK{memos: List<&2, OSP>}
  OSErr{why: String}

type OSP is Data:
  OSP{stm: U32, objs: List<&2, P.BO>}

type MRes is Data:
  MHit{objs: List<&2, P.BO>}
  MMiss{}

type OBF is Data:
  OBf{bo: P.BO}
  OBfNo{}

type OSDc is Data:
  DOK{objs: List<&2, P.BO>}
  DErr{why: String}

type OSDR is Data:
  OSDok{t: Bool, tv: P.Obj, n: Bool, nv: P.Obj, f: Bool, fv: P.Obj, fil: Bool}

type OSInt is Data:
  ISok{v: U32}
  ISbad{}

# header and slicing state (7.5.7): the scan walks the bytes before First,
# the walk checks the offsets increase, slicing cuts each object out
type OSGSt is Data:
  SGo{dat: String, raw: String, left: Nat, remn: Nat, phase: Nat, acc: U32, mode: Nat, pairs: List<&2, U32>}
  SOrd{orig: List<&2, U32>, walk: List<&2, U32>, prev: U32, first: Bool, dat: String, acc: List<&2, P.BO>}
  SCar{pairs: List<&2, U32>, dat: String, acc: List<&2, P.BO>}
  SPai{rest: List<&2, U32>, num: U32, off: U32, dat: String, acc: List<&2, P.BO>}
  SIns{rest: List<&2, U32>, n2: U32, o2: U32, oend: Nat, num: U32, offn: Nat, dat: String, acc: List<&2, P.BO>}
  SBad{why: String}

type OSSl is Data:
  OSV{bo: P.BO}
  OSW{why: String}

type XSt is Data:
  SXr{rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}
  SXm{mres: MRes, stmn: U32, idxn: U32, rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}
  SXf{fr: OBF, stmn: U32, idxn: U32, rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}
  SXo{res: OSDc, stmn: U32, idxn: U32, rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}
  SXb{bad: Bool, stmn: U32, objs: List<&2, P.BO>, rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}
  SXi{bad: Bool, rows: List<&2, XE>, robj: List<&2, P.BO>, acc: List<&2, OSP>}

# ---- slice take: keep the first n characters of a string (7.5.7: each
# stored object spans from its header offset to the next offset, or the
# end of the data).

def os_take(n: Nat, +s: String) -> String:
  match n:
    case 0n:
      SNil{}
    case 1n+m:
      match s:
        case SNil{}:
          SNil{}
        case SCon{h, tl}:
          SCon{h, os_take(m, tl)}

# ---- the stored-value parser (7.5.7: only the values are stored; the obj
# and endobj keywords are not (NOTE 7, errata)): the slice parses as one
# indirect object behind a synthetic frame, like the trailer dictionary.

def os_slice_pk(pst: P.PST) -> OSSl:
  match pst:
    case P.PST{stop, toks, stk, pend, acc}:
      match stop:
        case Some{res}:
          match res:
            case P.POks{bos}:
              match bos:
                case Con{bo, rest}:
                  OSV{bo}
                case x2:
                  OSW{"an object in an object stream shall be present (7.5.7)"}
            case P.PCut{bos, kw}:
              OSW{"an object in an object stream shall not stop the parse (internal)"}
            case P.PErr{why}:
              OSW{why}
        case None{}:
          OSW{"an object in an object stream shall terminate (7.5.7)"}

def os_slice_p(+toks: List<&2, Lx.Tok>) -> OSSl:
  match toks:
    case Nil{}:
      OSW{"an object in an object stream shall be present (7.5.7)"}
    case x:
      os_slice_pk(
        P.pval(Nat.add(Nat.mul(Nat.add(List.length(&2, Lx.Tok, toks), 1n), 2n), 8n),
          P.PST{None{}, List.append(&2, Lx.Tok, toks, Con{Lx.TWord{"endobj"}, Nil{}}),
                Con{P.FHead{P.ONum{False{}, 0, 0n, 1n}, P.ONum{False{}, 0, 0n, 1n}}, Nil{}},
                P.PNil{}, Nil{}}))

def os_slice_w(res: Lx.Lex) -> OSSl:
  match res:
    case Lx.LexErr{why}:
      OSW{why}
    case Lx.Lexed{toks}:
      os_slice_p(toks)

def os_slice_parse(slc: String) -> OSSl:
  os_slice_w(Lx.lex(P.str_byts(slc)))

# ---- the header scan step (7.5.7): N pairs of integers separated by
# white space, before the First offset. `left` is the byte budget from
# the First entry; `remn` counts the pairs still unread; `phase` 0 names
# an object number, 1 an offset; `mode` 0/1 = outside/inside a number.

def os_close(phase: Nat, remn: Nat, dat: String, left: Nat, val: U32, raw: String, pairs: List<&2, U32>) -> OSGSt:
  match phase:
    case 0n:
      # the number is an object number; an offset follows (7.5.7)
      SGo{dat, raw, left, remn, 1n, 0, 0n, Con{val, pairs}}
    case 1n+p2:
      match remn:
        case 0n:
          # an over-close: the header is malformed (7.5.7)
          SBad{"the object stream header shall contain N pairs of integers (7.5.7)"}
        case 1n:
          # the last pair completed: the offsets get their order check
          # (7.5.7/NOTE: the byte offsets shall be in increasing order)
          +fwd : List<&2, U32> = List.reverse(&2, U32, Con{val, pairs})
          SOrd{fwd, fwd, 0, True{}, raw, Nil{}}
        case 1n+q:
          SGo{dat, raw, left, q, 0n, 0, 0n, Con{val, pairs}}

def os_dec(dat: String, left: Nat, remn: Nat, phase: Nat, acc: U32, mode: Nat, raw: String, pairs: List<&2, U32>) -> OSGSt:
  match left:
    case 0n:
      match mode:
        case 0n:
          # the budget is spent before the header completes (Table 16)
          SBad{"the header of an object stream shall end before the First offset (Table 16, 7.5.7)"}
        case 1n+s:
          os_close(phase, remn, dat, 0n, acc, raw, pairs)
    case 1n+left2:
      SGo{dat, raw, left2, remn, phase, acc, mode, pairs}

def s0(d: Bool, w: Bool, h: Char, dv: U32, tl: String, left: Nat, remn: Nat, phase: Nat, raw: String, pairs: List<&2, U32>) -> OSGSt:
  match d:
    case True{}:
      # the number begins; its first digit rides in as the accumulator
      os_dec(tl, left, remn, phase, dv, 1n, raw, pairs)
    case False{}:
      match w:
        case True{}:
          # white space separates the pair items (7.5.7)
          os_dec(tl, left, remn, phase, 0, 0n, raw, pairs)
        case False{}:
          SBad{"the object stream header shall contain N pairs of integers (7.5.7)"}

def s1(d: Bool, w: Bool, h: Char, acc: U32, dv: U32, tl: String, left: Nat, remn: Nat, phase: Nat, raw: String, pairs: List<&2, U32>) -> OSGSt:
  match d:
    case True{}:
      # the number extends (7.5.7: pairs of integers)
      os_dec(tl, left, remn, phase, U32.add(U32.mul(acc, 10), dv), 1n, raw, pairs)
    case False{}:
      match w:
        case True{}:
          # the number closed at white space (7.5.7)
          os_close(phase, remn, tl, left, acc, raw, pairs)
        case False{}:
          # closed by a non-digit byte: it stays for the object region
          # (7.5.7: A PDF processor shall rely on the First entry)
          os_close(phase, remn, SCon{h, tl}, left, acc, raw, pairs)

# ---- the offset-order check (7.5.7): the computed comparison rides in
# as a Bool parameter and the walk continues.

def os_ordchk(orig: List<&2, U32>, rest2: List<&2, U32>, off2: U32, dat: String, acc: List<&2, P.BO>, ok: Bool) -> OSGSt:
  match ok:
    case True{}:
      SOrd{orig, rest2, off2, False{}, dat, acc}
    case False{}:
      SBad{"the offsets in an object stream shall be in increasing order (7.5.7)"}

# ---- the in-data check (7.5.7): the object's start offset shall fall
# within the data; the two copies decrement together, so no Bool rides.

def os_ran(offn: Nat, lenn: Nat, rest: List<&2, U32>, n2: U32, o2: U32, oend: Nat, num: U32, off0: Nat, dat: String, acc: List<&2, P.BO>) -> OSGSt:
  match offn:
    case 0n:
      SIns{rest, n2, o2, oend, num, off0, dat, acc}
    case 1n+o:
      match lenn:
        case 0n:
          SBad{"an object in an object stream shall start within the stream data (7.5.7)"}
        case 1n+l:
          os_ran(o, l, rest, n2, o2, oend, num, off0, dat, acc)

# ---- the stored-object legality check (7.5.7): stream objects and naked
# references are not stored; anything else joins the table as generation
# zero. The parsed value arrives as a parameter; the check terminates.

def os_leg(stg: OSSl, rest: List<&2, U32>, num: U32, dat: String, acc: List<&2, P.BO>) -> OSGSt:
  match stg:
    case OSW{why}:
      SBad{why}
    case OSV{P.BO{num2, gen2, o}}:
      match o:
        case P.OStream{d, datx}:
          SBad{"stream objects shall not be stored in an object stream (7.5.7)"}
        case P.OInd{rnum, rgen}:
          SBad{"an object in an object stream shall not consist solely of an object reference (7.5.7)"}
        case val2:
          SCar{rest, dat, Con{P.BO{num, 0, o}, acc}}

# ---- the header and slicing driver: one state step per fuel unit;
# helpers return states in argument position, in the style of the lexer.

def osh(f: Nat, st: OSGSt) -> OSDc:
  match f:
    case 0n:
      DErr{"out of object stream header fuel (internal)"}
    case 1n+f2:
      match st:
        case SBad{why}:
          DErr{why}
        case SGo{dat, raw, left, remn, phase, acc, mode, pairs}:
          match dat:
            case SNil{}:
              match mode:
                case 0n:
                  DErr{"the object stream header shall contain N pairs of integers (7.5.7)"}
                case 1n+s:
                  osh(f2, os_close(phase, remn, SNil{}, left, acc, raw, pairs))
            case SCon{+h, tl}:
              match mode:
                case 0n:
                  osh(f2, s0(Lx.is_digit(Char.to_u32(h)), Lx.is_ws(Char.to_u32(h)), h, Lx.digv(Char.to_u32(h)), tl, left, remn, phase, raw, pairs))
                case 1n+s:
                  osh(f2, s1(Lx.is_digit(Char.to_u32(h)), Lx.is_ws(Char.to_u32(h)), h, acc, Lx.digv(Char.to_u32(h)), tl, left, remn, phase, raw, pairs))
        case SOrd{orig, walk, prev, first, dat, acc}:
          match walk:
            case Nil{}:
              # the header held the N pairs (7.5.7): slicing starts
              osh(f2, SCar{orig, dat, acc})
            case Con{n2, Con{+off2, rest2}}:
              match first:
                case True{}:
                  osh(f2, SOrd{orig, rest2, off2, False{}, dat, acc})
                case False{}:
                  osh(f2, os_ordchk(orig, rest2, off2, dat, acc, Nat.is_lt(U32.to_nat(prev), U32.to_nat(off2))))
            case tail1:
              DErr{"the object stream header shall contain N pairs of integers (7.5.7)"}
        case SCar{pairs, dat, acc}:
          match pairs:
            case Nil{}:
              # all stored objects surfaced (7.5.7)
              DOK{List.reverse(&2, P.BO, acc)}
            case Con{num, Con{off, rest}}:
              osh(f2, SPai{rest, num, off, dat, acc})
            case tail2:
              DErr{"the object stream header shall contain N pairs of integers (7.5.7)"}
        case SPai{rest, num, +off, +dat, acc}:
          match rest:
            case Nil{}:
              # the last object spans to the end of the data (7.5.7)
              osh(f2, os_ran(U32.to_nat(off), String.length(dat), Nil{}, 0, 0, String.length(dat), num, U32.to_nat(off), dat, acc))
            case Con{+n2, Con{+o2, rest2}}:
              # the next pair bounds this slice and joins the walk again
              osh(f2, os_ran(U32.to_nat(off), String.length(dat), Con{n2, Con{o2, rest2}}, n2, o2, U32.to_nat(o2), num, U32.to_nat(off), dat, acc))
            case tail3:
              DErr{"the object stream header shall contain N pairs of integers (7.5.7)"}
        case SIns{rest, n2, o2, oend, num, +offn, +dat, acc}:
          osh(f2, os_leg(os_slice_parse(os_take(Nat.sub(oend, offn), Lx.sdrop(offn, dat))), rest, num, dat, acc))

def osh_start(+dat: String, +first: U32, n: Nat) -> OSDc:
  match n:
    case 0n:
      # zero objects: nothing stored (Table 16: N counts the objects)
      DOK{Nil{}}
    case 1n+p:
      # fuel: First bytes of scan, per-pair walks (len*len bounds N*len,
      # since a pair is at least two bytes), plus headroom
      f0 : Nat = Nat.add(U32.to_nat(first), Nat.add(Nat.mul(String.length(dat), String.length(dat)), 16n))
      osh(f0, SGo{dat, dat, U32.to_nat(first), n, 0n, 0, 0n, Nil{}})

# ---- a value must be a direct non-negative integer (Table 16: N and
# First are integers). Indirect values stay unresolved in v0 (7.3.10).

def os_int(o: P.Obj) -> OSInt:
  match o:
    case P.ONum{neg, whole, fnum, fden}:
      match neg:
        case True{}:
          ISbad{}
        case False{}:
          match fnum:
            case 0n:
              ISok{whole}
            case 1n+p:
              ISbad{}
    case val2:
      ISbad{}

# ---- the object stream dictionary walk (Table 16, 7.5.7): the Type, N
# and First entries settle with their values; the Filter entry only sets
# its flag (Table 5). Extends is ignored in v0.

def xodw(els: List<&2, P.PEntry>, t: Bool, tv: P.Obj, n: Bool, nv: P.Obj, f: Bool, fv: P.Obj, l: Bool, v: P.Obj, tk: Bool, nk: Bool, fk: Bool, lk: Bool) -> OSDR:
  match els:
    case Nil{}:
      match tk:
        case True{}:
          OSDok{True{}, v, n, nv, f, fv, l}
        case False{}:
          match nk:
            case True{}:
              OSDok{t, tv, True{}, v, f, fv, l}
            case False{}:
              match fk:
                case True{}:
                  OSDok{t, tv, n, nv, True{}, v, l}
                case False{}:
                  match lk:
                    case True{}:
                      OSDok{t, tv, n, nv, f, fv, True{}}
                    case False{}:
                      OSDok{t, tv, n, nv, f, fv, l}
    case Con{P.PE{+k, +v2}, rest}:
      # the pending pair settles; the new pair becomes pending (7.3.7)
      match tk:
        case True{}:
          xodw(rest, True{}, v, n, nv, f, fv, l, v2, String.eq(k, "Type"), String.eq(k, "N"), String.eq(k, "First"), String.eq(k, "Filter"))
        case False{}:
          match nk:
            case True{}:
              xodw(rest, t, tv, True{}, v, f, fv, l, v2, String.eq(k, "Type"), String.eq(k, "N"), String.eq(k, "First"), String.eq(k, "Filter"))
            case False{}:
              match fk:
                case True{}:
                  xodw(rest, t, tv, n, nv, True{}, v, l, v2, String.eq(k, "Type"), String.eq(k, "N"), String.eq(k, "First"), String.eq(k, "Filter"))
                case False{}:
                  match lk:
                    case True{}:
                      xodw(rest, t, tv, n, nv, f, fv, True{}, v2, String.eq(k, "Type"), String.eq(k, "N"), String.eq(k, "First"), String.eq(k, "Filter"))
                    case False{}:
                      xodw(rest, t, tv, n, nv, f, fv, l, v2, String.eq(k, "Type"), String.eq(k, "N"), String.eq(k, "First"), String.eq(k, "Filter"))

# ---- Table 16 validation: the computed results ride as parameters down
# the chain; the scan runs at the bottom. DOK carries the stored objects,
# DErr the diagnostic.

def os_fb(bad: Bool, first: U32, n: U32, dat: String) -> OSDc:
  match bad:
    case True{}:
      DErr{"the First entry shall locate the first object within the stream (Table 16, 7.5.7)"}
    case False{}:
      osh_start(dat, first, U32.to_nat(n))

def os_fil(+first: U32, n: U32, fil: Bool, +dat: String) -> OSDc:
  match fil:
    case True{}:
      DErr{"object streams stored with a Filter are not supported in v0 (Table 5 Filter, 7.4)"}
    case False{}:
      os_fb(Nat.is_lt(String.length(dat), U32.to_nat(first)), first, n, dat)

def os_fc(res: OSInt, n: U32, fil: Bool, dat: String) -> OSDc:
  match res:
    case ISbad{}:
      DErr{"First shall be a non-negative integer (Table 16, 7.5.7)"}
    case ISok{first}:
      os_fil(first, n, fil, dat)

def os_f(fv: P.Obj, f: Bool, n: U32, fil: Bool, dat: String) -> OSDc:
  match f:
    case True{}:
      os_fc(os_int(fv), n, fil, dat)
    case False{}:
      DErr{"the object stream dictionary shall have a First entry (Table 16, 7.5.7)"}

def os_nc(res: OSInt, f: Bool, fv: P.Obj, fil: Bool, dat: String) -> OSDc:
  match res:
    case ISbad{}:
      DErr{"N shall be a non-negative integer (Table 16, 7.5.7)"}
    case ISok{n}:
      os_f(fv, f, n, fil, dat)

def os_n(nv: P.Obj, n: Bool, f: Bool, fv: P.Obj, fil: Bool, dat: String) -> OSDc:
  match n:
    case True{}:
      os_nc(os_int(nv), f, fv, fil, dat)
    case False{}:
      DErr{"the object stream dictionary shall have an N entry (Table 16, 7.5.7)"}

def os_vc(ok: Bool, n: Bool, nv: P.Obj, f: Bool, fv: P.Obj, fil: Bool, dat: String) -> OSDc:
  match ok:
    case True{}:
      os_n(nv, n, f, fv, fil, dat)
    case False{}:
      DErr{"the object stream dictionary shall have a Type entry with the value ObjStm (Table 16, 7.5.7)"}

def os_vt(tv: P.Obj, n: Bool, nv: P.Obj, f: Bool, fv: P.Obj, fil: Bool, dat: String) -> OSDc:
  match tv:
    case P.OName{val}:
      os_vc(String.eq(val, "ObjStm"), n, nv, f, fv, fil, dat)
    case val2:
      DErr{"the object stream dictionary shall have a Type entry with the value ObjStm (Table 16, 7.5.7)"}

def os_val(r: OSDR, dat: String) -> OSDc:
  match r:
    case OSDok{t, tv, n, nv, f, fv, fil}:
      match t:
        case True{}:
          os_vt(tv, n, nv, f, fv, fil, dat)
        case False{}:
          DErr{"the object stream dictionary shall have a Type entry with the value ObjStm (Table 16, 7.5.7)"}

# ---- the object stream decode (7.5.7): the stream object's generation
# shall be zero; the dictionary walk collects Table 16, then the scan
# and slicing run.

def os_gen(g: Nat, +o: P.Obj) -> OSDc:
  match g:
    case 0n:
      match o:
        case P.OStream{d, dat}:
          match d:
            case P.ODict{els}:
              os_val(xodw(els, False{}, P.ONil{}, False{}, P.ONil{}, False{}, P.ONil{}, False{}, P.ONil{}, False{}, False{}, False{}, False{}), dat)
            case val2:
              DErr{"the object stream dictionary shall be a direct dictionary (7.3.8.1)"}
        case val3:
          DErr{"an object stream shall be a stream object (7.5.7)"}
    case 1n+gg:
      DErr{"the generation number of an object stream shall be zero (7.5.7)"}

def os_decode(bo: P.BO) -> OSDc:
  match bo:
    case P.BO{num, gen, o}:
      os_gen(U32.to_nat(gen), o)

def bof_eq(f: Nat, a: Nat, b: Nat, +num: U32, robj: List<&2, P.BO>, bo: P.BO) -> OBF:
  match f:
    case 0n:
      OBfNo{}
    case 1n+f2:
      match a:
        case 0n:
          match b:
            case 0n:
              OBf{bo}
            case 1n+m:
              # not this one: the scan continues into the remainder
              match robj:
                case Nil{}:
                  OBfNo{}
                case Con{P.BO{+n2, +g2, +o2}, rest2}:
                  bof_eq(f2, U32.to_nat(n2), U32.to_nat(num), num, rest2, P.BO{n2, g2, o2})
        case 1n+p:
          match b:
            case 0n:
              match robj:
                case Nil{}:
                  OBfNo{}
                case Con{P.BO{+n2, +g2, +o2}, rest2}:
                  bof_eq(f2, U32.to_nat(n2), U32.to_nat(num), num, rest2, P.BO{n2, g2, o2})
            case 1n+q:
              bof_eq(f2, p, q, num, robj, bo)

# ---- object lookup by number (7.3.10: the object number identifies the
# indirect object). The equality test walks both copies down together,
# so no computed Bool is ever matched.

def bof_find(+num: U32, +robj: List<&2, P.BO>) -> OBF:
  match robj:
    case Nil{}:
      OBfNo{}
    case Con{P.BO{n, g, o}, rest}:
      bof_eq(Nat.add(Nat.mul(List.length(&2, P.BO, robj), 40n), 16n), U32.to_nat(n), U32.to_nat(num), num, rest, P.BO{n, g, o})

# ---- memo lookup (7.5.7: a stream decodes once); MHit carries the
# stream's stored objects for the position check.

def os_meq(f: Nat, a: Nat, b: Nat, +stmn: U32, memos: List<&2, OSP>, objs: List<&2, P.BO>) -> MRes:
  match f:
    case 0n:
      MMiss{}
    case 1n+f2:
      match a:
        case 0n:
          match b:
            case 0n:
              MHit{objs}
            case 1n+m:
              match memos:
                case Nil{}:
                  MMiss{}
                case Con{OSP{+stm2, +objs2}, rest2}:
                  os_meq(f2, U32.to_nat(stm2), U32.to_nat(stmn), stmn, rest2, objs2)
        case 1n+p:
          match b:
            case 0n:
              match memos:
                case Nil{}:
                  MMiss{}
                case Con{OSP{+stm2, +objs2}, rest2}:
                  os_meq(f2, U32.to_nat(stm2), U32.to_nat(stmn), stmn, rest2, objs2)
            case 1n+q:
              os_meq(f2, p, q, stmn, memos, objs)

def os_mhit(+stmn: U32, +memos: List<&2, OSP>) -> MRes:
  match memos:
    case Nil{}:
      MMiss{}
    case Con{OSP{stm, objs}, rest}:
      os_meq(Nat.add(Nat.mul(List.length(&2, OSP, memos), 40n), 16n), U32.to_nat(stm), U32.to_nat(stmn), stmn, rest, objs)

# ---- the type-2 row walk (7.5.7): each entry names its object stream; a
# stream decodes once and its stored objects join the memo table. Helpers
# ride in argument position; only this driver recurses.

def xos(f: Nat, st: XSt) -> OSRes:
  match f:
    case 0n:
      OSErr{"out of object stream pass fuel (internal)"}
    case 1n+f2:
      match st:
        case SXr{+rows, +robj, +acc}:
          match rows:
            case Nil{}:
              OSOK{acc}
            case Con{XE{num, gen, in_use, offset}, rest}:
              # classic entries keep their byte offsets (Table 15, 7.5.4)
              xos(f2, SXr{rest, robj, acc})
            case Con{XEC{num, stmn, idxn}, rest}:
              xos(f2, SXm{os_mhit(stmn, acc), stmn, idxn, rest, robj, acc})
        case SXm{mres, +stmn, idxn, rows, +robj, +acc}:
          match mres:
            case MHit{objs}:
              xos(f2, SXi{Bool.not(Nat.is_lt(U32.to_nat(idxn), List.length(&2, P.BO, objs))), rows, robj, acc})
            case MMiss{}:
              xos(f2, SXf{bof_find(stmn, robj), stmn, idxn, rows, robj, acc})
        case SXf{fr, stmn, idxn, rows, robj, acc}:
          match fr:
            case OBfNo{}:
              OSErr{"a type-2 entry names an object stream that is not present (Table 18, 7.5.8.3)"}
            case OBf{bo}:
              xos(f2, SXo{os_decode(bo), stmn, idxn, rows, robj, acc})
        case SXo{res, stmn, idxn, rows, robj, acc}:
          match res:
            case DErr{why}:
              OSErr{why}
            case DOK{+objs}:
              xos(f2, SXb{Bool.not(Nat.is_lt(U32.to_nat(idxn), List.length(&2, P.BO, objs))), stmn, objs, rows, robj, acc})
        case SXb{bad, stmn, objs, rows, robj, acc}:
          match bad:
            case True{}:
              OSErr{"the position of a type-2 entry shall fall within the object stream's stored objects (Table 18, 7.5.8.3)"}
            case False{}:
              xos(f2, SXr{rows, robj, Con{OSP{stmn, objs}, acc}})
        case SXi{bad, rows, robj, acc}:
          match bad:
            case True{}:
              OSErr{"the position of a type-2 entry shall fall within the object stream's stored objects (Table 18, 7.5.8.3)"}
            case False{}:
              xos(f2, SXr{rows, robj, acc})

# ---- the merge wrapper: every memo's stored objects join the file's
# object table; the stream dictionary remains the trailer (7.5.8.1).

def os_mcat(memos: List<&2, OSP>, +acc: List<&2, P.BO>) -> List<&2, P.BO>:
  match memos:
    case Nil{}:
      acc
    case Con{OSP{stm, objs}, rest}:
      os_mcat(rest, List.append(&2, P.BO, acc, objs))

def xs_merge2(robj: List<&2, P.BO>, rows: List<&2, XE>, d: P.Obj, sx: U32, acc: List<&2, OSP>) -> FullRes:
  FullRes{List.append(&2, P.BO, robj, os_mcat(acc, Nil{})), rows, d, sx}

def xs_merge3(robj: List<&2, P.BO>, rows: List<&2, XE>, d: P.Obj, sx: U32, res: OSRes) -> FullRes:
  match res:
    case OSErr{why}:
      FullErr{why}
    case OSOK{acc}:
      xs_merge2(robj, rows, d, sx, acc)

def xs_merge(+robj: List<&2, P.BO>, +rows: List<&2, XE>, d: P.Obj, sx: U32) -> FullRes:
  f0 : Nat = Nat.add(Nat.mul(Nat.add(llen_bo(robj), 16n), 2n), 16n)
  xs_merge3(robj, rows, d, sx, xos(f0, SXr{rows, robj, Nil{}}))
def xs_runcase(robj: List<&2, P.BO>, d: P.Obj, dat: String, sx: U32, rr: XRRes) -> FullRes:
  match rr:
    case XRErr{why}:
      FullErr{why}
    case XROk{rows}:
      # the object-stream pass merges stored objects first (7.5.7); the
      # stream dictionary doubles as the trailer (7.5.8.1)
      xs_merge(robj, rows, d, sx)


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
