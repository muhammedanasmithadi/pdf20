# writer.bend — structural PDF writer (v0). Canonical re-serialization
# of the parsed object graph; not bit-precise.

import Base
import ./lex.bend as Lx
import ./parser.bend as P
import ./xref.bend as X

type SerInput is Data:
  SIObj{o: P.Obj}
  SIList{els: List<&2, P.Obj>}
  SIDict{els: List<&2, P.PEntry>}

def str_append(a: String, b: String) -> String:
  match a:
    case SNil{}: b
    case SCon{h, t}: SCon{h, str_append(t, b)}

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
              str_append(ser(fp, SIObj{d}), " stream\n")
        case SIList{els}:
          match els:
            case Nil{}: SNil{}
            case Con{h, Nil{}}: ser(fp, SIObj{h})
            case Con{h, t}: str_append(str_append(ser(fp, SIObj{h}), " "), ser(fp, SIList{t}))
        case SIDict{els}:
          match els:
            case Nil{}: SNil{}
            case Con{P.PE{k, v}, rest}:
              str_append(str_append(str_append(str_append("/", k), " "), ser(fp, SIObj{v})), str_append(" ", ser(fp, SIDict{rest})))

def ser_bo(bo: P.BO) -> String:
  match bo:
    case P.BO{num, gen, o}:
      str_append(str_append(str_append(str_append(U32.show(num), " "), str_append(U32.show(gen), " obj\n")), ser(1024n, SIObj{o})), "\nendobj\n")

def ser_bo_list(fuel: Nat, bos: List<&2, P.BO>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+fp:
      match bos:
        case Nil{}: SNil{}
        case Con{bo, rest}:
          str_append(ser_bo(bo), ser_bo_list(fp, rest))

def fullres_to_str(fr: X.FullRes) -> String:
  match fr:
    case X.FullErr{why}: why
    case X.FullRes{objs, xref, trailer, sx}:
      str_append(ser_bo_list(1024n, objs), str_append("\ntrailer\n", str_append(ser(1024n, SIObj{trailer}), "\n")))

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
    IO.print(fullres_to_str(fr))
