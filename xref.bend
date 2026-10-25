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
        case Some{P.PCut{bos}}:
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

def xfile(px: P.PlxFull) -> FullRes:
  match px:
    case P.PlxFull{pr, +rem}:
      match pr:
        case P.PCut{objs}:
          xfile_two(xref_parse(rem), rem, objs)
        case P.POks{objs}:
          FullErr{"no xref section found (7.5.4)"}
        case P.PErr{why}:
          FullErr{why}

# xfile_bytes: full file parse from raw bytes

def xfile_bytes(bytes: List<&2, U32>) -> FullRes:
  xfile(P.plx_full(Lx.lex(bytes)))
