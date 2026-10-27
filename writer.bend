# writer.bend — structural PDF writer (v0.3). Canonical re-serialization of
# the parsed object graph; not bit-precise. Emits header, all indirect
# objects (later-wins merge across incremental-update sections) with
# byte-offset tracking, xref subsections per contiguous object run, trailer,
# startxref and %%EOF. CLI: writer.bend <input.pdf> <output.pdf> — the
# output file is written with File.write_bytes, byte for byte.
# Note: the header binary-comment is ASCII-only (Bend has no \xff escapes),
# so strict 7.5.2 "binary marker" conformance is a known v0.1 deviation.

import Base
import ./lex.bend as Lx
import ./parser.bend as P
import ./xref.bend as X

# ---- string building ----

def str_append(a: String, b: String) -> String:
  match a:
    case SNil{}: b
    case SCon{h, t}: SCon{h, str_append(t, b)}

def cat(strs: List<&2, String>) -> String:
  match strs:
    case Nil{}: SNil{}
    case Con{h, t}: str_append(h, cat(t))

# length, counting a bounded fuel (rows/entries are tiny)
def str_len(+fuel: Nat, +s: String) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+fp:
      match s:
        case SNil{}: 0n
        case SCon{h, t}: Nat.add(1n, str_len(fp, t))

# a String kept together with its byte length
type SLK is Data:
  SLK{len: Nat, str: String}

def slk_of(+fuel: Nat, +s: String) -> SLK:
  SLK{str_len(fuel, s), s}

# zero-pad on the left to exact width w (deficit floors at 0 via Nat.sub)
def pad_left(+fuel: Nat, +d: Nat, +c: Char, +s: String) -> String:
  match fuel:
    case 0n: s
    case 1n+fp:
      match d:
        case 0n: s
        case 1n+dp: pad_left(fp, dp, c, SCon{c, s})

def pad_go(+w: Nat, +c: Char, +slk: SLK) -> String:
  match slk:
    case SLK{wl, s}:
      pad_left(32n, Nat.sub(w, wl), c, s)

def pad_str(+w: Nat, +c: Char, +s: String) -> String:
  pad_go(w, c, slk_of(32n, s))

# ---- number to decimal digits ----

def u32_show(+n: U32) -> String:
  U32.show(n)

def u32_pad(+w: Nat, +n: U32) -> String:
  pad_str(w, '0', u32_show(n))

# ---- string emission (7.3.4): literal for plain printable bytes, hex
# otherwise. The parser hands us decoded byte values, so a raw literal
# re-emission is only sound when every byte is printable ASCII and none
# is a string special ( ( ) \ ); binary bytes go out in the hex form.

def char_bin(+v: U32) -> Bool:
  Bool.or(U32.is_le(v, 31), Bool.or(U32.is_ge(v, 127), Bool.or(U32.is_eq(v, 40), Bool.or(U32.is_eq(v, 41), U32.is_eq(v, 92)))))

def char_bin_of(+h: Char) -> Bool:
  char_bin(Char.to_u32(h))

def str_binchk(+fuel: Nat, +s: String, +acc: Bool) -> Bool:
  match fuel:
    case 0n: acc
    case 1n+fp:
      match s:
        case SNil{}: acc
        case SCon{h, t}: str_binchk(fp, t, Bool.or(acc, char_bin_of(h)))

def hex_c_route(+d: U32, +lt: Bool) -> Char:
  match lt:
    case True{}: Char.from_u32(U32.add(48, d))
    case False{}: Char.from_u32(U32.add(55, d))

def hex_c(+d: U32) -> Char:
  hex_c_route(d, U32.is_lt(d, 10))

def hex_dig(+d: U32) -> String:
  SCon{hex_c(d), SNil{}}

def hex_split(qr: Nat & Nat) -> String:
  (q, r) = qr
  str_append(hex_dig(U32.from_nat(q)), hex_dig(U32.from_nat(r)))

def hex_pair(+v: Nat) -> String:
  hex_split(Nat.divmod(v, 16n))

def hex2(+c: Char) -> String:
  hex_pair(U32.to_nat(Char.to_u32(c)))

def hex_str(+fuel: Nat, +val: String) -> String:
  match fuel:
    case 0n: SNil{}
    case 1n+fp:
      match val:
        case SNil{}: SNil{}
        case SCon{h, t}: str_append(hex2(h), hex_str(fp, t))

