(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2010     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Pp
open Names

(** false iff the module is an element of an open module type *)
val printable_body : dir_path -> bool

val print_module : bool -> module_path -> std_ppcmds

val print_modtype : module_path -> std_ppcmds
