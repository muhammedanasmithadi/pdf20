# content.bend — content stream operator parser (§7.8.2).

import Base
import ./lex.bend as Pdf
import ./parser.bend as P
import ./flate.bend as F
import ./xref.bend as X

# ---- types ----

type ContentOp is Data:
  COp{operands: List<&2, P.Obj>, operator: String}

type ArrRes is Data:
  ArrOk{elems: List<&2, P.Obj>, rem: List<&2, Pdf.Tok>}
  ArrErr{why: String}

type DictRes is Data:
  DictOk{entries: List<&2, P.PEntry>, rem: List<&2, Pdf.Tok>}
  DictErr{why: String}

type ContentRes is Data:
  COk{ops: List<&2, ContentOp>}
  CErr{why: String}

# ---- bytes -> String ----

def bytes_to_str_go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case Con{h, t}:
      bytes_to_str_go(t, SCon{Char.from_u32(h), acc})

def bytes_to_str(bs: List<&2, U32>) -> String:
  bytes_to_str_go(bs, SNil{})

# ---- skip helpers ----

def skip_array(toks: List<&2, Pdf.Tok>, depth: Nat) -> List<&2, Pdf.Tok>:
  match toks:
    case Nil{}:
      Nil{}
    case Con{tok, rest}:
      match tok:
        case Pdf.TArg{open}:
          match open:
            case True{}:
              skip_array(rest, Nat.add(depth, 1n))
            case False{}:
              match depth:
                case 1n:
                  rest
                case 1n+p:
                  skip_array(rest, p)
                case 0n:
                  skip_array(rest, 0n)
        case x:
          skip_array(rest, depth)

def skip_dict(toks: List<&2, Pdf.Tok>, depth: Nat) -> List<&2, Pdf.Tok>:
  match toks:
    case Nil{}:
      Nil{}
    case Con{tok, rest}:
      match tok:
        case Pdf.TDict{open}:
          match open:
            case True{}:
              skip_dict(rest, Nat.add(depth, 1n))
            case False{}:
              match depth:
                case 1n:
                  rest
                case 1n+p:
                  skip_dict(rest, p)
                case 0n:
                  skip_dict(rest, 0n)
        case x:
          skip_dict(rest, depth)

# ---- array collector (flat elements; nested arrays/dicts skipped) ----

def parse_array_go(fuel: Nat, toks: List<&2, Pdf.Tok>, +acc: List<&2, P.Obj>) -> ArrRes:
  match fuel:
    case 0n:
      ArrErr{"out of fuel in array (7.8.2)"}
    case 1n+ +fp:
      match toks:
        case Nil{}:
          ArrErr{"unterminated array in content stream (7.8.2)"}
        case Con{tok, +rest}:
          match tok:
            case Pdf.TArg{open}:
              match open:
                case True{}:
                  rem : List<&2, Pdf.Tok> = skip_array(rest, 1n)
                  parse_array_go(fp, rem, acc)
                case False{}:
                  ArrOk{List.reverse(&2, P.Obj, acc), rest}
            case Pdf.TNum{neg, whole, fnum, fden}:
              parse_array_go(fp, rest, Con{P.ONum{neg, whole, fnum, fden}, acc})
            case Pdf.TStr{val}:
              parse_array_go(fp, rest, Con{P.OStr{val}, acc})
            case Pdf.THex{val}:
              parse_array_go(fp, rest, Con{P.OStr{val}, acc})
            case Pdf.TName{+val}:
              eqt : Bool = String.eq(val, "true")
              eqf : Bool = String.eq(val, "false")
              eqn : Bool = String.eq(val, "null")
              Bool.pick(ArrRes, eqt,
                parse_array_go(fp, rest, Con{P.OBool{True{}}, acc}),
                Bool.pick(ArrRes, eqf,
                  parse_array_go(fp, rest, Con{P.OBool{False{}}, acc}),
                  Bool.pick(ArrRes, eqn,
                    parse_array_go(fp, rest, Con{P.ONil{}, acc}),
                    parse_array_go(fp, rest, Con{P.OName{val}, acc}))))
            case Pdf.TDict{open}:
              match open:
                case True{}:
                  rem : List<&2, Pdf.Tok> = skip_dict(rest, 1n)
                  parse_array_go(fp, rem, acc)
                case False{}:
                  ArrErr{"unexpected >> in array (7.8.2)"}
            case Pdf.TWord{+val}:
              parse_array_go(fp, rest, Con{P.OName{"/" ++ val}, acc})
            case Pdf.TStreamBody{dat}:
              parse_array_go(fp, rest, acc)

