import Base
import ./parser.bend as P

# flate.bend — DEFLATE inflate (RFC 1951) for PDF /Filter FlateDecode (§7.8.2).

# ---- bit reader over bytes (LSB-first within each byte)

type BR is Data:
  BR{buf: U32, cnt: Nat, rest: List<&2, U32>}

type HR is Data:
  HR{br: BR, out: List<&2, U32>}

type RB is Data:
  RB{val: U32, br: BR}

def br_bit(+br: BR) -> U32:
  match br:
    case BR{+buf, cnt, rest}:
      match cnt:
        case 0n:
          match rest:
            case Nil{}: 0
            case Con{+b, t}: U32.and(b, 1)
        case 1n+p:
          U32.and(buf, 1)

def br_next(+br: BR) -> BR:
  match br:
    case BR{+buf, cnt, rest}:
      match cnt:
        case 0n:
          match rest:
            case Nil{}: br
            case Con{+b, t}: BR{U32.div(b, 2), 7n, t}
        case 1n+p:
          BR{U32.div(buf, 2), p, rest}

def br_readn(n: Nat, br: BR, +acc: U32, +shift: U32) -> RB:
  match n:
    case 0n:
      RB{acc, br}
    case 1n+p:
      match br:
        case BR{+buf, cnt, rest}:
          match cnt:
            case 0n:
              match rest:
                case Nil{}:
                  RB{acc, br}
                case Con{+b, t}:
                  br_readn(p, BR{U32.div(b, 2), 7n, t}, U32.add(acc, U32.mul(U32.and(b, 1), shift)), U32.mul(shift, 2))
            case 1n+q:
              br_readn(p, BR{U32.div(buf, 2), q, rest}, U32.add(acc, U32.mul(U32.and(buf, 1), shift)), U32.mul(shift, 2))

def br_align(br: BR) -> BR:
  match br:
    case BR{+buf, cnt, rest}:
      BR{0, 0n, rest}


# ---- helpers

def zeros_list(n: Nat) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{0, zeros_list(p)}

def rep_list(+val: U32, n: Nat) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{val, rep_list(val, p)}

def prepend_bytes(bs: List<&2, U32>, out: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: out
    case Con{h, t}: prepend_bytes(t, Con{h, out})

def nth_u32(n: Nat, xs: List<&2, U32>) -> U32:
  match n:
    case 0n:
      match xs:
        case Nil{}: 0
        case Con{h, t}: h
    case 1n+p:
      match xs:
        case Nil{}: 0
        case Con{h, t}: nth_u32(p, t)

def nth_nat(n: Nat, xs: List<&2, Nat>) -> Nat:
  match n:
    case 0n:
      match xs:
        case Nil{}: 0n
        case Con{h, t}: h
    case 1n+p:
      match xs:
        case Nil{}: 0n
        case Con{h, t}: nth_nat(p, t)

# set_u32 with helper for equality
def set_u32(+idx: Nat, val: U32, xs: List<&2, U32>, +pos: Nat, eq: Bool) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}:
      match eq:
        case True{}: Con{val, t}
        case False{}: Con{h, set_u32(idx, val, t, Nat.add(pos, 1n), Nat.is_eq(Nat.add(pos, 1n), idx))}

def get_u32(idx: Nat, xs: List<&2, U32>) -> U32:
  match idx:
    case 0n:
      match xs:
        case Nil{}: 0
        case Con{h, t}: h
    case 1n+p:
      match xs:
        case Nil{}: 0
        case Con{h, t}: get_u32(p, t)

# inc_u32_at with helper
def inc_u32_at(+idx: Nat, xs: List<&2, U32>, +pos: Nat, eq: Bool, valid: Bool) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}:
      match eq:
        case True{}:
          match valid:
            case True{}: Con{U32.add(h, 1), t}
            case False{}: Con{h, t}
        case False{}:
          match valid:
            case True{}: Con{h, inc_u32_at(idx, t, Nat.add(pos, 1n), Nat.is_eq(Nat.add(pos, 1n), idx), valid)}
            case False{}: Con{h, t}

# ---- Huffman table

type HEnt is Data:
  HEnt{len: Nat, code: U32, sym: U32}

def inc_count_at(+idx: Nat, counts: List<&2, U32>) -> List<&2, U32>:
  inc_u32_at(idx, counts, 0n, Nat.is_eq(0n, idx), Bool.and(Nat.is_lt(0n, idx), Nat.is_lt(idx, 16n)))

# We'll implement recursively with helper for cond
def build_counts2(lens: List<&2, U32>, counts: List<&2, U32>) -> List<&2, U32>:
  match lens:
    case Nil{}: counts
    case Con{h, t}:
      +l = U32.to_nat(h)
      build_counts2(t, inc_count_at(l, counts))

def build_counts_cond(t: List<&2, U32>, counts: List<&2, U32>, l: Nat, cond: Bool) -> List<&2, U32>:
  match cond:
    case True{}: build_counts2(t, inc_count_at(l, counts))
    case False{}: build_counts2(t, counts)

# redirect build_counts name
# (Bend requires def; we define build_counts as wrapper)
# Actually we already defined build_counts above? No, we defined build_counts2. Let's make build_counts = build_counts2.
# Redefine:
def build_counts(lens: List<&2, U32>, counts: List<&2, U32>) -> List<&2, U32>:
  build_counts2(lens, counts)

