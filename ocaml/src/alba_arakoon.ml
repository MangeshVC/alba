(*
Copyright (C) 2016 iNuron NV

This file is part of Open vStorage Open Source Edition (OSE), as available from


    http://www.openvstorage.org and
    http://www.openvstorage.com.

This file is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License v3 (GNU AGPLv3)
as published by the Free Software Foundation, in version 3 as it comes
in the <LICENSE.txt> file of the Open vStorage OSE distribution.

Open vStorage is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY of any kind.
*)

open Prelude
open Arakoon_client_config

module Config =
  struct
    type nonrec tcp_keepalive_cfg = tcp_keepalive_cfg = {
          enable_tcp_keepalive : bool;
          tcp_keepalive_time : int;
          tcp_keepalive_intvl : int;
          tcp_keepalive_probes : int;
        } [@@deriving show, yojson]

    type nonrec node_cfg = node_cfg = {
          ips : string list;
          port : int;
        } [@@deriving show, yojson]

    type ssl_protocol =
      Ssl.protocol =
      | SSLv23 (** accept all possible protocols (SSLv2 if supported by openssl,
               SSLv3, TLSv1, TLSv1.1 and TLSv1.2) *)
      | SSLv3 (** only SSL v3 protocol *)
      | TLSv1 (** only TLS v1 protocol *)
      | TLSv1_1 (** only TLS v1.1 protocol *)
      | TLSv1_2 (** only TLS v1.2 protocol *)
          [@@deriving show, yojson]

    type nonrec ssl_cfg = ssl_cfg = {
        ca_cert : string;
        creds : (string * string) option;
        protocol : ssl_protocol;
      } [@@deriving show, yojson]

    type cluster_id = string [@@deriving yojson, show]

    type nonrec t = t = {
          cluster_id : cluster_id;
          node_cfgs : (string * node_cfg) list;
          ssl_cfg : ssl_cfg option;
          tcp_keepalive : tcp_keepalive_cfg;
        } [@@deriving show, yojson]

    let node_cfg_to_buffer buf { ips; port; } =
      Llio.list_to Llio.string_to buf ips;
      Llio.int_to buf port

    let node_cfg_from_buffer buf =
      let ips = Llio.list_from Llio.string_from buf in
      let port = Llio.int_from buf in
      { ips; port; }

    let to_buffer buf { cluster_id;
                        node_cfgs;
                        ssl_cfg;
                        tcp_keepalive;
                      } =
      if ssl_cfg = None
         && tcp_keepalive = Tcp_keepalive.default_tcp_keepalive
      then
        begin
          let ser_version = 1 in
          Llio.int8_to buf ser_version;
          Llio.string_to buf cluster_id;
          Llio.list_to
            (Llio.pair_to
               Llio.string_to
               node_cfg_to_buffer)
            buf
            node_cfgs
        end
      else
        begin
          serialize
            (fun buf () ->
             let ser_version = 2 in
             Llio.int8_to buf ser_version;
             Llio.string_to buf cluster_id;

             Llio.list_to
               (Llio.pair_to
                  Llio.string_to
                  node_cfg_to_buffer)
               buf
               node_cfgs;

             let { enable_tcp_keepalive;
                   tcp_keepalive_time;
                   tcp_keepalive_intvl;
                   tcp_keepalive_probes; } = tcp_keepalive in
             Llio.bool_to buf enable_tcp_keepalive;
             Llio.int_to buf tcp_keepalive_time;
             Llio.int_to buf tcp_keepalive_intvl;
             Llio.int_to buf tcp_keepalive_probes;

             Llio.option_to
               (fun buf { ca_cert; creds; protocol; } ->
                Llio.string_to buf ca_cert;
                Llio.option_to
                  (Llio.pair_to Llio.string_to Llio.string_to)
                  buf creds;
                Llio.int8_to
                  buf
                  (match protocol with
                   | SSLv23  -> 1
                   | SSLv3   -> 2
                   | TLSv1   -> 3
                   | TLSv1_1 -> 4
                   | TLSv1_2 -> 5)
               )
               buf
               ssl_cfg)
            ()
          |> Llio.string_to buf
        end

    let from_buffer buf =
      let version = Llio.int8_from buf in
      match version with
      | 1 ->
         let cluster_id = Llio.string_from buf in
         let node_cfgs =
           Llio.list_from
             (Llio.pair_from
                Llio.string_from
                node_cfg_from_buffer)
             buf in
         { cluster_id;
           node_cfgs;
           ssl_cfg = None;
           tcp_keepalive = Tcp_keepalive.default_tcp_keepalive; }
      | 2 ->
         let buf = Llio.string_from buf in
         (* TODO this could be optimized to avoid a copy *)
         let buf = Llio.make_buffer buf 0 in

         let cluster_id = Llio.string_from buf in

         let node_cfgs =
           Llio.list_from
             (Llio.pair_from
                Llio.string_from
                node_cfg_from_buffer)
             buf in

         let enable_tcp_keepalive = Llio.bool_from buf in
         let tcp_keepalive_time = Llio.int_from buf in
         let tcp_keepalive_intvl = Llio.int_from buf in
         let tcp_keepalive_probes = Llio.int_from buf in
         let tcp_keepalive = {
             enable_tcp_keepalive;
             tcp_keepalive_time;
             tcp_keepalive_intvl;
             tcp_keepalive_probes;
           }
         in

         let ssl_cfg =
           Llio.option_from
             (fun buf ->
               let ca_cert = Llio.string_from buf in
               let creds =
                 Llio.option_from
                   (Llio.pair_from Llio.string_from Llio.string_from)
                   buf
               in
               let protocol =
                 match Llio.int8_from buf with
                 | 1 -> SSLv23
                 | 2 -> SSLv3
                 | 3 -> TLSv1
                 | 4 -> TLSv1_1
                 | 5 -> TLSv1_2
                 | k -> raise_bad_tag "Alba_arakoon.Config.ssl_cfg.protocol" k
               in
               { ca_cert; creds; protocol; })
             buf
         in

         { cluster_id;
           node_cfgs;
           ssl_cfg;
           tcp_keepalive; }
      | k ->
         raise_bad_tag "Alba_arakoon.Config.t" k

  end

let config_from_url url =
  let open Lwt.Infix in
  Arakoon_config_url.retrieve url >|= from_ini
