(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)
type caml_prim =
  (* Int31 operations *)
  | Int31print
  (* Array operations *)
  | ArrayMake
  | ArrayGet
  | ArrayGetdefault
  | ArraySet
  | ArrayCopy
  | ArrayReroot
  | ArrayLength
  | ArrayInit
  | ArrayMap
  (* Resource Operations *)
  | ResourceMake
  | ResourceGetc
  | ResourceGeti32

type iterator =
  | Int31foldi
  | Int31foldi_down
 
type prim_op = 
  | Int31head0
  | Int31tail0

  | Int31add
  | Int31sub
  | Int31mul
  | Int31div
  | Int31mod
  | Int31lsr
  | Int31lsl
  | Int31land
  | Int31lor
  | Int31lxor

  | Int31addc
  | Int31subc
  | Int31addCarryC
  | Int31subCarryC

  | Int31mulc
  | Int31diveucl
  | Int31div21

  | Int31addMulDiv

  | Int31eq
  | Int31lt
  | Int31le

  | Int31compare
  | Int31eqb_correct

type op =
  | Oprim of prim_op
  | Ocaml_prim of caml_prim
  | Oiterator of iterator


val prim_to_string : prim_op -> string
val caml_prim_to_string : caml_prim -> string
val to_string : op -> string

type arg_kind =
  | Kparam (* not needed for the elavuation of the primitive*)
  | Kwhnf  (* need to be reduced in whnf before reducing the primitive *)
  | Karg   (* no need to be reduced in whnf *)

type args_red = arg_kind list

val op_kind : op -> args_red

val caml_prim_arity : caml_prim -> int * int
val arity : op -> int * int (* number of parameters, number of arguments *)

val max_array_length32 : int

module type PARRAY = 
  sig 
    type 'a t
    val length  : 'a t -> Uint63.t
    val get     : 'a t -> Uint63.t -> 'a
    val set     : 'a t -> Uint63.t -> 'a -> 'a t
    val default : 'a t -> 'a 
    val make    : Uint63.t -> 'a -> 'a t
    val init    : Uint63.t -> (int -> 'a) -> 'a -> 'a t
    val copy    : 'a t -> 'a t
    val reroot  : 'a t -> 'a t

    val map : ('a -> 'b) -> 'a t -> 'b t

    (* /!\ Unsafe function *)
    val of_array : 'a array -> 'a t

  end


(* Implementation using array. Warning, the set operation copies array *)
module Narray : PARRAY with type 'a t = 'a array


(** Special Entries for Register **)

type prim_ind =
  | PIT_bool
  | PIT_carry
  | PIT_pair
  | PIT_cmp
  | PIT_eq

type prim_type =
  | PT_int31
  | PT_array
  | PT_resource

type retro_action =
  | Retro_ind of prim_ind
  | Retro_type of prim_type
  | Retro_inline 

type op_or_type = 
  | OT_op of op
  | OT_type of prim_type


val op_or_type_to_string : op_or_type -> string
val prim_ind_to_string : prim_ind -> string