def build_next(remaining: Nat, +bits: Nat, code: U32, +counts: List<&2, U32>, next_code: List<&2, U32>) -> List<&2, U32>:
  match remaining:
    case 0n: next_code
    case 1n+p:
      prev_count = get_u32(Nat.sub(bits, 1n), counts)
      +new_code = U32.shl(U32.add(code, prev_count))
      next_code2 = List.append(&2, U32, next_code, Con{new_code, Nil{}})
      build_next(p, Nat.add(bits, 1n), new_code, counts, next_code2)

def assign_codes(lens: List<&2, U32>, +sym: Nat, +next_code: List<&2, U32>, +table: List<&2, HEnt>) -> List<&2, HEnt>:
  match lens:
    case Nil{}: table
    case Con{h, t}:
      +l = U32.to_nat(h)
      +valid = Bool.and(Nat.is_lt(0n, l), Nat.is_lt(l, 16n))
      code = get_u32(l, next_code)
      next_code_true = inc_u32_at(l, next_code, 0n, Nat.is_eq(0n, l), valid)
      table_true = List.append(&2, HEnt, table, Con{HEnt{l, code, U32.from_nat(sym)}, Nil{}})
      next_code2 = Bool.pick(List<&2, U32>, valid, next_code_true, next_code)
      table2 = Bool.pick(List<&2, HEnt>, valid, table_true, table)
      assign_codes(t, Nat.add(sym, 1n), next_code2, table2)

def build_table(+lens: List<&2, U32>) -> List<&2, HEnt>:
  counts = build_counts(lens, zeros_list(16n))
  next_code = build_next(15n, 1n, 0, counts, Con{0, Nil{}})
  assign_codes(lens, 0n, next_code, Nil{})

# ---- Huffman decode

type DecRes is Data:
  DecOk{sym: U32, br: BR}
  DecFail{br: BR}

def lookup_ent_go(cur: List<&2, HEnt>, +len: Nat, +code: U32) -> Maybe<&2, U32>:
  match cur:
    case Nil{}: None{}
    case Con{HEnt{l, c, s}, t}:
      eq = Bool.and(Nat.is_eq(l, len), U32.is_eq(c, code))
      Bool.pick(Maybe<&2, U32>, eq, Some{s}, lookup_ent_go(t, len, code))

def lookup_ent(len: Nat, code: U32, table: List<&2, HEnt>) -> Maybe<&2, U32>:
  lookup_ent_go(table, len, code)


# ---- bit read result
type BitRead is Data:
  BitRead{newcode: U32, newlen: Nat, newbr: BR}

def huff_read_bit(+br: BR, +code: U32, +len: Nat) -> BitRead:
  match br:
    case BR{+buf, cnt, rest}:
      match cnt:
        case 0n:
          match rest:
            case Nil{}: BitRead{code, len, br}
            case Con{+b, t}:
              +bit = U32.and(b, 1)
              +newbr : BR = BR{U32.div(b, 2), 7n, t}
              +newcode = U32.add(U32.mul(code, 2), bit)
              BitRead{newcode, Nat.add(len, 1n), newbr}
        case 1n+q:
          +bit = U32.and(buf, 1)
          +newbr : BR = BR{U32.div(buf, 2), q, rest}
          +newcode = U32.add(U32.mul(code, 2), bit)
          BitRead{newcode, Nat.add(len, 1n), newbr}

def huff_decode_some(+sym: U32, +br: BR) -> DecRes:
  DecOk{sym, br}

def huff_decode(+remaining: Nat, +m: Maybe<&2, U32>, +br: BR, +table: List<&2, HEnt>, +code: U32, +len: Nat) -> DecRes:
  match remaining:
    case 0n: DecFail{br}
    case 1n+p:
      match m:
        case Some{sym}: huff_decode_some(sym, br)
        case None{}:
          match len:
            case 15n: DecFail{br}
            case 1n+p2:
              +bit = br_bit(br)
              +br2 = br_next(br)
              +newcode = U32.add(U32.mul(code, 2), bit)
              +newlen = Nat.add(p2, 2n)
              huff_decode(p, lookup_ent(newlen, newcode, table), br2, table, newcode, newlen)
            case 0n:
              +bit = br_bit(br)
              +br2 = br_next(br)
              +newcode = U32.add(U32.mul(code, 2), bit)
              huff_decode(p, lookup_ent(1n, newcode, table), br2, table, newcode, 1n)

def huff_decode_entry(+remaining: Nat, +br: BR, +table: List<&2, HEnt>, +code: U32, +len: Nat) -> DecRes:
  huff_decode(remaining, lookup_ent(len, code, table), br, table, code, len)

# ---- length / distance tables

def len_extra_bits(idx: Nat) -> Nat:
  match idx:
    case 0n: 0n
    case 1n: 0n
    case 2n: 0n
    case 3n: 0n
    case 4n: 0n
    case 5n: 0n
    case 6n: 0n
    case 7n: 0n
    case 8n: 1n
    case 9n: 1n
    case 10n: 1n
    case 11n: 1n
    case 12n: 2n
    case 13n: 2n
    case 14n: 2n
    case 15n: 2n
    case 16n: 3n
    case 17n: 3n
    case 18n: 3n
    case 19n: 3n
    case 20n: 4n
    case 21n: 4n
    case 22n: 4n
    case 23n: 4n
    case 24n: 5n
    case 25n: 5n
    case 26n: 5n
    case 27n: 5n
    case 28n: 0n
    case 1n+p: 0n

def len_base(idx: Nat) -> U32:
  match idx:
    case 0n: 3
    case 1n: 4
    case 2n: 5
    case 3n: 6
    case 4n: 7
    case 5n: 8
    case 6n: 9
    case 7n: 10
    case 8n: 11
    case 9n: 13
    case 10n: 15
    case 11n: 17
    case 12n: 19
    case 13n: 23
    case 14n: 27
    case 15n: 31
    case 16n: 35
    case 17n: 43
    case 18n: 51
    case 19n: 59
    case 20n: 67
    case 21n: 83
    case 22n: 99
    case 23n: 115
    case 24n: 131
    case 25n: 163
    case 26n: 195
    case 27n: 227
    case 28n: 258
    case 1n+p: 258

