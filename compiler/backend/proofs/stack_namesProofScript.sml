open preamble
     stack_namesTheory
     stackSemTheory stackPropsTheory
local open dep_rewrite in end

val _ = new_theory"stack_namesProof";

(* TODO: move *)

val BIJ_IMP_11 = prove(
  ``BIJ f UNIV UNIV ==> !x y. (f x = f y) = (x = y)``,
  fs [BIJ_DEF,INJ_DEF] \\ metis_tac []);

val FLOOKUP_MAP_KEYS = Q.store_thm("FLOOKUP_MAP_KEYS",
  `INJ f (FDOM m) UNIV ⇒
   FLOOKUP (MAP_KEYS f m) k =
   OPTION_BIND (some x. k = f x ∧ x ∈ FDOM m) (FLOOKUP m)`,
  strip_tac >> DEEP_INTRO_TAC some_intro >>
  simp[FLOOKUP_DEF,MAP_KEYS_def]);

val FLOOKUP_MAP_KEYS_MAPPED = Q.store_thm("FLOOKUP_MAP_KEYS_MAPPED",
  `INJ f UNIV UNIV ⇒
   FLOOKUP (MAP_KEYS f m) (f k) = FLOOKUP m k`,
  strip_tac >>
  `INJ f (FDOM m) UNIV` by metis_tac[INJ_SUBSET,SUBSET_UNIV,SUBSET_REFL] >>
  simp[FLOOKUP_MAP_KEYS] >>
  DEEP_INTRO_TAC some_intro >> rw[] >>
  fs[INJ_DEF] >> fs[FLOOKUP_DEF] >> metis_tac[]);

(* -- *)

val rename_state_def = Define `
  rename_state f s =
   s with
   <| regs := MAP_KEYS (find_name f) s.regs
    ; code := fromAList (compile f (toAList s.code))
    |>`

val get_var_find_name = store_thm("get_var_find_name[simp]",
  ``BIJ (find_name f) UNIV UNIV ==>
    get_var (find_name f v) (rename_state f s) = get_var v s``,
  fs [get_var_def,rename_state_def,FLOOKUP_DEF,MAP_KEYS_def]
  \\ rpt strip_tac \\ imp_res_tac BIJ_IMP_11 \\ fs []
  \\ rw [] \\ fs [] \\ once_rewrite_tac [EQ_SYM_EQ]
  \\ match_mp_tac (MAP_KEYS_def |> SPEC_ALL |> CONJUNCT2 |> MP_CANON)
  \\ fs [INJ_DEF]);

val FLOOKUP_rename_state_find_name = Q.store_thm("FLOOKUP_rename_state_find_name[simp]",
  `BIJ (find_name f) UNIV UNIV ⇒
   FLOOKUP (rename_state f s).regs (find_name f k) = FLOOKUP s.regs k`,
  rw[BIJ_DEF] >>
  rw[rename_state_def] >>
  simp[FLOOKUP_MAP_KEYS_MAPPED]);

val inst_rename = Q.store_thm("inst_rename",
  `BIJ (find_name f) UNIV UNIV ⇒
   inst (inst_find_name f i) (rename_state f s) =
   OPTION_MAP (rename_state f) (inst i s)`,
  rw[inst_def] >>
  rw[inst_find_name_def] >>
  CASE_TAC >> fs[] >- (
    EVAL_TAC >>
    simp[state_component_equality] >>
    dep_rewrite.DEP_REWRITE_TAC[MAP_KEYS_FUPDATE] >>
    conj_tac >- (
      fs[BIJ_IFF_INV,INJ_DEF] >>
      metis_tac[] ) >>
    simp[fmap_eq_flookup,FLOOKUP_UPDATE] >>
    gen_tac >>
    `INJ (find_name f) (FDOM s.regs) UNIV` by
      metis_tac[BIJ_IMP_11,INJ_DEF,IN_UNIV] >>
    simp[FLOOKUP_MAP_KEYS] >>
    DEEP_INTRO_TAC some_intro >> simp[] >>
    simp[find_name_def] ) >>
  cheat
  (*
  CASE_TAC >> fs[assign_def,word_exp_def] >>
  every_case_tac >> fs[LET_THM,word_exp_def,ri_find_name_def,wordSemTheory.num_exp_def] >>
  rw[] >> fs[] >> rfs[] >> rw[]
  *));

val comp_correct = prove(
  ``!p s r t.
      evaluate (p,s) = (r,t) /\ BIJ (find_name f) UNIV UNIV /\
      ~s.use_alloc /\ ~s.use_store /\ ~s.use_stack ==>
      evaluate (comp f p, rename_state f s) = (r, rename_state f t)``,
  recInduct evaluate_ind \\ rpt strip_tac
  THEN1 (fs [evaluate_def,comp_def] \\ rpt var_eq_tac)
  THEN1 (fs [evaluate_def,comp_def] \\ rpt var_eq_tac \\ CASE_TAC \\ fs [])
  THEN1 (fs [evaluate_def,comp_def,rename_state_def] \\ rpt var_eq_tac \\ fs [])
  THEN1 (fs [evaluate_def,comp_def] >>
    every_case_tac >> fs[] >> rveq >> fs[] >>
    imp_res_tac inst_rename >> fs[])
  THEN1 cheat
  THEN1 cheat
  THEN1 (fs [evaluate_def,comp_def,rename_state_def] \\ rw []
         \\ fs [] \\ rw [] \\ fs [empty_env_def,dec_clock_def])
  THEN1
   (simp [Once evaluate_def,Once comp_def]
    \\ fs [evaluate_def,LET_DEF] \\ split_pair_tac \\ fs []
    \\ rw [] \\ fs [] \\ rfs [] \\ fs []
    \\ imp_res_tac evaluate_consts \\ fs [])
  THEN1 (fs [evaluate_def,comp_def] \\ rpt var_eq_tac \\ every_case_tac \\ fs [])
  THEN1 (fs [evaluate_def,comp_def] \\ rpt var_eq_tac \\ every_case_tac \\ fs [])
  \\ cheat);

val compile_semantics = store_thm("compile_semantics",
  ``BIJ (find_name f) UNIV UNIV /\
    ~s.use_alloc /\ ~s.use_store /\ ~s.use_stack ==>
    semantics start (rename_state f s) = semantics start s``,
  cheat);

val _ = export_theory();