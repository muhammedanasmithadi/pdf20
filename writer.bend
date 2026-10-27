# writer.bend — structural PDF writer (v0.1). Canonical re-serialization of
# the parsed object graph; not bit-precise. Emits header, all indirect
# objects with byte-offset tracking, an xref table, trailer, startxref and
# %%EOF. Assumes object numbers are contiguous 1..N (single subsection).
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
              Bool.show(b)
            case P.ONum{neg, whole, fnum, fden}:
              ser_num(neg, whole, fnum, fden)
            case P.OName{val}:
              SCon{'/', val}
            case P.OStr{val}:
              SCon{'(', str_append(val, ")")}
            case P.OArr{els}:
              SCon{'[', str_append(ser(fp, SIList{els}), "]")}
            case P.ODict{els}:
              str_append("<< ", str_append(ser(fp, SIDict{els}), " >>"))
            case P.OInd{num, gen}:
              str_append(str_append(U32.show(num), " "), str_append(U32.show(gen), " R"))
            case P.OStream{d, dat}:
              str_append(str_append(str_append(ser(fp, SIObj{d}), " stream\n"), dat), "\nendstream\n")
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

type BSt is Data:
  BM0{bos: List<&2, P.BO>, off: U32}
  BM1{slk: SLK, gen5: String, off: U32, rest: List<&2, P.BO>}

type BOut is Data:
  BOut{out: String, rows: List<&2, String>, cnt: U32, sx: U32}

# prepends the entry to the output body and the row to the xref rows
def bo_join(+wr: BOut, +row: String, +ec: String) -> BOut:
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
              bo_walk(fp, BM1{slk_of(64n, entry_of(1024n, num, gen, o)), u32_pad(5n, gen), off, rest})
        case BM1{SLK{ln, es}, gen5, off, rest}:
          bo_join(bo_walk(fp, BM0{rest, U32.add(off, U32.from_nat(ln))}), row_of(off, gen5), es)

# ---- full file assembly ----

def tail_cnt(+cnt: U32) -> String:
  str_append("0 ", str_append(U32.show(U32.add(cnt, U32.from_nat(1n))), "\n"))

def tail_xref(+rows: List<&2, String>, +cnt: U32) -> String:
  str_append(str_append("xref\n", tail_cnt(cnt)), str_append("0000000000 65535 f \n", cat(rows)))

def tail_end(+trailer: P.Obj, +sx: U32) -> String:
  str_append(str_append("trailer\n", str_append(ser(1024n, SIObj{trailer}), "\nstartxref\n")), str_append(u32_show(sx), "\n%%EOF\n"))

def full_done2(+wr: BOut, +trailer: P.Obj) -> String:
  match wr:
    case BOut{out, rows, cnt, sx}:
      str_append(out, str_append(tail_xref(rows, cnt), tail_end(trailer, sx)))

def full_done1(+hdr: String, wr: BOut, +trailer: P.Obj) -> String:
  str_append(hdr, full_done2(wr, trailer))

def full_file_str(fr: X.FullRes) -> String:
  match fr:
    case X.FullErr{why}: why
    case X.FullRes{objs, xref, trailer, sx}:
      full_done1("%PDF-2.0\n%pdf20 writer\n", bo_walk(32768n, BM0{objs, U32.from_nat(23n)}), trailer)

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

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    path_str : String = P.arg1(args)
    bytes : List<&2, U32> <- read_file(P.str_byts(path_str))
    fr : X.FullRes = X.xfile_bytes(bytes)
    IO.print(full_file_str(fr))
