open preamble wordsTheory wordsLib integer_wordTheory gc_sharedTheory basic_gcTheory;

val _ = new_theory "generational_gc";

val gc_state_component_equality = DB.fetch "gc_shared" "gc_state_component_equality";

val _ = Datatype `
  gen_gc_conf =
    <| limit : num              (* size of heap *)
     ; isRef : 'a -> bool
     ; gen_start : num          (* start of generation *)
     ; gen_end : num            (* end of generation *)
     ; refs_start : num         (* start of references, gen_end < refs_start *)
     |>`;

val gc_move_def = Define `
  (gc_move conf state (Data d) = (Data d, state)) /\
  (gc_move conf state (Pointer ptr d) =
     if ptr < conf.gen_start \/ conf.refs_start <= ptr then
       (Pointer ptr d,state) else
     case heap_lookup ptr state.heap of
     | SOME (DataElement xs l dd) =>
      (let ok = state.ok /\ l+1 <= state.n /\ ~(conf.isRef dd) in
       let n = state.n - (l + 1) in
       let h2 = state.h2 ++ [DataElement xs l dd] in
       let (heap,ok) = gc_forward_ptr ptr state.heap state.a d ok in
       let a = state.a + l + 1 in
         (Pointer state.a d
         ,state with <| h2 := h2; n := n; a := a; heap := heap; ok := ok |>))
     | SOME (ForwardPointer ptr _ l) => (Pointer ptr d,state)
     | _ => (Pointer ptr d, state with <| ok := F |>) )`;

