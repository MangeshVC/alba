(*
Copyright 2015 iNuron NV

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*)

open Prelude
open Lwt.Infix
open Cli_common
open Cmdliner


let alba_list_namespaces_by_id cfg_file tls_config to_json attempts =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
       let first = 0l
       and finc = true
       and last = None
       and max = -1 in
       client # list_namespaces_by_id ~first ~finc ~last ~max
       >>= fun ((cnt,r),more) ->
       if to_json
       then
         let r' =
           `List [`Assoc (List.map
                     (fun (id,name,_info) ->
                      (Int32.to_string id),`String name)
                     r
                  );
                  `Bool more
                 ]
         in
         Lwt_io.printl (Yojson.Safe.to_string r')
       else
         begin
           Lwt_list.iter_s
             (fun (id, name, _info ) ->
              Lwt_io.printlf "%8li:%S" id name
             ) r
           >>= fun () ->
           if more
           then Lwt_io.printl "..."
           else Lwt.return ()
         end
      )
  in
  lwt_cmd_line to_json t

let alba_list_namespaces_by_id_cmd =
  Term.(pure alba_list_namespaces_by_id
        $ alba_cfg_file
        $ tls_config
        $ to_json
        $ attempts 1
  ),
  Term.info "list-namespaces-by-id"
            ~doc:"show id to name mapping"

let recover_namespace cfg_file tls_config namespace nsm_host_id =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
         client # recover_namespace ~namespace ~nsm_host_id)
  in
  lwt_cmd_line false t

let recover_namespace_cmd =
  Term.(pure recover_namespace
        $ alba_cfg_file
        $ tls_config
        $ namespace 0
        $ nsm_host 1),
  Term.info
    "recover-namespace"
    ~doc:"recover an existing namespace from which the metadata got lost to another nsm host"

let alba_list_osds cfg_file tls_config node_id to_json attempts =

  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
         client # list_all_claimed_osds
         >>= fun (i,devices) ->

         let open Albamgr_protocol.Protocol.Osd in

         let (i',devices') =
           match node_id
           with
           | None -> (i,devices)
           | Some node_id ->
              begin
                let r =
                  List.filter
                  (fun (_,osd) ->
                   node_id = osd.node_id) devices
                in
                (List.length r, r)
              end
         in
         if to_json
         then begin
           client # get_alba_id >>= fun alba_id ->
           let res =
             List.map
               (fun (id, info) -> Alba_json.Osd.make alba_id (ClaimInfo.ThisAlba id) info)
               devices'
           in
           print_result res Alba_json.Osd.t_list_to_yojson
         end else begin
           Lwt_io.printlf "\n%i devices" i' >>= fun ()->
           Lwt_list.iter_s
             (fun (d_id,d_info) ->
                Lwt_io.printlf
                  "%li : %s" d_id
                  (show d_info)
             )
             devices'
         end)
  in
  lwt_cmd_line to_json t

let node_id default =
  let doc = "the $(docv) just for this node" in
  Arg.(value
       & opt (some string) default
       & info ["node-id"] ~docv:"NODE_ID" ~doc
      )

let alba_list_osds_cmd =
  let alba_list_osds_t =
    Term.(pure alba_list_osds
          $ alba_cfg_file
          $ tls_config
          $ node_id None
          $ to_json
          $ attempts 1
    )
  in
  let info =
    let doc = "list registered osds" in
    Term.info "list-osds" ~doc
  in
  alba_list_osds_t, info

let alba_list_all_osds cfg_file tls_config node_id to_json attempts =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
         client # list_all_osds
         >>= fun (i,devices) ->
         client # get_alba_id >>= fun alba_id ->
         let (i',devices') =
           match node_id
           with
           | None -> (i,devices)
           | Some node_id ->
              begin
                let r =
                  List.filter
                  (fun (_,osd) ->
                   let open Albamgr_protocol.Protocol.Osd in
                   node_id = osd.node_id) devices
                in
                (List.length r, r)
              end
         in
         if to_json
         then begin
           let res =
             List.map
               (fun (claim, info) -> Alba_json.Osd.make alba_id claim info)
               devices'
           in
           print_result res Alba_json.Osd.t_list_to_yojson
         end else begin
           Lwt_io.printlf "\n%i devices" i' >>= fun ()->
           Lwt_list.iter_s
             (fun (claim, d_info) ->
                let open Albamgr_protocol.Protocol in
                Lwt_io.printlf
                  "%s : %s"
                  (Osd.ClaimInfo.show claim)
                  (Osd.show d_info)
             )
             devices'
         end)
  in
  lwt_cmd_line to_json t