def dist_extra_bits(idx: Nat) -> Nat:
  match idx:
    case 0n: 0n
    case 1n: 0n
    case 2n: 0n
    case 3n: 0n
    case 4n: 1n
    case 5n: 1n
    case 6n: 2n
    case 7n: 2n
    case 8n: 3n
    case 9n: 3n
    case 10n: 4n
    case 11n: 4n
    case 12n: 5n
    case 13n: 5n
    case 14n: 6n
    case 15n: 6n
    case 16n: 7n
    case 17n: 7n
    case 18n: 8n
    case 19n: 8n
    case 20n: 9n
    case 21n: 9n
    case 22n: 10n
    case 23n: 10n
    case 24n: 11n
    case 25n: 11n
    case 26n: 12n
    case 27n: 12n
    case 28n: 13n
    case 29n: 13n
    case 1n+p: 13n

def dist_base(idx: Nat) -> U32:
  match idx:
    case 0n: 1
    case 1n: 2
    case 2n: 3
    case 3n: 4
    case 4n: 5
    case 5n: 7
    case 6n: 9
    case 7n: 13
    case 8n: 17
    case 9n: 25
    case 10n: 33
    case 11n: 49
    case 12n: 65
    case 13n: 97
    case 14n: 129
    case 15n: 193
    case 16n: 257
    case 17n: 385
    case 18n: 513
    case 19n: 769
    case 20n: 1025
    case 21n: 1537
    case 22n: 2049
    case 23n: 3073
    case 24n: 4097
    case 25n: 6145
    case 26n: 8193
    case 27n: 12289
    case 28n: 16385
    case 29n: 24577
    case 1n+p: 24577

# ---- copy bytes for LZ77

def copy_bytes(+len: Nat, +dist: U32, +out: List<&2, U32>) -> List<&2, U32>:
  match len:
    case 0n: out
    case 1n+p:
      byte = nth_u32(U32.to_nat(U32.sub(dist, 1)), out)
      copy_bytes(p, dist, Con{byte, out})

# ---- fixed tables

def fixed_lit_lens() -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, rep_list(8, 144n), rep_list(9, 112n)), List.append(&2, U32, rep_list(7, 24n), rep_list(8, 8n)))

def fixed_dist_lens() -> List<&2, U32>:
  rep_list(5, 32n)

# ---- dynamic helpers

def clen_order() -> List<&2, Nat>:
  Con{16n, Con{17n, Con{18n, Con{0n, Con{8n, Con{7n, Con{9n, Con{6n, Con{10n, Con{5n, Con{11n, Con{4n, Con{12n, Con{3n, Con{13n, Con{2n, Con{14n, Con{1n, Con{15n, Nil{}}}}}}}}}}}}}}}}}}}}

def set_u32_wrap(+idx: Nat, val: U32, xs: List<&2, U32>) -> List<&2, U32>:
  set_u32(idx, val, xs, 0n, Nat.is_eq(0n, idx))

def fill_clen(rem: Nat, +lt: Bool, +lt2: Bool, r: RB, +i: Nat, +nclen: Nat, +order: List<&2, Nat>, +lens: List<&2, U32>) -> List<&2, U32> & BR:  match rem:
    case 0n:
      match lt:
        case False{}:
          match r:
            case RB{val, br}: (lens, br)
        case True{}:
          match lt2:
            case False{}:
              match r:
                case RB{val, br}: (lens, br)
            case True{}:
              match r:
                case RB{val, br}: (lens, br)
    case 1n+p:
      match lt:
        case False{}:
          match r:
            case RB{val, br}: (lens, br)
        case True{}:
          match lt2:
            case False{}:
              match r:
                case RB{val, br}: (lens, br)
            case True{}:
              match r:
                case RB{val, br}:
                  idx = nth_nat(i, order)
                  lens2 = set_u32_wrap(idx, val, lens)
                  fill_clen(p, Nat.is_lt(Nat.add(i, 1n), nclen), Nat.is_lt(Nat.add(i, 1n), 19n), br_readn(3n, br, 0, 1),
                    Nat.add(i, 1n), nclen, order, lens2)