# ---- dict collector ----

def parse_dict_go(fuel: Nat, toks: List<&2, Pdf.Tok>, +acc: List<&2, P.PEntry>) -> DictRes:
  match fuel:
    case 0n:
      DictErr{"out of fuel in dict (7.8.2)"}
    case 1n+ +fp:
      match toks:
        case Nil{}:
          DictErr{"unterminated dictionary in content stream (7.8.2)"}
        case Con{tok, +rest}:
          match tok:
            case Pdf.TDict{open}:
              match open:
                case False{}:
                  DictOk{List.reverse(&2, P.PEntry, acc), rest}
                case True{}:
                  DictErr{"unexpected << in dictionary (7.8.2)"}
            case Pdf.TName{+key}:
              match rest:
                case Nil{}:
                  DictErr{"dictionary value missing (7.8.2)"}
                case Con{vtok, vrest}:
                  match vtok:
                    case Pdf.TNum{neg, whole, fnum, fden}:
                      parse_dict_go(fp, vrest, Con{P.PE{key, P.ONum{neg, whole, fnum, fden}}, acc})
                    case Pdf.TStr{val}:
                      parse_dict_go(fp, vrest, Con{P.PE{key, P.OStr{val}}, acc})
                    case Pdf.THex{val}:
                      parse_dict_go(fp, vrest, Con{P.PE{key, P.OStr{val}}, acc})
                    case Pdf.TName{+val}:
                      eqt : Bool = String.eq(val, "true")
                      eqf : Bool = String.eq(val, "false")
                      eqn : Bool = String.eq(val, "null")
                      Bool.pick(DictRes, eqt,
                        parse_dict_go(fp, vrest, Con{P.PE{key, P.OBool{True{}}}, acc}),
                        Bool.pick(DictRes, eqf,
                          parse_dict_go(fp, vrest, Con{P.PE{key, P.OBool{False{}}}, acc}),
                          Bool.pick(DictRes, eqn,
                            parse_dict_go(fp, vrest, Con{P.PE{key, P.ONil{}}, acc}),
                            parse_dict_go(fp, vrest, Con{P.PE{key, P.OName{val}}, acc}))))
                    case Pdf.TArg{open}:
                      match open:
                        case True{}:
                          rem : List<&2, Pdf.Tok> = skip_array(vrest, 1n)
                          parse_dict_go(fp, rem, Con{P.PE{key, P.OName{"[array]"}}, acc})
                        case False{}:
                          DictErr{"unexpected ] in dictionary (7.8.2)"}
                    case Pdf.TDict{open}:
                      match open:
                        case True{}:
                          rem : List<&2, Pdf.Tok> = skip_dict(vrest, 1n)
                          parse_dict_go(fp, rem, Con{P.PE{key, P.OName{"<<dict>>"}}, acc})
                        case False{}:
                          DictErr{"unexpected >> in dictionary (7.8.2)"}
                    case Pdf.TWord{+val}:
                      parse_dict_go(fp, vrest, Con{P.PE{key, P.OName{"/" ++ val}}, acc})
                    case Pdf.TStreamBody{dat}:
                      parse_dict_go(fp, vrest, acc)
            case Pdf.TStr{val}:
              parse_dict_go(fp, rest, acc)
            case Pdf.THex{val}:
              parse_dict_go(fp, rest, acc)
            case Pdf.TNum{neg, whole, fnum, fden}:
              parse_dict_go(fp, rest, acc)
            case Pdf.TArg{open}:
              parse_dict_go(fp, rest, acc)
            case Pdf.TDict{open}:
              parse_dict_go(fp, rest, acc)
            case Pdf.TWord{+val}:
              parse_dict_go(fp, rest, acc)
            case Pdf.TStreamBody{dat}:
              parse_dict_go(fp, rest, acc)

# ---- main content parser ----

