(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)
open Util
open Names
open Esubst
open Term
open Declarations
open Pre_env
open Nativevalues
      
type lambda =
  | Lrel          of name * int 
  | Lvar          of identifier
  | Lprod         of lambda * lambda 
  | Llam          of name array * lambda  
  | Lrec          of name * lambda
  | Llet          of name * lambda * lambda
  | Lapp          of lambda * lambda array
  | Lconst        of string * constant (* prefix, constant name *)
  | Lprim         of (string * constant) option * Native.prim_op * lambda array
	(* No check if None *)
  | Lcprim        of string * constant * Native.caml_prim * lambda array
                  (* prefix, constant name, primitive, arguments *)
  | Lcase         of annot_sw * lambda * lambda * lam_branches 
                  (* annotations, term being matched, accu, branches *)
  | Lareint       of lambda array 
  | Lif           of lambda * lambda * lambda
  | Lfix          of (int array * int) * fix_decl 
  | Lcofix        of int * fix_decl 
  | Lmakeblock    of string * constructor * int * lambda array
                  (* prefix, constructor name, constructor tag, arguments *)
	(* A fully applied constructor *)
  | Lconstruct    of string * constructor (* prefix, constructor name *)
	(* A partially applied constructor *)
  | Lint          of Uint63.t
  | Lparray       of lambda array
  | Lval          of Nativevalues.t
  | Lsort         of sorts
  | Lind          of string * inductive (* prefix, inductive name *)
  | Llazy
  | Lforce

and lam_branches = (constructor * name array * lambda) array 
      
and fix_decl =  name array * lambda array * lambda array
      
(*s Constructors *)
  
let mkLapp f args =
  if Array.length args = 0 then f
  else
    match f with
    | Lapp(f', args') -> Lapp (f', Array.append args' args)
    | _ -> Lapp(f, args)
	  
let mkLlam ids body =
  if Array.length ids = 0 then body
  else 
    match body with
    | Llam(ids', body) -> Llam(Array.append ids ids', body)
    | _ -> Llam(ids, body)
  
let decompose_Llam lam =
  match lam with
  | Llam(ids,body) -> ids, body
  | _ -> [||], lam

(*s Operators on substitution *)
let subst_id = subs_id 0
let lift = subs_lift 
let liftn = subs_liftn
let cons v subst = subs_cons([|v|], subst)
let shift subst = subs_shft (1, subst)

(* Linked code location utilities *)
let get_mind_prefix env mind =
   let mib = lookup_mind mind env in
   match !(mib.mind_native_name) with
   | NotLinked -> ""
   | Linked s -> s
   | LinkedLazy s -> s

let get_const_prefix env c =
   let cb = lookup_constant c env in
   match !(cb.const_native_name) with
   | NotLinked -> ""
   | Linked s -> s
   | LinkedLazy s -> s
    
(* A generic map function *)