let alba_list_all_osds_cmd =
  let alba_list_all_osds_t =
    Term.(pure alba_list_all_osds
          $ alba_cfg_file
          $ tls_config
          $ node_id None
          $ to_json
          $ attempts 1
    )
  in
  let info =
    let doc = "list registered osds" in
    Term.info "list-all-osds" ~doc
  in
  alba_list_all_osds_t, info


let alba_list_available_osds alba_cfg_file tls_config to_json attempts =
  let t () =
    with_albamgr_client
      alba_cfg_file ~attempts tls_config
      (fun client -> client # list_available_osds) >>= fun (cnt, osds) ->
    if to_json
    then begin
      let res =
        List.map
          (fun info -> Alba_json.Osd.make "" Albamgr_protocol.Protocol.Osd.ClaimInfo.Available info)
          osds
      in
      print_result res Alba_json.Osd.t_list_to_yojson
    end else
      Lwt_log.debug_f
        "Found %i available osds: %s"
        cnt
        ([%show : Albamgr_protocol.Protocol.Osd.t list] osds)
  in
  lwt_cmd_line to_json t

let alba_list_available_osds_cmd =
  Term.(pure alba_list_available_osds
        $ alba_cfg_file
        $ tls_config
        $ to_json
        $ attempts 1
  ),
  Term.info
    "list-available-osds"
    ~doc:"list known osds still available for claiming by this alba instance"


let alba_list_nsm_hosts cfg_file tls_config to_json attempts =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
         client # list_all_nsm_hosts ()) >>= fun (cnt, nsm_hosts) ->
    if to_json
    then begin
      let res =
        List.map
          (fun (id, info, cnt) -> Alba_json.Nsm_host.make id info cnt)
          nsm_hosts
      in
      print_result res Alba_json.Nsm_host.t_list_to_yojson
    end else
      Lwt_io.printlf
        "Found %i nsm_hosts: %s"
        cnt
        ([%show: (string * Albamgr_protocol.Protocol.Nsm_host.t * int64) list]
           nsm_hosts)
  in
  lwt_cmd_line to_json t

let alba_list_nsm_hosts_cmd =
  Term.(pure alba_list_nsm_hosts
        $ alba_cfg_file
        $ tls_config
        $ to_json
        $ attempts 1),
  Term.info "list-nsm-hosts" ~doc:"list all nsm hosts"

let alba_add_nsm_host alba_cfg_file tls_config nsm_host_cfg_file to_json attempts =
  let t () =
    let open Albamgr_protocol.Protocol in
    with_albamgr_client
      alba_cfg_file ~attempts tls_config
      (fun client ->
       let cfg = Arakoon_config.from_config_file nsm_host_cfg_file in
       let nsm_host_id = fst cfg in
         client # add_nsm_host
                ~nsm_host_id
                ~nsm_host_info:Nsm_host.({ kind = (Arakoon cfg); lost = false; }))
  in
  lwt_cmd_line_unit to_json t

let alba_add_nsm_host_cmd =
  Term.(pure alba_add_nsm_host
        $ alba_cfg_file
        $ tls_config
        $ Arg.(required
               & pos 0 (some file) None
               & info [] ~docv:"CONFIG_FILE" ~doc:"config file for the nsm host")
        $ to_json
        $ attempts 1
  ),
  Term.info "add-nsm-host" ~doc:"add a nsm host"

let alba_update_nsm_host alba_cfg_file tls_config nsm_host_cfg_file lost to_json attempts =
  let t () =
    let open Albamgr_protocol.Protocol in
    with_albamgr_client
      alba_cfg_file ~attempts tls_config
      (fun client ->
       let cfg = Arakoon_config.from_config_file nsm_host_cfg_file in
       let nsm_host_id = fst cfg in
         client # update_nsm_host
                ~nsm_host_id
                ~nsm_host_info:Nsm_host.({ kind = (Arakoon cfg); lost; }))
  in
  lwt_cmd_line_unit to_json t

let alba_update_nsm_host_cmd =
  Term.(pure alba_update_nsm_host
        $ alba_cfg_file
        $ tls_config
        $ Arg.(required &
               pos 0 (some file) None &
               info [] ~docv:"CONFIG_FILE" ~doc:"config file for the nsm host")
        $ Arg.(value &
               flag &
               info ["lost"] ~doc:"optionally mark the nsm host as lost (so it will not be used for new namespaces)")
        $ to_json
        $ attempts 1
  ),
  Term.info "update-nsm-host" ~doc:"update a nsm host"

let alba_mgr_get_version cfg_file tls_config attempts =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
       client # get_version >>= fun (major,minor, patch, hash) ->
       Lwt_io.printlf "(%i, %i, %i, %S)" major minor patch hash
      )
  in
  lwt_cmd_line false t