def repeat_prepend(+val: U32, n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: repeat_prepend(val, p, Con{val, acc})

def rb_val(r: RB) -> U32:
  match r:
    case RB{val, br}: val

def rb_br(r: RB) -> BR:
  match r:
    case RB{val, br}: br

def split_lens(lens: List<&2, U32>, n: Nat, acc: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match lens:
    case Nil{}: (List.reverse(&2, U32, acc), Nil{})
    case Con{h, t}:
      match n:
        case 0n: (List.reverse(&2, U32, acc), lens)
        case 1n+p: split_lens(t, p, Con{h, acc})

# decode_lengths: self-recursive state machine for decoding code-length symbol runs.
# phase 0: need to decode m (call huff_decode_entry)
# phase 1: have m (DecRes), match it
# phase 2: have sym+br2 from DecOk, compute is_lt16
# phase 3: have is_lt16, branch
# phase 4: have is16, branch
# phase 5: have is17, branch
# phase 6: have r (RB from br_readn), extract rep and recurse
def decode_lengths(
  +fuel: Nat, +remaining: Nat, +br: BR, +table: List<&2, HEnt>, +prev_len: U32, +lens_rev: List<&2, U32>,
  +phase: Nat,
  +m: DecRes, +sym: U32, +br2: BR, +is_lt16: Bool, +is16: Bool, +is17: Bool, +r: RB
) -> BR & List<&2, U32>:
  match fuel:
    case 0n:
      (br, List.reverse(&2, U32, lens_rev))
    case 1n+fp:
      match remaining:
        case 0n:
          (br, List.reverse(&2, U32, lens_rev))
        case 1n+p:
          match phase:
            case 0n:
              +m2 = huff_decode_entry(15n, br, table, 0, 0n)
              decode_lengths(fp, remaining, br, table, prev_len, lens_rev, 1n, m2, 0, br, False{}, False{}, False{}, RB{0, br})
            case 1n:
              match m:
                case DecFail{br2}:
                  (br2, List.reverse(&2, U32, lens_rev))
                case DecOk{+sym, +br}:
                  decode_lengths(fp, p, br, table, prev_len, lens_rev, 2n, DecFail{br}, sym, br, False{}, False{}, False{}, RB{0, br})
            case 2n:
              +is_lt16 = U32.is_lt(sym, 16)
              decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 3n, DecFail{br2}, sym, br2, is_lt16, False{}, False{}, RB{0, br2})
            case 3n:
              match is_lt16:
                case True{}:
                  decode_lengths(fp, Nat.sub(remaining, 1n), br2, table, sym, Con{sym, lens_rev}, 0n, DecFail{br2}, 0, br2, False{}, False{}, False{}, RB{0, br2})
                case False{}:
                  +is16 = U32.is_eq(sym, 16)
                  decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 4n, DecFail{br2}, sym, br2, False{}, is16, False{}, RB{0, br2})
            case 4n:
              match is16:
                case True{}:
                  +r2 = br_readn(2n, br2, 0, 1)
                  decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 6n, DecFail{br2}, 0, br2, False{}, False{}, False{}, r2)
                case False{}:
                  +is17 = U32.is_eq(sym, 17)
                  decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 5n, DecFail{br2}, sym, br2, False{}, False{}, is17, RB{0, br2})
            case 5n:
              match is17:
                case True{}:
                  +r3 = br_readn(3n, br2, 0, 1)
                  decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 6n, DecFail{br2}, 0, br2, False{}, False{}, False{}, r3)
                case False{}:
                  +r7 = br_readn(7n, br2, 0, 1)
                  decode_lengths(fp, remaining, br2, table, prev_len, lens_rev, 6n, DecFail{br2}, 0, br2, False{}, False{}, False{}, r7)
            case 6n:
              match r:
                case RB{+rep0, +br2}:
                  +rep = Nat.add(U32.to_nat(rep0), 3n)
                  lens_rev_ = repeat_prepend(prev_len, rep, lens_rev)
                  decode_lengths(fp, Nat.sub(remaining, rep), br2, table, prev_len, lens_rev_, 0n, DecFail{br2}, 0, br2, False{}, False{}, False{}, RB{0, br2})
            case 1n+p:
              (br, List.reverse(&2, U32, lens_rev))

def decode_lengths_entry(+fuel: Nat, +remaining: Nat, +br: BR, +table: List<&2, HEnt>, +prev_len: U32, +lens_rev: List<&2, U32>) -> BR & List<&2, U32>:
  decode_lengths(fuel, remaining, br, table, prev_len, lens_rev, 0n, DecFail{br}, 0, br, False{}, False{}, False{}, RB{0, br})

# ---- huffman block inflate

