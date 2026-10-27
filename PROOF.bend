# PROOF.bend — the gate. AI writes proofs here; LAWS.bend is not editable.
# Run: bend PROOF.bend            (fast check)
# Run: bend PROOF.bend --verdict  (proven BendTT kernel, include in CI)

import Base
import ./LAWS.bend as Laws

def Laws.nat_add_zero(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Laws.nat_add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def Laws.lex_empty():
  {==}

def Laws.lex_int12():
  {==}

def Laws.lex_ws_gap():
  {==}

def Laws.lex_comment():
  {==}

def Laws.lex_str_esc():
  {==}

def Laws.lex_name_gs():
  {==}

def Laws.lex_dict_open():
  {==}

def Laws.par_empty():
  {==}

def Laws.par_num_obj():
  {==}

def Laws.par_ref_err():
  {==}

def Laws.res_dict_root():
  {==}

def Laws.res_obj_miss():
  {==}

def Laws.res_obj_found():
  {==}

def Laws.val_one_page():
  {==}

def Laws.val_trailer_no_root():
  {==}

def Laws.val_page_no_parent():
  {==}

def Laws.dict_get_encrypt_found():
  {==}

def Laws.dict_get_encrypt_missing():
  {==}

def Laws.val_encrypt_rejected():
  {==}

def Laws.xs_lex_body():
  {==}

def Laws.xs_w_w142():
  {==}

def Laws.xs_decode_w1410():
  {==}

def Laws.xs_audit_exact():
  {==}

def Laws.os_take_two():
  {==}

def Laws.os_drop_header8():
  {==}

def Laws.osh_fuel_gate():
  {==}

def Laws.os_gen_gen_zero():
  {==}

def Laws.osh_ord_bad():
  {==}

def Laws.osh_start_two_pairs():
  {==}



def Laws.bool_true():
  {==}

def Laws.bool_false():
  {==}

def Laws.bool_case():
  {==}

def Laws.bool_dict_true():
  {==}

def Laws.null_stored():
  {==}

def Laws.null_trailer_missing():
  {==}

def Laws.lex_int_neg():
  {==}

def Laws.lex_int_pos():
  {==}

def Laws.lex_real_embed():
  {==}

def Laws.lex_real_neg():
  {==}

def Laws.lex_real_lead_dot():
  {==}

def Laws.lex_real_trail_dot():
  {==}

def Laws.size_real_rejected():
  {==}

def Laws.xref_offset_int():
  {==}

def Laws.xref_offset_real():
  {==}

def Laws.xref_entry_offset_real():
  {==}

def Laws.xref_entry_gen_real():
  {==}

def Laws.xref_entry_int_ok():
  {==}


def Laws.par_arr():
  {==}

def Laws.par_hex_str():
  {==}

def Laws.par_name_hash():
  {==}

def Laws.par_name_empty():
  {==}

def Laws.par_str():
  {==}


def Laws.hdr_valid():
  {==}

def Laws.hdr_obj_zero():
  {==}

def Laws.hdr_obj_neg():
  {==}

def Laws.hdr_obj_frac():
  {==}

def Laws.hdr_gen_neg():
  {==}

def Laws.hdr_gen_frac():
  {==}


def Laws.par_hdr_valid():
  {==}

def Laws.par_hdr_obj_zero():
  {==}

def Laws.par_hdr_obj_neg():
  {==}

def Laws.par_hdr_obj_frac():
  {==}

def Laws.par_hdr_gen_neg():
  {==}

def Laws.par_hdr_gen_frac():
  {==}

def Laws.val_page_no_count():
  {==}

def Laws.val_page_mediabox_bad():
  {==}

def Laws.val_page_count_mismatch():
  {==}

def Laws.val_page_badres():
  {==}

def Laws.val_catalog_badres():
  {==}