let alba_mgr_get_version_cmd =
  Term.(pure alba_mgr_get_version
        $ alba_cfg_file
        $ tls_config
        $ attempts 1
  ),
  Term.info
    "mgr-get-version"
    ~doc:"the alba mgr's version info"

let alba_mgr_statistics cfg_file tls_config attempts clear =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
       client # statistics clear >>= fun statistics ->
       Lwt_io.printlf "%s" (Albamgr_plugin.Statistics.show statistics)
      )
  in
  lwt_cmd_line false t

let alba_mgr_statistics_cmd =
  Term.(pure alba_mgr_statistics
        $ alba_cfg_file
        $ tls_config
        $ attempts 1
        $ clear
  ),
  Term.info
    "mgr-statistics"
    ~doc:"the alba mgr's statistics"

let alba_list_decommissioning_osds
      cfg_file tls_config to_json attempts
  =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
         client # list_all_decommissioning_osds >>= fun (cnt, osds) ->
         let open Albamgr_protocol.Protocol in
         if to_json
         then
           client # get_alba_id >>= fun alba_id ->
           let res =
             List.map
               (fun (id, info) ->
                  Alba_json.Osd.make
                    alba_id
                    (Osd.ClaimInfo.ThisAlba id)
                    info)
               osds
           in
           print_result res Alba_json.Osd.t_list_to_yojson
         else
           Lwt_log.debug_f "%i osds still decommissioning: %s"
             cnt
             ([%show : (Osd.id * Osd.t) list] osds))
  in
  lwt_cmd_line to_json t

let alba_list_decommissioning_osds_cmd =
  Term.(pure alba_list_decommissioning_osds
        $ alba_cfg_file
        $ tls_config
        $ to_json
        $ attempts 1
  ),
  Term.info
    "list-decommissioning-osds"
    ~doc:"list osds that are not yet fully decommissioned"

let alba_list_participants cfg_file tls_config prefix =
  let t () =
    with_albamgr_client
      cfg_file tls_config
      ~attempts:1
      (fun client ->
       client # get_participants ~prefix >>= fun (cnt, participants) ->
       Lwt_log.debug_f
         "Found %i participants:\n%s"
         cnt
         ([%show : (string*int) list] participants))
  in
  lwt_cmd_line false t

let alba_list_participants_cmd =
  Term.(pure alba_list_participants
        $ alba_cfg_file
        $ tls_config
        $ Arg.(required
               & pos 0 (some string) None
               & info [] ~docv:"PREFIX" ~doc:"prefix")),
  Term.info
    "list-participants"
    ~doc:"list participants"


let alba_list_work cfg_file tls_config attempts =
  let t () =
    with_albamgr_client
      cfg_file ~attempts tls_config
      (fun client ->
       let first = 0l
       and finc = true
       and last = None
       and max = -1 in
       client # get_work  ~first ~finc ~last ~max ~reverse:false
       >>= fun ((cnt,r),more) ->
       begin
         Lwt_io.printlf "received %i items\n" cnt >>= fun () ->
         Lwt_io.printlf "    id   | item " >>= fun () ->
         Lwt_io.printlf "---------+------" >>= fun () ->
         Lwt_list.iter_s
           (fun (id, item) ->
            Lwt_io.printlf "%8li | %S" id ([%show : Albamgr_protocol.Protocol.Work.t] item)
           ) r
         >>= fun () ->
         if more
         then Lwt_io.printl "..."
         else Lwt.return ()
       end
      )
  in
  lwt_cmd_line false t