val gc_move_IMP = prove(
  ``!x x' state state1.
    (gc_move conf state x = (x',state1)) ==>
    (state1.old = state.old) /\
    (state1.h1 = state.h1) /\
    (state1.r3 = state.r3) /\
    (state1.r2 = state.r2) /\
    (state1.r1 = state.r1)``,
  Cases
  \\ fs [gc_move_def]
  \\ ntac 3 strip_tac
  \\ IF_CASES_TAC >- fs [gc_state_component_equality]
  \\ strip_tac
  \\ fs []
  \\ Cases_on `heap_lookup n state.heap`
  \\ fs [gc_state_component_equality]
  \\ Cases_on `x`
  \\ fs [LET_THM,gc_state_component_equality]
  \\ rpt (pairarg_tac \\ fs [])
  \\ fs [gc_state_component_equality]);

val gc_move_list_def = Define `
  (gc_move_list conf state [] = ([], state)) /\
  (gc_move_list conf state (x::xs) =
    let (x,state) = gc_move conf state x in
    let (xs,state) = gc_move_list conf state xs in
      (x::xs,state))`;

val gc_move_list_IMP = prove(
  ``!xs xs' state state1.
    (gc_move_list conf state xs = (xs',state1)) ==>
    (LENGTH xs = LENGTH xs') /\
    (state1.old = state.old) /\
    (state1.h1 = state.h1) /\
    (state1.r3 = state.r3) /\
    (state1.r2 = state.r2) /\
    (state1.r1 = state.r1)``,
  Induct
  \\ fs [gc_move_list_def,LET_THM]
  \\ ntac 5 strip_tac
  \\ pairarg_tac
  \\ Cases_on `xs'`
  \\ fs []
  \\ pairarg_tac \\ fs []
  \\ rpt var_eq_tac
  \\ drule gc_move_IMP
  \\ metis_tac []);

val gc_move_data_def = tDefine "gc_move_data"  `
  (gc_move_data conf state =
    case state.h2 of
    | [] => state
    | h::h2 =>
      if conf.limit < heap_length (state.h1 ++ h::h2) then state with <| ok := F |> else
       case h of
       | DataElement xs l d =>
         let (xs,state) = gc_move_list conf state xs in
         let h1 = state.h1 ++ [DataElement xs l d] in
         let h2 = TL state.h2 in
         let ok = state.ok /\ state.h2 <> [] /\ (HD state.h2 = h) in
           gc_move_data conf (state with <| h1 := h1; h2 := h2; ok := ok |>)
       | _ => state with <| ok := F |>)`
  (WF_REL_TAC `measure (\(conf,state). conf.limit - heap_length state.h1)`
  \\ rw [heap_length_def,el_length_def,SUM_APPEND]
  \\ imp_res_tac (GSYM gc_move_list_IMP)
  \\ fs []
  \\ decide_tac)

val gc_move_data_IMP = prove(
  ``!conf state state1.
    (gc_move_data conf state = state1) ==>
    (state1.old = state.old) /\
    (state1.r1 = state.r1)
  ``,
  recInduct (fetch "-" "gc_move_data_ind")
  \\ rpt gen_tac
  \\ strip_tac
  \\ once_rewrite_tac [gc_move_data_def]
  \\ CASE_TAC
  \\ IF_CASES_TAC \\ fs []
  \\ CASE_TAC \\ fs []
  \\ pairarg_tac \\ fs []
  \\ rfs []
  \\ drule gc_move_list_IMP
  \\ strip_tac \\ fs []);

val gc_move_ref_list_def = Define `
  (gc_move_ref_list conf state [] = ([], state)) /\
  (gc_move_ref_list conf state (DataElement ptrs l d::xs) =
    let (ptrs', state) = gc_move_list conf state ptrs in
    let (xs,state) = gc_move_ref_list conf state xs in
      (DataElement ptrs' l d::xs,state)) /\
  (gc_move_ref_list conf state (x::xs) = (x::xs,state with ok := F))`;

val gc_move_ref_list_IMP = prove (
  ``!conf state refs state1 refs1.
    (gc_move_ref_list conf state refs = (refs1,state1)) ==>
    (state1.old = state.old) /\
    (heap_length refs = heap_length refs1) /\
    (!ptr.
       isSomeDataElement (heap_lookup ptr refs) ==>
       isSomeDataElement (heap_lookup ptr refs1))
  ``,
  recInduct (theorem "gc_move_ref_list_ind")
  \\ once_rewrite_tac [gc_move_ref_list_def] \\ fs []
  \\ rpt gen_tac
  \\ strip_tac
  \\ rpt gen_tac
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ strip_tac \\ rveq
  \\ drule gc_move_list_IMP
  \\ strip_tac \\ rveq
  \\ fs []
  \\ fs [heap_length_def,el_length_def]
  \\ simp [heap_lookup_def]
  \\ strip_tac
  \\ IF_CASES_TAC \\ fs []
  >- simp [isSomeDataElement_def]
  \\ IF_CASES_TAC \\ fs [el_length_def]);

val partial_gc_def = Define `
  partial_gc conf (roots,heap) =
    let ok0 = (heap_length heap = conf.limit) in
    case heap_segment (conf.gen_start,conf.refs_start) heap of
    | NONE => (roots,empty_state with <| ok := F |>)
    | SOME (old,current,refs) =>
      let n = heap_length current in
      let state = empty_state
          with <| heap := heap
                ; old := old
                ; r2 := refs
                ; a := conf.gen_start; n := n |> in
        (* process roots: *)
      let (roots,state) = gc_move_list conf state roots in
        (* process references: *)
      let (refs',state) = gc_move_ref_list conf state refs in
        (* process rest: *)
      let state = gc_move_data conf (state with r1 := refs') in
      (* let ok = ok0 /\ state.ok /\ *)
      (*          (state.a = conf.gen_start + heap_length state.h1) /\ *)
      (*          (state.r = heap_length state.r1) /\ *)
      (*          (heap_length state.heap = conf.limit) /\ *)
      (*          (state.a + state.n + state.r = conf.limit) /\ *)
      (*          state.a + state.r <= conf.limit in *)
      (roots,state)`;

val partial_gc_IMP = prove(
  ``!roots heap roots1 state1 heap_old heap_current heap_refs.
    (partial_gc conf (roots,heap) = (roots1,state1)) /\
    (heap_segment (conf.gen_start,conf.refs_start) heap =
      SOME (heap_old,heap_current,heap_refs)) ==>
    (state1.old = heap_old) /\
    (heap_length state1.r1 = heap_length heap_refs) /\
    (LENGTH roots = LENGTH roots1) /\
    (!ptr.
       isSomeDataElement (heap_lookup ptr heap_refs) ==>
       isSomeDataElement (heap_lookup ptr state1.r1))
  ``,
  rpt gen_tac
  \\ strip_tac
  \\ fs [partial_gc_def]
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ drule gc_move_data_IMP
  \\ strip_tac \\ fs []
  \\ rveq
  \\ pop_assum (assume_tac o GSYM)
  \\ fs []
  \\ drule gc_move_ref_list_IMP \\ strip_tac
  \\ fs []
  \\ drule gc_move_list_IMP
  \\ strip_tac \\ fs []);

(* Pointers between current and old generations are correct *)
val heap_gen_ok_def = Define `
  heap_gen_ok heap conf =
    ?old current refs.
      (SOME (old, current, refs) = heap_segment (conf.gen_start, conf.refs_start) heap) /\
      (* old points only to itself and references *)
      (!ptr xs l d u. MEM (DataElement xs l d) old /\ MEM (Pointer ptr u) xs ==>
        (ptr < conf.gen_start \/ conf.refs_start <= ptr)) /\
      (* old contains no references *)
      (!xs l d. MEM (DataElement xs l d) old ==> ~ (conf.isRef d)) /\
      (* refs only contains references *)
      (!xs l d. MEM (DataElement xs l d) refs ==> conf.isRef d)`;

val _ = Datatype `
  data_sort = Protected 'a      (* pointer to old generations *)
            | Real 'b`;         (* data or pointer to current generation *)

val to_basic_heap_address_def = Define `
  (to_basic_heap_address conf (Data a) = Data (Real a)) /\
  (to_basic_heap_address conf (Pointer ptr a) =
    if ptr < conf.gen_start then
      Data (Protected (Pointer ptr a))
    else if conf.refs_start <= ptr then
      Data (Protected (Pointer ptr a))
    else
      Pointer (ptr - conf.gen_start) (Real a))`;

(* val to_gen_heap_address_def = Define ` *)
(*   (to_gen_heap_address gen_start (Data (Protected a)) = a) /\ *)
(*   (to_gen_heap_address gen_start (Data (Real b)) = Data b) /\ *)
(*   (to_gen_heap_address gen_start (Pointer ptr (Real a)) = Pointer (ptr + gen_start) a)`; *)

val to_basic_conf_def = Define `
  to_basic_conf (conf:'a gen_gc_conf) =
    <| limit := conf.limit - conf.gen_start - (conf.limit - conf.refs_start)
     ; isRef := conf.isRef |>
     : 'a basic_gc_conf`;

val to_basic_heap_element_def = Define `
  (to_basic_heap_element conf (Unused n) = Unused n) /\
  (to_basic_heap_element conf (ForwardPointer ptr a l) =
    ForwardPointer (ptr - conf.gen_start) (Real a) l) /\
  (to_basic_heap_element conf (DataElement ptrs l d) =
    DataElement (MAP (to_basic_heap_address conf) ptrs) l d)`;

val to_basic_heap_list_def = Define `
  to_basic_heap_list conf heap =
    MAP (to_basic_heap_element conf) heap`;

val to_basic_heap_list_heap_length = prove(
  ``!xs.
    heap_length (to_basic_heap_list conf xs) = heap_length xs``,
  Induct
  \\ fs [to_basic_heap_list_def]
  \\ Cases
  \\ fs [heap_length_def,to_basic_heap_element_def,el_length_def]);

val to_basic_heap_def = Define `
  to_basic_heap conf heap =
    to_basic_heap_list conf
        (heap_restrict conf.gen_start conf.refs_start heap)`;

val to_basic_state_def = Define `
  to_basic_state conf state =
    empty_state with
    <| h1 := to_basic_heap_list conf state.h1
     ; h2 := to_basic_heap_list conf state.h2
     ; r4 := []
     ; r3 := []
     ; r2 := []
     ; r1 := []
     ; a := state.a - conf.gen_start
     ; n := state.n
     ; ok := state.ok
     ; heap := to_basic_heap conf state.heap
     ; heap0 := to_basic_heap conf state.heap0
     |>`;

val to_basic_roots_def = Define `
  to_basic_roots conf roots =
    MAP (to_basic_heap_address conf) roots`;

val refs_to_roots_def = Define `
  (refs_to_roots conf [] = []) /\
  (refs_to_roots conf (DataElement ptrs _ _::refs) =
    MAP (to_basic_heap_address conf) ptrs ++ refs_to_roots conf refs) /\
  (refs_to_roots conf (_::refs) = refs_to_roots conf refs)`;

val (RootsRefs_def,RootsRefs_ind,RootsRefs_cases) = Hol_reln `
  (RootsRefs [] []) /\
  (!ptrs m b refs roots ptr a.
     RootsRefs (DataElement ptrs m b::refs) roots ==>
     RootsRefs (DataElement (Pointer ptr a::ptrs) m b::refs) (Pointer ptr a::roots)) /\
  (!ptrs m b refs roots a.
     RootsRefs (DataElement ptrs m b::refs) roots ==>
     RootsRefs (DataElement (Data a::ptrs) m b::refs) (Data a::roots)) /\
  (!refs roots m b.
     RootsRefs refs roots ==>
     RootsRefs (DataElement [] m b::refs) roots) /\
  (!refs roots n.
     RootsRefs refs roots ==>
     RootsRefs (Unused n::refs) roots) /\
  (!refs roots.
     RootsRefs refs roots ==>
     RootsRefs (ForwardPointer _ _ _::refs) roots)`;

(* val RootsRefs_related = prove( *)
(*   ``!refs. RootsRefs (to_basic_heap_list conf refs) (refs_to_roots conf refs)``, *)
(*   Induct *)
(*   >- (simp [refs_to_roots_def] *)
(*      \\ metis_tac [RootsRefs_cases]) *)
(*   \\ Cases \\ fs [refs_to_roots_def,to_basic_heap_list_def,to_basic_heap_element_def] *)
(*   >- metis_tac [RootsRefs_cases] *)
(*   >- metis_tac [RootsRefs_cases] *)
(*   \\ Induct_on `l` \\ fs [] *)
(*   >- metis_tac [RootsRefs_cases] *)
(*   \\ reverse Cases *)
(*   >- (fs [to_basic_heap_address_def] *)
(*      \\ metis_tac [RootsRefs_cases]) *)
(*   \\ fs [to_basic_heap_address_def] *)
(*   \\ IF_CASES_TAC *)
(*   >- metis_tac [RootsRefs_cases] *)
(*   \\ IF_CASES_TAC *)
(*   \\ metis_tac [RootsRefs_cases]); *)

(*

     GenGC     GC
inp    o ----> o
       |       |
       |       |
       v       v
out    o ----> o

last step: need a relation <---
 *)

val heap_element_is_ref_def = Define `
  (heap_element_is_ref conf (DataElement xs l d) = conf.isRef d) /\
  (heap_element_is_ref conf _ = F)`;

val gen_inv_def = Define `
  gen_inv (conf:'b gen_gc_conf) heap =
    conf.gen_start <= conf.refs_start /\
    conf.refs_start <= conf.limit /\
    ?heap_old heap_current heap_refs.
      (heap_segment (conf.gen_start,conf.refs_start) heap =
        SOME (heap_old,heap_current,heap_refs)) /\
      EVERY (λe. ¬heap_element_is_ref conf e) heap_old /\
      EVERY (λe. ¬heap_element_is_ref conf e) heap_current /\
      EVERY isDataElement heap_refs /\
      (!n a d.
         MEM (ForwardPointer n a d) heap ==>
         conf.gen_start <= n /\ n < conf.refs_start) /\
      EVERY isDataElement heap_old /\
      !xs l d ptr u.
        MEM (DataElement xs l d) heap_old /\ MEM (Pointer ptr u) xs ==>
        ptr < conf.gen_start \/ conf.refs_start <= ptr`;

val heap_length_to_basic_heap_list = store_thm("heap_length_to_basic_heap_list[simp]",
  ``!h2. heap_length (to_basic_heap_list conf h2) = heap_length h2``,
  rewrite_tac [to_basic_heap_list_def]
  \\ Induct
  \\ fs [heap_length_def]
  \\ Cases
  \\ fs [to_basic_heap_element_def]
  \\ fs [el_length_def]);

val gc_move_simulation = prove(
  ``!ptr ptr' state state'.
      gen_inv conf state.heap /\
      conf.gen_start <= state.a /\
      (gc_move conf state ptr = (ptr', state')) ==>
      gen_inv conf state'.heap /\
      conf.gen_start <= state'.a /\
      (basic_gc$gc_move
         (to_basic_conf conf)
         (to_basic_state conf state)
         (to_basic_heap_address conf ptr)
       = (to_basic_heap_address conf ptr', to_basic_state conf state'))``,

  reverse Cases
  \\ fs []
  \\ rpt gen_tac
  \\ strip_tac
  \\ fs [to_basic_heap_address_def]
  >- (fs [gc_move_def,basic_gcTheory.gc_move_def]
     \\ rveq
     \\ fs [to_basic_heap_address_def]
     \\ metis_tac [])
  \\ fs []
  \\ IF_CASES_TAC
  >- (fs [gc_move_def,basic_gcTheory.gc_move_def]
     \\ rveq
     \\ fs [to_basic_heap_address_def]
     \\ metis_tac [])
  \\ IF_CASES_TAC
  >- (fs [gc_move_def,basic_gcTheory.gc_move_def]
     \\ rveq
     \\ fs [to_basic_heap_address_def]
     \\ metis_tac [])
  \\ fs [gc_move_def,basic_gcTheory.gc_move_def]
  \\ `heap_lookup (n − conf.gen_start) (to_basic_state conf state).heap =
      case heap_lookup n state.heap of
      | NONE => NONE
      | SOME y => SOME (to_basic_heap_element conf y)` by
   (fs [gen_inv_def] \\ fs [heap_restrict_def]
    \\ drule heap_segment_IMP \\ fs []
    \\ disch_then (strip_assume_tac o GSYM)
    \\ fs [heap_length_APPEND]
    \\ full_simp_tac std_ss [GSYM APPEND_ASSOC]
    \\ fs [heap_lookup_APPEND,to_basic_state_def,to_basic_heap_def]
    \\ fs [heap_restrict_def]
    \\ qmatch_goalsub_rename_tac `heap_lookup i (_ _ h1)`
    \\ qspec_tac (`i`,`i`)
    \\ qspec_tac (`h1`,`h1`)
    \\ Induct \\ fs [heap_lookup_def,to_basic_heap_list_def]
    \\ `!h:('a,'b) heap_element.
         el_length (to_basic_heap_element conf h) = el_length h` by
           (Cases \\ EVAL_TAC) \\ fs []
    \\ rw [] \\ fs [] \\ rfs [] \\ NO_TAC)
  \\ fs []
  \\ Cases_on `heap_lookup n state.heap` \\ fs []
  THEN1 (fs [] \\ rveq
         \\ fs [to_basic_heap_address_def,to_basic_state_def,gen_inv_def]
         \\ metis_tac [])
  \\ Cases_on `x` \\ fs [to_basic_heap_element_def]
  THEN1 (rveq \\ fs [to_basic_heap_address_def,to_basic_state_def,gen_inv_def]
         \\ metis_tac [])
  THEN1
   (rveq \\ fs [to_basic_heap_address_def,to_basic_state_def]
    \\ rfs [to_basic_heap_def,heap_restrict_def,gen_inv_def]
    \\ rfs [] \\ imp_res_tac heap_lookup_IMP_MEM
    \\ fs [to_basic_heap_list_def,MEM_MAP]
    \\ res_tac \\ fs [])
  \\ fs [EVAL ``(to_basic_conf conf).isRef b``]
  \\ `~conf.isRef b` by
   (fs [gen_inv_def]
    \\ drule heap_segment_IMP \\ fs []
    \\ disch_then (strip_assume_tac o GSYM)
    \\ fs [heap_length_APPEND]
    \\ full_simp_tac std_ss [GSYM APPEND_ASSOC]
    \\ fs [heap_lookup_APPEND,to_basic_state_def,to_basic_heap_def]
    \\ rfs []
    \\ drule heap_lookup_IMP_MEM
    \\ rw [] \\ fs [EVERY_MEM] \\ res_tac
    \\ fs [heap_element_is_ref_def] \\ NO_TAC)
  \\ fs [EVAL ``(to_basic_state conf state).ok``,
         EVAL ``(to_basic_state conf state).a``,
         EVAL ``(to_basic_state conf state).n``]
  \\ rpt (pairarg_tac \\ fs [])
  \\ rveq \\ fs [to_basic_heap_address_def]
  \\ simp [to_basic_state_def,empty_state_def,
       gc_sharedTheory.gc_state_component_equality]
  \\ fs [to_basic_heap_list_def,to_basic_heap_element_def]
  \\ fs [gen_inv_def]
  \\ drule heap_segment_IMP \\ fs []
  \\ disch_then (strip_assume_tac o GSYM) \\ fs []
  \\ full_simp_tac std_ss [GSYM APPEND_ASSOC]
  \\ full_simp_tac std_ss [heap_lookup_APPEND]
  \\ rfs [heap_length_APPEND,to_basic_state_def,to_basic_heap_def,heap_restrict_def]
  \\ fs [] \\ rfs []
  \\ drule heap_lookup_SPLIT
  \\ strip_tac \\ fs [] \\ rveq
  \\ `n = heap_length ha + heap_length heap_old` by fs []
  \\ fs [] \\ rveq
  \\ `gc_forward_ptr (heap_length (heap_old ++ ha))
         ((heap_old ++ ha) ++ DataElement l n' b::(hb ++ heap_refs))
         state.a a (state.ok ∧ n' + 1 ≤ state.n) = (heap',ok')` by
    (fs [heap_length_APPEND]
     \\ full_simp_tac std_ss [GSYM APPEND_ASSOC,APPEND] \\ NO_TAC)
  \\ full_simp_tac std_ss [gc_forward_ptr_thm] \\ rveq
  \\ `gc_forward_ptr (heap_length (to_basic_heap_list conf ha))
         (to_basic_heap_list conf ha ++
          DataElement (MAP (to_basic_heap_address conf) l) n' b ::
          to_basic_heap_list conf hb)
         (state.a − heap_length heap_old) (Real a)
         (state.ok ∧ n' + 1 ≤ state.n) = (heap,ok)` by
    (fs [heap_length_APPEND,heap_length_to_basic_heap_list]
     \\ full_simp_tac std_ss [GSYM APPEND_ASSOC,APPEND,
          to_basic_heap_list_def,MAP_APPEND,MAP,to_basic_heap_element_def] \\ NO_TAC)
  \\ full_simp_tac std_ss [gc_forward_ptr_thm] \\ rveq
  \\ qmatch_goalsub_abbrev_tac `heap_segment xx yy`
  \\ `heap_segment xx yy = SOME
       (heap_old,ha++ForwardPointer state.a a n'::hb,heap_refs)` by cheat
  \\ fs [] \\ fs [to_basic_heap_list_def,to_basic_heap_element_def]
  \\ simp [heap_element_is_ref_def]
  \\ cheat);

val gc_move_list_simulation = prove(
  ``!state0 roots0 roots1 state1.
      (gc_move_list conf state0 roots0 = (roots1,state1))
      ==>
      (gc_move_list (to_basic_conf conf)
        (to_basic_state conf state0) (to_basic_roots conf roots0) =
          (to_basic_roots conf roots1,to_basic_state conf state1))``,
  cheat);

val gc_move_list_APPEND = prove(
  ``!conf state0 xs ys roots' state'.
      (basic_gc$gc_move_list conf state0 (xs ++ ys) = (roots',state')) ==>
      ?roots1 roots2 state1.
        (basic_gc$gc_move_list conf state0 xs = (roots1,state1)) /\
        (basic_gc$gc_move_list conf state1 ys = (roots2,state')) /\
        (roots' = roots1 ++ roots2)``,
  Induct_on `xs` \\ fs [basic_gcTheory.gc_move_list_def]
  \\ rw [] \\ rpt (pairarg_tac \\ fs []) \\ rveq
  \\ res_tac \\ fs [] \\ rveq \\ fs []);

val heap_restrict_NIL = store_thm("heap_restrict_NIL[simp]",
  ``heap_restrict gen_start refs_start [] = []``,
  rewrite_tac [heap_restrict_def]
  \\ fs [heap_segment_def]
  \\ fs [heap_split_def]);

val to_basic_heap_NIL = store_thm("to_basic_heap_NIL[simp]",
  ``to_basic_heap conf [] = []``,
  rewrite_tac [to_basic_heap_def]
  \\ fs [heap_restrict_def,to_basic_heap_list_def]);

val to_basic_heap_list_NIL = store_thm("to_basic_heap_list_NIL[simp]",
  ``to_basic_heap_list conf [] = []``,
  rewrite_tac [to_basic_heap_list_def]
  \\ fs []);

val gc_move_data_r1 = prove(
  ``!refs state conf.
    (gc_move_data conf (state with r1 := refs)).r1 = refs
  ``,
  rpt gen_tac
  \\ qmatch_goalsub_abbrev_tac `moved.r1 = _`
  \\ fs [markerTheory.Abbrev_def]
  \\ pop_assum (assume_tac o GSYM)
  \\ fs []
  \\ drule gc_move_data_IMP
  \\ strip_tac
  \\ fs []);

val gc_move_ref_list_simulation = prove(
  ``!conf state refs0 state1 state1' refs1 refs1'.
    (gc_move_ref_list conf (state : ('b,'a) gc_state) (refs0 : ('b,'a) heap_element list)
      = (refs1,state1)) /\
    (gc_move_list (to_basic_conf conf)
                  (to_basic_state conf state)
                  (refs_to_roots conf refs0)
      = (refs1',state1')) /\
    EVERY isDataElement refs0
    ==>
    (refs1' = refs_to_roots conf refs1) /\
    (state1' = to_basic_state conf state1)
  ``,
  recInduct (theorem "gc_move_ref_list_ind")
  \\ strip_tac
  >- (rpt gen_tac
     \\ once_rewrite_tac [gc_move_ref_list_def]
     \\ simp [refs_to_roots_def]
     \\ once_rewrite_tac [basic_gcTheory.gc_move_list_def]
     \\ strip_tac \\ rveq
     \\ simp [refs_to_roots_def]
     \\ fs [])
  \\ reverse strip_tac
  >- fs [EVERY_DEF,isDataElement_def]
  \\ rpt gen_tac
  \\ strip_tac
  \\ rpt gen_tac
  \\ once_rewrite_tac [gc_move_ref_list_def]
  \\ fs []
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ strip_tac \\ rveq
  \\ drule gc_move_list_simulation
  \\ strip_tac
  \\ fs [refs_to_roots_def]
  \\ drule gc_move_list_APPEND
  \\ strip_tac
  \\ rveq
  \\ fs [to_basic_roots_def]
  \\ rveq
  \\ first_x_assum drule
  \\ fs []);

val gc_move_list_r1 = prove(
  ``!s0 xs ys s1. (gc_move_list conf s0 xs = (ys,s1)) ==> (s1.r1 = s0.r1)``,
  Induct_on `xs` \\ fs [gc_move_list_def]
  \\ rw [] \\ rpt (pairarg_tac \\ fs []) \\ fs []
  \\ res_tac \\ fs [] \\ rveq
  \\ Cases_on `h` \\ fs [gc_move_def]
  \\ every_case_tac \\ fs [] \\ rveq \\ fs []
  \\ rw [] \\ rpt (pairarg_tac \\ fs []) \\ fs []
  \\ rveq \\ fs []);

val gc_move_data_r1 = prove(
  ``(gc_move_data conf (state' with r1 := refs') = state1) ==>
    (state1.r1 = refs')``,
  qabbrev_tac `s0 = state' with r1 := refs'`
  \\ `s0.r1 = refs'` by fs [Abbr `s0`]
  \\ rveq \\ pop_assum kall_tac
  \\ qspec_tac (`state1`,`s1`)
  \\ qspec_tac (`s0`,`s0`)
  \\ qspec_tac (`conf`,`conf`)
  \\ ho_match_mp_tac (fetch "-" "gc_move_data_ind")
  \\ rw [] \\ once_rewrite_tac [gc_move_data_def]
  \\ rpt (CASE_TAC \\ fs [])
  \\ full_simp_tac std_ss [GSYM APPEND_ASSOC,APPEND]
  \\ pairarg_tac \\ fs []
  \\ drule gc_move_list_r1 \\ fs []);

val partial_gc_simulation = prove(
  ``!conf roots heap0 roots1 state1 heap0_old heap0_current heap0_refs.
    (partial_gc conf (roots,heap0) = (roots1,state1)) /\
    heap_gen_ok heap0 conf /\
    conf.gen_start ≤ conf.refs_start ∧ conf.refs_start ≤ conf.limit /\
    (heap_segment (conf.gen_start,conf.refs_start) heap0
      = SOME (heap0_old,heap0_current,heap0_refs)) /\
    EVERY (\e. ~(heap_element_is_ref conf e)) (heap0_old ++ heap0_current) /\
    EVERY isDataElement heap0_refs /\
    roots_ok roots heap0 /\
    heap_ok heap0 conf.limit ==>
    ?refs refs1.
      (refs = refs_to_roots conf heap0_refs) /\
      (refs1 = refs_to_roots conf state1.r1) /\
      (basic_gc (to_basic_conf conf)
                (to_basic_roots conf roots ++ refs,
                to_basic_heap_list conf heap0_current)
      = (to_basic_roots conf roots1 ++ refs1,
        to_basic_state conf state1)) /\
      (!xs l d ptr u.
         (MEM (DataElement xs l d) state1.h1 \/ MEM (DataElement xs l d) state1.r1) /\
         MEM (Pointer ptr u) xs /\
         (ptr < conf.gen_start \/ conf.refs_start <= ptr) ==>
         isSomeDataElement
           (heap_lookup ptr (state1.old ++ state1.h1 ++
                             heap_expand state1.n ++ state1.r1)))``,
  rpt strip_tac
  \\ fs []
  \\ fs [basic_gc_def]
  \\ pairarg_tac \\ fs []
  \\ fs [partial_gc_def]
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ rveq
  \\ drule gc_move_list_APPEND
  \\ strip_tac \\ fs []
  \\ rveq
  \\ drule gc_move_list_simulation
  \\ qmatch_asmsub_abbrev_tac `generational_gc$gc_move_list _ stateA`
  \\ qmatch_asmsub_abbrev_tac `basic_gc$gc_move_list _ stateB _ = (roots1,state1)`
  \\ `stateB = to_basic_state conf stateA` by all_tac
  >- (unabbrev_all_tac
     \\ simp [to_basic_state_def,empty_state_def]
     \\ simp [to_basic_conf_def,to_basic_heap_def]
     \\ simp [heap_restrict_def]
     \\ drule heap_segment_IMP
     \\ simp [heap_length_APPEND])
  \\ fs []
  \\ strip_tac
  \\ simp [gc_move_data_r1]
  \\ rveq
  \\ drule gc_move_ref_list_simulation
  \\ disch_then drule
  \\ disch_then drule
  \\ strip_tac \\ rveq
  \\ fs []
  \\ rewrite_tac [METIS_PROVE [] ``b \/ c <=> (~b ==> c)``]
  \\ fs [SIMP_RULE std_ss [] (GEN_ALL gc_move_data_r1)]
  \\ cheat);

(* always rewrite with gen_inv_def *)
val _ = augment_srw_ss [rewrites [gen_inv_def]];

val f_old_ptrs_def = Define `
  f_old_ptrs conf heap =
    {a | isSomeDataElement (heap_lookup a heap)
         /\ (a < conf.gen_start \/ conf.refs_start <= a)}`;

val f_old_ptrs_finite = store_thm("f_old_ptrs_finite[simp]",
  ``!heap conf.
    FINITE (f_old_ptrs conf heap)``,
  rpt strip_tac
  \\ match_mp_tac (MP_CANON SUBSET_FINITE)
  \\ qexists_tac `{a | isSomeDataElement (heap_lookup a heap)}`
  \\ reverse CONJ_TAC
  >- fs [f_old_ptrs_def,SUBSET_DEF]
  \\ qspec_tac (`heap`,`heap`)
  \\ ho_match_mp_tac SNOC_INDUCT
  \\ rw []
  >- fs [heap_lookup_def,isSomeDataElement_def]
  \\ reverse
     (`?y. FINITE y /\
          ({a | isSomeDataElement (heap_lookup a (SNOC x heap))} =
           y UNION {a | isSomeDataElement (heap_lookup a heap)})` by all_tac)
  >- fs []
  \\ fs [SNOC_APPEND]
  \\ fs [heap_lookup_APPEND]
  \\ Cases_on `x`
  \\ TRY (qexists_tac `{}`
     \\ fs []
     \\ fs [EXTENSION,heap_lookup_def]
     \\ rw [isSomeDataElement_def]
     \\ CCONTR_TAC
     \\ fs []
     \\ imp_res_tac heap_lookup_LESS
     \\ fs []
     \\ NO_TAC)
  \\ qexists_tac `{heap_length heap}`
  \\ fs []
  \\ fs [EXTENSION]
  \\ rw []
  \\ Cases_on `x = heap_length heap` \\ fs []
  \\ fs [heap_lookup_def,isSomeDataElement_def]
  \\ CCONTR_TAC
  \\ fs []
  \\ imp_res_tac heap_lookup_LESS);

val f_old_ptrs_finite_open = save_thm("f_old_ptrs_finite_open[simp]",
  f_old_ptrs_finite |> SIMP_RULE std_ss [f_old_ptrs_def]);

val new_f_def = Define `
  new_f f conf heap =
    FUNION (FUN_FMAP I (f_old_ptrs conf heap))
           (FUN_FMAP (\a. conf.gen_start + f ' (a - conf.gen_start))
                     (IMAGE ((+) conf.gen_start) (FDOM f)))`;

val APPEND_LENGTH_IMP = prove(
  ``!a c b d.
    ((a ++ b) = (c ++ d)) /\ (LENGTH a = LENGTH c) ==>
    (a = c) /\ (b = d)``,
  Induct >- (Cases \\ fs [])
  \\ strip_tac
  \\ Cases \\ fs []
  \\ rpt strip_tac \\ res_tac);

val roots_ok_APPEND = prove(
  ``!left right heap.
    roots_ok (left ++ right) heap ==>
    roots_ok left heap /\
    roots_ok right heap
  ``,
  fs [roots_ok_def] \\ rpt strip_tac \\ res_tac);

val roots_ok_CONS = prove(
  ``!h t.
    roots_ok (h::t) heap ==>
    roots_ok t heap``,
  metis_tac [CONS_APPEND,roots_ok_APPEND]);

val isSomeDataElement_to_basic_heap_list
  = store_thm("isSomeDataElement_to_basic_heap_list[simp]",
  ``!n heap.
    isSomeDataElement (heap_lookup n (to_basic_heap_list conf heap))
    = isSomeDataElement (heap_lookup n heap)``,
  rewrite_tac [to_basic_heap_list_def]
  \\ Induct_on `heap`
  >- fs [heap_lookup_def,isSomeDataElement_def]
  \\ Cases \\ strip_tac
  \\ rpt
     (fs [heap_lookup_def,to_basic_heap_element_def]
     \\ IF_CASES_TAC >- fs [isSomeDataElement_def]
     \\ simp []
     \\ IF_CASES_TAC
     \\ fs [el_length_def]
     \\ fs [isSomeDataElement_def]));

val isSomeDataElement_to_basic_heap_element = save_thm("isSomeDataElement_to_basic_heap_element",
  isSomeDataElement_to_basic_heap_list |> SIMP_RULE std_ss [to_basic_heap_list_def]);

val MEM_refs_to_roots_IMP_MEM = prove(
  ``!heap_refs.
    MEM (Pointer ptr u) (refs_to_roots conf heap_refs) ==>
    ?xs l d ptr' u'.
    MEM (DataElement xs l d) heap_refs /\
    MEM (Pointer ptr' u') xs /\
    (ptr = ptr' - conf.gen_start) /\
    (u = Real u') /\
    (conf.gen_start <= ptr') /\
    (ptr' < conf.refs_start)
  ``,
  Induct \\ fs [refs_to_roots_def]
  \\ Cases \\ fs [refs_to_roots_def]
  \\ reverse strip_tac
  >- metis_tac []
  \\ qexists_tac `l` \\ qexists_tac `n` \\ qexists_tac `b`
  \\ simp []
  \\ pop_assum mp_tac
  \\ qspec_tac (`l`,`xs`)
  \\ Induct \\ fs []
  \\ Cases \\ fs [to_basic_heap_address_def]
  \\ IF_CASES_TAC \\ fs [] >- metis_tac []
  \\ IF_CASES_TAC \\ fs [] >- metis_tac []
  \\ reverse strip_tac \\ rveq
  >- metis_tac []
  \\ qexists_tac `n` \\ qexists_tac `a`
  \\ fs []);

val MEM_to_basic_roots_IMP_MEM = prove(
  ``!roots.
    MEM (Pointer ptr u) (to_basic_roots conf roots)
    ==>
    ?ptr' u'.
    MEM (Pointer ptr' u') roots /\
    (ptr = ptr' - conf.gen_start) /\
    (u = Real u') /\
    (conf.gen_start <= ptr') /\
    (ptr' < conf.refs_start)
  ``,
  Induct \\ fs [to_basic_roots_def]
  \\ Cases \\ fs [to_basic_heap_address_def]
  \\ IF_CASES_TAC \\ fs []
  >- metis_tac []
  \\ IF_CASES_TAC \\ fs []
  >- metis_tac []
  \\ reverse strip_tac \\ rveq
  >- metis_tac []
  \\ qexists_tac `n` \\ qexists_tac `a`
  \\ strip_tac \\ fs []);

val roots_ok_simulation = prove(
  ``!roots heap heap_old heap_current heap_refs (conf :'b gen_gc_conf).
    roots_ok roots (heap :('a,'b) heap_element list) /\
    heap_ok heap conf.limit /\
    (heap_segment (conf.gen_start,conf.refs_start) heap = SOME (heap_old,heap_current,heap_refs)) /\
    (conf.gen_start ≤ conf.refs_start)
    ==>
    roots_ok
      (to_basic_roots conf roots ++ refs_to_roots conf heap_refs)
      (MAP (to_basic_heap_element conf) heap_current)
  ``,
  rpt strip_tac
  \\ drule heap_segment_IMP
  \\ simp [] \\ strip_tac \\ rveq
  \\ simp [roots_ok_def]
  \\ rpt strip_tac
  >- (fs [roots_ok_def]
     \\ drule MEM_to_basic_roots_IMP_MEM
     \\ strip_tac \\ rveq
     \\ first_x_assum drule
     \\ rewrite_tac [heap_lookup_APPEND]
     \\ fs []
     \\ simp [isSomeDataElement_to_basic_heap_element])
  \\ drule MEM_refs_to_roots_IMP_MEM
  \\ strip_tac \\ rveq
  \\ fs [heap_ok_def]
  \\ qpat_x_assum `!xs. _` (qspecl_then [`xs`,`l`,`d`] mp_tac) \\ simp []
  \\ disch_then drule
  \\ rewrite_tac [heap_lookup_APPEND]
  \\ fs []
  \\ simp [isSomeDataElement_to_basic_heap_element]);

val heap_length_to_basic_heap_element = save_thm("heap_length_to_basic_heap_element[simp]",
  heap_length_to_basic_heap_list |> SIMP_RULE std_ss [to_basic_heap_list_def]);

val MEM_to_basic_heap_IMP_MEM = prove(
  ``!heap_current xs l d ptr u.
    MEM (DataElement xs l d) (MAP (to_basic_heap_element conf) heap_current) /\
    MEM (Pointer ptr u) xs
    ==>
    ?xs' u' ptr'.
    MEM (DataElement xs' l d) heap_current /\
    MEM (Pointer ptr' u') xs' /\
    (xs = MAP (to_basic_heap_address conf) xs') /\
    (ptr = ptr' - conf.gen_start) /\
    (u = Real u') /\
    (ptr' < conf.refs_start) /\
    (conf.gen_start <= ptr')
  ``,
  Induct \\ fs []
  \\ Cases \\ fs [to_basic_heap_element_def]
  \\ rpt gen_tac \\ simp []
  \\ reverse strip_tac
  >- metis_tac []
  \\ rveq
  \\ qexists_tac `l` \\ simp []
  \\ pop_assum mp_tac
  \\ qspec_tac (`l`,`xs`)
  \\ Induct \\ fs []
  \\ Cases \\ simp [to_basic_heap_address_def]
  \\ IF_CASES_TAC \\ simp []
  >- metis_tac []
  \\ IF_CASES_TAC \\ simp []
  >- metis_tac []
  \\ reverse strip_tac \\ rveq \\ simp []
  >- metis_tac []
  \\ qexists_tac `n`
  \\ fs []);

val heap_ok_simulation = prove(
  ``!heap heap_old heap_current heap_refs (conf :'b gen_gc_conf).
    heap_ok (heap :('a,'b) heap_element list) conf.limit /\
    (heap_segment (conf.gen_start,conf.refs_start) heap = SOME (heap_old,heap_current,heap_refs)) /\
    (conf.gen_start ≤ conf.refs_start) /\
    (conf.refs_start ≤ conf.limit)
    ==>
    heap_ok
      (MAP (to_basic_heap_element conf) heap_current)
      (to_basic_conf conf).limit``,
  rpt strip_tac
  \\ drule heap_segment_IMP \\ simp []
  \\ strip_tac \\ rveq
  \\ fs [heap_ok_def]
  \\ fs [to_basic_conf_def]
  \\ rpt strip_tac
  >- fs [heap_length_APPEND]
  >- (fs [FILTER_APPEND]
     \\ qpat_x_assum `FILTER _ heap_current = []` mp_tac
     \\ qspec_tac (`heap_current`,`heaps`)
     \\ Induct
     \\ fs []
     \\ Cases \\ fs [isForwardPointer_def,to_basic_heap_element_def])
  \\ drule MEM_to_basic_heap_IMP_MEM \\ simp []
  \\ disch_then drule
  \\ strip_tac \\ rveq
  \\ qpat_x_assum `!xs. _` (qspecl_then [`xs'`,`l`,`d`] mp_tac)
  \\ simp []
  \\ disch_then drule
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ rewrite_tac [Once heap_lookup_APPEND] \\ fs []
  \\ drule heap_segment_IMP \\ simp []
  \\ rewrite_tac [Once heap_lookup_APPEND] \\ fs [heap_length_APPEND]
  \\ simp [isSomeDataElement_to_basic_heap_element]);

val new_f_FDOM = prove(``
  (∀i. i ∈ FDOM f ⇒ isSomeDataElement (heap_lookup (i + conf.gen_start) heap)) ==>
  (x IN FDOM (new_f f conf heap) =
  if x < conf.gen_start ∨ conf.refs_start ≤ x then
  isSomeDataElement (heap_lookup x heap) else
  x IN (IMAGE ($+ conf.gen_start) (FDOM f)))``,
  strip_tac
  \\ fs [new_f_def]
  \\ simp [f_old_ptrs_def]
  \\ reverse IF_CASES_TAC
  >- simp []
  \\ simp []
  \\ eq_tac
  \\ rw []
  \\ fs []);

val new_f_FAPPLY = prove(
  ``(x ∈ FDOM (new_f f conf heap)) /\
    (∀i. i ∈ FDOM f ⇒ isSomeDataElement (heap_lookup (i + conf.gen_start) heap)) ==>
    (new_f f conf heap ' x =
    if x < conf.gen_start ∨ conf.refs_start ≤ x then
    x else
    conf.gen_start + f ' (x − conf.gen_start))``,
  strip_tac
  \\ drule new_f_FDOM
  \\ simp []
  \\ strip_tac
  \\ simp [new_f_def]
  \\ IF_CASES_TAC
  >- (fs [FUNION_DEF,f_old_ptrs_def]
     \\ fs [FUN_FMAP_DEF])
  \\ fs [FUNION_DEF,f_old_ptrs_def]
  \\ fs [FUN_FMAP_DEF]);

val isSomeDataElement_heap_lookup_heap_expand
  = store_thm("isSomeDataElement_heap_lookup_heap_expand[simp]",
  ``~isSomeDataElement (heap_lookup x (heap_expand n))``,
  rewrite_tac [heap_expand_def]
  \\ Cases_on `n` \\ fs []
  \\ fs [heap_lookup_def,isSomeDataElement_def]);

val heap_lookup_heap_expand = isSomeDataElement_heap_lookup_heap_expand
  |> SIMP_RULE std_ss [isSomeDataElement_def];

val heap_lookup_old_IMP = prove(
  ``!i ys.
    (partial_gc conf (roots,heap) = (roots1,state1)) /\
    gen_inv conf heap /\
    (heap_lookup i heap = SOME (DataElement xs l d)) /\
    (i < conf.gen_start) ==>
    (heap_lookup i (state1.old ++ ys) = SOME (DataElement xs l d))``,
  fs [] \\ rpt strip_tac \\ fs [gen_inv_def]
  \\ drule partial_gc_IMP
  \\ fs [] \\ strip_tac
  \\ drule heap_segment_IMP
  \\ fs []
  \\ strip_tac
  \\ qpat_x_assum `_ = heap` (assume_tac o GSYM)
  \\ qpat_x_assum `_ = conf.gen_start` (assume_tac o GSYM)
  \\ fs []
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ drule LESS_IMP_heap_lookup
  \\ disch_then (qspec_then `heap_current ++ heap_refs` assume_tac)
  \\ fs []
  \\ drule LESS_IMP_heap_lookup
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ metis_tac []);

val heap_lookup_old_IMP_ALT = prove(
  ``!ys.
    (partial_gc conf (roots,heap) = (roots1,state1)) /\
    gen_inv conf heap /\
    isSomeDataElement (heap_lookup x heap) /\
    (x < conf.gen_start) ==>
    isSomeDataElement (heap_lookup x (state1.old ++ ys))``,
  metis_tac [isSomeDataElement_def,heap_lookup_old_IMP]);

val heap_lookup_refs_IMP = prove(
  ``!x.
    (partial_gc conf (roots,heap) = (roots1,state1)) /\
    gen_inv conf heap /\
    (heap_lookup x heap = SOME (DataElement xs l d)) /\
    (heap_length (state1.old ++ state1.h1 ++ heap_expand state1.n) = conf.refs_start) /\
    (conf.refs_start ≤ x)
    ==>
    ?xs1.
    (heap_lookup x (state1.old ++ state1.h1 ++ heap_expand state1.n ++ state1.r1) =
      SOME (DataElement xs1 l d))
  ``,
  rpt strip_tac
  \\ fs [gen_inv_def]
  \\ drule heap_segment_IMP \\ simp []
  \\ strip_tac
  \\ rveq
  \\ fs [partial_gc_def]
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ drule gc_move_list_IMP \\ strip_tac
  \\ qmatch_asmsub_abbrev_tac `gc_move_list _ state0 _ = _`
  \\ qpat_x_assum `heap_lookup _ _ = _` mp_tac
  \\ `heap_length (heap_old ++ heap_current) = conf.refs_start` by all_tac
  >- simp [heap_length_APPEND]
  \\ once_rewrite_tac [heap_lookup_APPEND]
  \\ fs []
  \\ qpat_x_assum `gc_move_ref_list _ _ _ = _` mp_tac
  \\ drule gc_move_data_IMP \\ fs []
  \\ strip_tac
  \\ fs []
  \\ qspec_tac (`x - conf.refs_start`, `ptr`)
  \\ qspec_tac (`state`,`state`)
  \\ qspec_tac (`state'`,`state'`)
  \\ qspec_tac (`refs'`,`refs'`)
  \\ qspec_tac (`heap_refs`,`heap_refs`)
  \\ Induct
  >- simp [gc_move_ref_list_def]
  \\ Cases \\ simp [gc_move_ref_list_def]
  \\ rpt gen_tac
  \\ pairarg_tac \\ simp []
  \\ pairarg_tac \\ simp []
  \\ strip_tac
  \\ rveq
  \\ fs [heap_lookup_def]
  \\ IF_CASES_TAC \\ fs []
  \\ simp [el_length_def]
  \\ simp [heap_lookup_def]
  \\ strip_tac
  \\ qpat_x_assum `!refs state state' ptr. _ ==> __` drule
  \\ fs []);

val heap_lookup_refs_IMP_ALT = prove(
  ``(partial_gc conf (roots,heap) = (roots1,state1)) /\
    gen_inv conf heap /\
    isSomeDataElement (heap_lookup x heap) /\
    (heap_length (state1.old ++ state1.h1 ++ heap_expand state1.n) = conf.refs_start) /\
    (conf.refs_start ≤ x)
    ==>
    isSomeDataElement (heap_lookup x (state1.old ++ state1.h1 ++ heap_expand state1.n ++ state1.r1))
  ``,
  metis_tac [isSomeDataElement_def,heap_lookup_refs_IMP]);

val ADDR_MAP_ID = prove(
  ``(!x u. MEM (Pointer x u) xs ==> (x = f x))
    ==> (xs = ADDR_MAP f xs)``,
  Induct_on `xs`
  \\ fs [ADDR_MAP_def]
  \\ Cases
  \\ fs [ADDR_MAP_def]
  \\ metis_tac []);

val MEM_heap_old = prove(
  ``!n m i x.
    (heap_segment (n,m) heap = SOME (heap_old,heap_current,heap_refs)) /\
    (n <= m) /\
    i < n /\
    (heap_lookup i heap = SOME x)
    ==>
    MEM x heap_old``,
  rpt strip_tac
  \\ drule heap_segment_IMP
  \\ disch_then drule
  \\ rpt strip_tac
  \\ rveq
  \\ fs []
  \\ drule LESS_IMP_heap_lookup
  \\ metis_tac [heap_lookup_IMP_MEM,GSYM APPEND_ASSOC]);

val FILTER_isForward_to_basic = prove(
  ``!xs.
    (FILTER isForwardPointer (to_basic_heap_list conf xs) = []) ==>
    (FILTER isForwardPointer xs = [])``,
  Induct
  \\ fs [to_basic_heap_list_def]
  \\ Cases
  \\ fs [to_basic_heap_element_def,isForwardPointer_def]);

val isSomeData_to_basic_heap_IMP = prove(
  ``!xs ptr conf ys l d.
    (heap_lookup ptr (to_basic_heap_list conf xs) = SOME (DataElement ys l d))
    ==>
    isSomeDataElement (heap_lookup ptr xs)``,
  Induct
  \\ fs [to_basic_heap_list_def,heap_lookup_def]
  \\ Cases \\ fs [to_basic_heap_element_def] \\ rpt gen_tac
  >- (IF_CASES_TAC \\ fs [el_length_def]
     \\ strip_tac
     \\ metis_tac [])
  >- (IF_CASES_TAC \\ fs [el_length_def]
     \\ strip_tac
     \\ metis_tac [])
  \\ IF_CASES_TAC \\ fs [el_length_def]
  >- simp [isSomeDataElement_def]
  \\ strip_tac
  \\ metis_tac []);

val refs_to_roots_APPEND = prove(
  ``!xs ys.
    refs_to_roots conf (xs ++ ys) = refs_to_roots conf xs ++ refs_to_roots conf ys``,
  Induct
  \\ fs [refs_to_roots_def]
  \\ Cases \\ fs [refs_to_roots_def]);

val gc_move_refs_isForwardPointer = prove(
  ``∀refs refs1 state1 state.
    (gc_move_ref_list conf state refs = (refs1,state1)) ∧
    (FILTER isForwardPointer refs = []) ⇒
    (FILTER isForwardPointer refs1 = [])
  ``,
  Induct
  >- (rpt strip_tac
     \\ fs [gc_move_ref_list_def]
     \\ rveq \\ fs [])
  \\ Cases
  \\ fs [gc_move_ref_list_def]
  \\ fs [isForwardPointer_def]
  \\ strip_tac
  \\ rveq
  \\ rpt strip_tac
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ rveq
  \\ simp [FILTER] \\ fs [isForwardPointer_def]
  \\ res_tac);

val el_length_to_basic_heap_element = store_thm("el_length_to_basic_heap_element[simp]",
  ``el_length (to_basic_heap_element conf h) = el_length h``,
  Cases_on `h` \\ fs [to_basic_heap_element_def,el_length_def]);

val to_basic_heap_element_isSomeData = prove(
  ``!xs n.
    isSomeDataElement (heap_lookup n (MAP (to_basic_heap_element (conf : 'b gen_gc_conf)) (xs:('a,'b) heap_element list))) ==>
    isSomeDataElement (heap_lookup n xs)``,
  Induct
  >- (fs [] \\ rw []
     \\ fs [heap_lookup_def]
     \\ fs [isSomeDataElement_def])
  \\ gen_tac
  \\ fs []
  \\ fs [heap_lookup_def]
  \\ strip_tac
  \\ IF_CASES_TAC \\ fs []
  >- (Cases_on `h`
     \\ fs [to_basic_heap_element_def,isSomeDataElement_def])
  \\ IF_CASES_TAC \\ fs []
  >- (fs [isSomeDataElement_def])
  \\ fs [el_length_to_basic_heap_element]
  \\ fs []);

val heap_lookup_GT_FALSE = prove(
  ``!xs n.
    ¬(n < heap_length xs) ==>
    ~(isSomeDataElement (heap_lookup n xs))``,
  Induct
  >- (fs [heap_lookup_def,isSomeDataElement_def])
  \\ fs [heap_lookup_def,heap_length_def]
  \\ rpt gen_tac
  \\ IF_CASES_TAC \\ fs []
  \\ metis_tac [el_length_NOT_0]);

val heap_lookup_to_basic_heap_element = prove(
  ``!heap_current i.
      isSomeDataElement
        (heap_lookup i (MAP (to_basic_heap_element conf) heap_current)) =
      isSomeDataElement (heap_lookup i heap_current)``,
  Induct THEN1 fs [heap_lookup_def,isSomeDataElement_def]
  \\ fs [heap_lookup_def] \\ rw []
  \\ Cases_on `h` \\ fs [to_basic_heap_element_def,isSomeDataElement_def]);

val partial_gc_heap_length_lemma = prove (
  ``!roots'.
    (partial_gc conf (roots,heap) = (roots1,state1)) /\
    (basic_gc (to_basic_conf conf) (basic_roots,basic_heap) =
      (roots',to_basic_state conf state1)) /\
    (heap_segment (conf.gen_start,conf.refs_start) heap = SOME (heap_old,heap_current,heap_refs)) /\
    (conf.gen_start ≤ conf.refs_start) /\
    (conf.refs_start ≤ conf.limit) /\
    roots_ok basic_roots basic_heap /\
    heap_ok basic_heap (to_basic_conf conf).limit
    ==>
    (heap_length (state1.old ++ state1.h1 ++ heap_expand state1.n) = conf.refs_start)
  ``,
  rpt strip_tac
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ once_rewrite_tac [heap_length_APPEND]
  \\ fs [partial_gc_def] \\ rfs []
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ drule gc_move_data_IMP
  \\ strip_tac \\ fs []
  \\ drule gc_move_ref_list_IMP
  \\ strip_tac \\ fs []
  \\ drule gc_move_list_IMP
  \\ strip_tac \\ fs []
  \\ drule basic_gc_thm
  \\ disch_then drule
  \\ strip_tac
  \\ rveq
  \\ `state'' = to_basic_state conf state1` by all_tac
  >- fs []
  \\ drule heap_segment_IMP \\ fs []
  \\ strip_tac
  \\ fs []
  \\ `heap_length (state1.h1 ++ heap_expand state1.n) = heap_length (to_basic_heap_list conf state1.h1 ++ heap_expand state1.n)` by all_tac
  >- (fs [heap_length_APPEND]
     \\ fs [heap_length_heap_expand])
  \\ `heap_length (to_basic_heap_list conf state1.h1 ++ heap_expand state1.n) = conf.refs_start - conf.gen_start` by all_tac
  >- (fs [gc_inv_def]
     \\ rewrite_tac [heap_length_APPEND]
     \\ qpat_x_assum `_ = (to_basic_state conf state1).a` mp_tac
     \\ qpat_x_assum `_ = (to_basic_conf conf).limit` kall_tac
     \\ qpat_x_assum `_ = (to_basic_conf conf).limit` mp_tac
     \\ rewrite_tac [to_basic_state_def]
     \\ rewrite_tac [empty_state_def,gc_state_component_equality]
     \\ simp [gc_state_component_equality]
     \\ fs [to_basic_conf_def]
     \\ simp [heap_length_heap_expand])
  \\ rveq
  \\ fs []);

val gc_move_ref_list_isSomeDataElement = prove (
  ``!refs ptr state state1 refs1.
    (gc_move_ref_list conf state refs = (refs1,state1)) /\
    isSomeDataElement (heap_lookup ptr refs) ==>
    isSomeDataElement (heap_lookup ptr refs1)
  ``,
  Induct
  >- fs [heap_lookup_def,isSomeDataElement_def]
  \\ Cases
  \\ fs [gc_move_ref_list_def]
  \\ ntac 3 gen_tac
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ strip_tac
  \\ rveq
  \\ fs [heap_lookup_def]
  \\ IF_CASES_TAC \\ simp []
  >- fs [isSomeDataElement_def]
  \\ IF_CASES_TAC \\ fs [el_length_def]
  \\ res_tac);

val heap_lookup_MEM = prove (
  ``!heap x xs l b.
    (heap_lookup x heap = SOME (DataElement xs l b)) ==>
    MEM (DataElement xs l b) heap
  ``,
  Induct \\ fs [heap_lookup_def]
  \\ rpt gen_tac
  \\ IF_CASES_TAC
  >- (Cases_on `h` \\ fs [])
  \\ IF_CASES_TAC \\ fs []
  \\ metis_tac []);

val ptr_Real_lemma = prove(
  ``!ys ptr. MEM (Pointer ptr u) ys /\
    (conf.gen_start <= ptr) /\
    (ptr < conf.refs_start)
    ==>
    MEM (Pointer (ptr − conf.gen_start) (Real u)) (MAP (to_basic_heap_address conf) ys)
  ``,
  gen_tac
  \\ fs [Once MEM_SPLIT]
  \\ rpt strip_tac
  \\ rveq
  \\ fs [MAP_APPEND]
  \\ fs [to_basic_heap_address_def]);

val partial_gc_refs_isSomeDataElement_isSomeDataElement = prove(
  ``!ptr heap state1 heap_current heap_refs.
    (partial_gc conf (roots,heap)
     = (roots1,state1)) /\
    (heap_segment (conf.gen_start,conf.refs_start) heap = SOME (state1.old,heap_current,heap_refs)) /\
    isSomeDataElement (heap_lookup ptr heap_refs)
    ==>
    isSomeDataElement (heap_lookup ptr state1.r1)
  ``,
  rpt strip_tac
  \\ fs [partial_gc_def]
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ drule gc_move_data_IMP
  \\ strip_tac \\ rveq
  \\ fs [gc_state_component_equality]
  \\ qpat_x_assum `isSomeDataElement _` mp_tac
  \\ qpat_x_assum `gc_move_ref_list _ _ _ = _` mp_tac
  \\ qspec_tac (`state`,`state0`)
  \\ qspec_tac (`state'`,`state1`)
  \\ qspec_tac (`ptr`,`ptr0`)
  \\ qspec_tac (`refs'`,`refs1`)
  \\ qspec_tac (`heap_refs`,`refs0`)
  \\ Induct
  \\ fs [gc_move_ref_list_def]
  \\ Cases
  \\ fs [gc_move_ref_list_def]
  \\ rpt gen_tac
  \\ pairarg_tac \\ fs []
  \\ pairarg_tac \\ fs []
  \\ strip_tac \\ rveq
  \\ fs [heap_lookup_def]
  \\ IF_CASES_TAC \\ simp []
  >- fs [isSomeDataElement_def]
  \\ IF_CASES_TAC \\ fs [el_length_def]
  \\ first_x_assum match_mp_tac
  \\ metis_tac []);

val isSomeData_to_basic_heap_IMP_isSomeData = prove (
  ``!heap ptr.
    isSomeDataElement (heap_lookup ptr (to_basic_heap_list conf heap ++ heap_expand state1.n)) ==>
    isSomeDataElement (heap_lookup ptr (heap ++ heap_expand state1.n))
  ``,
  Induct
  \\ fs [heap_lookup_def,to_basic_heap_list_def]
  \\ Cases \\ strip_tac
  >- (IF_CASES_TAC \\ simp []
     >- fs [to_basic_heap_element_def,isSomeDataElement_def]
     \\ IF_CASES_TAC \\ simp [] >- simp [isSomeDataElement_def])
  >- (IF_CASES_TAC \\ simp []
     >- fs [to_basic_heap_element_def,isSomeDataElement_def]
     \\ IF_CASES_TAC \\ simp [] >- simp [isSomeDataElement_def])
  \\ IF_CASES_TAC \\ simp []
  >- simp [isSomeDataElement_def]
  \\ IF_CASES_TAC \\ simp []
  \\ simp [isSomeDataElement_def]);

val refs_root_IMP_isSomeData = prove(
  ``!(state1 : ('a,'b) gc_state) (conf : 'b gen_gc_conf) refs.
    MEM (DataElement xs l d) refs /\
    MEM (Pointer ptr u) xs /\
    roots_ok (refs_to_roots conf refs)
      (to_basic_heap_list conf state1.h1 ++ heap_expand state1.n) /\
    (ptr < conf.refs_start) /\
    ~(ptr < conf.gen_start)
    ==>
    isSomeDataElement (heap_lookup (ptr − conf.gen_start) (state1.h1 ++ heap_expand state1.n))
  ``,
  ntac 2 gen_tac \\ Induct \\ fs []
  \\ Cases \\ fs [refs_to_roots_def]
  \\ reverse strip_tac \\ rveq \\ fs []
  >- (drule roots_ok_APPEND \\ strip_tac
     \\ fs [])
  \\ qpat_x_assum `MEM _ _` mp_tac \\ simp [MEM_SPLIT]
  \\ strip_tac \\ rveq
  \\ fs [MAP]
  \\ qpat_x_assum `roots_ok _ _` mp_tac
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ strip_tac
  \\ drule roots_ok_APPEND \\ strip_tac
  \\ drule roots_ok_APPEND \\ strip_tac
  \\ qpat_x_assum `roots_ok [_] _` mp_tac
  \\ simp [roots_ok_def]
  \\ simp [to_basic_heap_address_def]
  \\ metis_tac [isSomeData_to_basic_heap_IMP_isSomeData]);

val ADDR_MAP_APPEND_LENGTH_IMP = prove(
  ``!(roots : 'a heap_address list) (heap_refs : ('a,'b) heap_element list) (f : num |-> num) roots1 (r1 : ('a,'b) heap_element list) (conf : 'b gen_gc_conf).
    (ADDR_MAP ($' f) (to_basic_roots conf roots ++ refs_to_roots conf heap_refs) =
       to_basic_roots conf roots1 ++ refs_to_roots conf r1) /\
    (LENGTH roots = LENGTH roots1)
    ==>
    (ADDR_MAP ($' f) (to_basic_roots conf roots) = to_basic_roots conf roots1) /\
    (ADDR_MAP ($' f) (refs_to_roots conf heap_refs) = refs_to_roots conf r1)
  ``,
  Induct \\ rpt gen_tac
  >- (simp [to_basic_roots_def]
     \\ simp [ADDR_MAP_def]
     \\ Cases_on `roots1`
     \\ fs [])
  \\ fs [to_basic_roots_def]
  \\ Cases_on `roots1`
  \\ fs []
  \\ strip_tac
  \\ Cases_on `h`
  \\ fs [to_basic_heap_address_def]
  >- (IF_CASES_TAC
     \\ fs [ADDR_MAP_def]
     >- (first_x_assum drule \\ fs [])
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ first_x_assum drule \\ fs [])
  \\ fs [ADDR_MAP_def]
  \\ first_x_assum drule \\ fs []);

val heap_lookup_by_f_isSomeData_lemma = prove(
  ``!h1 x xs (state1 : ('a,'b) gc_state) (heap : ('a,'b) heap_element list) conf.
    (heap_lookup x
      (MAP (to_basic_heap_element conf) h1 ++ heap_expand state1.n) =
      SOME (DataElement (ADDR_MAP ($' f) (MAP (to_basic_heap_address conf) xs)) l d)) /\
    (∀u ptr.
       MEM (Pointer ptr u) xs ⇒
       isSomeDataElement (heap_lookup ptr heap)) /\
    (∀ptr u.
       MEM (Pointer ptr u) (MAP (to_basic_heap_address conf) xs) ⇒
       ptr ∈ FDOM f)
    ==>
    (heap_lookup x (h1 ++ heap_expand state1.n ++ state1.r1) =
      SOME (DataElement (ADDR_MAP ($' (new_f f conf heap)) xs) l d))
  ``,
  Induct
  >- (rpt strip_tac \\ fs [MAP]
     \\ fs [heap_lookup_heap_expand])
  \\ rpt gen_tac
  \\ fs [MAP]
  \\ fs [heap_lookup_def]
  \\ reverse IF_CASES_TAC \\ fs []
  >- (rpt strip_tac
     \\ metis_tac [])
  \\ qpat_x_assum `!x. _` kall_tac
  \\ Cases_on `h` \\ fs [to_basic_heap_element_def]
  \\ rw []
  \\ ntac 3 (pop_assum mp_tac)
  \\ qspec_tac (`l'`,`left`)
  \\ qspec_tac (`xs`,`right`)
  \\ Induct \\ fs []
  >- (Cases \\ fs [ADDR_MAP_def,MAP,to_basic_heap_address_def])
  \\ Cases_on `left`
  >- (Cases
     \\ fs [to_basic_heap_address_def,ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def])
  \\ fs [MAP]
  \\ Cases \\ Cases_on `h` \\ fs [to_basic_heap_address_def]
  >- (IF_CASES_TAC \\ IF_CASES_TAC
     >- (fs [ADDR_MAP_def] \\ reverse (rw [])
        >- metis_tac []
        \\ simp [new_f_def,f_old_ptrs_def]
        \\ pop_assum kall_tac
        \\ pop_assum (qspecl_then [`a`,`n`] assume_tac)
        \\ fs []
        \\ simp [FUNION_DEF]
        \\ simp [FUN_FMAP_DEF])
     >- (IF_CASES_TAC \\ fs [ADDR_MAP_def])
     >- (IF_CASES_TAC \\ fs [ADDR_MAP_def]
        \\ IF_CASES_TAC \\ fs [ADDR_MAP_def]
        \\ reverse (rw [])
        >- metis_tac []
        \\ simp [new_f_def,f_old_ptrs_def]
        \\ pop_assum kall_tac
        \\ pop_assum (qspecl_then [`a`,`n`] assume_tac)
        \\ fs []
        \\ simp [FUNION_DEF]
        \\ simp [FUN_FMAP_DEF])
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ reverse (rw [])
     >- metis_tac []
     \\ simp [new_f_def,f_old_ptrs_def] \\ fs []
     \\ simp [FUNION_DEF]
     \\ pop_assum (qspecl_then [`n − conf.gen_start`,`Real a`] assume_tac)
     \\ fs []
     \\ `n IN IMAGE ($+ conf.gen_start) (FDOM f)` by all_tac
     >- (fs [] \\ qexists_tac `n - conf.gen_start` \\ fs [])
     \\ simp [FUN_FMAP_DEF])
  >- (IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def])
  >- (IF_CASES_TAC \\ fs [ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs [ADDR_MAP_def])
  \\ fs [ADDR_MAP_def]
  \\ rw []
  \\ metis_tac []);

val similar_ptr_def = Define `
  (similar_ptr conf (Pointer p1 d1) (Pointer p2 d2) <=> (d2 = d1)) /\
  (similar_ptr conf x1 x2 = (x1 = x2))`

val similar_data_def = Define `
  (similar_data conf (DataElement xs1 l1 d1) (DataElement xs2 l2 d2) <=>
    (l2 = l1) /\ (d2 = d1) /\ LIST_REL (similar_ptr conf) xs1 xs2) /\
  (similar_data conf x y = (x = y))`;

val LENGTH_ADDR_MAP = prove(
  ``!xs. LENGTH (ADDR_MAP f xs) = LENGTH xs``,
  Induct \\ fs [LENGTH,ADDR_MAP_def]
  \\ Cases \\ fs [LENGTH,ADDR_MAP_def]);

val heap_lookup_similar_data_IMP = prove(
  ``!h1 h2 n.
      LIST_REL (similar_data conf) h1 h2 /\
      (heap_lookup n h1 = SOME (DataElement xs1 l d)) /\
      (ADDR_MAP ($FAPPLY f) (refs_to_roots conf h1) = refs_to_roots conf h2) ==>
      ?xs2. (heap_lookup n h2 = SOME (DataElement xs2 l d)) /\
            (ADDR_MAP ($' f) (MAP (to_basic_heap_address conf) xs1) =
               MAP (to_basic_heap_address conf) xs2)``,
  Induct THEN1 fs [heap_lookup_def]
  \\ fs [heap_lookup_def,PULL_EXISTS]
  \\ rpt gen_tac
  \\ Cases_on `n = 0` \\ fs []
  THEN1
   (strip_tac \\ rveq
    \\ Cases_on `y` \\ fs [similar_data_def] \\ rveq
    \\ fs [refs_to_roots_def,ADDR_MAP_APPEND]
    \\ qmatch_assum_abbrev_tac `ys1 ++ ys2 = ts1 ++ ts2`
    \\ qsuff_tac `LENGTH ys1 = LENGTH ts1`
    THEN1 metis_tac [APPEND_11_LENGTH]
    \\ unabbrev_all_tac \\ fs [LENGTH_ADDR_MAP]
    \\ imp_res_tac LIST_REL_LENGTH \\ fs [])
  \\ Cases_on `h` \\ Cases_on `y` \\ fs [similar_data_def]
  \\ strip_tac \\ rveq
  \\ fs [el_length_def]
  \\ first_x_assum match_mp_tac \\ fs []
  \\ fs [refs_to_roots_def,ADDR_MAP_APPEND]
  \\ qmatch_assum_abbrev_tac `ys1 ++ ys2 = ts1 ++ ts2`
  \\ qsuff_tac `LENGTH ys1 = LENGTH ts1`
  THEN1 metis_tac [APPEND_11_LENGTH]
  \\ unabbrev_all_tac \\ fs [LENGTH_ADDR_MAP]
  \\ imp_res_tac LIST_REL_LENGTH \\ fs []);

val new_f_old_parts = prove(
  ``n IN FDOM (new_f f conf heap) /\
    (∀i. i ∈ FDOM f ⇒
         isSomeDataElement (heap_lookup (i + conf.gen_start) heap)) /\
    (n < conf.gen_start \/ conf.refs_start ≤ n) ==>
    (new_f f conf heap ' n = n)``,
  fs [new_f_FAPPLY]);

val gc_move_list_similar = prove(
  ``!xs state1 ys state2.
      (gc_move_list conf state1 xs = (ys,state2)) ==>
      LIST_REL (similar_ptr conf) xs ys``,
  Induct \\ fs [gc_move_list_def]
  \\ rw[] \\ rpt (pairarg_tac \\ fs []) \\ rveq \\ fs []
  \\ res_tac \\ fs []
  \\ Cases_on `h` \\ fs [gc_move_def]
  \\ every_case_tac \\ fs []
  \\ rw[] \\ rpt (pairarg_tac \\ fs []) \\ rveq \\ fs []
  \\ fs [similar_ptr_def]);

val gc_move_ref_list_similar = prove(
  ``!heap_refs state refs' state' conf.
      (gc_move_ref_list conf state heap_refs = (refs',state')) ==>
      LIST_REL (similar_data conf) heap_refs refs'``,
  Induct \\ fs [gc_move_ref_list_def]
  \\ Cases
  \\ fs [gc_move_ref_list_def,similar_data_def]
  \\ TRY (rw [] \\ match_mp_tac EVERY2_refl \\ fs []
          \\ Cases \\ fs [similar_data_def]
          \\ rw [] \\ match_mp_tac EVERY2_refl \\ fs []
          \\ Cases \\ fs [similar_ptr_def] \\ NO_TAC)
  \\ rw[] \\ rpt (pairarg_tac \\ fs []) \\ rveq
  \\ fs [] \\ res_tac \\ fs []
  \\ fs [similar_data_def]
  \\ imp_res_tac gc_move_list_similar \\ fs []);

val partial_gc_related = store_thm("partial_gc_related",
  ``roots_ok roots heap /\
    heap_ok (heap:('a,'b) heap_element list) conf.limit /\
    heap_gen_ok heap conf /\
    gen_inv conf heap
    ==>
    ?state f.
      (partial_gc conf (roots:'a heap_address list,heap) =
         (ADDR_MAP (FAPPLY f) roots,state)) /\
      (!ptr u. MEM (Pointer ptr u) roots ==> ptr IN FDOM f) /\
      (heap_ok (state.old ++ state.h1 ++ heap_expand state.n ++ state.r1) conf.limit) /\
      gc_related f heap (state.old ++ state.h1 ++ heap_expand state.n ++ state.r1)
  ``,
  rpt strip_tac
  \\ fs [gen_inv_def]
  \\ Cases_on `partial_gc conf (roots,heap)` \\ fs []
  \\ rename1 `_ = (roots1,state1)`
  \\ drule partial_gc_simulation
  \\ fs []
  \\ strip_tac
  \\ drule roots_ok_simulation
  \\ disch_then drule \\ simp [] \\ strip_tac
  \\ drule heap_ok_simulation
  \\ fs []
  \\ strip_tac
  \\ qabbrev_tac `basic_roots = to_basic_roots conf roots ++ refs_to_roots conf heap_refs`
  \\ qabbrev_tac `basic_heap = MAP (to_basic_heap_element conf) heap_current`
  \\ drule basic_gc_related
  \\ disch_then drule
  \\ fs []
  \\ strip_tac \\ fs []
  \\ qexists_tac `new_f f conf heap`
  \\ fs [to_basic_heap_list_def]
  \\ rveq
  \\ drule partial_gc_heap_length_lemma
  \\ disch_then drule
  \\ fs []
  \\ strip_tac
  \\ strip_tac    (* (roots1 = ADDR_MAP ($' (new_f f conf heap)) roots) *)
  >- (fs [gc_related_def]
     \\ qunabbrev_tac `basic_roots`
     \\ fs [ADDR_MAP_APPEND]
     \\ qpat_x_assum `ADDR_MAP _ _ ++ _ = _` mp_tac
     \\ strip_tac
     \\ drule APPEND_LENGTH_IMP
     \\ impl_tac
     >- (fs [GSYM ADDR_MAP_LENGTH]
        \\ fs [to_basic_roots_def]
        \\ fs [partial_gc_def]
        \\ rfs []
        \\ pairarg_tac \\ fs []
        \\ pairarg_tac \\ fs []
        \\ drule gc_move_list_IMP
        \\ metis_tac [])
     \\ strip_tac
     \\ pop_assum kall_tac
     \\ pop_assum mp_tac
     \\ simp [to_basic_roots_def]
     \\ qpat_x_assum `roots_ok _ _` kall_tac
     \\ qpat_x_assum `roots_ok _ _` mp_tac
     \\ qpat_x_assum `!ptr u. _ ==> ptr IN FDOM f` mp_tac
     \\ qspec_tac (`roots`, `roots`)
     \\ qspec_tac (`roots1`, `roots1`)
     \\ Induct
     >- (Cases
        \\ strip_tac
        >- fs [ADDR_MAP_def]
        \\ rpt strip_tac
        \\ fs [MAP]
        \\ Cases_on `to_basic_heap_address conf h`
        \\ fs [ADDR_MAP_def])
     \\ reverse Cases
     >- (Cases \\ ntac 2 strip_tac
        >- (fs [to_basic_heap_address_def]
           \\ rpt (IF_CASES_TAC >- fs [ADDR_MAP_def])
           \\ fs [ADDR_MAP_def])
        \\ Cases_on `h`
        \\ fs [to_basic_heap_address_def,ADDR_MAP_def]
        >- (rpt (IF_CASES_TAC >- fs [ADDR_MAP_def])
           \\ fs [ADDR_MAP_def])
        \\ rpt strip_tac
        \\ rveq
        \\ drule roots_ok_CONS
        \\ strip_tac
        \\ fs [to_basic_roots_def]
        \\ metis_tac [])
     \\ Cases
     \\ ntac 2 strip_tac
     \\ fs [ADDR_MAP_def]
     \\ reverse (Cases_on `h`)
     >- (fs [to_basic_heap_address_def]
        \\ rpt (IF_CASES_TAC >- fs [ADDR_MAP_def])
        \\ fs [ADDR_MAP_def])
     \\ fs [to_basic_heap_address_def,new_f_def]
     \\ qpat_x_assum `!ptr u. _` mp_tac
     \\ simp [to_basic_roots_def] \\ strip_tac
     \\ rw []
     \\ drule roots_ok_CONS
     \\ fs [ADDR_MAP_def]
     \\ fs [FUNION_DEF]
     \\ fs [FUN_FMAP_DEF]
     >- (`n ∈ f_old_ptrs conf heap` by all_tac
        >- fs [f_old_ptrs_def,roots_ok_def]
        \\ fs []
        \\ metis_tac [to_basic_roots_def])
     >- (`n ∈ f_old_ptrs conf heap` by all_tac
        >- fs [f_old_ptrs_def,roots_ok_def]
        \\ fs []
        \\ metis_tac [to_basic_roots_def])
     \\ `~(n' ∈ f_old_ptrs conf heap)` by all_tac
     >- fs [f_old_ptrs_def,roots_ok_def]
     \\ fs []
     \\ rveq
     \\ strip_tac
     \\ qispl_then [`(\a. conf.gen_start + f ' (a − conf.gen_start))`] mp_tac FUN_FMAP_DEF
     \\ disch_then (qspec_then `IMAGE ($+ conf.gen_start) (FDOM f)` mp_tac)
     \\ impl_tac
     >- (fs [IMAGE_FINITE,FDOM_FINITE])
     \\ fs []
     \\ disch_then (qspec_then `n'` mp_tac) \\ fs []
     \\ impl_tac
     >- (qexists_tac `n' − conf.gen_start`
        \\ fs []
        \\ first_x_assum match_mp_tac
        \\ fs [to_basic_roots_def,to_basic_heap_address_def]
        \\ metis_tac [])
     \\ fs []
     \\ strip_tac
     \\ fs [AND_IMP_INTRO]
     \\ first_x_assum match_mp_tac
     \\ fs []
     \\ rpt strip_tac
     \\ first_x_assum match_mp_tac
     \\ fs [to_basic_roots_def,to_basic_heap_address_def]
     \\ metis_tac [])
  \\ strip_tac (* ∀ptr u. MEM (Pointer ptr u) roots ⇒ ptr ∈ FDOM (new_f f conf heap) *)
  >- (rpt gen_tac
     \\ fs [new_f_def]
     \\ Cases_on `ptr < conf.gen_start`
     >- (fs [f_old_ptrs_def,roots_ok_def]
        \\ metis_tac [])
     \\ Cases_on `conf.refs_start ≤ ptr`
     >- (fs [f_old_ptrs_def,roots_ok_def]
        \\ metis_tac [])
     \\ fs [f_old_ptrs_def]
     \\ strip_tac
     \\ qexists_tac `ptr - conf.gen_start`
     \\ fs []
     \\ first_x_assum match_mp_tac
     \\ qunabbrev_tac `basic_roots`
     \\ fs [to_basic_roots_def]
     \\ fs [MEM_MAP]
     \\ qexists_tac `Real u`
     \\ disj1_tac
     \\ qexists_tac `Pointer ptr u`
     \\ fs []
     \\ fs [to_basic_heap_address_def])
  \\ `heap_ok (state1.old ++ state1.h1 ++ heap_expand state1.n ++ state1.r1) conf.limit` by all_tac
  >- (drule basic_gc_thm
     \\ disch_then drule
     \\ fs []
     \\ strip_tac
     \\ drule basic_gc_ok
     \\ disch_then drule
     \\ fs []
     \\ strip_tac
     \\ pop_assum mp_tac
     \\ simp [heap_ok_def]
     \\ strip_tac
     \\ fs [to_basic_conf_def]
     \\ strip_tac               (* heap_length *)
     >- (ntac 2 (first_x_assum kall_tac)
        \\ pop_assum mp_tac
        \\ drule heap_segment_IMP
        \\ fs [] \\ strip_tac \\ fs []
        \\ simp [heap_length_APPEND]
        \\ simp [to_basic_state_def]
        \\ drule partial_gc_IMP \\ fs []
        \\ strip_tac \\ fs []
        \\ fs [heap_length_heap_expand,heap_ok_def])
     \\ strip_tac               (* no ForwardPointers *)
     >- (fs [FILTER_APPEND]
        \\ pop_assum kall_tac
        \\ fs [to_basic_state_def]
        \\ drule FILTER_isForward_to_basic \\ strip_tac
        \\ fs []
        \\ rpt strip_tac
        >- (fs [heap_ok_def]
           \\ drule partial_gc_IMP
           \\ fs [] \\ strip_tac \\ fs []
           \\ drule heap_segment_IMP
           \\ fs [] \\ strip_tac
           \\ rveq
           \\ fs [FILTER_APPEND])
        >- (fs [heap_expand_def]
           \\ IF_CASES_TAC
           \\ fs [isForwardPointer_def])
        \\ fs [partial_gc_def] \\ rfs [] (*  *)
        \\ pairarg_tac \\ fs []
        \\ pairarg_tac \\ fs []
        \\ drule gc_move_data_IMP
        \\ strip_tac \\ fs []
        \\ rveq
        \\ fs []
        \\ drule gc_move_refs_isForwardPointer
        \\ impl_tac
        >- (fs [heap_ok_def]
           \\ drule heap_segment_IMP
           \\ fs []
           \\ strip_tac
           \\ qpat_x_assum `_ = heap` (assume_tac o GSYM)
           \\ fs []
           \\ fs [FILTER_APPEND])
        \\ fs [])
     \\ rpt gen_tac
     \\ strip_tac
     (* MEM old *)
     >- (drule partial_gc_IMP
        \\ fs [] \\ strip_tac \\ fs []
        \\ qpat_x_assum `heap_ok _ _` kall_tac
        \\ qpat_x_assum `heap_ok _ _` mp_tac
        \\ simp [heap_ok_def]
        \\ strip_tac
        \\ drule heap_segment_IMP \\ simp [] \\ strip_tac
        \\ rveq
        \\ qpat_x_assum `!xs l d ptr u. MEM _ _ /\ _ ==> _` drule
        \\ disch_then drule
        \\ strip_tac
        >- (qpat_x_assum `!xs. _` mp_tac
           \\ rewrite_tac [GSYM APPEND_ASSOC]
           \\ simp [heap_lookup_APPEND]
           \\ disch_then (qspecl_then [`xs`,`l`,`d`,`ptr`,`u`] mp_tac)
           \\ simp [])
        \\ qpat_x_assum `!xs l d ptr u. _` (qspecl_then [`xs`,`l`,`d`,`ptr`,`u`] mp_tac)
        \\ simp [MEM_APPEND]
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ simp []
        \\ drule partial_gc_refs_isSomeDataElement_isSomeDataElement
        \\ disch_then drule
        \\ metis_tac [])
     (* MEM state1.h1 *)
     >- (`MEM (DataElement (MAP (to_basic_heap_address conf) xs) l d) (to_basic_state conf state1).h1` by all_tac
        >- (ntac 2 (pop_assum mp_tac)
           \\ simp [to_basic_state_def,to_basic_heap_list_def]
           \\ qspec_tac (`state1.h1`,`h1`)
           \\ Induct \\ fs []
           \\ Cases \\ fs [to_basic_heap_element_def]
           \\ strip_tac \\ rveq
           \\ fs []
           \\ metis_tac [])
        \\ drule partial_gc_IMP \\ fs [] \\ strip_tac \\ fs []
        \\ drule heap_segment_IMP \\ fs [] \\ strip_tac \\ rveq
        \\ qpat_x_assum `!xs' l' d' ptr' u'. (MEM _ state1.h1 \/ _) /\ _ ==> _` mp_tac
        \\ disch_then (qspecl_then [`xs`,`l`,`d`] mp_tac)
        \\ simp []
        \\ disch_then drule
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ reverse IF_CASES_TAC \\ fs []
        \\ rewrite_tac [GSYM APPEND_ASSOC]
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ IF_CASES_TAC \\ fs []
        \\ fs [to_basic_state_def]
        \\ qpat_x_assum `!xs. _` (qspecl_then [`MAP (to_basic_heap_address conf) xs`,`l`,`d`] mp_tac)
        \\ fs [] \\ strip_tac
        \\ qpat_x_assum `MEM (Pointer _ _) xs` mp_tac \\ simp [MEM_SPLIT]
        \\ strip_tac \\ rveq
        \\ qpat_x_assum `MEM _ _` mp_tac
        \\ qpat_x_assum `!ptr. _` mp_tac
        \\ simp [to_basic_heap_address_def]
        \\ ntac 2 strip_tac
        \\ rfs []
        \\ fs []
        \\ qpat_x_assum `!ptr. _` (qspecl_then [`ptr - conf.gen_start`,`Real u`] assume_tac)
        \\ fs []
        \\ drule isSomeData_to_basic_heap_IMP_isSomeData \\ fs [])
     >- (fs [heap_expand_def] \\ Cases_on `state1.n` \\ fs [])
     (* MEM state1.r1 *)
     \\ qpat_x_assum `_ = ADDR_MAP _ _` (assume_tac o GSYM)
     \\ fs []
     \\ qpat_x_assum `roots_ok _ _` mp_tac
     \\ simp [to_basic_state_def] \\ strip_tac
     \\ qunabbrev_tac `basic_roots`
     \\ qpat_x_assum `!xs' l' d' ptr' u'. (MEM _ state1.h1 \/ _) /\ _ ==> _` mp_tac
     \\ disch_then (qspecl_then [`xs`,`l`,`d`] mp_tac) \\ simp []
     \\ disch_then drule
     \\ drule partial_gc_IMP \\ fs [] \\ strip_tac \\ fs []
     \\ drule heap_segment_IMP \\ fs [] \\ strip_tac \\ rveq
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ reverse IF_CASES_TAC \\ fs []
     \\ rewrite_tac [GSYM APPEND_ASSOC]
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ IF_CASES_TAC \\ fs []
     \\ drule roots_ok_APPEND
     \\ strip_tac
     \\ drule refs_root_IMP_isSomeData \\ simp [])
  \\ fs []
  \\ fs [gc_related_def]
  \\ `∀i. i ∈ FDOM f ⇒ isSomeDataElement (heap_lookup (i + conf.gen_start) heap)` by all_tac
  >- (rpt strip_tac
     \\ res_tac
     \\ qunabbrev_tac `basic_heap`
     \\ drule heap_segment_IMP
     \\ fs [] \\ strip_tac
     \\ rveq
     \\ rewrite_tac [GSYM APPEND_ASSOC]
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ IF_CASES_TAC
     >- decide_tac
     \\ fs []
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ IF_CASES_TAC
     >- (qpat_x_assum `isSomeDataElement _` mp_tac
        \\ fs [heap_lookup_to_basic_heap_element])
     \\ fs [heap_lookup_to_basic_heap_element]
     \\ fs [heap_lookup_GT_FALSE])
  \\ strip_tac
  (* INJ new_f *)
  >- (fs [INJ_DEF] \\ strip_tac
     >- (fs [new_f_FAPPLY]
        \\ fs [new_f_FDOM]
        \\ rpt strip_tac
        \\ Cases_on `x < conf.gen_start` \\ fs []
        >- (drule heap_lookup_old_IMP_ALT
           \\ fs [isSomeDataElement_def,gen_inv_def]
           \\ metis_tac [GSYM APPEND_ASSOC])
        \\ IF_CASES_TAC \\ fs []
        >- (drule heap_lookup_refs_IMP_ALT
           \\ fs [gen_inv_def]
           \\ impl_tac \\ fs []
           \\ metis_tac [])
        \\ `(to_basic_state conf state1).r1 = []` by all_tac
        >- EVAL_TAC
        \\ fs []
        \\ qpat_x_assum `!x'. x' IN FDOM f ==> _` mp_tac
        \\ qpat_x_assum `!x'. x' IN FDOM f ==> _` drule
        \\ strip_tac \\ strip_tac
        \\ drule heap_segment_IMP
        \\ fs [] \\ strip_tac \\ fs []
        \\ fs [to_basic_state_def]
        \\ simp []
        \\ full_simp_tac std_ss [GSYM APPEND_ASSOC]
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ fs [heap_length_APPEND]
        \\ IF_CASES_TAC
        \\ drule partial_gc_IMP
        \\ fs [] \\ strip_tac
        \\ fs []
        \\ rewrite_tac [GSYM APPEND_ASSOC]
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ IF_CASES_TAC
        >- (qpat_x_assum `isSomeDataElement (heap_lookup _ _)` mp_tac
           \\ unabbrev_all_tac
           (* \\ strip_tac *)
           (* \\ simp [isSomeDataElement_to_basic_heap_element] *)
           (* \\ simp [isSomeDataElement_def] *)
           \\ simp [Once isSomeDataElement_def]
           \\ strip_tac
           \\ qpat_x_assum `!i xs l d. i IN FDOM f /\ _ ==> _` drule
           \\ disch_then drule
           \\ rewrite_tac [heap_lookup_APPEND]
           \\ reverse IF_CASES_TAC
           >- (rewrite_tac [heap_expand_def] \\ Cases_on `state1.n` \\ simp [heap_lookup_def])
           \\ strip_tac
           \\ drule isSomeData_to_basic_heap_IMP
           \\ simp [])
        (* current heap *)
        \\ `heap_length (state1.h1 ++ heap_expand state1.n) = heap_length (to_basic_heap_list conf state1.h1 ++ heap_expand state1.n)` by all_tac
        >- (fs [heap_length_APPEND]
           \\ fs [heap_expand_def]
           \\ IF_CASES_TAC \\ fs []
           \\ fs [heap_length_def,el_length_def])
        \\ unabbrev_all_tac
        \\ qpat_x_assum `!i xs l d. i IN FDOM f /\ _ ==> _` drule
        \\ fs [isSomeDataElement_def]
        \\ rewrite_tac [Once heap_lookup_APPEND]
        \\ simp []
        \\ simp [heap_expand_def]
        \\ IF_CASES_TAC
        \\ fs [heap_lookup_def])
     \\ fs [new_f_FAPPLY]
     \\ fs [new_f_FDOM]
     \\ rpt gen_tac
     \\ IF_CASES_TAC \\ IF_CASES_TAC \\ fs []
     \\ TRY (rpt strip_tac \\ rveq \\ fs [] \\ NO_TAC)
     \\ unabbrev_all_tac
     \\ simp [isSomeDataElement_def]
     \\ strip_tac
     \\ fs []
     \\ rveq
     \\ strip_tac
     \\ rveq
     \\ rpt strip_tac
     \\ qpat_x_assum `!i. i IN FDOM f ==> _` kall_tac
     \\ qpat_x_assum `!i. i IN FDOM f ==> _` drule
     \\ simp [isSomeDataElement_def]
     \\ rpt strip_tac
     \\ first_x_assum drule
     \\ disch_then drule
     \\ strip_tac
     \\ pop_assum kall_tac
     \\ pop_assum mp_tac
     \\ simp []
     \\ fs [to_basic_state_def]
     \\ drule heap_segment_IMP
     \\ fs [] \\ strip_tac \\ rveq
     \\ `heap_length heap_current = conf.refs_start - conf.gen_start` by fs [heap_length_APPEND]
     \\ `heap_length (to_basic_heap_list conf state1.h1 ++ heap_expand state1.n) = conf.refs_start - conf.gen_start` by
        (drule basic_gc_thm
        \\ disch_then drule
        \\ fs [] \\ strip_tac \\ fs []
        \\ fs [gc_inv_def]
        \\ rewrite_tac [heap_length_APPEND]
        \\ rewrite_tac [heap_length_to_basic_heap_list]
        \\ asm_rewrite_tac []
        \\ rewrite_tac [heap_length_heap_expand]
        \\ simp []
        \\ simp [to_basic_conf_def])
     \\ match_mp_tac (heap_lookup_GT_FALSE |> SIMP_RULE std_ss [isSomeDataElement_def])
     \\ fs [])
  \\ strip_tac
  >- (fs [new_f_FDOM]
     \\ strip_tac
     \\ IF_CASES_TAC \\ fs []
     \\ strip_tac
     \\ metis_tac [])
  \\ rpt gen_tac
  \\ fs [new_f_FAPPLY]
  \\ fs [new_f_FDOM]
  \\ Cases_on `i < conf.gen_start` \\ fs []
  >- (strip_tac
     \\ drule heap_lookup_old_IMP
     \\ fs [gen_inv_def,GSYM PULL_FORALL,GSYM AND_IMP_INTRO]
     \\ fs [AND_IMP_INTRO]
     \\ impl_tac THEN1 metis_tac []
     \\ disch_then drule
     \\ fs []
     \\ full_simp_tac std_ss [GSYM APPEND_ASSOC]
     \\ strip_tac
     \\ fs [heap_gen_ok_def]
     \\ fs []
     \\ strip_tac
     >- (match_mp_tac ADDR_MAP_ID
        \\ rpt strip_tac
        \\ drule MEM_heap_old
        \\ fs []
        \\ ntac 2 (disch_then drule)
        \\ fs []
        \\ strip_tac
        \\ `x IN FDOM (new_f f conf heap)` by all_tac
        >- (fs [new_f_FDOM]
           \\ reverse IF_CASES_TAC
           >- (res_tac \\ fs [])
           \\ fs [heap_ok_def]
           \\ metis_tac [heap_lookup_IMP_MEM])
        \\ fs [new_f_FAPPLY]
        \\ IF_CASES_TAC \\ fs []
        \\ res_tac \\ fs [])
     \\ rpt strip_tac
     \\ drule MEM_heap_old
     \\ fs []
     \\ disch_then drule \\ fs []
     \\ strip_tac
     \\ IF_CASES_TAC
     >- (`MEM (DataElement xs l d) heap` by all_tac
        >- (drule heap_segment_IMP \\ fs []
           \\ rveq
           \\ metis_tac [MEM_APPEND])
        \\ fs [heap_ok_def] \\ metis_tac [])
     \\ fs []
     \\ qexists_tac `ptr - conf.gen_start`
     \\ fs []
     \\ res_tac \\ fs [])
  \\ Cases_on `conf.refs_start ≤ i` \\ fs []
  >- (
     strip_tac
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ IF_CASES_TAC \\ fs []
     \\ `heap_lookup (i - conf.refs_start) heap_refs = SOME (DataElement xs l d)` by all_tac
     >- (drule heap_segment_IMP
        \\ fs [] \\ strip_tac
        \\ rveq
        \\ qpat_x_assum `heap_lookup i _ = _` mp_tac
        \\ once_rewrite_tac [heap_lookup_APPEND]
        \\ simp [heap_length_APPEND])
     \\ unabbrev_all_tac
     \\ drule partial_gc_IMP
     \\ simp []
     \\ strip_tac
     \\ drule ADDR_MAP_APPEND_LENGTH_IMP
     \\ simp [] \\ strip_tac
     \\ rpt (disch_then assume_tac)
     \\ fs [ADDR_MAP_APPEND]
     \\ `LIST_REL (similar_data conf) heap_refs state1.r1` by
      (rfs [partial_gc_def]
       \\ pairarg_tac \\ fs []
       \\ pairarg_tac \\ fs []
       \\ imp_res_tac gc_move_data_r1 \\ fs []
       \\ imp_res_tac gc_move_ref_list_similar
       \\ asm_rewrite_tac [] \\ NO_TAC)
     \\ drule (GEN_ALL heap_lookup_similar_data_IMP)
     \\ rpt (disch_then drule)
     \\ strip_tac \\ fs []
     \\ reverse conj_asm2_tac THEN1
      (rpt strip_tac
       \\ qpat_x_assum `heap_ok heap conf.limit` mp_tac
       \\ simp [heap_ok_def]
       \\ imp_res_tac heap_lookup_IMP_MEM \\ fs []
       \\ strip_tac
       \\ pop_assum drule
       \\ disch_then drule \\ fs [METIS_PROVE [] ``b\/c<=>(~b==>c)``]
       \\ rpt strip_tac
       \\ qexists_tac `ptr - conf.gen_start` \\ fs []
       \\ first_x_assum match_mp_tac
       \\ qpat_x_assum `MEM _ heap_refs` mp_tac
       \\ qspec_tac (`heap_refs`,`heap_refs`)
       \\ Induct \\ fs [refs_to_roots_def]
       \\ strip_tac \\ Cases_on `DataElement xs l d = h` \\ rveq
       THEN1
        (fs [refs_to_roots_def,MEM_MAP]
         \\ qexists_tac `Real u` \\ fs [] \\ strip_tac
         \\ disj1_tac \\ qexists_tac `Pointer ptr u`  \\ fs []
         \\ fs [to_basic_heap_address_def])
       \\ fs [] \\ Cases_on `h`
       \\ fs [refs_to_roots_def] \\ metis_tac [])
     \\ `!ptr u. MEM (Pointer ptr u) xs ==>
                 ptr IN FDOM (new_f f conf heap)` by
      (rpt strip_tac \\ fs [new_f_FDOM] \\ first_x_assum drule \\ fs [] \\ NO_TAC)
     \\ pop_assum mp_tac
     \\ pop_assum kall_tac
     \\ pop_assum mp_tac
     \\ qspec_tac (`xs2`,`xs2`)
     \\ qspec_tac (`xs`,`xs`)
     \\ Induct THEN1 (Cases \\ fs [ADDR_MAP_def])
     \\ reverse Cases THEN1
      (Cases \\ fs [to_basic_heap_address_def,ADDR_MAP_def]
       \\ Cases_on `h` \\ fs [to_basic_heap_address_def,ADDR_MAP_def]
       \\ rw [] \\ fs [] \\ metis_tac [])
     \\ fs [to_basic_heap_address_def,ADDR_MAP_def]
     \\ IF_CASES_TAC \\ fs []
     THEN1
      (Cases \\ fs [ADDR_MAP_def]
       \\ Cases_on `h` \\ fs [to_basic_heap_address_def]
       \\ rw [] \\ fs []
       \\ `n IN FDOM (new_f f conf heap)` by metis_tac []
       \\ rpt strip_tac
       \\ drule (GEN_ALL new_f_old_parts) \\ fs []
       \\ TRY (disch_then drule)
       \\ metis_tac[])
     \\ IF_CASES_TAC \\ fs []
     THEN1
      (Cases \\ fs [ADDR_MAP_def]
       \\ Cases_on `h` \\ fs [to_basic_heap_address_def]
       \\ rw [] \\ fs []
       \\ `n IN FDOM (new_f f conf heap)` by metis_tac []
       \\ rpt strip_tac
       \\ drule (GEN_ALL new_f_old_parts) \\ fs []
       \\ TRY (disch_then drule)
       \\ metis_tac[])
     \\ Cases \\ fs [ADDR_MAP_def]
     \\ Cases_on `h` \\ fs [to_basic_heap_address_def]
     \\ reverse (rw [] \\ fs []) THEN1 metis_tac[]
     \\ `n IN FDOM (new_f f conf heap)` by metis_tac []
     \\ drule (GEN_ALL new_f_FAPPLY) \\ fs [])
  \\ strip_tac
  \\ rveq
  \\ fs []
  \\ fs [INJ_DEF]
  \\ qpat_x_assum `!i. i IN FDOM f ==> isSomeDataElement _` kall_tac
  \\ qpat_x_assum `!i. i IN FDOM f ==> isSomeDataElement _` drule
  \\ fs [isSomeDataElement_def]
  \\ strip_tac
  \\ first_x_assum drule
  \\ fs []
  \\ strip_tac
  \\ rewrite_tac [GSYM APPEND_ASSOC]
  \\ once_rewrite_tac [heap_lookup_APPEND]
  \\ `heap_length state1.old = conf.gen_start` by all_tac
  >- (drule partial_gc_IMP
     \\ disch_then drule
     \\ strip_tac
     \\ rveq
     \\ drule heap_segment_IMP
     \\ strip_tac \\ fs [])
  \\ fs []
  \\ fs [to_basic_state_def]
  \\ fs [to_basic_heap_list_def]
  \\ `(l = l') /\ (d = d') /\ (ys = MAP (to_basic_heap_address conf) xs)` by all_tac
  >- (rveq
     \\ qunabbrev_tac `basic_heap`
     \\ drule heap_segment_IMP
     \\ fs [] \\ strip_tac
     \\ rveq
     \\ qpat_x_assum `heap_lookup (x + conf.gen_start) _ = _` mp_tac
     \\ rewrite_tac [GSYM APPEND_ASSOC]
     \\ once_rewrite_tac [heap_lookup_APPEND]
     \\ fs []
     \\ qpat_x_assum `heap_lookup x _ = _` mp_tac
     \\ qspec_tac (`x`,`x`)
     \\ qspec_tac (`heap_current`,`heap`)
     \\ Induct
     >- fs [MAP,heap_lookup_def]
     \\ strip_tac
     \\ fs [heap_lookup_def]
     \\ strip_tac
     \\ IF_CASES_TAC \\ fs []
     >- (Cases_on `h` \\ fs [to_basic_heap_element_def]
        \\ rw [])
     \\ fs []
     \\ metis_tac [])
  \\ rveq
  \\ CONJ_TAC
  >- (fs [heap_ok_def]
     \\ ntac 4 (pop_assum mp_tac)
     \\ drule heap_lookup_IMP_MEM
     \\ strip_tac
     \\ ntac 4 strip_tac
     \\ drule heap_lookup_by_f_isSomeData_lemma
     \\ res_tac
     \\ disch_then drule
     \\ disch_then drule
     \\ fs [])
  \\ fs [heap_ok_def]
  \\ rpt strip_tac
  \\ IF_CASES_TAC
  >- (pop_assum mp_tac
     \\ fs []
     \\ imp_res_tac heap_lookup_IMP_MEM
     \\ res_tac
     \\ fs [isSomeDataElement_def])
  \\ qexists_tac `ptr - conf.gen_start`
  \\ fs []
  \\ first_x_assum match_mp_tac
  \\ qexists_tac `Real u`
  \\ qpat_x_assum `MEM _ _` mp_tac
  \\ simp [Once MEM_SPLIT]
  \\ strip_tac
  \\ fs []
  \\ simp [to_basic_heap_address_def]);

val _ = export_theory();
