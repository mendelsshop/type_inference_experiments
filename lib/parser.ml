open AMPCL
open Expr

let key_words = [ "in"; "let"; "if"; "rec"; "then"; "else"; "\\" ]

let junk =
  let non_newline = sat (fun c -> c != '\n') in
  let comment_contents = many non_newline <$> implode in
  let comment =
    string "--" >>= fun comment_start ->
    comment_contents <$> fun contents -> comment_start ^ contents
  in
  let white_space = sat (function ' ' | '\n' | '\t' -> true | _ -> false) in
  let white_spaces = white_space <$> String.make 1 in
  many (white_spaces <|> comment) <$> String.concat ""

let skip_garbage f = junk >>= fun _ -> f
let ( << ) f g x = f (g x)
let ( ! ) = skip_garbage

(*TODO: comments and whitespace*)

let number_parser wrapper =
  many1 digit <$> (float_of_int << int_of_string << implode) <$> wrapper

let boolean_parser wrapper =
  let true_parser = string "true" <$> fun _ -> wrapper true in
  let false_parser = string "false" <$> fun _ -> wrapper false in
  true_parser <|> false_parser

let ident =
  let idents = many alphanum in
  let flatten (f, rest) = f :: rest in
  seq letter idents <$> flatten <$> implode
  |> check (fun x -> not (List.mem x key_words))

let ident_parser wrapper = ident <$> wrapper

let parens_parser expr =
  char '(' >>= fun _ ->
  expr >>= fun expr ->
  !(char ')') <$> fun _ -> expr

let tuple expr wrapper =
  let rec tuple input =
    ( expr >>= fun e1 ->
      !(char ',') >>= (fun _ -> tuple) |> opt <$> function
      | Some e2 -> wrapper e1 e2
      | None -> e1 )
      input
  in
  tuple

(*|> many*)
(*List.fold*)
(*<$> ( List.fold_left wrapper e1)*)
(*function*)
(*| [] -> e1*)
(*| tuples -> wrapper (e1, e2)*)
let record wrapper ident_wrapper expr =
  (let ( << ) = keep_right in
   let record =
     seq !ident (opt (!(char '=') << expr)) <$> function
     | name, None -> (name, ident_wrapper name)
     | name, Some value -> (name, value)
   in
   let record_mid = record >> !(char ';') in
   !(char '{')
   << (many1 record_mid
      >> !(char '}')
      <|> (seq (many record_mid) record
          <$> (fun (rs, r) -> rs @ [ r ])
          >> !(char '}'))))
  <$> Row.of_list <$> wrapper

let rec pattern input =
  let basic_forms =
    choice
      [
        parens_parser pattern;
        (char '_' <$> fun _ -> PWildcard);
        ident_parser (fun i -> PVar i);
        number_parser (fun n -> PNumber n);
        boolean_parser (fun b -> PBoolean b);
        record (fun r -> PRecord r) (fun i -> PVar i) pattern;
      ]
  in
  tuple !basic_forms (fun t1 t2 -> PTuple (t1, t2)) input

let lambda_parser expr =
  char '\\' >>= fun _ ->
  !pattern >>= fun ident ->
  !(char '.') >>= fun _ ->
  expr <$> fun expr -> Lambda (ident, expr)

let if_parser expr =
  string "if" >>= fun _ ->
  expr >>= fun cond ->
  !(string "then") >>= fun _ ->
  expr >>= fun cons ->
  !(string "else") >>= fun _ ->
  expr <$> fun alt -> If (cond, cons, alt)

let let_parser expr =
  string "let" >>= fun _ ->
  !pattern >>= fun ident ->
  !(char '=') >>= fun _ ->
  expr >>= fun e1 ->
  !(string "in") >>= fun _ ->
  expr <$> fun e2 -> 
  Let (ident, e1, e2)

let record_acces_parser expr =
  expr >>= fun record ->
  many (char '.' >>= fun _ -> ident) <$> fun acceses ->
  List.fold_left
    (fun record field -> RecordAcces (record, field))
    record acceses

let rec expr_inner input =
  let basic_forms =
    !(choice
        [
          parens_parser (expr_inner <|> !(let_parser expr_inner));
          boolean_parser (fun b -> Boolean b);
          number_parser (fun n -> Number n);
          ident_parser (fun i -> Var i);
          record (fun r -> Record r) (fun i -> Var i) expr_inner;
          lambda_parser expr_inner;
          if_parser expr_inner;
        ])
  in
  let basic_forms =
    tuple (record_acces_parser basic_forms) (fun t1 t2 -> Tuple (t1, t2))
  in
  let rec application_parser input =
    ( basic_forms >>= fun abs ->
      application_parser <$> (fun arg -> Application (abs, arg)) <|> return abs
    )
      input
  in
  application_parser input

let rec expr input = (expr_inner <|> !(let_parser expr)) input

let let_parser =
  string "let" >>= fun _ ->
  !pattern >>= fun ident ->
  !(char '=') >>= fun _ ->
  expr >>= fun e1 -> Bind (ident, e1) |> return

let top_level = expr <$> (fun e -> Expr e) <|> !let_parser

let parse =
  many top_level >>= fun tl ->
  junk <$> fun _ -> tl

let run = run
