(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Pervasiveext
open Fun
open Network_utils
open Xstringext

module D = Debug.Make(struct let name = "networkd" end)
open D

module Server = Network_interface.Server(Network_server)

let resources = [
  { Xcp_service.name = "network-conf";
    description = "used to select the network backend";
    essential = true;
    path = Network_server.network_conf;
    perms = [ Unix.R_OK ];
  };
  { Xcp_service.name = "brctl";
    description = "used to set up bridges";
    essential = true;
    path = Network_utils.brctl;
    perms = [ Unix.X_OK ];
  };
  { Xcp_service.name = "ethtool";
    description = "used to configure network interfaces";
    essential = true;
    path = Network_utils.ethtool;
    perms = [ Unix.X_OK ];
  };
  { Xcp_service.name = "fcoedriver";
    description = "used to identify fcoe interfaces";
    essential = false;
    path = Network_utils.fcoedriver;
    perms = [ Unix.X_OK ];
  }
]

let options = [
	"monitor_blacklist", Arg.String (fun x -> Network_monitor_thread.monitor_blacklist := String.split ',' x), (fun () -> String.concat "," !Network_monitor_thread.monitor_blacklist), "List of prefixes of interface names that are not to be monitored";
]

(** This just sets up an environment variable and has no effect unless
 *  we are compiling for profiling *)

let setup_coverage_profiling name =
  let (//) = Filename.concat in
  let tmpdir =
    let getenv n   = try Sys.getenv n with Not_found -> "" in
    let dirs    = 
      [ getenv "TMP"
      ; getenv "TEMP"
      ; "/tmp"
      ; "/usr/tmp"
      ; "/var/tmp"
      ] in
    let is_dir  = function 
    | ""    -> false
    | path  -> try Sys.is_directory path with Sys_error _ -> false
    in try
      List.find is_dir dirs
    with
      Not_found -> D.error "can't find temp directory %s" __LOC__; exit 1
  in try 
    ignore (Sys.getenv "BISECT_FILE") 
  with Not_found ->
    Unix.putenv "BISECT_FILE" (tmpdir // Printf.sprintf "bisect-%s-" name)
 
let start server =
	Network_monitor_thread.start ();
	Network_server.on_startup ();
	let (_: Thread.t) = Thread.create (fun () ->
		Xcp_service.serve_forever server
	) () in
	()

let stop signal =
	Network_server.on_shutdown signal;
	Network_monitor_thread.stop ();
	exit 0

let handle_shutdown () =
	Sys.set_signal Sys.sigterm (Sys.Signal_handle stop);
	Sys.set_signal Sys.sigint (Sys.Signal_handle stop);
	Sys.set_signal Sys.sigpipe Sys.Signal_ignore

let doc = String.concat "\n" [
	"This is the xapi toolstack network management daemon.";
	"";
	"This service looks after host network configuration, including setting up bridges and/or openvswitch instances, configuring IP addresses etc.";
]

let _ =
  setup_coverage_profiling "networkd";
	begin match Xcp_service.configure2
		~name:Sys.argv.(0)
		~version:Version.version
		~doc ~options ~resources () with
	| `Ok () -> ()
	| `Error m ->
		Printf.fprintf stderr "%s\n" m;
		exit 1
	end;

	let server = Xcp_service.make
		~path:!Network_interface.default_path
		~queue_name:!Network_interface.queue_name
		~rpc_fn:(Server.process ())
		() in

	Xcp_service.maybe_daemonize ();

	Debug.set_facility Syslog.Local5;

	(* We should make the following configurable *)
	Debug.disable "http";

	handle_shutdown ();
	Debug.with_thread_associated "main" start server;

	while true do
		Thread.delay 300.;
		Network_server.on_timer ()
	done

