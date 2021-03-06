open preamble;
local open closLangTheory in end;

val _ = new_theory "dataLang";
val _ = set_grammar_ancestry ["closLang" (* for op *), "misc" (* for num_set *)]

(* dataLang = last language with a data abstraction *)

(* dataLang is the next step from BVL: (1) dataLang is an imperative version of
   BVL, i.e. operations update state; (2) there is a new state
   component (called space) and an explicit MakeSpace operation that
   increases space. Space is consumed by Ref and Cons. *)

(* The idea is that the MakeSpace calls can be moved around and lumped
   together. This optimisation reduces the number of calls to the
   allocator and, thus, simplifies the program.  The MakeSpace function
   can, unfortunately, not be moved across function calls or bignum
   operations, which can internally call the allocator. *)

(* The MakeSpace command has an optional variable name list. If this
   list is provided, i.e. SOME var_names, then only these variables
   can survive the execution of the MakeSpace command. The idea is
   that one generates MakeSpace X NONE when compiling into dataLang. Then
   optimisations move around and combine MakeSpace commands. Then
   liveness analysis annotates each MakeSpace command with a SOME. The
   translation from dataLang into more concete forms must implement a GC
   that only looks at the variables in the SOME annotations. *)


(* --- Syntax of dataLang --- *)

val _ = Datatype `
  prog = Skip
       | Move num num
       | Call ((num # num_set) option) (* return var, cut-set *)
                          (num option) (* target of call *)
                            (num list) (* arguments *)
                 ((num # prog) option) (* handler: varname, handler code *)
       | Assign num op (num list) (num_set option)
       | Seq prog prog
       | If num prog prog
       | MakeSpace num num_set
       | Raise num
       | Return num
       | Tick`;

val mk_ticks_def = Define `
  mk_ticks n e = FUNPOW (Seq Tick) n e`;

val _ = export_theory();