let alba_list_work_cmd =
  Term.(pure alba_list_work
        $ alba_cfg_file
        $ tls_config
        $ attempts 1
  ),
  Term.info
    "list-work"
    ~doc:"list outstanding work items"



let alba_add_osd cfg_file tls_config host port node_id to_json attempts =
  let node_id = match node_id with
    | None ->  failwith "A node id is needed here"
    | Some n -> n
  in
  let t () =
    Discovery.get_kind Buffer_pool.default_buffer_pool [host] port >>= function
    | None -> Lwt.fail_with "I don't think this is an OSD"
    | Some kind ->

       Remotes.Pool.Osd.factory Buffer_pool.osd_buffer_pool kind >>= fun (osd_client, closer) ->
       Lwt_log.debug_f "long_id :%S" (osd_client # get_long_id) >>= fun () ->
       let other = "other?" in
       (* TODO: we guess it's a 4TB drive for now *)
       let total = Int64.of_int (1 lsl 42) in
       let used = 0L in
       let osd_info =
         Albamgr_protocol.Protocol.Osd.({
                 kind;
                 decommissioned = false;
                 node_id;
                 other;
                 total; used;
                 seen = [ Unix.gettimeofday (); ];
                 read = [];
                 write = [];
                 errors = [];
               })
       in
       with_albamgr_client
         cfg_file ~attempts tls_config
         (fun client -> client # add_osd osd_info
         )
  in
  lwt_cmd_line false t

let alba_add_osd_cmd =
  Term.(pure alba_add_osd
        $ alba_cfg_file
        $ tls_config
        $ host $ port 8000
        $ (node_id None)
        $ to_json
        $ attempts 1
  ),
  Term.info
    "add-osd"
    ~doc:("add osd to manager so it could be claimed later." ^
            "The long id is fetched from the device." ^
              " Note: this is for development purposes only."
         )

let alba_add_iter_namespace_item cfg_file tls_config namespace name factor action =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
       client # get_namespace ~namespace >>= function
       | None -> Lwt.fail_with ""
       | Some (_, namespace_info) ->
          let open Albamgr_protocol.Protocol in
          let namespace_id = namespace_info.Namespace.id in
          client # add_work_items
                 [ Work.(IterNamespace
                           (action,
                            namespace_id,
                            name,
                            factor)) ])
  in
  lwt_cmd_line false t

let alba_rewrite_namespace cfg_file tls_arg namespace name factor =
  alba_add_iter_namespace_item
    cfg_file tls_arg namespace name factor
    Albamgr_protocol.Protocol.Work.Rewrite

let job_name p =
  Arg.(required
       & pos p (some string) None
       & info [] ~docv:"JOB_NAME")

let alba_rewrite_namespace_cmd =
  Term.(pure alba_rewrite_namespace
        $ alba_cfg_file
        $ tls_config
        $ namespace 0
        $ job_name 1
        $ Arg.(value
               & opt int 1
               & info ["factor"] ~docv:"specifies into how many pieces the job should be divided")),
  Term.info
    "rewrite-namespace"
    ~doc:"rewrite all objects in the specified namespace"


let alba_verify_namespace
      cfg_file tls_config namespace name factor
      no_verify_checksum no_repair_osd_unavailable =
  alba_add_iter_namespace_item
    cfg_file tls_config namespace name factor
    (let open Albamgr_protocol.Protocol.Work in
     Verify { checksum = not no_verify_checksum;
              repair_osd_unavailable = not no_repair_osd_unavailable; })

let alba_verify_namespace_cmd =
  Term.(pure alba_verify_namespace
        $ alba_cfg_file
        $ tls_config
        $ namespace 0
        $ job_name 1
        $ Arg.(value
               & opt int 1
               & info ["factor"] ~docv:"specifies into how many pieces the job should be divided")
        $ Arg.(value
               & flag
               & info ["no-verify-checksum"] ~docv:"flag to specify checksums should not be verified")
        $ Arg.(value
               & flag
               & info ["no-repair-osd-unavailable"] ~docv:"flag to specify that fragments on unavailable osds should not be repaired")),
  Term.info
    "verify-namespace"
    ~doc:"verify all objects in the specified namespace"

let alba_show_job_progress cfg_file tls_config name =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
       client # get_progress_for_prefix name >>= fun (_, progresses) ->
       Lwt_list.iter_s
         (fun (id, p) ->
          Lwt_log.debug_f
            "%i: %s"
            id
            ([%show : Albamgr_protocol.Protocol.Progress.t] p))
         progresses)
  in
  lwt_cmd_line false t

