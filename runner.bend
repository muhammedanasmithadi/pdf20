import Base
import ./lex.bend as Pdf

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

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    ret : Pdf.Lex & U32 <- lex_file(str_byts(arg1(args)))
    IO.print(lex_rpt(ret))
