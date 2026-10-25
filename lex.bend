import Base

# pdf20 lexer — ISO 32000-2:2020 clause 7.2 (lexical conventions) and 7.3
# (syntax of objects). Bytes arrive as U32 codes in a List<&2, U32>; Bend
# has no U8.
#
# Defs bind in order, so this file is laid out dependency-first: byte
# classes, transitions (tr_*), eofout, then the single recursive toks.
# The checker refuses mutual recursion and forward references, so tr_*
# never call back; toks recurses on the Frame its transition answered
# (call-argument form). Scrutinees are always parameters or field binders,
# and tokens ending at a delimiter re-feed that byte as the new rest.

type Tok is Data:
  TNum{neg: Bool, whole: U32, fnum: Nat, fden: Nat}
  TName{val: String}
  TStr{val: String}
  THex{val: String}
  TArg{open: Bool}
  TDict{open: Bool}
  TWord{val: String}
  TStreamBody{dat: String}

type Lex is Data:
  Lexed{toks: List<&2, Tok>}
  LexErr{why: String}

# Automaton states. rev fields accumulate reversed (final String.reverse).
# StCR eats a raw CR and normalizes to LF; StEsc* handle Table 3 escapes.
type St is Data:
  StTop{}
  StCom{}
  StLt{}
  StGt{}
  StDot{neg: Bool}
  StSign{neg: Bool}
  StNum{neg: Bool, whole: U32, phase: Bool, fnum: Nat, fden: Nat}
  StWord{rev: String}
  StName{rev: String}
  StHash{rev: String}
  StHash1{rev: String, hi: U32}
  StStr{depth: U32, rev: String}
  StEsc{depth: U32, rev: String}
  StEscCR{depth: U32, rev: String}
  StCR{depth: U32, rev: String}
  StOct1{depth: U32, rev: String, ov: U32}
  StOct2{depth: U32, rev: String, ov: U32}
  StHex{pend: Maybe<&2, U32>, rev: String}
  StWantEOL{}
  StSkipBody{rev: String, depth: Nat}
  StErr{why: String}

type Frame is Data:
  Frame{rest: List<&2, U32>, st: St, acc: List<&2, Tok>}

# ---- byte classes (7.2 / Table 3)
def is_ws(+b: U32) -> Bool:
  (U32.is_eq(b, 0) || U32.is_eq(b, 9) || U32.is_eq(b, 10) || U32.is_eq(b, 12) || U32.is_eq(b, 13) || U32.is_eq(b, 32))

def is_delim(+b: U32) -> Bool:
  (U32.is_eq(b, 40) || U32.is_eq(b, 41) || U32.is_eq(b, 60) || U32.is_eq(b, 62) || U32.is_eq(b, 91) || U32.is_eq(b, 93) || U32.is_eq(b, 123) || U32.is_eq(b, 125) || U32.is_eq(b, 47) || U32.is_eq(b, 37))

def is_digit(+b: U32) -> Bool:
  (U32.is_lt(47, b) && U32.is_lt(b, 58))

def is_octd(+b: U32) -> Bool:
  (U32.is_lt(47, b) && U32.is_lt(b, 56))

def is_hd(+b: U32) -> Bool:
  ((U32.is_lt(47, b) && U32.is_lt(b, 58)) || (U32.is_lt(64, b) && U32.is_lt(b, 71)) || (U32.is_lt(96, b) && U32.is_lt(b, 103)))

def negb(x: Bool) -> Bool:
  match x:
    case True{}:
      False{}
    case False{}:
      True{}

def is_wordch(+b: U32) -> Bool:
  negb((is_ws(b) || is_delim(b)))

def digv(b: U32) -> U32:
  U32.sub(b, 48)

def hexval(zdig: Bool, zlow: Bool, b: U32) -> U32:
  match zdig:
    case True{}:
      digv(b)
    case False{}:
      match zlow:
        case True{}:
          U32.sub(b, 87)
        case False{}:
          U32.sub(b, 55)