# inflate_huffman_block: self-recursive state machine for one Huffman block.
# phase 0: need to decode m (call huff_decode_entry)
# phase 1: have m (DecRes), match it
# phase 2: have sym+br from DecOk, check is256
# phase 3: have is256, branch
# phase 4: have islt256, branch
# phase 5: length path: compute idx, extra, read r_len
# phase 6: have r_len (RB), compute length, decode dist symbol
# phase 7: have res_d (DecRes for dist), match it
# phase 8: have dsym+brd from DecOk, compute dextra, read r_dist
# phase 9: have r_dist (RB), compute distance, copy bytes, recurse
def inflate_huffman_block(
  fuel: Nat, +br: BR, +out: List<&2, U32>, +lit_table: List<&2, HEnt>, +dist_table: List<&2, HEnt>,
  +phase: Nat,
  +res: DecRes, +sym: U32, +br2: BR, +is256: Bool, +islt256: Bool, +idx: Nat, +extra: Nat, +r_len: RB, +eval: U32, +length: U32, +res_d: DecRes, +dsym: U32, +br3: BR, +dextra: Nat, +r_dist: RB, +dval: U32, +br4: BR, +distance: U32, +out2: List<&2, U32>
) -> HR:
  match fuel:
    case 0n: HR{br, out}
    case 1n+fp:
      match phase:
        case 0n:
          +m = huff_decode_entry(15n, br, lit_table, 0, 0n)
          inflate_huffman_block(fp, br, out, lit_table, dist_table, 1n, m, 0, br, False{}, False{}, 0n, 0n, RB{0, br}, 0, 0, DecFail{br}, 0, br, 0n, RB{0, br}, 0, br, 0, out)
        case 1n:
          match res:
            case DecFail{br2}: HR{br2, out}
            case DecOk{+sym, +br}:
              inflate_huffman_block(fp, br, out, lit_table, dist_table, 2n, DecFail{br}, sym, br, False{}, False{}, 0n, 0n, RB{0, br}, 0, 0, DecFail{br}, 0, br, 0n, RB{0, br}, 0, br, 0, out)
        case 2n:
          +is256 = U32.is_eq(sym, 256)
          inflate_huffman_block(fp, br2, out, lit_table, dist_table, 3n, DecFail{br2}, sym, br2, is256, False{}, 0n, 0n, RB{0, br2}, 0, 0, DecFail{br2}, 0, br2, 0n, RB{0, br2}, 0, br2, 0, out)
        case 3n:
          match is256:
            case True{}: HR{br2, out}
            case False{}:
              +islt256 = U32.is_lt(sym, 256)
              inflate_huffman_block(fp, br2, out, lit_table, dist_table, 4n, DecFail{br2}, sym, br2, False{}, islt256, 0n, 0n, RB{0, br2}, 0, 0, DecFail{br2}, 0, br2, 0n, RB{0, br2}, 0, br2, 0, out)
        case 4n:
          match islt256:
            case True{}:
              inflate_huffman_block(fp, br2, Con{sym, out}, lit_table, dist_table, 0n, DecFail{br2}, 0, br2, False{}, False{}, 0n, 0n, RB{0, br2}, 0, 0, DecFail{br2}, 0, br2, 0n, RB{0, br2}, 0, br2, 0, out)
            case False{}:
              +idx = U32.to_nat(U32.sub(sym, 257))
              +extra = len_extra_bits(idx)
              +r_len = br_readn(extra, br2, 0, 1)
              inflate_huffman_block(fp, br2, out, lit_table, dist_table, 5n, DecFail{br2}, 0, br2, False{}, False{}, idx, extra, r_len, 0, 0, DecFail{br2}, 0, br2, 0n, RB{0, br2}, 0, br2, 0, out)
        case 5n:
          match r_len:
            case RB{+eval, +br3}:
              +length = U32.add(len_base(idx), eval)
              +res_d = huff_decode_entry(15n, br3, dist_table, 0, 0n)
              inflate_huffman_block(fp, br3, out, lit_table, dist_table, 6n, res_d, 0, br3, False{}, False{}, 0n, 0n, RB{0, br3}, eval, length, res_d, 0, br3, 0n, RB{0, br3}, 0, br3, 0, out)
        case 6n:
          match res_d:
            case DecFail{brd}: HR{brd, out}
            case DecOk{+dsym, +brd}:
              +dextra = dist_extra_bits(U32.to_nat(dsym))
              +r_dist = br_readn(dextra, brd, 0, 1)
              inflate_huffman_block(fp, brd, out, lit_table, dist_table, 7n, DecFail{brd}, 0, brd, False{}, False{}, 0n, 0n, RB{0, brd}, 0, 0, DecFail{brd}, dsym, brd, dextra, r_dist, 0, brd, 0, out)
        case 7n:
          match r_dist:
            case RB{+dval, +br4}:
              distance = U32.add(dist_base(U32.to_nat(dsym)), dval)
              +out2 = copy_bytes(U32.to_nat(length), distance, out)
              inflate_huffman_block(fp, br4, out2, lit_table, dist_table, 0n, DecFail{br4}, 0, br4, False{}, False{}, 0n, 0n, RB{0, br4}, 0, 0, DecFail{br4}, 0, br4, 0n, RB{0, br4}, 0, br4, 0, out2)
        case 1n+p:
          HR{br, out}

# ---- main block loop

type InfState is Data:
  IS{br: BR, out: List<&2, U32>}

type InfRes is Data:
  IRFinal{out: List<&2, U32>}
  IRContinue{st: InfState}


# ---- InfRes result for block handlers
# (defined after InfState below; InfState already defined above? ensure)
# We'll add type after InfState definition later; here use InfState.


def uncomp_finish2(br: BR, out: List<&2, U32>, isfinal: Bool) -> InfRes:
  match isfinal:
    case True{}: IRFinal{out}
    case False{}: IRContinue{IS{br, out}}

def uncomp_finish(br: BR, bfinal: U32, out: List<&2, U32>) -> InfRes:
  uncomp_finish2(br, out, U32.is_eq(bfinal, 1))



def uncomp_block(fuel: Nat, +bits: Nat, +br: BR, +bfinal: U32, +out: List<&2, U32>, +phase: Nat, +len: U32, +byte_acc: U32, +shift: U32, +remaining: Nat) -> InfRes:  match fuel:
    case 0n:
      IRFinal{out}
    case 1n+fp:
      match bits:
        case 8n:
          match phase:
            case 0n:
              uncomp_block(fp, 0n, br, bfinal, out, 1n, byte_acc, 0, 1, remaining)
            case 1n:
              len2 = U32.add(len, U32.mul(byte_acc, 256))
              uncomp_block(fp, 0n, br, bfinal, out, 2n, len2, 0, 1, remaining)
            case 2n:
              uncomp_block(fp, 0n, br, bfinal, out, 3n, len, 0, 1, remaining)
            case 3n:
              uncomp_block(fp, 0n, br, bfinal, out, 4n, len, 0, 1, U32.to_nat(len))
            case 4n:
              match remaining:
                case 0n:
                  uncomp_finish(br, bfinal, Con{byte_acc, out})
                case 1n:
                  uncomp_finish(br, bfinal, Con{byte_acc, out})
                case 2n+q:
                  uncomp_block(fp, 0n, br, bfinal, Con{byte_acc, out}, 4n, len, 0, 1, Nat.sub(remaining, 1n))
            case 1n+p:
              uncomp_finish(br, bfinal, out)
        case x:
          match br:
            case BR{+buf, cnt, rest}:
              match cnt:
                case 0n:
                  match rest:
                    case Nil{}: IRFinal{out}
                    case Con{+b, t}:
                      uncomp_block(fp, Nat.add(bits, 1n), BR{U32.div(b, 2), 7n, t}, bfinal, out, phase, len,
                        U32.add(byte_acc, U32.mul(U32.and(b, 1), shift)), U32.mul(shift, 2), remaining)
                case 1n+q:
                  uncomp_block(fp, Nat.add(bits, 1n), BR{U32.div(buf, 2), q, rest}, bfinal, out, phase, len,
                    U32.add(byte_acc, U32.mul(U32.and(buf, 1), shift)), U32.mul(shift, 2), remaining)