let map_lam_with_binders g f n lam =
  match lam with
  | Lrel _ | Lvar _  | Lconst _ | Lint _ | Lval _
  | Lsort _ | Lind _ | Lconstruct _ | Llazy | Lforce -> lam
  | Lprod(dom,codom) -> 
      let dom' = f n dom in
      let codom' = f n codom in
      if dom == dom' && codom == codom' then lam else Lprod(dom',codom')
  | Llam(ids,body) ->
      let body' = f (g (Array.length ids) n) body in
      if body == body' then lam else mkLlam ids body'
  | Lrec(id,body) ->
      let body' = f (g 1 n) body in
      if body == body' then lam else Lrec(id,body')
  | Llet(id,def,body) ->
      let def' = f n def in
      let body' = f (g 1 n) body in
      if body == body' && def == def' then lam else Llet(id,def',body')
  | Lapp(fct,args) ->
      let fct' = f n fct in
      let args' = array_smartmap (f n) args in
      if fct == fct' && args == args' then lam else mkLapp fct' args'
  | Lprim(kn,op,args) ->
      let args' = array_smartmap (f n) args in
      if args == args' then lam else Lprim(kn,op,args')
  | Lcprim(prefix,kn,op,args) ->
      let args' = array_smartmap (f n) args in
      if args == args' then lam else Lcprim(prefix,kn,op,args')
  | Lcase(annot,t,a,br) ->
      let t' = f n t in
      let a' = f n a in
      let on_b b = 
	let (cn,ids,body) = b in
	let body' = 
	  let len = Array.length ids in
	  if len = 0 then f n body 
	  else f (g (Array.length ids) n) body in
	if body == body' then b else (cn,ids,body') in
      let br' = array_smartmap on_b br in
      if t == t' && a == a' && br == br' then lam else Lcase(annot,t',a',br')
  | Lareint a ->
      let a' = array_smartmap (f n) a in
      if a == a' then lam else Lareint a' 
  | Lif(t,bt,bf) ->
      let t' = f n t in
      let bt' = f n bt in
      let bf' = f n bf in
      if t == t' && bt == bt' && bf == bf' then lam else Lif(t',bt',bf')
  | Lfix(init,(ids,ltypes,lbodies)) ->
      let ltypes' = array_smartmap (f n) ltypes in
      let lbodies' = array_smartmap (f (g (Array.length ids) n)) lbodies in
      if ltypes == ltypes' && lbodies == lbodies' then lam
      else Lfix(init,(ids,ltypes',lbodies'))
  | Lcofix(init,(ids,ltypes,lbodies)) ->
      let ltypes' = array_smartmap (f n) ltypes in
      let lbodies' = array_smartmap (f (g (Array.length ids) n)) lbodies in
      if ltypes == ltypes' && lbodies == lbodies' then lam
      else Lcofix(init,(ids,ltypes',lbodies'))
  | Lmakeblock(prefix,cn,tag,args) ->
      let args' = array_smartmap (f n) args in
      if args == args' then lam else Lmakeblock(prefix,cn,tag,args')
  | Lparray p -> 
      let p' = array_smartmap (f n) p in
      if p == p' then lam else Lparray p'

(*s Lift and substitution *)
 
let rec lam_exlift el lam =
  match lam with
  | Lrel(id,i) -> 
      let i' = reloc_rel i el in
      if i == i' then lam else Lrel(id,i')
  | _ -> map_lam_with_binders el_liftn lam_exlift el lam

let lam_lift k lam =
  if k = 0 then lam
  else lam_exlift (el_shft k el_id) lam

