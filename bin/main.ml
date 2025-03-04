open Ml
open Expr
open Parser
open Infer

let read_to_string file = open_in file |> Stdio.In_channel.input_all

let () =
  let args = Array.to_list Sys.argv in
  let file =
    match List.nth_opt args 1 with
    | Some file -> file
    | None ->
        print_endline "usage strings [file]";
        exit 1
  in
  let input = read_to_string file in
  let parsed = Ml.Parser.run parse input in
  Result.fold ~error:Fun.id
    ~ok:(fun exprs ->
      List.map program_to_string exprs |> String.concat "\n" |> print_endline;
      infer [] exprs
      |> Result.fold ~error:Fun.id ~ok:(fun exprs' ->
             List.map tprogram_to_string exprs' |> String.concat "\n"))
    parsed
  |> print_endline