def tuple_fst_br(r: BR & List<&2, U32>) -> BR:
  match r:
    case (a, b): a

def tuple_snd_list(r: BR & List<&2, U32>) -> List<&2, U32>:
  match r:
    case (a, b): b

def hr_br(h: HR) -> BR:
  match h:
    case HR{br, out}: br

def hr_out(h: HR) -> List<&2, U32>:
  match h:
    case HR{br, out}: out

def inflate_loop_fixed(+out: List<&2, U32>, bfinal: U32, +br2: BR) -> InfRes:
  lit_table = build_table(fixed_lit_lens())
  dist_table = build_table(fixed_dist_lens())
  +hr = inflate_huffman_block(100000n, br2, out, lit_table, dist_table, 0n, DecFail{br2}, 0, br2, False{}, False{}, 0n, 0n, RB{0, br2}, 0, 0, DecFail{br2}, 0, br2, 0n, RB{0, br2}, 0, br2, 0, out)
  br3 = hr_br(hr)
  +out2 = hr_out(hr)
  isfinal = U32.is_eq(bfinal, 1)
  Bool.pick(InfRes, isfinal, IRFinal{out2}, IRContinue{IS{br3, out2}})


def inflate_loop_dyn_done2(out2: List<&2, U32>, br8: BR, isfinal: Bool) -> InfRes:
  match isfinal:
    case True{}: IRFinal{out2}
    case False{}: IRContinue{IS{br8, out2}}
def inflate_loop_dyn6(out: List<&2, U32>, bfinal: U32, br7: BR, lit: List<&2, HEnt>, dist: List<&2, HEnt>, r: HR) -> InfRes:
  match r:
    case HR{br, out}:
      inflate_loop_dyn_done2(out, br, U32.is_eq(bfinal, 1))


def inflate_loop_dyn5b(+out: List<&2, U32>, +bfinal: U32, +br7: BR, nlit: Nat, all_lens: List<&2, U32>, r: List<&2, U32> & List<&2, U32>) -> InfRes:  match r:
    case (lit_lens, dist_lens):
      +lit_table = build_table(lit_lens)
      +dist_table = build_table(dist_lens)
      inflate_loop_dyn6(out, bfinal, br7, lit_table, dist_table, inflate_huffman_block(100000n, br7, out, lit_table, dist_table, 0n, DecFail{br7}, 0, br7, False{}, False{}, 0n, 0n, RB{0, br7}, 0, 0, DecFail{br7}, 0, br7, 0n, RB{0, br7}, 0, br7, 0, out))
def inflate_loop_dyn5(+out: List<&2, U32>, +bfinal: U32, +nlit: Nat, +ndist: Nat, +br6: BR, +clen_table: List<&2, HEnt>, r: BR & List<&2, U32>) -> InfRes:  match r:
    case (br7, all_lens):
      +br7b = br7
      +all_lensb = all_lens
      inflate_loop_dyn5b(out, bfinal, br7b, nlit, all_lensb, split_lens(all_lensb, nlit, Nil{}))




def inflate_loop_dyn4(+out: List<&2, U32>, +bfinal: U32, +nlit: Nat, +ndist: Nat, +nclen: Nat, +br5: BR, +order: List<&2, Nat>, +zeros: List<&2, U32>, r: List<&2, U32> & BR) -> InfRes:  match r:
    case (clen_lens, +br6):
      +clen_table = build_table(clen_lens)
      inflate_loop_dyn5(out, bfinal, nlit, ndist, br6, clen_table, decode_lengths_entry(Nat.add(nlit, ndist), Nat.add(nlit, ndist), br6, clen_table, 0, Nil{}))
def inflate_loop_dyn3(out: List<&2, U32>, bfinal: U32, hlit: U32, hdist: U32, r: RB) -> InfRes:
  match r:
    case RB{val, +br}:
      nlit = U32.to_nat(U32.add(hlit, 257))
      ndist = U32.to_nat(U32.add(hdist, 1))
      +nclen = U32.to_nat(U32.add(val, 4))
      +order = clen_order()
      +zeros = zeros_list(19n)
      inflate_loop_dyn4(out, bfinal, nlit, ndist, nclen, br, order, zeros, fill_clen(nclen, Nat.is_lt(0n, nclen), Nat.is_lt(0n, 19n), br_readn(3n, br, U32.from_nat(0n), U32.from_nat(1n)), 0n, nclen, order, zeros))


















def inflate_loop_dyn2(out: List<&2, U32>, bfinal: U32, hlit: U32, r: RB) -> InfRes:
  match r:
    case RB{+val, +br}:
      +brx = br
      inflate_loop_dyn3(out, bfinal, hlit, val, br_readn(4n, brx, 0, 1))

def inflate_loop_dyn1(out: List<&2, U32>, bfinal: U32, r: RB) -> InfRes:
  match r:
    case RB{val, br}:
      inflate_loop_dyn2(out, bfinal, val, br_readn(5n, br, 0, 1))