def ser_str_lit(+fuel: Nat, +val: String) -> String:
  SCon{'(', str_append(val, ")")}

def ser_str_hex(+fuel: Nat, +val: String) -> String:
  SCon{'<', str_append(hex_str(fuel, val), ">")}

def ser_str_pick(+fuel: Nat, +bin: Bool, +val: String) -> String:
  match bin:
    case True{}: ser_str_hex(fuel, val)
    case False{}: ser_str_lit(fuel, val)

def ser_str_bin(+fuel: Nat, +val: String) -> String:
  ser_str_pick(fuel, str_binchk(4096n, val, False{}), val)

# ---- ser: object model to text (v0 core; SIDict spacing fixed, stream body added) ----

type SerInput is Data:
  SIObj{o: P.Obj}
  SIList{els: List<&2, P.Obj>}
  SIDict{els: List<&2, P.PEntry>}

def ser_num_pos(whole: U32, fnum: Nat, fden: Nat) -> String:
  match fnum:
    case 0n:
      U32.show(whole)
    case 1n+p:
      str_append(U32.show(whole), SCon{'.', Nat.show(fnum)})

def ser_num(neg: Bool, whole: U32, fnum: Nat, fden: Nat) -> String:
  match neg:
    case True{}:
      SCon{'-', ser_num_pos(whole, fnum, fden)}
    case False{}:
      ser_num_pos(whole, fnum, fden)

# stream tail (7.3.8.1: one end-of-line marker between the body and
# endstream, not part of either): the separating EOL is needed only when the
# body itself does not end with one; bodies that already end in LF/CR keep
# their own terminator so the lex round trip recovers the body byte-exactly
def s_eol_e(+h: Char) -> Bool:
  U32.is_eq(Char.to_u32(h), 10)

def s_eol_r(+h: Char) -> Bool:
  U32.is_eq(Char.to_u32(h), 13)

def s_eol_ckr(+nl: Bool, +cr: Bool) -> String:
  match nl:
    case True{}:
      "endstream\n"
    case False{}:
      match cr:
        case True{}:
          "endstream\n"
        case False{}:
          "\nendstream\n"

def s_eol_tail2(+rev: String) -> String:
  match rev:
    case SNil{}:
      "\nendstream\n"
    case SCon{+h, t}:
      s_eol_ckr(s_eol_e(h), s_eol_r(h))