let alba_show_job_progress_cmd =
  Term.(pure alba_show_job_progress
        $ alba_cfg_file
        $ tls_config
        $ job_name 0),
  Term.info
    "show-job-progress"
    ~doc:"show progress of a certain job"

let alba_clear_job_progress cfg_file tls_config name =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
       client # get_progress_for_prefix name >>= fun (_, progresses) ->
       Lwt_list.iter_s
         (fun (i, p) ->
          let name = serialize (Llio.pair_to
                                  Llio.raw_string_to
                                  Llio.int_to)
                               (name, i)
          in
          client # update_progress name p None)
         progresses)
  in
  lwt_cmd_line false t

let alba_clear_job_progress_cmd =
  Term.(pure alba_clear_job_progress
        $ alba_cfg_file
        $ tls_config
        $ job_name 0),
  Term.info
    "clear-job-progress"
    ~doc:"clear progress of a certain job"

let alba_get_maintenance_config cfg_file tls_config to_json =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
       client # get_maintenance_config >>= fun cfg ->
       if to_json
       then
         print_result cfg Maintenance_config.to_yojson
       else
         Lwt_io.printlf
           "Maintenance config = %s"
           (Maintenance_config.show cfg))
  in
  lwt_cmd_line to_json t

let alba_get_maintenance_config_cmd =
  Term.(pure alba_get_maintenance_config
        $ alba_cfg_file
        $ tls_config
        $ to_json),
  Term.info "get-maintenance-config" ~doc:"get the maintenance config from the albamgr"

let alba_update_maintenance_config
      cfg_file tls_config
      enable_auto_repair'
      auto_repair_timeout_seconds'
      auto_repair_add_disabled_nodes
      auto_repair_remove_disabled_nodes
      enable_rebalance'
  =
  let t () =
    with_albamgr_client
      cfg_file ~attempts:1 tls_config
      (fun client ->
       client # update_maintenance_config
              Maintenance_config.Update.({ enable_auto_repair';
                                           auto_repair_timeout_seconds';
                                           auto_repair_add_disabled_nodes;
                                           auto_repair_remove_disabled_nodes;
                                           enable_rebalance';
                                         }) >>= fun maintenance_config ->
       Lwt_io.printlf
         "Maintenance config now is %s"
         (Maintenance_config.show maintenance_config))
  in
  lwt_cmd_line false t

let alba_update_maintenance_config_cmd =
  Term.(pure alba_update_maintenance_config
        $ alba_cfg_file
        $ tls_config
        $ Arg.(value
               & vflag None
                       [ (Some true,
                          info ["enable-auto-repair"]);
                         (Some false,
                          info ["disable-auto-repair"]); ])
        $ Arg.(value
               & opt (some float) None
               & info ["auto-repair-timeout-seconds"])
        $ Arg.(value
               & opt_all string []
               & info ["auto-repair-add-disabled-node"])
        $ Arg.(value
               & opt_all string []
               & info ["auto-repair-remove-disabled-node"])
        $ Arg.(value
               & vflag None
                       [ (Some true,
                          info ["enable-rebalance"]);
                         (Some false,
                          info ["disable-rebalance"]); ])),
  Term.info "update-maintenance-config" ~doc:"update the maintenance config"

let cmds = [
  alba_list_namespaces_by_id_cmd;

  recover_namespace_cmd;
  alba_mgr_get_version_cmd;

  alba_list_osds_cmd;
  alba_list_all_osds_cmd;
  alba_list_available_osds_cmd;
  alba_list_decommissioning_osds_cmd;

  alba_add_nsm_host_cmd;
  alba_update_nsm_host_cmd;
  alba_list_nsm_hosts_cmd;
  alba_add_osd_cmd;
  alba_mgr_statistics_cmd;

  alba_list_participants_cmd;
  alba_list_work_cmd;

  alba_rewrite_namespace_cmd;
  alba_verify_namespace_cmd;
  alba_show_job_progress_cmd;
  alba_clear_job_progress_cmd;

  alba_get_maintenance_config_cmd;
  alba_update_maintenance_config_cmd;
]