let lam_subst_rel lam id n subst =
  match expand_rel n subst with
  | Inl(k,v) -> lam_lift k v
  | Inr(n',_) -> 
      if n == n' then lam
      else Lrel(id, n') 

let rec lam_exsubst subst lam =
  match lam with
  | Lrel(id,i) -> lam_subst_rel lam id i subst
  | _ -> map_lam_with_binders liftn lam_exsubst subst lam

let lam_subst subst lam =
  if is_subs_id subst then lam
  else lam_exsubst subst lam

let lam_subst_args subst args =
  if is_subs_id subst then args 
  else array_smartmap (lam_exsubst subst) args
  
(** Simplification of lambda expression *)
      
(* [simplify subst lam] simplify the expression [lam_subst subst lam] *)
(* that is :                                                          *)
(* - Reduce [let] is the definition can be substituted i.e:           *)
(*    - a variable (rel or identifier)                                *)
 (*    - a constant                                                    *)
(*    - a structured constant                                         *)
(*    - a function                                                    *)
(* - Transform beta redex into [let] expression                       *)
(* - Move arguments under [let]                                       *) 
(* Invariant : Terms in [subst] are already simplified and can be     *)
(*             substituted                                            *)
  
let can_subst lam = 
  match lam with
  | Lrel _ | Lvar _ | Lconst _ | Lint _ 
  | Lval _ | Lsort _ | Lind _ | Llam _ | Lconstruct _ -> true
  | _ -> false

let can_merge_if bt bf =
  match bt, bf with
  | Llam(idst,_), Llam(idsf,_) -> true
  | _ -> false

let merge_if t bt bf =
  let (idst,bodyt) = decompose_Llam bt in
  let (idsf,bodyf) = decompose_Llam bf in
  let nt = Array.length idst in
  let nf = Array.length idsf in
  let common,idst,idsf = 
    if nt = nf then idst, [||], [||] 
    else
      if nt < nf then idst,[||], Array.sub idsf nt (nf - nt)
      else idsf, Array.sub idst nf (nt - nf), [||] in
  Llam(common,
       Lif(lam_lift (Array.length common) t, 
	   mkLlam idst bodyt,
	   mkLlam idsf bodyf))

let rec simplify subst lam =
  match lam with
  | Lrel(id,i) -> lam_subst_rel lam id i subst 

  | Llet(id,def,body) ->
      let def' = simplify subst def in
      if can_subst def' then simplify (cons def' subst) body
      else 
	let body' = simplify (lift subst) body in
	if def == def' && body == body' then lam
	else Llet(id,def',body')

  | Lapp(f,args) ->
      begin match simplify_app subst f subst args with
      | Lapp(f',args') when f == f' && args == args' -> lam
      | lam' -> lam'
      end

  | Lif(t,bt,bf) ->
      let t' = simplify subst t in
      let bt' = simplify subst bt in
      let bf' = simplify subst bf in
      if can_merge_if bt' bf' then merge_if t' bt' bf'
      else 
	if t == t' && bt == bt' && bf == bf' then lam
	else Lif(t',bt',bf')
  | _ -> map_lam_with_binders liftn simplify subst lam

and simplify_app substf f substa args =
  match f with
  | Lrel(id, i) ->
      begin match lam_subst_rel f id i substf with
      | Llam(ids, body) ->
	  reduce_lapp 
	    subst_id (Array.to_list ids) body  
	    substa (Array.to_list args)
      | f' -> mkLapp f' (simplify_args substa args)
      end
  | Llam(ids, body) ->
      reduce_lapp substf (Array.to_list ids) body substa (Array.to_list args)
  | Llet(id, def, body) ->
      let def' = simplify substf def in
      if can_subst def' then
	simplify_app (cons def' substf) body substa args
      else 
	Llet(id, def', simplify_app (lift substf) body (shift substa) args)
  | Lapp(f, args') ->
      let args = Array.append 
	  (lam_subst_args substf args') (lam_subst_args substa args) in
      simplify_app substf f subst_id args
  | _ -> mkLapp (simplify substf f) (simplify_args substa args)
  
and simplify_args subst args = array_smartmap (simplify subst) args

and reduce_lapp substf lids body substa largs =
  match lids, largs with
  | id::lids, a::largs ->
      let a = simplify substa a in
      if can_subst a then
	reduce_lapp (cons a substf) lids body substa largs
      else
	let body = reduce_lapp (lift substf) lids body (shift substa) largs in
	Llet(id, a, body)
  | [], [] -> simplify substf body
  | _::_, _ -> 
      Llam(Array.of_list lids,  simplify (liftn (List.length lids) substf) body)
  | [], _::_ -> simplify_app substf body substa (Array.of_list largs)


(* [occurence kind k lam]:
   If [kind] is [true] return [true] if the variable [k] does not appear in 
   [lam], return [false] if the variable appear one time and not
   under a lambda, a fixpoint, a cofixpoint; else raise Not_found.
   If [kind] is [false] return [false] if the variable does not appear in [lam]
   else raise [Not_found]
*)

let rec occurence k kind lam =   
  match lam with
  | Lrel (_,n) -> 
      if n = k then 
	if kind then false else raise Not_found
      else kind
  | Lvar _  | Lconst _  | Lint _ | Lval _ | Lsort _ | Lind _
  | Lconstruct _ | Llazy | Lforce -> kind
  | Lprod(dom, codom) ->
      occurence k (occurence k kind dom) codom
  | Llam(ids,body) ->
      let _ = occurence (k+Array.length ids) false body in kind
  | Lrec(id,body) ->
      let _ = occurence (k+1) false body in kind
  | Llet(_,def,body) ->
      occurence (k+1) (occurence k kind def) body
  | Lapp(f, args) ->
      occurence_args k (occurence k kind f) args
  | Lprim(_,_, args) | Lcprim(_,_,_,args) | Lmakeblock(_,_,_,args) ->
      occurence_args k kind args
  | Lcase(_,t,a,br) ->
      let kind = occurence k (occurence k kind t) a in
      let r = ref kind in
      Array.iter (fun (_,ids,c) -> 
	r := occurence (k+Array.length ids) kind c && !r) br;
      !r 
  | Lareint a -> 
      occurence_args k kind a
  | Lif (t, bt, bf) ->
      let kind = occurence k kind t in
      kind && occurence k kind bt && occurence k kind bf
  | Lfix(_,(ids,ltypes,lbodies)) 
  | Lcofix(_,(ids,ltypes,lbodies)) ->
      let kind = occurence_args k kind ltypes in
      let _ = occurence_args (k+Array.length ids) false lbodies in
      kind 
  | Lparray p -> occurence_args k kind p

and occurence_args k kind args = 
  Array.fold_left (occurence k) kind args
    
let occur_once lam = 
  try let _ = occurence 1 true lam in true
  with Not_found -> false
      
(* [remove_let lam] remove let expression in [lam] if the variable is *)
(* used at most once time in the body, and does not appear under      *)
(* a lambda or a fix or a cofix                                       *)
      
let rec remove_let subst lam =
  match lam with
  | Lrel(id,i) -> lam_subst_rel lam id i subst 
  | Llet(id,def,body) ->
      let def' = remove_let subst def in
      if occur_once body then remove_let (cons def' subst) body
      else 
	let body' = remove_let (lift subst) body in
	if def == def' && body == body' then lam else Llet(id,def',body')
  | _ -> map_lam_with_binders liftn remove_let subst lam


(*s Translation from [constr] to [lambda] *)

(* Translation of constructor *)

let is_value lc =
  match lc with
  | Lint _ | Lval _ -> true
  | Lmakeblock(_,_,_,args) when Array.length args = 0 -> true
  | _ -> false
	
let get_value lc =
  match lc with
  | Lint i -> Nativevalues.mk_uint i
  | Lval v -> v
  | Lmakeblock(_,_,tag,args) when Array.length args = 0 -> 
      Nativevalues.mk_int tag
  | _ -> raise Not_found
	
let make_args start _end =
  Array.init (start - _end + 1) (fun i -> Lrel (Anonymous, start - i))
    
(* Translation of constructors *)	

let makeblock env cn tag args =
  if array_for_all is_value args && Array.length args > 0 then
    let args = Array.map get_value args in
    Lval (Nativevalues.mk_block tag args)
  else
    let prefix = get_mind_prefix env (fst (fst cn)) in
    Lmakeblock(prefix, cn, tag, args)

let makearray args =   
  try
    let p = Array.map get_value args in
    Lval (Nativevalues.parray_of_array p) 
  with Not_found -> Lparray args

(* Translation of constants *)

let rec get_allias env kn =
  let tps = (lookup_constant kn env).const_body_code in
  match Cemitcodes.force tps with
  |  Cemitcodes.BCallias kn' -> get_allias env kn'
  | _ -> kn

(* Translation of iterators *)

let isle l1 l2 = Lprim(None, Native.Int63le, [|l1;l2|])
let islt l1 l2 = Lprim(None, Native.Int63lt, [|l1;l2|])
let areint l1 l2 = Lareint [|l1; l2|]
let isint l = Lareint [|l|]
let add63 l1 l2 =Lprim(None, Native.Int63add, [|l1;l2|]) 
let sub63 l1 l2 =Lprim(None, Native.Int63sub, [|l1;l2|]) 
let one63 = Lint (Uint63.of_int 1)

let _f = Name(id_of_string "f")
let _min = Name (id_of_string "min") 
let _max = Name (id_of_string "max") 
let _cont = Name (id_of_string "cont")
let _aux = Name (id_of_string "aux") 
let _i = Name (id_of_string "i") 
let _i' = Name (id_of_string "i'")
let _a = Name (id_of_string "a")

let mkLrel id i = Lrel(id,i) 

let r_f = mkLrel _f
let r_min = mkLrel _min
let r_max = mkLrel _max
let r_cont = mkLrel _cont
let r_aux = mkLrel _aux
let r_i = mkLrel _i
let r_i' = mkLrel _i'
let r_a = mkLrel _a

let lambda_of_iterator env kn op args =
  match op with
  | Native.Int63foldi ->
      (* args = [|A;B;f;min;max;cont;extra|] *)
      (* 
         if min <= max then
           (rec aux i a =
              if i < max then f i (aux (i+1)) a
              else f i cont a) 
            min
         else
 	   (fun a => cont a)
       *)
      
      let extra =
	if Array.length args > 6 then
	  Array.sub args 6 (Array.length args - 6)
	else [||] in
      let prefix = get_const_prefix env kn in
      let extra4 = Array.map (lam_lift 4) extra in
      Llet(_cont, args.(5),
      Llet(_max, lam_lift 1 args.(4),
      Llet(_min, lam_lift 2 args.(3),
      Llet(_f, lam_lift 3 args.(2),
      (* f->#1;min->#2;max->#3;cont->#4 *)
      Lif(areint (r_min 2) (r_max 3), (*then*)
  	  Lif(isle (r_min 2) (r_max 3), (*then*)
	      Lapp(Lrec(_aux,
			Llam([|_i;_a|],
			     Lif(islt (r_i 2) (r_max 6),
				 Lapp(r_f 4,
				      [| r_i 2;
					 Llam([|_a|],
					      Lapp(r_aux 4,
						   [| add63 (r_i 3) one63; 
						      r_a 1|]));
					 r_a 1|]),
				 Lapp(r_f 4, [|r_i 2; r_cont 7; r_a 1|])))),
		   Array.append [|r_min 2|] extra4),
	      mkLapp 
		(Llam([|_a|],Lapp(r_cont 5,[|r_a 1|])))
		extra4),
	  Lapp(Lconst (prefix, kn),
	       Array.append
		 [|lam_lift 4 args.(0); lam_lift 4 args.(1);
		   r_f 1; r_min 2; r_max 3; r_cont 4|]
		 extra4))))))
	
   | Native.Int63foldi_down -> 
       (* args = [|A;B;f;max;min;cont;extra|] *)
      (* 
         if min <= max then
           (rec aux i a =
              if min < i then f i (aux (i-1)) a
              else f i cont a) 
            max
         else
 	   (fun a => cont a)
       *)
      
      let extra =
	if Array.length args > 6 then
	  Array.sub args 6 (Array.length args - 6)
	else [||] in
      let prefix = get_const_prefix env kn in
      let extra4 = Array.map (lam_lift 4) extra in
      Llet(_cont, args.(5),
      Llet(_max, lam_lift 1 args.(3),
      Llet(_min, lam_lift 2 args.(4),
      Llet(_f, lam_lift 3 args.(2),
      (* f->#1;min->#2;max->#3;cont->#4 *)
      Lif(areint (r_min 2) (r_max 3), (*then*)
  	  Lif(isle (r_min 2) (r_max 3), (*then*)
	      Lapp(Lrec(_aux,
			Llam([|_i;_a|],
			     Lif(islt (r_min 5) (r_i 2),
				 Lapp(r_f 4,
				      [| r_i 2;
					 Llam([|_a|],
					      Lapp(r_aux 4,
						   [| sub63 (r_i 3) one63;
						      r_a 1|]));
					 r_a 1|]),
				 Lapp(r_f 4, [|r_i 2; r_cont 7; r_a 1|])))),
		   Array.append [|r_max 3|] extra4),
	      mkLapp 
		(Llam([|_a|],Lapp(r_cont 5,[|r_a 1|])))
		extra4),
	  Lapp(Lconst (prefix, kn),
	       Array.append
		 [|lam_lift 4 args.(0); lam_lift 4 args.(1);
		   r_f 1; r_max 3; r_min 2; r_cont 4|]
		 extra4))))))

(* Compilation of primitive *)
let _h =  Name(id_of_string "f")

let prim env kn op args =
  match op with
  | Native.Oprim Native.Int63eqb_correct ->
      let prefix = get_const_prefix env kn in
      let h = Lrel(_h,1) in
      Llet(_h,args.(2),
	Lif(isint h,
            Lint (Uint63.of_int 0) (* constructor eq_refl *),
	    Lapp(Lconst (prefix,kn), [|lam_lift 1 args.(0);lam_lift 1 args.(1);h|])))
  | Native.Oprim p      ->
      let prefix = get_const_prefix env kn in
      Lprim(Some (prefix, kn), p, args)
  | Native.Ocaml_prim p ->
      let prefix = get_const_prefix env kn in
      Lcprim(prefix, kn, p, args)
  | Native.Oiterator p  -> lambda_of_iterator env kn p args

let expand_prim env kn op arity =
  let ids = Array.make arity Anonymous in
  let args = make_args arity 1 in
  Llam(ids, prim env kn op args)

let lambda_of_prim env kn op args = 
  let (nparams, arity) = Native.arity op in
  let expected = nparams + arity in
  if Array.length args >= expected then prim env kn op args
  else mkLapp (expand_prim env kn op expected) args


(*i Global environment *)

let global_env = ref empty_env 

let set_global_env env = global_env := env

let get_names decl = 
  let decl = Array.of_list decl in
  Array.map fst decl

(* Rel Environment *)
module Vect = 
  struct
    type 'a t = {
	mutable elems : 'a array;
	mutable size : int;
      }

    let make n a = {
      elems = Array.make n a;
      size = 0;
    }

    let length v = v.size

    let extend v =
      if v.size = Array.length v.elems then 
	let new_size = min (2*v.size) Sys.max_array_length in
	if new_size <= v.size then raise (Invalid_argument "Vect.extend");
	let new_elems = Array.make new_size v.elems.(0) in
	Array.blit v.elems 0 new_elems 0 (v.size);
	v.elems <- new_elems

    let push v a = 
      extend v;
      v.elems.(v.size) <- a;
      v.size <- v.size + 1

    let push_pos v a =
      let pos = v.size in
      push v a;
      pos

    let popn v n =
      v.size <- max 0 (v.size - n)

    let pop v = popn v 1
	
    let get v n =
      if v.size <= n then raise 
	  (Invalid_argument "Vect.get:index out of bounds");
      v.elems.(n)

    let get_last v n =
      if v.size <= n then raise 
	  (Invalid_argument "Vect.get:index out of bounds");
      v.elems.(v.size - n - 1)


    let last v =
      if v.size = 0 then raise
	  (Invalid_argument "Vect.last:index out of bounds");
      v.elems.(v.size - 1)

    let clear v = v.size <- 0

    let to_array v = Array.sub v.elems 0 v.size
      
  end

let empty_args = [||]

module Renv = 
  struct

    type constructor_info = tag * int * int (* nparam nrealargs *)

    type t = {
	name_rel : name Vect.t;
	construct_tbl : (constructor, constructor_info) Hashtbl.t;

       }


    let make () = {
      name_rel = Vect.make 16 Anonymous;
      construct_tbl = Hashtbl.create 111
    }

    let push_rel env id = Vect.push env.name_rel id

    let push_rels env ids = 
      Array.iter (push_rel env) ids

    let pop env = Vect.pop env.name_rel
	    
    let popn env n =
      for i = 1 to n do pop env done

    let get env n =
      Lrel (Vect.get_last env.name_rel (n-1), n)

    let get_construct_info env c =
      try Hashtbl.find env.construct_tbl c 
      with Not_found -> 
	let ((mind,j), i) = c in
	let oib = lookup_mind mind !global_env in
	let oip = oib.mind_packets.(j) in
	let tag,arity = oip.mind_reloc_tbl.(i-1) in
	let nparams = oib.mind_nparams in
	let r = (tag, nparams, arity) in
	Hashtbl.add env.construct_tbl c r;
	r
  end

let is_lazy t = (* APPROXIMATION *)
  isApp t || isLetIn t

let empty_ids = [||]

let rec lambda_of_constr env c =
(*  try *)
  match kind_of_term c with
  | Meta _ -> raise (Invalid_argument "Nativelambda.lambda_of_constr: Meta")
  | Evar _ -> raise (Invalid_argument "Nativelambda.lambda_of_constr : Evar")
	
  | Cast (c, _, _) -> lambda_of_constr env c
	
  | Rel i -> Renv.get env i
	
  | Var id -> Lvar id

  | Sort s -> Lsort s
  | Ind ind ->
      let prefix = get_mind_prefix !global_env (fst ind) in
      Lind (prefix, ind)
	
  | Prod(id, dom, codom) ->
      let ld = lambda_of_constr env dom in
      Renv.push_rel env id;
      let lc = lambda_of_constr env codom in
      Renv.pop env;
      Lprod(ld,  Llam([|id|], lc))

  | Lambda _ ->
      let params, body = decompose_lam c in
      let ids = get_names (List.rev params) in
      Renv.push_rels env ids;
      let lb = lambda_of_constr env body in
      Renv.popn env (Array.length ids);
      mkLlam ids lb

  | LetIn(id, def, _, body) ->
      let ld = lambda_of_constr env def in
      Renv.push_rel env id;
      let lb = lambda_of_constr env body in
      Renv.pop env;
      Llet(id, ld, lb)

  | App(f, args) -> lambda_of_app env f args

  | Const _ -> lambda_of_app env c empty_args

  | Construct _ ->  lambda_of_app env c empty_args

  | Case(ci,t,a,branches) ->  
      let (mind,i as ind) = ci.ci_ind in
      let mib = lookup_mind mind !global_env in
      let oib = mib.mind_packets.(i) in
      let tbl = oib.mind_reloc_tbl in 
      (* Building info *)
      let prefix = get_mind_prefix !global_env mind in
      let annot_sw = 
	    { asw_ind = ind;
          asw_ci = ci;
          asw_reloc = tbl; 
          asw_finite = mib.mind_finite;
          asw_prefix = prefix}
      in
      (* translation of the argument *)
      let la = lambda_of_constr env a in
      (* translation of the type *)
      let lt = lambda_of_constr env t in
      (* translation of branches *)
      let mk_branch i b =
	let cn = (ind,i+1) in
	let _, arity = tbl.(i) in
	let b = lambda_of_constr env b in
	if arity = 0 then (cn, empty_ids, b)
	else 
	  match b with
	  | Llam(ids, body) when Array.length ids = arity -> (cn, ids, body)
	  | _ -> 
	      let ids = Array.make arity Anonymous in
	      let args = make_args arity 1 in
	      let ll = lam_lift arity b in
	      (cn, ids, mkLapp  ll args) in
      let bs = Array.mapi mk_branch branches in
      Lcase(annot_sw, lt, la, bs)
	
  | Fix(rec_init,(names,type_bodies,rec_bodies)) ->
      let ltypes = lambda_of_args env 0 type_bodies in
      Renv.push_rels env names;
      let lbodies = lambda_of_args env 0 rec_bodies in
      Renv.popn env (Array.length names);
      Lfix(rec_init, (names, ltypes, lbodies))
	
  | CoFix(init,(names,type_bodies,rec_bodies)) ->
      let ltypes = lambda_of_args env 0 type_bodies in 
      Renv.push_rels env names;
      let lbodies = lambda_of_args env 0 rec_bodies in
      Renv.popn env (Array.length names);
      Lcofix(init, (names, ltypes, lbodies))
  | NativeInt i -> Lint i
  | NativeArr(_,p) -> makearray (lambda_of_args env 0 p)


and lambda_of_app env f args =
  match kind_of_term f with
  | Const kn ->
      let kn = get_allias !global_env kn in
      let cb = lookup_constant kn !global_env in
      begin match cb.const_body with
      | Primitive op -> lambda_of_prim !global_env kn op (lambda_of_args env 0 args)
      | Def csubst ->
          if cb.const_inline_code then lambda_of_app env (force csubst) args
          else
          let prefix = get_const_prefix !global_env kn in
          let t =
            if is_lazy (force csubst) then mkLapp Lforce [|Lconst (prefix, kn)|]
            else Lconst (prefix, kn)
          in
        mkLapp t (lambda_of_args env 0 args)
      | OpaqueDef _ | Undef _ ->
          let prefix = get_const_prefix !global_env kn in
          mkLapp (Lconst (prefix, kn)) (lambda_of_args env 0 args)
      end
  | Construct c ->
      let tag, nparams, arity = Renv.get_construct_info env c in
      let expected = nparams + arity in
      let nargs = Array.length args in
      if nargs = expected then 
	let args = lambda_of_args env nparams args in
	makeblock !global_env c tag args
      else
        let prefix = get_mind_prefix !global_env (fst (fst c)) in
        mkLapp (Lconstruct (prefix, c)) (lambda_of_args env 0 args)
  | _ -> 
      let f = lambda_of_constr env f in
      let args = lambda_of_args env 0 args in
      mkLapp f args
	
and lambda_of_args env start args =
  let nargs = Array.length args in
  if start < nargs then
    Array.init (nargs - start) 
      (fun i -> lambda_of_constr env args.(start + i))
  else empty_args

let optimize lam =
  let lam = simplify subst_id lam in
(*  if Flags.vm_draw_opt () then 
    (msgerrnl (str "Simplify = \n" ++ pp_lam lam);flush_all()); 
  let lam = remove_let subst_id lam in
  if Flags.vm_draw_opt () then 
    (msgerrnl (str "Remove let = \n" ++ pp_lam lam);flush_all()); *)
  lam

let lambda_of_constr env c =
  set_global_env env;
  let env = Renv.make () in
  let ids = List.rev_map (fun (id, _, _) -> id) !global_env.env_rel_context in
  Renv.push_rels env (Array.of_list ids);
  let lam = lambda_of_constr env c in
(*  if Flags.vm_draw_opt () then begin
    (msgerrnl (str "Constr = \n" ++ pr_constr c);flush_all()); 
    (msgerrnl (str "Lambda = \n" ++ pp_lam lam);flush_all()); 
  end; *)
  optimize lam

let mk_lazy c =
  mkLapp Llazy [|c|]