def hexv(+b: U32) -> U32:
  hexval(is_digit(b), U32.is_lt(83, b), b)

# ---- transitions: one def per state, non-recursive, answer the next Frame

def ttop(zws: Bool, z37: Bool, z40: Bool, z47: Bool, z60: Bool, z62: Bool, z91: Bool, z93: Bool, z123: Bool, z125: Bool, z43: Bool, z45: Bool, z46: Bool, zdig: Bool, zwordch: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zws:
    case True{}:
      Frame{t, StTop{}, acc}
    case False{}:
      match z37:
        case True{}:
          Frame{t, StCom{}, acc}
        case False{}:
          match z40:
            case True{}:
              Frame{t, StStr{1, SNil{}}, acc}
            case False{}:
              match z47:
                case True{}:
                  Frame{t, StName{SNil{}}, acc}
                case False{}:
                  match z60:
                    case True{}:
                      Frame{t, StLt{}, acc}
                    case False{}:
                      match z62:
                        case True{}:
                          Frame{t, StGt{}, acc}
                        case False{}:
                          match z91:
                            case True{}:
                              Frame{t, StTop{}, Con{TArg{True{}}, acc}}
                            case False{}:
                              match z93:
                                case True{}:
                                  Frame{t, StTop{}, Con{TArg{False{}}, acc}}
                                case False{}:
                                  match z123:
                                    case True{}:
                                      Frame{t, StErr{"bad brace in file syntax"}, acc}
                                    case False{}:
                                      match z125:
                                        case True{}:
                                          Frame{t, StErr{"bad brace in file syntax"}, acc}
                                        case False{}:
                                          match z43:
                                            case True{}:
                                              Frame{t, StSign{False{}}, acc}
                                            case False{}:
                                              match z45:
                                                case True{}:
                                                  Frame{t, StSign{True{}}, acc}
                                                case False{}:
                                                  match z46:
                                                    case True{}:
                                                      Frame{t, StDot{False{}}, acc}
                                                    case False{}:
                                                      match zdig:
                                                        case True{}:
                                                          Frame{t, StNum{False{}, digv(b), True{}, 0n, 1n}, acc}
                                                        case False{}:
                                                          match zwordch:
                                                            case True{}:
                                                              Frame{t, StWord{SCon{Char.from_u32(b), SNil{}}}, acc}
                                                            case False{}:
                                                              Frame{t, StErr{"bad file byte"}, acc}

def tcom(znl: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match znl:
    case True{}:
      Frame{t, StTop{}, acc}
    case False{}:
      Frame{t, StCom{}, acc}

def tlt(zhd: Bool, z60: Bool, z62: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zhd:
    case True{}:
      Frame{t, StHex{Some{hexv(b)}, SNil{}}, acc}
    case False{}:
      match z60:
        case True{}:
          # "<<" — dictionary opens (7.3.8.1); resume at StTop for the body
          Frame{t, StTop{}, Con{TDict{True{}}, acc}}
        case False{}:
          match z62:
            case True{}:
              # "<>" — empty hex string (7.3.4.2)
              Frame{t, StTop{}, Con{THex{SNil{}}, acc}}
            case False{}:
              Frame{t, StErr{"bad lt sequence"}, acc}

def tgt(z62: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match z62:
    case True{}:
      Frame{t, StTop{}, Con{TDict{False{}}, acc}}
    case False{}:
      Frame{t, StErr{"stray gt"}, acc}

def tdot(zdig: Bool, neg: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zdig:
    case True{}:
      Frame{t, StNum{neg, 0, False{}, U32.to_nat(digv(b)), 10n}, acc}
    case False{}:
      Frame{t, StErr{"dot without digit"}, acc}

def tsign(zdig: Bool, zdot: Bool, neg: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zdig:
    case True{}:
      Frame{t, StNum{neg, digv(b), True{}, 0n, 1n}, acc}
    case False{}:
      match zdot:
        case True{}:
          Frame{t, StDot{neg}, acc}
        case False{}:
          Frame{t, StErr{"sign without number"}, acc}

def tnum(zdig: Bool, zdot: Bool, neg: Bool, whole: U32, phase: Bool, fnum: Nat, fden: Nat, dv: U32, dnat: Nat, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zdig:
    case True{}:
      match phase:
        case True{}:
          Frame{t, StNum{neg, U32.add(U32.mul(whole, 10), dv), True{}, fnum, fden}, acc}
        case False{}:
          Frame{t, StNum{neg, whole, False{}, Nat.add(Nat.mul(fnum, 10n), dnat), Nat.mul(fden, 10n)}, acc}
    case False{}:
      match zdot:
        case True{}:
          match phase:
            case True{}:
              Frame{t, StNum{neg, whole, False{}, fnum, fden}, acc}
            case False{}:
              # "5." — real without fraction digits: emit, readd the dot
              Frame{Con{b, t}, StTop{}, Con{TNum{neg, whole, fnum, fden}, acc}}
        case False{}:
          # token ends at a non-number byte: readd that byte at top
          Frame{Con{b, t}, StTop{}, Con{TNum{neg, whole, fnum, fden}, acc}}
def tword_stream(zs: Bool, +fwd: String, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match zs:
    case True{}:
      Frame{Con{b, t}, StWantEOL{}, Con{TWord{"stream"}, acc}}
    case False{}:
      Frame{Con{b, t}, StTop{}, Con{TWord{fwd}, acc}}

# StWantEOL: the byte after `stream` shall be a LF, or CR+LF — never a
# CARRIAGE RETURN alone (7.3.8.1)


def tword_fwd(+fwd: String, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  tword_stream(String.eq(fwd, "stream"), fwd, b, t, acc)

# only `stream` changes state: an end-of-line marker is next (7.3.8.1);
# every other word emits normally


def tword(zwordch: Bool, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zwordch:
    case True{}:
      Frame{t, StWord{SCon{Char.from_u32(b), rev}}, acc}
    case False{}:
      # word end: reverse once, then route the whole word (7.3.8.1)
      tword_fwd(String.reverse(rev), b, t, acc)

# the completed word is a param, so the stream check can ride beside it




def tws_crl(z10: Bool, t2: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match z10:
    case True{}:
      Frame{t2, StSkipBody{SNil{}, 0n}, acc}
    case False{}:
      Frame{t2, StErr{"carriage return alone after stream keyword (7.3.8.1)"}, acc}

# drop the first n characters of a string (reversed accumulator)



def tws_cr(t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match t:
    case Nil{}:
      Frame{t, StErr{"carriage return alone after stream keyword (7.3.8.1)"}, acc}
    case Con{b2, t2}:
      tws_crl(U32.is_eq(b2, 10), t2, acc)



def tws(z10: Bool, z13: Bool, b: U32, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  match z10:
    case True{}:
      Frame{t, StSkipBody{SNil{}, 0n}, acc}
    case False{}:
      match z13:
        case True{}:
          tws_cr(t, acc)
        case False{}:
          Frame{t, StErr{"no end-of-line marker after stream keyword (7.3.8.1)"}, acc}

# after a raw CR, the LF is required; anything else is CR alone,
# which 7.3.8.1 explicitly forbids



def sdrop(n: Nat, +s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+p:
      match s:
        case SNil{}:
          SNil{}
        case SCon{h, tl}:
          sdrop(p, tl)

# ---- StSkipBody: consume stream data opaquely until the endstream
# sequence (end-of-line after stream already consumed per 7.3.8.1).
# depth = how many bytes of the matched prefix are seen (0..8); a
# mismatch re-seeds at depth 1 when the byte is 'e' (101), else 0.
# The matched bytes accumulate into rev and are trimmed at completion.



# completion: body first, then endstream, both prepended in that order

def tsb_done(+dat: String, t: List<&2, U32>, acc: List<&2, Tok>) -> Frame:
  # nest BODY below endstream so the emission order is body then keyword
  Frame{t, StTop{}, Con{TWord{"endstream"}, Con{TStreamBody{dat}, acc}}}

def tsb_end(zc: Bool, zez: Bool, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zc:
    case True{}:
      tsb_done(String.reverse(sdrop(8n, rev)), t, acc)
    case False{}:
      match zez:
        case True{}:
          Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, 1n}, acc}
        case False{}:
          Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, 0n}, acc}

# completion: body first, then endstream, both prepended in that order



def tsb_go(zc: Bool, zez: Bool, dnext: Nat, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zc:
    case True{}:
      Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, dnext}, acc}
    case False{}:
      match zez:
        case True{}:
          Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, 1n}, acc}
        case False{}:
          Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, 0n}, acc}

# at depth 8 a match completes: the 8 accumulated match chars leave rev,
# the body token is emitted with the endstream word after it, and the
# walk resumes at top level on the bytes past the match



def tsb(depth: Nat, +b: U32, t: List<&2, U32>, +rev: String, acc: List<&2, Tok>) -> Frame:
  match depth:
    case 0n:
      tsb_go(U32.is_eq(b, 101), U32.is_eq(b, 101), 1n, b, t, rev, acc)
    case 1n:
      tsb_go(U32.is_eq(b, 110), U32.is_eq(b, 101), 2n, b, t, rev, acc)
    case 2n:
      tsb_go(U32.is_eq(b, 100), U32.is_eq(b, 101), 3n, b, t, rev, acc)
    case 3n:
      tsb_go(U32.is_eq(b, 115), U32.is_eq(b, 101), 4n, b, t, rev, acc)
    case 4n:
      tsb_go(U32.is_eq(b, 116), U32.is_eq(b, 101), 5n, b, t, rev, acc)
    case 5n:
      tsb_go(U32.is_eq(b, 114), U32.is_eq(b, 101), 6n, b, t, rev, acc)
    case 6n:
      tsb_go(U32.is_eq(b, 101), U32.is_eq(b, 101), 7n, b, t, rev, acc)
    case 7n:
      tsb_go(U32.is_eq(b, 97), U32.is_eq(b, 101), 8n, b, t, rev, acc)
    case 8n:
      tsb_end(U32.is_eq(b, 109), U32.is_eq(b, 101), b, t, rev, acc)
    case 1n+p:
      # depth never exceeds 8 (completion resets to StTop); keep the
      # match exhaustive with a safe no-op
      Frame{t, StSkipBody{SCon{Char.from_u32(b), rev}, 0n}, acc}



def tname(zwordch: Bool, z35: Bool, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zwordch:
    case True{}:
      match z35:
        case True{}:
          Frame{t, StHash{rev}, acc}
        case False{}:
          Frame{t, StName{SCon{Char.from_u32(b), rev}}, acc}
    case False{}:
      Frame{Con{b, t}, StTop{}, Con{TName{String.reverse(rev)}, acc}}

def thash(zhd: Bool, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zhd:
    case True{}:
      Frame{t, StHash1{rev, hexv(b)}, acc}
    case False{}:
      Frame{t, StErr{"hash without two hex digits"}, acc}

def thash1(zhd: Bool, hi: U32, b: U32, t: List<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zhd:
    case True{}:
      Frame{t, StName{SCon{Char.from_u32(U32.add(U32.mul(hi, 16), hexv(b))), rev}}, acc}
    case False{}:
      Frame{t, StErr{"hash without second hex digit"}, acc}

def tstr(z92: Bool, z40: Bool, z41: Bool, zdeep: Bool, z13: Bool, z10: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, acc: List<&2, Tok>) -> Frame:
  match z92:
    case True{}:
      Frame{t, StEsc{depth, rev}, acc}
    case False{}:
      match z40:
        case True{}:
          Frame{t, StStr{U32.add(depth, 1), SCon{Char.from_u32(b), rev}}, acc}
        case False{}:
          match z41:
            case True{}:
              match zdeep:
                case True{}:
                  Frame{t, StTop{}, Con{TStr{String.reverse(rev)}, acc}}
                case False{}:
                  Frame{t, StStr{U32.sub(depth, 1), SCon{Char.from_u32(b), rev}}, acc}
            case False{}:
              match z13:
                case True{}:
                  Frame{t, StCR{depth, rev}, acc}
                case False{}:
                  match z10:
                    case True{}:
                      Frame{t, StStr{depth, SCon{Char.from_u32(10), rev}}, acc}
                    case False{}:
                      Frame{t, StStr{depth, SCon{Char.from_u32(b), rev}}, acc}

# after a backslash: the escape byte itself (Table 3)
def tesc(z110: Bool, z114: Bool, z116: Bool, z98: Bool, z102: Bool, z40: Bool, z41: Bool, z92: Bool, z13: Bool, z10: Bool, zoct: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, acc: List<&2, Tok>) -> Frame:
  match z110:
    case True{}:
      # "\<n>" — newline enters the string (Table 3)
      Frame{t, StStr{depth, SCon{Char.from_u32(10), rev}}, acc}
    case False{}:
      match z114:
        case True{}:
          Frame{t, StEscCR{depth, rev}, acc}
        case False{}:
          match z116:
            case True{}:
              Frame{t, StStr{depth, SCon{Char.from_u32(9), rev}}, acc}
            case False{}:
              match z98:
                case True{}:
                  Frame{t, StStr{depth, SCon{Char.from_u32(8), rev}}, acc}
                case False{}:
                  match z102:
                    case True{}:
                      Frame{t, StStr{depth, SCon{Char.from_u32(12), rev}}, acc}
                    case False{}:
                      match z40:
                        case True{}:
                          Frame{t, StStr{depth, SCon{Char.from_u32(40), rev}}, acc}
                        case False{}:
                          match z41:
                            case True{}:
                              Frame{t, StStr{depth, SCon{Char.from_u32(41), rev}}, acc}
                            case False{}:
                              match z92:
                                case True{}:
                                  Frame{t, StStr{depth, SCon{Char.from_u32(92), rev}}, acc}
                                case False{}:
                                  match z13:
                                    case True{}:
                                      Frame{t, StEscCR{depth, rev}, acc}
                                    case False{}:
                                      match z10:
                                        case True{}:
                                          Frame{t, StStr{depth, rev}, acc}
                                        case False{}:
                                          match zoct:
                                            case True{}:
                                              Frame{t, StOct1{depth, rev, digv(b)}, acc}
                                            case False{}:
                                              Frame{t, StStr{depth, SCon{Char.from_u32(b), rev}}, acc}

# after backslash-CR: an optional LF is dropped, anything else is readd
def tecr(z10: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, acc: List<&2, Tok>) -> Frame:
  match z10:
    case True{}:
      Frame{t, StStr{depth, rev}, acc}
    case False{}:
      Frame{Con{b, t}, StStr{depth, rev}, acc}

# after a raw CR: CRLF collapses to one LF, a lone CR stays one LF
def tcr(z10: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, acc: List<&2, Tok>) -> Frame:
  match z10:
    case True{}:
      Frame{t, StStr{depth, SCon{Char.from_u32(10), rev}}, acc}
    case False{}:
      Frame{Con{b, t}, StStr{depth, SCon{Char.from_u32(10), rev}}, acc}

def toct1(zoct: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, ov: U32, acc: List<&2, Tok>) -> Frame:
  match zoct:
    case True{}:
      Frame{t, StOct2{depth, rev, U32.add(U32.mul(ov, 8), digv(b))}, acc}
    case False{}:
      Frame{Con{b, t}, StStr{depth, SCon{Char.from_u32(ov), rev}}, acc}

def toct2(zoct: Bool, b: U32, t: List<&2, U32>, depth: U32, rev: String, ov: U32, acc: List<&2, Tok>) -> Frame:
  match zoct:
    case True{}:
      Frame{t, StStr{depth, SCon{Char.from_u32(U32.add(U32.mul(ov, 8), digv(b))), rev}}, acc}
    case False{}:
      Frame{Con{b, t}, StStr{depth, SCon{Char.from_u32(ov), rev}}, acc}

def thex(zhd: Bool, z62: Bool, zws: Bool, b: U32, t: List<&2, U32>, pend: Maybe<&2, U32>, rev: String, acc: List<&2, Tok>) -> Frame:
  match zhd:
    case True{}:
      match pend:
        case None{}:
          Frame{t, StHex{Some{hexv(b)}, rev}, acc}
        case Some{h}:
          Frame{t, StHex{None{}, SCon{Char.from_u32(U32.add(U32.mul(h, 16), hexv(b))), rev}}, acc}
    case False{}:
      match z62:
        case True{}:
          match pend:
            case None{}:
              Frame{t, StTop{}, Con{THex{String.reverse(rev)}, acc}}
            case Some{h}:
              # odd digit count: low nibble is 0
              Frame{t, StTop{}, Con{THex{String.reverse(SCon{Char.from_u32(U32.mul(h, 16)), rev})}, acc}}
        case False{}:
          match zws:
            case True{}:
              Frame{t, StHex{pend, rev}, acc}
            case False{}:
              Frame{t, StErr{"bad hex string byte"}, acc}

# ---- EOF per state
def eofout(st: St, acc: List<&2, Tok>) -> Lex:
  match st:
    case StTop{}:
      Lexed{List.reverse(&2, Tok, acc)}
    case StCom{}:
      Lexed{List.reverse(&2, Tok, acc)}
    case StLt{}:
      LexErr{"unterminated lt"}
    case StGt{}:
      LexErr{"stray gt"}
    case StDot{x}:
      LexErr{"dot without digit"}
    case StSign{x}:
      LexErr{"sign without number"}
    case StNum{neg, whole, phase, fnum, fden}:
      Lexed{List.reverse(&2, Tok, Con{TNum{neg, whole, fnum, fden}, acc})}
    case StWord{rev}:
      Lexed{List.reverse(&2, Tok, Con{TWord{String.reverse(rev)}, acc})}
    case StName{rev}:
      Lexed{List.reverse(&2, Tok, Con{TName{String.reverse(rev)}, acc})}
    case StHash{rev}:
      LexErr{"hash without two hex digits"}
    case StHash1{rev, hi}:
      LexErr{"hash without second hex digit"}
    case StStr{depth, rev}:
      LexErr{"unterminated string"}
    case StEsc{depth, rev}:
      LexErr{"unterminated string"}
    case StEscCR{depth, rev}:
      LexErr{"unterminated string"}
    case StCR{depth, rev}:
      Lexed{List.reverse(&2, Tok, Con{TStr{String.reverse(SCon{Char.from_u32(10), rev})}, acc})}
    case StOct1{depth, rev, ov}:
      LexErr{"unterminated string"}
    case StOct2{depth, rev, ov}:
      LexErr{"unterminated string"}
    case StHex{pend, rev}:
      LexErr{"unterminated hex string"}
    case StWantEOL{}:
      LexErr{"no end-of-line marker after stream keyword (7.3.8.1)"}
    case StSkipBody{rev, depth}:
      LexErr{"stream body not terminated by endstream (7.3.8.1)"}
    case StErr{why}:
      LexErr{why}

# ---- the single recursive automaton. One recursion per state transition;
# fuel counts the byte budget twice over (a byte can pass through one
# token-emit and one refeed). Exhaustion is diagnostic, never silent.
def toks(fuel: Nat, r: Frame) -> Lex:
  match fuel:
    case 0n:
      LexErr{"out of lexer fuel"}
    case 1n+p:
      match r:
        case Frame{rest, st, acc}:
          match rest:
            case Nil{}:
              eofout(st, acc)
            case Con{+b, t}:
              match st:
                case StTop{}:
                  toks(p, ttop(is_ws(b), U32.is_eq(b, 37), U32.is_eq(b, 40), U32.is_eq(b, 47), U32.is_eq(b, 60), U32.is_eq(b, 62), U32.is_eq(b, 91), U32.is_eq(b, 93), U32.is_eq(b, 123), U32.is_eq(b, 125), U32.is_eq(b, 43), U32.is_eq(b, 45), U32.is_eq(b, 46), is_digit(b), is_wordch(b), b, t, acc))
                case StCom{}:
                  toks(p, tcom((U32.is_eq(b, 10) || U32.is_eq(b, 13)), b, t, acc))
                case StLt{}:
                  toks(p, tlt(is_hd(b), U32.is_eq(b, 60), U32.is_eq(b, 62), b, t, acc))
                case StGt{}:
                  toks(p, tgt(U32.is_eq(b, 62), b, t, acc))
                case StDot{neg}:
                  toks(p, tdot(is_digit(b), neg, b, t, acc))
                case StSign{neg}:
                  toks(p, tsign(is_digit(b), U32.is_eq(b, 46), neg, b, t, acc))
                case StNum{neg, whole, phase, fnum, fden}:
                  toks(p, tnum(is_digit(b), U32.is_eq(b, 46), neg, whole, phase, fnum, fden, digv(b), U32.to_nat(digv(b)), b, t, acc))
                case StWord{rev}:
                  toks(p, tword(is_wordch(b), b, t, rev, acc))
                case StName{rev}:
                  toks(p, tname(is_wordch(b), U32.is_eq(b, 35), b, t, rev, acc))
                case StHash{rev}:
                  toks(p, thash(is_hd(b), b, t, rev, acc))
                case StHash1{rev, hi}:
                  toks(p, thash1(is_hd(b), hi, b, t, rev, acc))
                case StStr{+depth, rev}:
                  toks(p, tstr(U32.is_eq(b, 92), U32.is_eq(b, 40), U32.is_eq(b, 41), U32.is_eq(depth, 1), U32.is_eq(b, 13), U32.is_eq(b, 10), b, t, depth, rev, acc))
                case StEsc{depth, rev}:
                  toks(p, tesc(U32.is_eq(b, 110), U32.is_eq(b, 114), U32.is_eq(b, 116), U32.is_eq(b, 98), U32.is_eq(b, 102), U32.is_eq(b, 40), U32.is_eq(b, 41), U32.is_eq(b, 92), U32.is_eq(b, 13), U32.is_eq(b, 10), is_octd(b), b, t, depth, rev, acc))
                case StEscCR{depth, rev}:
                  toks(p, tecr(U32.is_eq(b, 10), b, t, depth, rev, acc))
                case StCR{depth, rev}:
                  toks(p, tcr(U32.is_eq(b, 10), b, t, depth, rev, acc))
                case StOct1{depth, rev, ov}:
                  toks(p, toct1(is_octd(b), b, t, depth, rev, ov, acc))
                case StOct2{depth, rev, ov}:
                  toks(p, toct2(is_octd(b), b, t, depth, rev, ov, acc))
                case StHex{pend, rev}:
                  toks(p, thex(is_hd(b), U32.is_eq(b, 62), is_ws(b), b, t, pend, rev, acc))
                case StWantEOL{}:
                  toks(p, tws(U32.is_eq(b, 10), U32.is_eq(b, 13), b, t, acc))
                case StSkipBody{rev, depth}:
                  toks(p, tsb(depth, b, t, rev, acc))
                case StErr{why}:
                  LexErr{why}

# ---- entry
def lex(+bytes: List<&2, U32>) -> Lex:
  toks(Nat.add(Nat.mul(List.length(&2, U32, bytes), 2n), 8n), Frame{bytes, StTop{}, Nil{}})