def inflate_loop_dyn(out: List<&2, U32>, bfinal: U32, +br2: BR) -> InfRes:
  r = br_readn(5n, br2, U32.from_nat(0n), U32.from_nat(1n))
  inflate_loop_dyn1(out, bfinal, r)

def inflate_loop_uncomp(out: List<&2, U32>, bfinal: U32, br2: BR) -> InfRes:
  br3 = br_align(br2)
  uncomp_block(100000n, 0n, br3, bfinal, out, 0n, 0, 0, 1, 0n)

def inflate_loop_handle(out: List<&2, U32>, bfinal: U32, br2: BR, bt: Nat) -> InfRes:
  match bt:
    case 0n: inflate_loop_uncomp(out, bfinal, br2)
    case 1n: inflate_loop_fixed(out, bfinal, br2)
    case 2n: inflate_loop_dyn(out, bfinal, br2)
    case 3n: IRFinal{out}
    case 1n+p: IRFinal{out}

def inflate_loop_top2(+out: List<&2, U32>, +bfinal: U32, +br: BR) -> InfRes:
  inflate_loop_handle(out, bfinal, br, U32.to_nat(bfinal))

def inflate_loop_top(out: List<&2, U32>, bfinal: U32, +br1: BR) -> InfRes:
  +bit0 = br_bit(br1)
  +br1b = br_next(br1)
  +bit1 = br_bit(br1b)
  +br2 = br_next(br1b)
  +btype_val = U32.add(bit0, U32.mul(bit1, 2))
  inflate_loop_handle(out, bfinal, br2, U32.to_nat(btype_val))

def inflate_loop_fuel(fuel: Nat, res: InfRes, fallback: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      fallback
    case 1n+fp:
      match res:
        case IRFinal{out}: out
        case IRContinue{st2}:
          match st2:
            case IS{+br2, +out2}:
              inflate_loop_fuel(fp, inflate_loop_top(out2, br_bit(br2), br_next(br2)), Nil{})

def inflate_loop(st: InfState) -> List<&2, U32>:
  match st:
    case IS{+br, +out}:
      inflate_loop_fuel(100000n, inflate_loop_top(out, br_bit(br), br_next(br)), Nil{})

# ---- public entry

def inflate(data: List<&2, U32>) -> List<&2, U32>:
  br : BR = BR{0, 0n, data}
  out_rev = inflate_loop(IS{br, Nil{}})
  List.reverse(&2, U32, out_rev)

# ---- filter name helpers

def name_flatedecode(n: String) -> Bool:
  String.eq(n, "FlateDecode")

# Find a dictionary entry by key string
def dict_find_key(els: List<&2, P.PEntry>, +k: String) -> P.Obj:
  match els:
    case Nil{}: P.ONil{}
    case Con{P.PE{+k2, +v}, rest}:
      Bool.pick(P.Obj, String.eq(k2, k), v, dict_find_key(rest, k))

# Check if an object is the name "FlateDecode"
def is_flate_name(o: P.Obj) -> Bool:
  match o:
    case P.OName{n}: name_flatedecode(n)
    case x: False{}

# Check if an array of names contains FlateDecode
def arr_contains_flate_next(rest: List<&2, P.Obj>, +hit: Bool) -> Bool:
  match rest:
    case Nil{}: False{}
    case Con{+e2, rest2}:
      match hit:
        case True{}: True{}
        case False{}: arr_contains_flate_next(rest2, is_flate_name(e2))

def arr_contains_flate(els: List<&2, P.Obj>) -> Bool:
  match els:
    case Nil{}: False{}
    case Con{+e, rest}:
      arr_contains_flate_next(rest, is_flate_name(e))

# Check if a filter spec (name or array of names) uses FlateDecode
def filter_is_flate(f: P.Obj) -> Bool:
  match f:
    case P.OName{n}: name_flatedecode(n)
    case P.OArr{els}:
      arr_contains_flate(els)
    case x: False{}
def hex_val(+b: U32) -> U32:
  is_d : Bool = Bool.and(U32.is_ge(b, 48), U32.is_le(b, 57))
  is_u : Bool = Bool.and(U32.is_ge(b, 65), U32.is_le(b, 70))
  is_l : Bool = Bool.and(U32.is_ge(b, 97), U32.is_le(b, 102))
  Bool.pick(U32, is_d, U32.sub(b, 48),
    Bool.pick(U32, is_u, U32.sub(b, 55),
      Bool.pick(U32, is_l, U32.sub(b, 87), 16)))

def is_ws(+b: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(b, 9), U32.is_eq(b, 10)),
          Bool.or(U32.is_eq(b, 13), U32.is_eq(b, 32)))

def ah_go(bs: List<&2, U32>, +acc: List<&2, U32>, +hi: U32, +has: Bool) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Bool.pick(List<&2, U32>, has,
        List.reverse(&2, U32, Con{U32.shln(hi, 4n), acc}),
        List.reverse(&2, U32, acc))
    case Con{+b, +t}:
      is_term : Bool = U32.is_eq(b, 62)
      ws : Bool = is_ws(b)
      +hv : U32 = hex_val(b)
      is_bad : Bool = U32.is_eq(hv, 16)
      Bool.pick(List<&2, U32>, is_term,
        Bool.pick(List<&2, U32>, has,
          List.reverse(&2, U32, Con{U32.shln(hi, 4n), acc}),
          List.reverse(&2, U32, acc)),
        Bool.pick(List<&2, U32>, ws,
          ah_go(t, acc, hi, has),
          Bool.pick(List<&2, U32>, is_bad,
            Bool.pick(List<&2, U32>, has,
              ah_go(t, acc, hi, True{}),
              ah_go(t, acc, 0, False{})),
            Bool.pick(List<&2, U32>, has,
              ah_go(t, Con{U32.or(U32.shln(hi, 4n), hv), acc}, 0, False{}),
              ah_go(t, acc, hv, True{})))))

