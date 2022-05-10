let read_lexbuf
    ?annot_schema
    ?(expand = false) ?keep_poly ?(xdebug = false)
    ?(inherit_fields = false)
    ?(inherit_variants = false)
    ?(pos_fname = "")
    ?(pos_lnum = 1)
    lexbuf =

  Lexer.init_fname lexbuf pos_fname pos_lnum;
  let head, body = Parser.full_module Lexer.token lexbuf in
  Check.check body;
  let body =
    if inherit_fields || inherit_variants then
      Inherit.expand_module_body ~inherit_fields ~inherit_variants body
    else
      body
  in
  let imports, (type_defs, original_types) =
    if expand then
      Ast.map_type_defs body
        (Expand.expand_type_defs ?keep_poly ~debug: xdebug)
    else
      Ast.map_type_defs body (fun type_defs -> (type_defs, Hashtbl.create 0))
  in
  let body =
    imports @ List.map (fun td -> Ast.Type td) type_defs
  in
  let full_module = (head, body) in
  (match annot_schema with
   | None -> ()
   | Some schema ->
       Annot.validate schema (Ast.Full_module full_module)
  );
  (full_module, original_types)

let read_channel
    ?annot_schema ?expand ?keep_poly ?xdebug ?inherit_fields ?inherit_variants
    ?pos_fname ?pos_lnum
    ic =
  let lexbuf = Lexing.from_channel ic in
  let pos_fname =
    if pos_fname = None && ic == stdin then
      Some "<stdin>"
    else
      pos_fname
  in
  read_lexbuf ?annot_schema ?expand ?keep_poly ?xdebug
    ?inherit_fields ?inherit_variants ?pos_fname ?pos_lnum lexbuf

let load_file
    ?annot_schema ?expand ?keep_poly ?xdebug ?inherit_fields ?inherit_variants
    ?pos_fname ?pos_lnum
    file =
  let ic = open_in file in
  let finally () = close_in_noerr ic in
  try
    let pos_fname =
      match pos_fname with
          None -> Some file
        | Some _ -> pos_fname
    in
    let ast =
      read_channel
        ?annot_schema ?expand ?keep_poly ?xdebug ?inherit_fields
        ?inherit_variants ?pos_fname ?pos_lnum ic
    in
    finally ();
    ast
  with e ->
    finally ();
    raise e

let load_string
    ?annot_schema ?expand ?keep_poly ?xdebug ?inherit_fields ?inherit_variants
    ?pos_fname ?pos_lnum
    s =
  let lexbuf = Lexing.from_string s in
  read_lexbuf ?annot_schema ?expand ?keep_poly ?xdebug
    ?inherit_fields ?inherit_variants ?pos_fname ?pos_lnum lexbuf

module Tsort = Sort.Make (
  struct
    type t = Ast.type_def
    type id = string (* type name *)
    let id (_, (name, _, _), _) = name
    let to_string name = name
  end
)

let tsort type_defs0 =
  let ignorable = [ "unit"; "bool"; "int"; "float"; "string"; "abstract" ] in
  let type_defs =
    List.map (fun ((_, (_, _, _), x) as def) ->
      let deps = Ast.extract_type_names ~ignorable x in
      (def, deps)
    ) type_defs0
  in
  List.rev (Tsort.sort type_defs)
