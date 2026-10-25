import Base
import ./lex.bend as Pdf
import ./parser.bend as P
import ./xref.bend as X

# Benchmark entry: read one PDF path (argv[1]), lex it (clause 7.2/7.3),
# report "OK <tokens> <bytes>" or "ERR <why> <bytes>" on one line.
# Throughput is measured outside (MB/s from bytes and wall time).
#
# Do-blocks accept only plain-binder patterns, so every pair unpack
# happens in a plain def body as a parameter pattern-match.

# argv[1]: the first argument after the program name
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

# Char codes as path bytes (corpus paths are ASCII)
def str_byts(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      Con{Char.to_u32(h), str_byts(t)}

# report line: unpack (Lex, size) at the parameter, then match
def lex_rpt(rp: Pdf.Lex & U32) -> String:
  (l, sz) = rp
  match l:
    case Pdf.Lexed{toks}:
      (("OK " ++ Nat.show(List.length(&2, Pdf.Tok, toks))) ++ " " ++ U32.show(sz))
    case Pdf.LexErr{why}:
      ((("ERR " ++ why) ++ " ") ++ U32.show(sz))

# parse report line: unpack (PRes, size) at the parameter, then match
def parse_rpt(rp: P.PRes & U32) -> String:
  (pr, sz) = rp
  match pr:
    case P.POks{o}:
      (("OK " ++ Nat.show(List.length(&2, P.BO, o))) ++ " objects " ++ U32.show(sz))
    case P.PCut{o}:
      (("CUT " ++ Nat.show(List.length(&2, P.BO, o))) ++ " objects " ++ U32.show(sz))
    case P.PErr{why}:
      (("ERR " ++ why) ++ " " ++ U32.show(sz))

# xref report line: unpack (FullRes, size) at the parameter, then match
def xref_rpt(rp: X.FullRes & U32) -> String:
  (xr, sz) = rp
  match xr:
    case X.FullRes{objs, xref, trailer, startxref}:
      (("XOK " ++ Nat.show(List.length(&2, X.XE, xref))) ++ " entries, objs=" ++ Nat.show(List.length(&2, P.BO, objs)) ++ " startxref=" ++ U32.show(startxref) ++ " " ++ U32.show(sz))
    case X.FullErr{why}:
      (("ERR " ++ why) ++ " " ++ U32.show(sz))

# main flow stages, dependency-first (defs bind in order)

# stage 3: with the whole file in hand, lex it
def lex_bytes_exec(rbp: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sz: U32) -> IO(Pdf.Lex & U32):
  (f3, rres) = rbp
  do IO<Pdf.Lex & U32>:
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, rres)
    lexr : Pdf.Lex = Pdf.lex(bytes)
    return (lexr, sz)

# stage 2: with the size known, read the file whole
def lex_read_exec(f2: File, +sz: U32) -> IO(Pdf.Lex & U32):
  do IO<Pdf.Lex & U32>:
    rbp : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f2, sz)
    ret : Pdf.Lex & U32 <- lex_bytes_exec(rbp, sz)
    return ret

# stage 1: unpack the size report, thread the handle on
def lex_size_exec(sfp: File & Result<&1, &1, U32 & String, U32>) -> IO(Pdf.Lex & U32):
  (f2, sres) = sfp
  match sres:
    case Fail{(code, msg)}:
      IO.die(Pdf.Lex & U32, code, msg)
    case Done{sz}:
      lex_read_exec(f2, sz)

# stage 0: path in, file out
def lex_file(path: List<&2, U32>) -> IO(Pdf.Lex & U32):
  do IO<Pdf.Lex & U32>:
    f1 : File <- IO.try(File, File.open_bytes(path, "r"))
    sfp : File & Result<&1, &1, U32 & String, U32> <- File.size(f1)
    ret : Pdf.Lex & U32 <- lex_size_exec(sfp)
    return ret

# read whole file into bytes (shared by lex, parse, xref stages)
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

# ---- parse stage: read the file whole, then parse it (clause 7.5)

# stage 3: with the whole file in hand, parse it
def parse_bytes_exec(rbp: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sz: U32) -> IO(P.PRes & U32):
  (f3, rres) = rbp
  do IO<P.PRes & U32>:
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, rres)
    pr : P.PRes = P.pfile(bytes)
    return (pr, sz)

# stage 2: with the size known, read the file whole
def parse_read_exec(f2: File, +sz: U32) -> IO(P.PRes & U32):
  do IO<P.PRes & U32>:
    rbp : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f2, sz)
    ret : P.PRes & U32 <- parse_bytes_exec(rbp, sz)
    return ret

# stage 1: unpack the size report, thread the handle on
def parse_size_exec(sfp: File & Result<&1, &1, U32 & String, U32>) -> IO(P.PRes & U32):
  (f2, sres) = sfp
  match sres:
    case Fail{(code, msg)}:
      IO.die(P.PRes & U32, code, msg)
    case Done{sz}:
      parse_read_exec(f2, sz)

# stage 0: path in, file out
def parse_file(path: List<&2, U32>) -> IO(P.PRes & U32):
  do IO<P.PRes & U32>:
    f1 : File <- IO.try(File, File.open_bytes(path, "r"))
    sfp : File & Result<&1, &1, U32 & String, U32> <- File.size(f1)
    ret : P.PRes & U32 <- parse_size_exec(sfp)
    return ret

# ---- xref stage: read the file whole, then parse xref regime (clause 7.5.4)

def xref_bytes_exec(rbp: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sz: U32) -> IO(X.FullRes & U32):
  (f3, rres) = rbp
  do IO<X.FullRes & U32>:
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, rres)
    xr : X.FullRes = X.xfile_bytes(bytes)
    return (xr, sz)

def xref_read_exec(f2: File, +sz: U32) -> IO(X.FullRes & U32):
  do IO<X.FullRes & U32>:
    rbp : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f2, sz)
    ret : X.FullRes & U32 <- xref_bytes_exec(rbp, sz)
    return ret

def xref_size_exec(sfp: File & Result<&1, &1, U32 & String, U32>) -> IO(X.FullRes & U32):
  (f2, sres) = sfp
  match sres:
    case Fail{(code, msg)}:
      IO.die(X.FullRes & U32, code, msg)
    case Done{sz}:
      xref_read_exec(f2, sz)

def xref_file(path: List<&2, U32>) -> IO(X.FullRes & U32):
  do IO<X.FullRes & U32>:
    f1 : File <- IO.try(File, File.open_bytes(path, "r"))
    sfp : File & Result<&1, &1, U32 & String, U32> <- File.size(f1)
    ret : X.FullRes & U32 <- xref_size_exec(sfp)
    return ret

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +path_str : String = arg1(args)
    lex_ret : Pdf.Lex & U32 <- lex_file(str_byts(path_str))
    par_ret : P.PRes & U32 <- parse_file(str_byts(path_str))
    xref_ret : X.FullRes & U32 <- xref_file(str_byts(path_str))
    IO.print(((lex_rpt(lex_ret) ++ " | " ++ parse_rpt(par_ret)) ++ " | " ++ xref_rpt(xref_ret)))

