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
# xref_parse (xref table + startxref). Returns XRes.

def xfile(px: P.PlxFull) -> XRes:
  match px:
    case P.PlxFull{pr, rem}:
      match pr:
        case P.PCut{o}:
          xref_parse(rem)
        case P.POks{o}:
          XErr{"no xref section found (7.5.4)"}
        case P.PErr{why}:
          XErr{why}

# xfile_bytes: full file parse from raw bytes

def xfile_bytes(bytes: List<&2, U32>) -> XRes:
  xfile(P.plx_full(Lx.lex(bytes)))


