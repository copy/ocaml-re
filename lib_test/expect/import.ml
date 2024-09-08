module Re = Re_private.Re
include Re_private.Import
module Fmt = Re_private.Fmt

let printf = Printf.printf

let t re s =
  let group = Re.exec_opt (Re.compile re) s in
  Format.printf "%a@." (Fmt.opt Re.Group.pp) group
;;

let re_whitespace = Re.Pcre.regexp "[\t ]+"
let re_eol = Re.compile Re.eol
let re_bow = Re.compile Re.bow
let re_eow = Re.compile Re.eow
let strings = Format.printf "[%a]@." Fmt.(list ~pp_sep:(Fmt.lit "; ") Fmt.quoted_string)
let re_empty = Re.Posix.compile_pat ""

let invalid_argument f =
  match f () with
  | s -> ignore s
  | exception Invalid_argument s -> Format.printf "Invalid_argument %S@." s
;;

let exec_partial_detailed ?pos re s =
  let re = Re.compile re in
  let res = Re.exec_partial_detailed ?pos re s in
  match res with
  | `Mismatch -> Format.printf "`Mismatch@."
  | `Partial position -> Format.printf "`Partial %d@." position
  | `Full groups ->
    Re.Group.all_offset groups
    |> Array.to_list
    |> List.map ~f:(fun (a, b) -> Printf.sprintf "%d,%d" a b)
    |> String.concat ";"
    |> Format.printf "`Full [|%s|]@."
;;
