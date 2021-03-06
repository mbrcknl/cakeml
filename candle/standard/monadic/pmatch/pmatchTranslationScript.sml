open HolKernel boolLib bossLib lcsymtacs
open holKernelTheory
open pmatchExamplesTheory ml_translatorLib
open ml_monadTheory

val _ = new_theory"pmatchTranslation"

val _ = translation_extends"ml_monad";

val res = translate alphavars_def
val res = translate raconv_PMATCH
val res = translate is_eq_PMATCH
(*
dest_eq (* m_translate *)
dest_abs (* m_translate *)
dest_comb (* m_translate *)
dest_var (* m_translate *)
type_of (* m_translate *)
*)

val _ = export_theory()