def parse_content_go(fuel: Nat, toks: List<&2, Pdf.Tok>, +cur_ops: List<&2, P.Obj>, +ops: List<&2, ContentOp>) -> ContentRes:
  match fuel:
    case 0n:
      COk{List.reverse(&2, ContentOp, ops)}
    case 1n+ +fp:
      match toks:
        case Nil{}:
          COk{List.reverse(&2, ContentOp, ops)}
        case Con{tok, +rest}:
          match tok:
            case Pdf.TNum{neg, whole, fnum, fden}:
              parse_content_go(fp, rest, Con{P.ONum{neg, whole, fnum, fden}, cur_ops}, ops)
            case Pdf.TStr{val}:
              parse_content_go(fp, rest, Con{P.OStr{val}, cur_ops}, ops)
            case Pdf.THex{val}:
              parse_content_go(fp, rest, Con{P.OStr{val}, cur_ops}, ops)
            case Pdf.TName{+val}:
              eqt : Bool = String.eq(val, "true")
              eqf : Bool = String.eq(val, "false")
              eqn : Bool = String.eq(val, "null")
              Bool.pick(ContentRes, eqt,
                parse_content_go(fp, rest, Con{P.OBool{True{}}, cur_ops}, ops),
                Bool.pick(ContentRes, eqf,
                  parse_content_go(fp, rest, Con{P.OBool{False{}}, cur_ops}, ops),
                  Bool.pick(ContentRes, eqn,
                    parse_content_go(fp, rest, Con{P.ONil{}, cur_ops}, ops),
                    parse_content_go(fp, rest, Con{P.OName{val}, cur_ops}, ops))))
            case Pdf.TArg{open}:
              match open:
                case True{}:
                  rem : List<&2, Pdf.Tok> = skip_array(rest, 1n)
                  parse_content_go(fp, rem, Con{P.OArr{Nil{}}, cur_ops}, ops)
                case False{}:
                  CErr{"unexpected ] in content stream (7.8.2)"}
            case Pdf.TDict{open}:
              match open:
                case True{}:
                  rem : List<&2, Pdf.Tok> = skip_dict(rest, 1n)
                  parse_content_go(fp, rem, Con{P.ODict{Nil{}}, cur_ops}, ops)
                case False{}:
                  CErr{"unexpected >> in content stream (7.8.2)"}
            case Pdf.TWord{+val}:
              eqt : Bool = String.eq(val, "true")
              eqf : Bool = String.eq(val, "false")
              eqn : Bool = String.eq(val, "null")
              Bool.pick(ContentRes, eqt,
                parse_content_go(fp, rest, Con{P.OBool{True{}}, cur_ops}, ops),
                Bool.pick(ContentRes, eqf,
                  parse_content_go(fp, rest, Con{P.OBool{False{}}, cur_ops}, ops),
                  Bool.pick(ContentRes, eqn,
                    parse_content_go(fp, rest, Con{P.ONil{}, cur_ops}, ops),
                    parse_content_go(fp, rest, Nil{}, Con{COp{List.reverse(&2, P.Obj, cur_ops), val}, ops}))))
            case Pdf.TStreamBody{dat}:
              parse_content_go(fp, rest, cur_ops, ops)

def parse_content(toks: List<&2, Pdf.Tok>) -> ContentRes:
  parse_content_go(32768n, toks, Nil{}, Nil{})

# ---- report helpers ----

def content_op_count(ops: List<&2, ContentOp>, acc: Nat) -> Nat:
  match ops:
    case Nil{}: acc
    case Con{COp{operands, operator}, rest}:
      content_op_count(rest, Nat.add(acc, 1n))

def content_report(res: ContentRes) -> String:
  match res:
    case COk{ops}:
      ("CONTENT ops=" ++ Nat.show(content_op_count(ops, 0n)))
    case CErr{why}:
      ("CONTENT ERR " ++ why)

# ---- content_report_of_lex ----

def content_report_of_lex(lx: Pdf.Lex) -> String:
  match lx:
    case Pdf.Lexed{toks}:
      content_report(parse_content(toks))
    case Pdf.LexErr{why}:
      ("CONTENT LEX ERR " ++ why)

# ---- content_report_of_go ----

def content_report_of_go(objs: List<&2, P.BO>) -> String:
  match objs:
    case Nil{}:
      "CONTENT no stream found"
    case Con{P.BO{num, gen, o}, rest}:
      match o:
        case P.OStream{d, dat}:
          body : List<&2, U32> = P.str_byts(dat)
          decoded : List<&2, U32> = F.decode_stream_body(d, body)
          content_report_of_lex(Pdf.lex(decoded))
        case x:
          content_report_of_go(rest)

# ---- top-level report from a FullRes ----

def content_report_of(fr: X.FullRes) -> String:
  match fr:
    case X.FullErr{why}:
      ("CONTENT ERR " ++ why)
    case X.FullRes{objs, xref, trailer, sx}:
      content_report_of_go(objs)