def ascii_hex_decode(bs: List<&2, U32>) -> List<&2, U32>:
  ah_go(bs, Nil{}, 0, False{})



# Apply a single filter by name.



def head_of(bs: List<&2, U32>) -> U32:
  match bs:
    case Nil{}: 0
    case Con{b, t}: b

def tail_of(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: Nil{}
    case Con{b, t}: t

def rl_go(fuel: Nat, bs: List<&2, U32>, mode: Nat, n: U32, +byte: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+ +fp:
      match bs:
        case Nil{}:
          List.reverse(&2, U32, acc)
        case Con{+b, +t}:
          match mode:
            case 0n:
              # decode mode: classify b, compute next params, recurse once
              +is_eod : Bool = U32.is_eq(b, 128)
              +is_copy : Bool = U32.is_le(b, 127)
              next_mode : Nat = Bool.pick(Nat, is_eod, 3n, Bool.pick(Nat, is_copy, 1n, 2n))
              next_n : U32 = Bool.pick(U32, is_eod, U32.from_nat(0n),
                Bool.pick(U32, is_copy, U32.add(b, 1), U32.sub(257, b)))
              next_byte : U32 = Bool.pick(U32, is_eod, U32.from_nat(0n),
                Bool.pick(U32, is_copy, U32.from_nat(0n), head_of(t)))
              next_bs : List<&2, U32> = Bool.pick(List<&2, U32>, is_eod, t,
                Bool.pick(List<&2, U32>, is_copy, t, tail_of(t)))
              rl_go(fp, next_bs, next_mode, next_n, next_byte, acc)
            case 1n:
              # copy mode
              match n:
                case 0:
                  rl_go(fp, bs, 0n, U32.from_nat(0n), U32.from_nat(0n), acc)
                case _:
                  rl_go(fp, t, 1n, U32.sub(n, 1), U32.from_nat(0n), Con{b, acc})
            case 2n:
              # repeat mode
              match n:
                case 0:
                  rl_go(fp, bs, 0n, U32.from_nat(0n), U32.from_nat(0n), acc)
                case _:
                  rl_go(fp, bs, 2n, U32.sub(n, 1), byte, Con{byte, acc})
            case 3n+p:
              List.reverse(&2, U32, acc)

def run_length_decode(bs: List<&2, U32>) -> List<&2, U32>:
  rl_go(32768n, bs, 0n, U32.from_nat(0n), U32.from_nat(0n), Nil{})

def apply_filter_by_name3(+name: String, +body: List<&2, U32>) -> List<&2, U32>:
  eq_rl : Bool = String.eq(name, "RunLengthDecode")
  Bool.pick(List<&2, U32>, eq_rl, run_length_decode(body), body)


# ---- RunLengthDecode (7.4.4) ----
def apply_filter_by_name2(+name: String, +body: List<&2, U32>) -> List<&2, U32>:
  eq_hex : Bool = String.eq(name, "ASCIIHexDecode")
  Bool.pick(List<&2, U32>, eq_hex, ascii_hex_decode(body),
    apply_filter_by_name3(name, body))

# Helper: dispatch on a pre-computed Bool (binder) to avoid eager evaluation
# of both filter branches.
def apply_filter_by_name_dispatch(is_flate: Bool, name: String, +body: List<&2, U32>) -> List<&2, U32>:
  match is_flate:
    case True{}:
      inflate(body)
    case False{}:
      apply_filter_by_name2(name, body)

def apply_filter_by_name(+name: String, +body: List<&2, U32>) -> List<&2, U32>:
  eq_flate : Bool = String.eq(name, "FlateDecode")
  apply_filter_by_name_dispatch(eq_flate, name, body)

# Apply a filter spec (name or array) to a body.
# Arrays are applied in reverse order when decoding (last filter first).
def apply_filter_name(f: P.Obj, body: List<&2, U32>) -> List<&2, U32>:
  match f:
    case P.OName{n}:
      apply_filter_by_name(n, body)
    case x: body


def apply_filter_chain_fwd(els: List<&2, P.Obj>, body: List<&2, U32>) -> List<&2, U32>:
  match els:
    case Nil{}: body
    case Con{f, rest}:
      # dispatch f by name (avoid mutual recursion with apply_filter)
      decoded : List<&2, U32> = apply_filter_name(f, body)
      apply_filter_chain_fwd(rest, decoded)

def apply_filter_chain(els: List<&2, P.Obj>, body: List<&2, U32>) -> List<&2, U32>:
  # Filters applied in order when encoding; decode in reverse.
  # Reverse the list, then apply each filter in sequence.
  rev : List<&2, P.Obj> = List.reverse(&2, P.Obj, els)
  apply_filter_chain_fwd(rev, body)

def apply_filter(filt: P.Obj, body: List<&2, U32>) -> List<&2, U32>:
  match filt:
    case P.OName{n}: apply_filter_by_name(n, body)
    case P.OArr{els}: apply_filter_chain(els, body)
    case x: body



def decode_stream_body_dict(els: List<&2, P.PEntry>, body: List<&2, U32>) -> List<&2, U32>:
  filt = dict_find_key(els, "Filter")
  apply_filter(filt, body)

def decode_stream_body(d: P.Obj, body: List<&2, U32>) -> List<&2, U32>:
  match d:
    case P.ODict{els}:
      decode_stream_body_dict(els, body)
    case x: body

# ---- ASCIIHexDecode (7.4.2) ----