open Core
open Fastrest
open Coinbasepro

let base_url =
  Uri.make ~scheme:"https" ~host:"api.pro.coinbase.com" ()

let sandbox_url =
  Uri.make ~scheme:"https" ~host:"api-public.sandbox.pro.coinbase.com" ()

type order = {
  price : float ;
  size : float ;
  order_id : Uuidm.t ;
} [@@deriving sexp]

let order_encoding =
  let open Json_encoding in
  conv
    (fun { price ; size ; order_id } -> price, size, order_id)
    (fun (price, size, order_id) -> { price ; size ; order_id })
    (tup3 strfloat strfloat Uuidm.encoding)

type book = {
  sequence : int64 ;
  bids : order list ;
  asks : order list ;
} [@@deriving sexp]

(* let int64str =
 *   Json_encoding.(conv Int64.to_string Int64.of_string string) *)

let book_encoding =
  let open Json_encoding in
  conv
    (fun { sequence ; bids ; asks } -> (sequence, bids, asks))
    (fun (sequence, bids, asks) -> { sequence ; bids ; asks })
    (obj3
       (req "sequence" int53)
       (req "bids" (list order_encoding))
       (req "asks" (list order_encoding)))

let result_encoding encoding =
  let open Json_encoding in
  union [
    case
      (obj1 (req "message" string))
      (function Ok _ -> None | Error msg -> Some msg)
      (fun msg -> Error msg) ;
    case encoding
      (function Ok v -> Some v | _ -> None)
      (fun v -> Ok v) ;
  ]

let book ?(sandbox=false) symbol =
  let url = if sandbox then sandbox_url else base_url in
  get (result_encoding book_encoding)
    (Uri.with_query'
       (Uri.with_path url ("products/" ^ symbol ^ "/book"))
       ["level", "3"])

type account = {
  id : Uuidm.t ;
  currency : string ;
  balance : float ;
  available : float ;
  hold : float ;
  profile_id : Uuidm.t ;
} [@@deriving sexp]

let account_encoding =
  let open Json_encoding in
  conv
    (fun { id ; currency ; balance ; available ; hold ; profile_id } ->
       (id, currency, balance, available, hold, profile_id))
    (fun (id, currency, balance, available, hold, profile_id) ->
       { id ; currency ; balance ; available ; hold ; profile_id })
    (obj6
       (req "id" Uuidm.encoding)
       (req "currency" string)
       (req "balance" strfloat)
       (req "available" strfloat)
       (req "hold" strfloat)
       (req "profile_id" Uuidm.encoding))

let auth (type a) (srv : (a, _, _) service) { key ; secret ; meta } =
  let ts =
    Float.to_string @@
    Time_ns.(Span.to_int_ms (to_span_since_epoch (now ())) // 1000) in
  let meth = match srv.meth with
    | Get -> "GET"
    | _ -> "POST" in
  let path = Uri.path srv.url in
  let body = match body_hdrs_of_service srv with
    | None -> ""
    | Some (_, body) -> body in
  let prehash = ts ^ meth ^ path ^ body in
  let passphrase =
    List.Assoc.find_exn meta "passphrase" ~equal:String.equal in
  let sign = Base64.encode_exn
      Digestif.SHA256.(hmac_string ~key:secret prehash |> to_raw_string) in
  let headers = Httpaf.Headers.of_list [
      "CB-ACCESS-KEY", key ;
      "CB-ACCESS-SIGN", sign ;
      "CB-ACCESS-TIMESTAMP", ts ;
      "CB-ACCESS-PASSPHRASE", passphrase ;
    ] in
  { params = [] ; headers }

let accounts ?(sandbox=false) () =
  let url = if sandbox then sandbox_url else base_url in
  get ~auth
    (result_encoding (Json_encoding.list account_encoding))
    (Uri.with_path url "accounts")
