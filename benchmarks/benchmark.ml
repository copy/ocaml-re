open Core
open Core_bench

module Http = struct
  open Re

  let space = rep blank
  let crlf = str "\r\n"
  let token = rep1 @@ compl [ rg '\000' '\031'; set "\127)(<>@,;:\\/[]?={}" ]
  let meth = token

  let version =
    let digits = rep1 digit in
    let decimal = seq [ digits; opt (seq [ char '.'; digits ]) ] in
    seq [ str "HTTP/"; decimal ]
  ;;

  let uri = rep1 (compl [ char '\n' ])
  let request_line = [ space; group meth; space; group uri; group version; space ] |> seq

  let header =
    let key = group (rep1 (Re.compl [ char ':' ])) in
    let value = group (rep1 (Re.compl [ char '\n' ])) in
    seq [ space; key; space; char ':'; space; value; space; crlf ]
  ;;

  let request' = seq [ request_line; crlf; rep header; crlf ]

  module Export = struct
    let request = request'
    let request_g = request' |> no_group
    let requests = request' |> rep1
    let requests_g = request' |> no_group |> rep1
  end
end

let http_requests = Stdio.In_channel.read_all "benchmarks/http-requests.txt"
let str_20_zeroes = String.make 20 '0'
let re_20_zeroes = Re.(str str_20_zeroes)

let lots_of_a's =
  String.init 101 ~f:(function
    | 100 -> 'b'
    | _ -> 'a')
;;

let lots_o_a's_re = Re.(seq [ char 'a'; opt (char 'a'); char 'b' ])

let media_type_re =
  let re = Re.Emacs.re ~case:true "[ \t]*\\([^ \t;]+\\)" in
  Re.(seq [ start; re ])
;;

(* Taken from https://github.com/rgrinberg/ocaml-uri/blob/903ef1010f9808d6f3f6d9c1fe4b4eabbd76082d/lib/uri.ml*)
let uri_reference =
  Re.Posix.re "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
;;

let uris =
  [ "https://google.com"
  ; "http://yahoo.com/xxx/yyy?query=param&one=two"
  ; "file:/random_crap"
  ]
;;

let benchmarks =
  [ "20 zeroes", re_20_zeroes, [ str_20_zeroes ]
  ; "lots of a's", lots_o_a's_re, [ lots_of_a's ]
  ; "media type match", media_type_re, [ " foo/bar ; charset=UTF-8" ]
  ; "uri", uri_reference, uris
  ]
;;

let exec_bench exec name (re : Re.t) cases =
  Bench.Test.create_group
    ~name
    (List.map cases ~f:(fun data ->
       let name =
         let len = String.length data in
         if len > 40
         then Printf.sprintf "%s .. (%d)" (String.sub data ~pos:0 ~len:10) len
         else data
       in
       let re = Re.compile re in
       Bench.Test.create ~name (fun () -> ignore (exec re data))))
;;

let exec_bench_many exec name re cases =
  let re = Re.compile re in
  Bench.Test.create ~name (fun () -> List.iter cases ~f:(fun x -> ignore (exec re x)))
;;

let rec read_all_http pos re reqs =
  if pos >= String.length reqs
  then ()
  else (
    let g = Re.exec ~pos re reqs in
    let _, pos = Re.Group.offset g 0 in
    read_all_http (pos + 1) re reqs)
;;

let rec drain_gen gen =
  match gen () with
  | Seq.Nil -> ()
  | Cons (_, tail) -> drain_gen tail
;;

let string_traversal =
  let open Bench in
  let len = 1000 * 1000 in
  let s = String.make len 'a' in
  let re = Re.Pcre.regexp "aaaaaaaaaaaaaaaaz" in
  Test.create ~name:"string traversal from #210" (fun () -> ignore (Re.execp re s ~pos:0))
;;

let compile_clean_star =
  let c = 'c' in
  let s = String.make 10_000 c in
  let re = Re.rep (Re.char 'c') in
  let re = Re.compile re in
  Bench.Test.create ~name:"kleene star compilation" (fun () -> ignore (Re.execp re s))
;;

let benchmarks =
  let benches =
    List.map benchmarks ~f:(fun (name, re, cases) ->
      Bench.Test.create_group
        ~name
        [ exec_bench Re.exec "exec" re cases
        ; exec_bench Re.execp "execp" re cases
        ; exec_bench Re.exec_opt "exec_opt" re cases
        ])
  in
  let http_benches =
    let open Bench in
    let open Http.Export in
    let manual =
      [ request, "no group"; request_g, "group" ]
      |> List.map ~f:(fun (re, name) ->
        let re = Re.compile re in
        Test.create ~name (fun () -> read_all_http 0 re http_requests))
      |> Test.create_group ~name:"manual"
    in
    let many =
      let requests = Re.compile requests in
      let requests_g = Re.compile requests_g in
      [ Test.create ~name:"execp no group" (fun () ->
          ignore (Re.execp requests http_requests))
      ; Test.create ~name:"all_gen group" (fun () ->
          http_requests |> Re.Seq.all requests_g |> drain_gen)
      ]
      |> Test.create_group ~name:"auto"
    in
    Test.create_group ~name:"http" [ manual; many ]
  in
  benches
  @ [ [ exec_bench_many Re.execp "execp"; exec_bench_many Re.exec_opt "exec_opt" ]
      |> List.map ~f:(fun f -> f Tex.ignore_re Tex.ignore_filesnames)
      |> Bench.Test.create_group ~name:"tex gitignore"
    ]
  @ [ http_benches ]
  @ [ string_traversal ]
  @ [ compile_clean_star ]
  @ Memory.benchmarks
;;

let () =
  let benchmarks =
    match Sys.getenv "RE_BENCH_FILTER" with
    | None -> benchmarks
    | Some only ->
      let only = String.split ~on:',' only in
      let filtered =
        List.filter benchmarks ~f:(fun bench ->
          let name = Bench.Test.name bench in
          List.mem only name ~equal:String.equal)
      in
      (match filtered with
       | _ :: _ -> filtered
       | [] ->
         print_endline "No benchmarks to run. Your options are:";
         List.iter benchmarks ~f:(fun bench ->
           let name = Bench.Test.name bench in
           Printf.printf "- %s\n" name);
         exit 1)
  in
  Command_unix.run (Bench.make_command benchmarks)
;;