def bool_kw(+b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def ser(+fuel: Nat, inp: SerInput) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+fp:
      match inp:
        case SIObj{o}:
          match o:
            case P.ONil{}:
              "null"
            case P.OBool{b}:
              bool_kw(b)
            case P.ONum{neg, whole, fnum, fden}:
              ser_num(neg, whole, fnum, fden)
            case P.OName{val}:
              SCon{'/', val}
            case P.OStr{val}:
              ser_str_bin(fp, val)
            case P.OArr{els}:
              SCon{'[', str_append(ser(fp, SIList{els}), "]")}
            case P.ODict{+els}:
              str_append("<< ", str_append(ser(fp, SIDict{els}), " >>"))
            case P.OInd{num, gen}:
              str_append(str_append(U32.show(num), " "), str_append(U32.show(gen), " R"))
            case P.OStream{d, +dat}:
              str_append(str_append(str_append(ser(fp, SIObj{d}), " stream\n"), dat), s_eol_tail2(String.reverse(dat)))
        case SIList{els}:
          match els:
            case Nil{}: SNil{}
            case Con{h, Nil{}}: ser(fp, SIObj{h})
            case Con{h, t}: str_append(str_append(ser(fp, SIObj{h}), " "), ser(fp, SIList{t}))
        case SIDict{els}:
          match els:
            case Nil{}: SNil{}
            case Con{P.PE{k, v}, Nil{}}:
              str_append(str_append(str_append("/", k), " "), ser(fp, SIObj{v}))
            case Con{P.PE{k, v}, rest}:
              str_append(str_append(str_append(str_append("/", k), " "), ser(fp, SIObj{v})), str_append(" ", ser(fp, SIDict{rest})))

# ---- offset-tracked object walk ----

# one full indirect object: "num gen obj\n" + body + "\nendobj\n"
def entry_of(+fuel: Nat, +num: U32, +gen: U32, +o: P.Obj) -> String:
  str_append(str_append(str_append(u32_show(num), " "), str_append(u32_show(gen), " obj\n")), str_append(ser(fuel, SIObj{o}), "\nendobj\n"))

# 10-digit offset + gen digits + type marker, exactly 20 bytes
def row_of(+off: U32, +gen5: String) -> String:
  str_append(str_append(u32_pad(10n, off), " "), str_append(gen5, " n \n"))

# xref row carried together with its object number (7.5.4 subsections)
type BRow is Data:
  BRow{num: U32, row: String}

type BSt is Data:
  BM0{bos: List<&2, P.BO>, off: U32}
  BM1{num: U32, slk: SLK, gen5: String, off: U32, rest: List<&2, P.BO>}

type BOut is Data:
  BOut{out: String, rows: List<&2, BRow>, cnt: U32, sx: U32}

# prepends the entry to the output body and the row to the xref rows
def bo_join(+wr: BOut, +row: BRow, +ec: String) -> BOut:
  match wr:
    case BOut{out, rows, cnt, sx}:
      BOut{str_append(ec, out), Con{row, rows}, U32.add(cnt, U32.from_nat(1n)), sx}

# two-phase walker (state machine): BM0 builds one entry, BM1 joins its row
def bo_walk(+fuel: Nat, +st: BSt) -> BOut:
  match fuel:
    case 0n:
      BOut{SNil{}, Nil{}, U32.from_nat(0n), U32.from_nat(0n)}
    case 1n+fp:
      match st:
        case BM0{bos, off}:
          match bos:
            case Nil{}:
              BOut{SNil{}, Nil{}, U32.from_nat(0n), off}
            case Con{P.BO{num, gen, o}, rest}:
              bo_walk(fp, BM1{num, slk_of(64n, entry_of(1024n, num, gen, o)), u32_pad(5n, gen), off, rest})
        case BM1{num, SLK{ln, es}, gen5, off, rest}:
          bo_join(bo_walk(fp, BM0{rest, U32.add(off, U32.from_nat(ln))}), BRow{num, row_of(off, gen5)}, es)

# ---- full file assembly ----

# subsection header: "first count" + this run's rows (7.5.4)
def sec_text(+start: U32, +cnt: U32, +rowsd: String) -> String:
  str_append(str_append(str_append(u32_show(start), " "), str_append(u32_show(cnt), "\n")), rowsd)

def run_eq(+num: U32, +start: U32, +cnt: U32) -> Bool:
  U32.is_eq(num, U32.add(start, cnt))

# assembler modes: AP opens the first run, AR streams rows into the current
# run, AB applies the contiguity comparison (compare computed in AR, matched
# as a state field in AB, per the no-match-on-computed-value rule)
type ASt is Data:
  AP{rows: List<&2, BRow>}
  AR{rows: List<&2, BRow>, cur: String, start: U32, cnt: U32}
  AB{eq: Bool, num: U32, row: String, rest: List<&2, BRow>, cur: String, start: U32, cnt: U32}

def asm_tail(+fuel: Nat, +st: ASt) -> String:
  match fuel:
    case 0n:
      "## assembler fuel exhausted\n"
    case 1n+fp:
      match st:
        case AP{rows}:
          match rows:
            case Nil{}: SNil{}
            case Con{BRow{num, row}, rest}:
              asm_tail(fp, AR{rest, row, num, U32.from_nat(1n)})
        case AR{rows, cur, start, cnt}:
          match rows:
            case Nil{}:
              sec_text(start, cnt, cur)
            case Con{BRow{num, row}, rest}:
              asm_tail(fp, AB{run_eq(num, start, cnt), num, row, rest, cur, start, cnt})
        case AB{eq, num, row, rest, cur, start, cnt}:
          match eq:
            case True{}:
              asm_tail(fp, AR{rest, str_append(cur, row), start, U32.add(cnt, U32.from_nat(1n))})
            case False{}:
              str_append(sec_text(start, cnt, cur), asm_tail(fp, AR{rest, row, num, U32.from_nat(1n)}))

def tail_xref(+rows: List<&2, BRow>) -> String:
  str_append(str_append("xref\n0 1\n", "0000000000 65535 f \n"), asm_tail(32768n, AP{rows}))

def tail_end(+trailer: P.Obj, +sx: U32) -> String:
  str_append(str_append("trailer\n", str_append(ser(1024n, SIObj{trailer}), "\nstartxref\n")), str_append(u32_show(sx), "\n%%EOF\n"))

def full_done2(+wr: BOut, +trailer: P.Obj) -> String:
  match wr:
    case BOut{out, rows, cnt, sx}:
      str_append(out, str_append(tail_xref(rows), tail_end(trailer, sx)))

def full_done1(+hdr: String, wr: BOut, +trailer: P.Obj) -> String:
  str_append(hdr, full_done2(wr, trailer))

# ---- trailer normalization for a consolidated (single-section) rewrite
# (7.5.6): drop stale /Prev and /XRefStm entries (the merged document has no
# previous section) and set /Size to the highest object number + 1.

def max_obj_num_go(objs: List<&2, P.BO>, +acc: U32) -> U32:
  match objs:
    case Nil{}:
      acc
    case Con{P.BO{+num, gen, o}, t}:
      max_obj_num_go(t, Bool.pick(U32, U32.is_gt(num, acc), num, acc))

def max_obj_num(objs: List<&2, P.BO>) -> U32:
  max_obj_num_go(objs, U32.from_nat(0n))

def has_size_go(els: List<&2, P.PEntry>, acc: Bool) -> Bool:
  match els:
    case Nil{}:
      acc
    case Con{P.PE{+k, v}, t}:
      has_size_go(t, Bool.or(acc, String.eq(k, "Size")))

def has_size(els: List<&2, P.PEntry>) -> Bool:
  has_size_go(els, False{})

def rewrite_entries(+maxn: U32, els: List<&2, P.PEntry>) -> List<&2, P.PEntry>:
  match els:
    case Nil{}:
      Nil{}
    case Con{P.PE{+k, v}, t}:
      +rest : List<&2, P.PEntry> = rewrite_entries(maxn, t)
      is_prev : Bool = String.eq(k, "Prev")
      is_xstm : Bool = String.eq(k, "XRefStm")
      is_size : Bool = String.eq(k, "Size")
      drop : Bool = Bool.or(is_prev, is_xstm)
      new_size_val : P.Obj = P.ONum{False{}, U32.add(maxn, U32.from_nat(1n)), 0n, 1n}
      # build the candidate entry for the non-drop case
      size_entry : P.PEntry = P.PE{k, new_size_val}
      keep_entry : P.PEntry = P.PE{k, v}
      chosen_entry : P.PEntry = Bool.pick(P.PEntry, is_size, size_entry, keep_entry)
      Bool.pick(List<&2, P.PEntry>, drop, rest, Con{chosen_entry, rest})

def fix_trailer(trailer: P.Obj, +maxn: U32) -> P.Obj:
  match trailer:
    case P.ODict{+els}:
      +new_els : List<&2, P.PEntry> = rewrite_entries(maxn, els)
      hs : Bool = has_size(els)
      Bool.pick(P.Obj, hs, P.ODict{new_els}, P.ODict{Con{P.PE{"Size", P.ONum{False{}, U32.add(maxn, U32.from_nat(1n)), 0n, 1n}}, new_els}})
    case x:
      trailer

def full_file_str(fr: X.FullRes) -> String:
  match fr:
    case X.FullErr{why}: why
    case X.FullRes{+objs, xref, trailer, sx}:
      full_done1("%PDF-2.0\n%pdf20 writer\n", bo_walk(32768n, BM0{objs, U32.from_nat(23n)}), fix_trailer(trailer, max_obj_num(objs)))

# ---- read_file (from runner.bend) ----

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

def write_pack_exec(wbp: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f9, wres) = wbp
  match wres:
    case Fail{(code, msg)}:
      IO.die(Unit, code, msg)
    case Done{u}:
      IO.pure(Unit, u)

def write_file_exec(f8: File, +out: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    wbp : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f8, out)
    ret : Unit <- write_pack_exec(wbp)
    return ret

def io_go(inout: String & String) -> IO(Unit):
  (path_str, out_str) = inout
  do IO<Unit>:
    bytes : List<&2, U32> <- read_file(P.str_byts(path_str))
    fr : X.FullRes = X.xfile_bytes(bytes)
    outp : List<&2, U32> = P.str_byts(full_file_str(fr))
    f8 : File <- IO.try(File, File.open_bytes(P.str_byts(out_str), "w"))
    rwx : Unit <- write_file_exec(f8, outp)
    return rwx

# argv[2] names the output file; File.write_bytes emits the byte list
# unencoded, so the written file is the exact byte image of the serialized
# document (IO.print would UTF-8-encode every char past 127 and mangle
# binary stream bodies for the next reader)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    gox : Unit <- io_go(P.args2p(args))
    return gox
