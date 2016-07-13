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



module OsdCapabilities = struct
  type capability =
    | CMultiGet2
    | CPartialGet
    | CRoraFetcher of int [@@deriving show]

  let capability_to buf c =
    let version = 1 in
    Llio2.WriteBuffer.int8_to buf version;
    match c with
    | CMultiGet2     -> Llio2.WriteBuffer.int8_to buf 1
    | CPartialGet    -> Llio2.WriteBuffer.int8_to buf 2
    | CRoraFetcher p -> Llio2.WriteBuffer.int8_to buf 3;
                        Llio2.WriteBuffer.int_to buf p

  let capability_from buf =
    let version = Llio2.ReadBuffer.int8_from buf in
    assert (version = 1);
    let tag = Llio2.ReadBuffer.int8_from buf in
    match tag with
    | 1 -> CMultiGet2
    | 2 -> CPartialGet
    | 3 -> let port = Llio2.ReadBuffer.int_from buf in
           CRoraFetcher port
    | k -> Prelude.raise_bad_tag "asd_capability" k

  type t = capability Prelude.counted_list
  let to_buffer   = Llio2.WriteBuffer.counted_list_to  capability_to
  let from_buffer = Llio2.ReadBuffer.counted_list_from capability_from

  let deser = from_buffer,to_buffer
  let default = (0,[])

end