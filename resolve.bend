# resolve.bend — trailer/catalog/page tree validation (§7.10)
# Validates the file trailer (Table 15): Size, Root.
# Resolves Root -> catalog dictionary (Table 29): Type=/Catalog, Pages.
# Resolves Pages -> page tree root (Table 30): Type=/Pages, Kids array.
# Walks Kids: each kid must be an indirect reference to a /Page dictionary.
# v0 restriction: one-level page tree (kids are leaf pages, no nested /Pages).

import Base
import ./lex.bend as Lx
import ./parser.bend as P
import ./xref.bend as X

# ---- resolution result

type Resolved is Data:
  Res{obj: P.Obj}
  RErr{why: String}

# ---- validation result

type ValRes is Data:
  VOk{n_pages: U32}
  VErr{why: String}

# ---- the walker state machine. scrutinee field first, context after;
# every computed result (dict_get, resolve_obj, String.eq, U32.add) is
# carried into the next state and matched in the following round.

type VST is Data:
  VSz{sg: Resolved, objs: List<&2, P.BO>, tels: List<&2, P.PEntry>}
  VSzEnc{enc: Resolved, objs: List<&2, P.BO>, tels: List<&2, P.PEntry>}
  VSzO{sz: P.Obj, tels: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VRes{rr: Resolved, els: List<&2, P.PEntry>, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VResCat{rr: Resolved, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VCnt{cr: Resolved, dict_obj: P.Obj, objs: List<&2, P.BO>}
  VPr{pr: Resolved, els: List<&2, P.PEntry>, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VPrO{rt: P.Obj, els: List<&2, P.PEntry>, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VRt{rg: Resolved, objs: List<&2, P.BO>}
  VRtO{rt: P.Obj, objs: List<&2, P.BO>}
  VCt{cr: Resolved, objs: List<&2, P.BO>}
  VCtO{ct: P.Obj, objs: List<&2, P.BO>}
  VTp{td: Resolved, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VTpO{tp: P.Obj, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VCI{ic: Bool, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VPg{pr: Resolved, objs: List<&2, P.BO>}
  VPgO{pg: P.Obj, objs: List<&2, P.BO>}
  VPn{nr: Resolved, objs: List<&2, P.BO>}
  VPnO{nd: P.Obj, objs: List<&2, P.BO>}
  VNV{nv: Resolved, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VNVO{nt: P.Obj, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VNI{ip: Bool, els: List<&2, P.PEntry>, objs: List<&2, P.BO>}
  VKg{kr: Resolved, objs: List<&2, P.BO>}
  VKgO{ko: P.Obj, objs: List<&2, P.BO>}
  VLp{arr: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VKr{kr: Resolved, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VKrO{ob: P.Obj, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VKt{td: Resolved, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VKtO{tp: P.Obj, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VKI{ip: Bool, rk: List<&2, P.Obj>, cnt: U32, objs: List<&2, P.BO>}
  VFin{cnt: U32}

# ---- U32_eq: Bool comparison wrapper for U32 (avoids computed scrutinee)

def U32_eq(a: U32, b: U32) -> Bool:
  U32.is_eq(a, b)

# ---- dict_get_els: self-recursive dictionary lookup.
# Match order: rest, key, eq, k, v.

def dict_get_els(rest: List<&2, P.PEntry>, +key: String, eq: Bool, k: String, v: P.Obj) -> Resolved:
  match rest:
    case Nil{}:
      match eq:
        case True{}:
          Res{v}
        case False{}:
          RErr{"key not found in dictionary (7.3.7)"}
    case Con{P.PE{+k2, v2}, rest2}:
      match eq:
        case True{}:
          Res{v}
        case False{}:
          dict_get_els(rest2, key, String.eq(k2, key), k2, v2)

# ---- dict_get: find entry by key name in a dictionary

def dict_get(+key: String, dict_obj: P.Obj) -> Resolved:
  match dict_obj:
    case P.ODict{els}:
      match els:
        case Nil{}:
          RErr{"key not found in dictionary (7.3.7)"}
        case Con{P.PE{+k, v}, rest}:
          dict_get_els(rest, key, String.eq(k, key), k, v)
    case x:
      RErr{"not a dictionary (7.3.7)"}

# ---- resolve_obj: self-recursive search for matching num/gen.
# Params: rest, snum, sgen, eq_num, eq_gen, cur_o.

def resolve_obj(rest: List<&2, P.BO>, +snum: U32, +sgen: U32, eq_num: Bool, eq_gen: Bool, cur_o: P.Obj) -> Resolved:
  match rest:
    case Nil{}:
      match eq_num:
        case True{}:
          match eq_gen:
            case True{}:
              Res{cur_o}
            case False{}:
              # a reference to a nonexistent object is treated as null (7.3.9)
              Res{P.ONil{}}
        case False{}:
          # a reference to a nonexistent object is treated as null (7.3.9)
          Res{P.ONil{}}
    case Con{P.BO{num, gen, o}, rest2}:
      match eq_num:
        case True{}:
          match eq_gen:
            case True{}:
              Res{cur_o}
            case False{}:
              resolve_obj(rest2, snum, sgen, U32_eq(num, snum), U32_eq(gen, sgen), o)
        case False{}:
          resolve_obj(rest2, snum, sgen, U32_eq(num, snum), U32_eq(gen, sgen), o)

# ---- llen: object-table length, for the walker fuel budget

def llen(list: List<&2, P.BO>) -> Nat:
  match list:
    case Nil{}:
      0n
    case Con{head, rest}:
      (1n + llen(rest) : Nat)

# ---- trav: the fuel-driven validation walker.
# One match per round, in ascending field order; computed results ride
# into the next state. fuel = 32 * len(objs) + 24: up to ~10 setup rounds
# plus ~5 rounds per kid (kids never exceed the object table length).

def trav(fuel: Nat, st: VST) -> ValRes:
  match fuel:
    case 0n:
      VErr{"out of validation fuel"}
    case 1n+p:
      match st:

        # -- trailer Size (Table 15)
        case VSz{sg, objs, tels}:
          match sg:
            case Res{sz}:
              trav(p, VSzO{sz, tels, objs})
            case RErr{why}:
              VErr{"trailer missing Size (Table 15, 7.5.5)"}

        case VSzO{sz, tels, objs}:
          match sz:
            case P.ONum{neg, whole, fnum, fden}:
              match fnum:
                case 0n:
                  # an integer-valued Size (7.3.3: a real shall not appear
                  # where an integer is expected)
                  trav(p, VRt{dict_get("Root", P.ODict{tels}), objs})
                case 1n+p:
                  VErr{"trailer Size shall be an integer (7.3.3)"}
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"trailer missing Size (Table 15, 7.5.5)"}
            case x:
              VErr{"trailer Size not a number (Table 15, 7.3.9)"}

        # -- encryption check (7.6.2): Encrypt present → reject
        case VSzEnc{enc, objs, +tels}:
          match enc:
            case Res{_}:
              VErr{"document is encrypted (7.6); encryption not supported in v0"}
            case RErr{_}:
              trav(p, VSz{dict_get("Size", P.ODict{tels}), objs, tels})

        # -- trailer Root (Table 15): resolve the reference
        case VRt{rg, objs}:
          match rg:
            case Res{rt}:
              trav(p, VRtO{rt, objs})
            case RErr{why}:
              VErr{"trailer missing Root (Table 15, 7.5.5)"}

        case VRtO{rt, +objs}:
          match rt:
            case P.OInd{num, gen}:
              trav(p, VCt{resolve_obj(objs, num, gen, False{}, False{}, P.ONil{}), objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"trailer missing Root (Table 15, 7.5.5)"}
            case x:
              VErr{"trailer Root not an indirect reference (7.3.10, Table 15)"}

        # -- document catalog (Table 29)
        case VCt{cr, objs}:
          match cr:
            case Res{ct}:
              trav(p, VCtO{ct, objs})
            case RErr{why}:
              VErr{why}

        case VCtO{ct, objs}:
          match ct:
            case P.ODict{+els}:
              trav(p, VResCat{dict_get("Resources", P.ODict{els}), els, objs})
            case x:
              VErr{"Root not a dictionary (7.3.7, Table 29)"}

        # -- catalog Resources (Table 34): optional entry, must be a dictionary if present
        case VResCat{rr, +els, objs}:
          match rr:
            case Res{r}:
              match r:
                case P.ODict{res_els}:
                  trav(p, VTp{dict_get("Type", P.ODict{els}), els, objs})
                case x:
                  VErr{"catalog Resources not a dictionary (Table 34, 7.7.4)"}
            case RErr{why}:
              trav(p, VTp{dict_get("Type", P.ODict{els}), els, objs})

        case VTp{td, els, objs}:
          match td:
            case Res{tp}:
              trav(p, VTpO{tp, els, objs})
            case RErr{why}:
              VErr{"catalog missing Type (Table 29, 7.7.2)"}

        case VTpO{tp, els, objs}:
          match tp:
            case P.OName{val}:
              trav(p, VCI{String.eq(val, "Catalog"), els, objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"catalog missing Type (Table 29, 7.7.2)"}
            case x:
              VErr{"catalog Type not a name (7.3.5, Table 29)"}

        case VCI{ic, els, objs}:
          match ic:
            case True{}:
              trav(p, VPg{dict_get("Pages", P.ODict{els}), objs})
            case False{}:
              VErr{"catalog Type is not /Catalog (Table 29, 7.7.2)"}

        # -- catalog Pages (Table 29): resolve the reference
        case VPg{pr, objs}:
          match pr:
            case Res{pg}:
              trav(p, VPgO{pg, objs})
            case RErr{why}:
              VErr{"catalog missing Pages (Table 29, 7.7.2)"}

        case VPgO{pg, +objs}:
          match pg:
            case P.OInd{num, gen}:
              trav(p, VPn{resolve_obj(objs, num, gen, False{}, False{}, P.ONil{}), objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"catalog missing Pages (Table 29, 7.7.2)"}
            case x:
              VErr{"catalog Pages not an indirect reference (7.3.10, Table 29)"}

        # -- page tree root (Table 30)
        case VPn{nr, objs}:
          match nr:
            case Res{nd}:
              trav(p, VPnO{nd, objs})
            case RErr{why}:
              VErr{why}

        case VPnO{nd, objs}:
          match nd:
            case P.ONil{}:
              # a null-valued page tree root is the omitted entry (7.3.9)
              VErr{"catalog missing Pages (Table 29, 7.7.2)"}
            case P.ODict{+els}:
              trav(p, VNV{dict_get("Type", P.ODict{els}), els, objs})
            case x:
              VErr{"page tree root not a dictionary (7.3.7, Table 30)"}

        case VNV{nv, els, objs}:
          match nv:
            case Res{nt}:
              trav(p, VNVO{nt, els, objs})
            case RErr{why}:
              VErr{"page tree root missing Type (Table 30, 7.7.3)"}

        case VNVO{nt, els, objs}:
          match nt:
            case P.OName{val}:
              trav(p, VNI{String.eq(val, "Pages"), els, objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"page tree root missing Type (Table 30, 7.7.3)"}
            case x:
              VErr{"page tree root Type not a name (7.3.5, Table 30)"}

        case VNI{ip, +els, objs}:
          match ip:
            case True{}:
              trav(p, VCnt{dict_get("Count", P.ODict{els}), P.ODict{els}, objs})
            case False{}:
              VErr{"page tree root Type is not /Pages (Table 30, 7.7.3)"}

        # -- Count (Table 30): required non-negative integer
        case VCnt{cr, dict_obj, objs}:
          match cr:
            case Res{ct}:
              match ct:
                case P.ONum{neg, whole, fnum, fden}:
                  match neg:
                    case False{}:
                      match fnum:
                        case 0n:
                          trav(p, VKg{dict_get("Kids", dict_obj), objs})
                        case 1n+p:
                          VErr{"page tree root Count shall be an integer (7.3.3, Table 30)"}
                    case True{}:
                      VErr{"page tree root Count shall be a non-negative integer (7.3.3, Table 30)"}
                case P.ONil{}:
                  # a null-valued entry is the omitted entry (7.3.9)
                  VErr{"page tree root missing Count (Table 30, 7.7.3)"}
                case x:
                  VErr{"page tree root Count not a number (7.3.3, Table 30)"}
            case RErr{why}:
              VErr{"page tree root missing Count (Table 30, 7.7.3)"}

        # -- Kids array (Table 30)
        case VKg{kr, objs}:
          match kr:
            case Res{ko}:
              trav(p, VKgO{ko, objs})
            case RErr{why}:
              VErr{"page tree root missing Kids (Table 30, 7.7.3)"}

        case VKgO{ko, objs}:
          match ko:
            case P.OArr{arr}:
              trav(p, VLp{arr, 0, objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"page tree root missing Kids (Table 30, 7.7.3)"}
            case x:
              VErr{"page tree root Kids not an array (7.3.6, Table 30)"}

        # -- the kid loop
        case VLp{arr, cnt, +objs}:
          match arr:
            case Nil{}:
              trav(p, VFin{cnt})
            case Con{num, rk}:
              match num:
                case P.OInd{knum, kgen}:
                  trav(p, VKr{resolve_obj(objs, knum, kgen, False{}, False{}, P.ONil{}), rk, cnt, objs})
                case x:
                  VErr{"page tree kid not an indirect reference (7.3.10, Table 30)"}

        case VKr{kr, rk, cnt, objs}:
          match kr:
            case Res{ob}:
              trav(p, VKrO{ob, rk, cnt, objs})
            case RErr{why}:
              VErr{why}

        case VKrO{ob, rk, cnt, objs}:
          match ob:
            case P.ONil{}:
              # a null-valued page tree kid is the omitted entry (7.3.9)
              VErr{"page tree kid missing (Table 30, 7.7.3)"}
            case P.ODict{+els}:
              # check Resources (Table 34) before Parent (Table 30)
              trav(p, VRes{dict_get("Resources", P.ODict{els}), els, rk, cnt, objs})
            case x:
              VErr{"page tree kid not a dictionary (7.3.7, Table 30)"}

        # -- page Resources (Table 34): optional entry, must be a dictionary if present
        case VRes{rr, +els, rk, cnt, objs}:
          match rr:
            case Res{r}:
              match r:
                case P.ODict{res_els}:
                  trav(p, VPr{dict_get("Parent", P.ODict{els}), els, rk, cnt, objs})
                case x:
                  VErr{"page Resources not a dictionary (Table 34, 7.7.4)"}
            case RErr{why}:
              trav(p, VPr{dict_get("Parent", P.ODict{els}), els, rk, cnt, objs})

        # -- page Parent (Table 30): required entry, indirect reference
        case VPr{pr, els, rk, cnt, objs}:
          match pr:
            case Res{rt}:
              trav(p, VPrO{rt, els, rk, cnt, objs})
            case RErr{why}:
              VErr{"page missing Parent (Table 30, 7.7.3)"}

        case VPrO{rt, els, rk, cnt, objs}:
          match rt:
            case P.OInd{num, gen}:
              trav(p, VKt{dict_get("Type", P.ODict{els}), rk, cnt, objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"page missing Parent (Table 30, 7.7.3)"}
            case x:
              VErr{"page Parent not an indirect reference (7.3.10, Table 30)"}

        case VKt{td, rk, cnt, objs}:
          match td:
            case Res{tp}:
              trav(p, VKtO{tp, rk, cnt, objs})
            case RErr{why}:
              VErr{"page missing Type (Table 30, 7.7.3)"}

        case VKtO{tp, rk, cnt, objs}:
          match tp:
            case P.OName{val}:
              trav(p, VKI{String.eq(val, "Page"), rk, cnt, objs})
            case P.ONil{}:
              # a null-valued entry is the omitted entry (7.3.9)
              VErr{"page missing Type (Table 30, 7.7.3)"}
            case x:
              VErr{"page Type not a name (7.3.5, Table 30)"}

        case VKI{ip, rk, cnt, +objs}:
          match ip:
            case True{}:
              trav(p, VLp{rk, U32.add(cnt, 1), objs})
            case False{}:
              VErr{"page tree kid Type is not /Page (Table 30, 7.7.3)"}

        # -- terminal: done counting
        case VFin{cnt}:
          VOk{cnt}

# ---- validate: entry point — fuel then the walker

def validate(fr: X.FullRes) -> ValRes:
  match fr:
    case X.FullRes{+objs, xref, trailer, startxref}:
      match trailer:
        case P.ODict{+tels}:
          # encryption check first (7.6.2): Encrypt present → reject
          trav(Nat.add(Nat.mul(llen(objs), 32n), 24n), VSzEnc{dict_get("Encrypt", P.ODict{tels}), objs, tels})
        case x:
          VErr{"trailer not a dictionary (7.3.7, Table 15)"}
    case X.FullErr{why}:
      VErr{why}

# ---- check_encrypt: Encrypt present → reject (7.6)
# Matches the dict_get result as a parameter (Bend requires this pattern).
def check_encrypt(enc: Resolved, p: Nat, tels: List<&2, P.PEntry>, objs: List<&2, P.BO>) -> ValRes:
  match enc:
    case Res{_}:
      VErr{"document is encrypted (7.6); encryption not supported in v0"}
    case RErr{_}:
      trav(p, VRt{dict_get("Root", P.ODict{tels}), objs})

# ---- report + entry

def val_res_rpt(vr: ValRes) -> String:
  match vr:
    case VOk{n_pages}:
      ((("VALID " ++ U32.show(n_pages)) ++ " pages"))
    case VErr{why}:
      (("INVALID " ++ why))

def str_byts(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      Con{Char.to_u32(h), str_byts(t)}

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
    +path_str : String = arg1(args)
    bytes : List<&2, U32> <- read_file(str_byts(path_str))
    fr : X.FullRes = X.xfile_bytes(bytes)
    vr : ValRes = validate(fr)
    IO.print(val_res_rpt(vr))
